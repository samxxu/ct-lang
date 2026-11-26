#!/usr/bin/env bash
#
# run.sh - S1b-S1 probe: the TIR typed shadow (docs/design/tir-lir-contract.md).
#
# What it proves, one section per claim:
#
#   A  the TIR vocabularies are one value set: every `#define` repeated in
#      backend/tir/TModule.h.ct, TBuilder.h.ct and backend/verify/Verifier.h.ct
#      agrees (a macro does not cross a unit, so the mirrors must be checked);
#   B  `CT_TIR=1` builds and verifies TIR over the pinned corpus and the
#      generated C is byte-identical to the path without the switch (default
#      unchanged, shadow never writes);
#   C  V1-V4 reject four deliberately malformed TIR rows with `E-IR-1xx` and
#      leave no `.c` behind (the fault seam is `CT_TIR_FAULT=<key>`);
#   D  a multi-unit `build` gets the same shadow and the emitted C tree is
#      byte-identical;
#   E  (optional, CT_IR_SELFHOST=0 to skip) the compiler's own source, 70
#      units, builds under the shadow; the self-host tree stays byte-identical
#      and is a fixpoint;
#   F  the coverage / timing report is emitted only when asked for.
#
# Usage: bash test/ir/run.sh <ct-ast-binary>
#        CT_IR_SELFHOST=0 bash test/ir/run.sh <ct-ast-binary>
set -u

CT=${1:?usage: run.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/ctir.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
export CT_C_BOUNDARY=allow

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf 'FAIL ir: %s\n' "$1" >&2; }

if [ ! -x "$CT" ]; then
    printf 'FAIL ir: not executable: %s\n' "$CT" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# A. the three units spell the same vocabulary
# ---------------------------------------------------------------------------
if python3 - "$root" <<'PY'
import re, sys
root = sys.argv[1]
files = [
    "selfhost/ct-ast/backend/tir/TModule.h.ct",
    "selfhost/ct-ast/backend/tir/TBuilder.h.ct",
    "selfhost/ct-ast/backend/verify/Verifier.h.ct",
]
pat = re.compile(r"^#define\s+([A-Z][A-Z0-9_]*)\s+([0-9]+)\s*$")
seen = {}
for rel in files:
    with open(root + "/" + rel, encoding="utf-8") as fh:
        for line in fh:
            m = pat.match(line.rstrip("\n"))
            if not m:
                continue
            name, value = m.group(1), int(m.group(2))
            if name in seen and seen[name] != value:
                print("mirror drift: %s is %d and %d" % (name, seen[name], value),
                      file=sys.stderr)
                sys.exit(1)
            seen[name] = value
if not seen:
    print("no mirrored defines found", file=sys.stderr)
    sys.exit(1)
print("ir: %d mirrored defines agree across the three TIR units" % len(seen))
PY
then ok; else bad "the TIR mirror defines disagree"; fi

# ---------------------------------------------------------------------------
# B. the pinned corpus: shadow builds, C is byte-identical
# ---------------------------------------------------------------------------
corpus=0
cdiff=0
for f in test/cases/*.ct examples/*/*.ct; do
    case "$f" in *07_dialect*|*ct-dialects*) continue ;; esac
    corpus=$((corpus + 1))
    base="$work/base.c"
    shad="$work/shadow.c"
    rm -f "$base" "$shad"
    if ! "$CT" "$f" -o "$base" >"$work/b.log" 2>&1; then
        bad "baseline compile failed: $f"
        continue
    fi
    if ! CT_TIR=1 "$CT" "$f" -o "$shad" >"$work/s.log" 2>&1; then
        bad "shadow compile failed: $f ($(head -2 "$work/s.log" | tr '\n' ' '))"
        continue
    fi
    if ! cmp -s "$base" "$shad"; then
        bad "shadow changed the generated C: $f"
        cdiff=$((cdiff + 1))
        continue
    fi
done
if [ "$cdiff" -eq 0 ] && [ "$corpus" -gt 0 ]; then
    ok
else
    bad "the corpus is not byte-identical under CT_TIR=1"
fi
printf 'ir: corpus %d files, %d byte-differences\n' "$corpus" "$cdiff"

# ---------------------------------------------------------------------------
# C. V1-V4 negatives: `E-IR-1xx`, non-zero exit, no `.c`
# ---------------------------------------------------------------------------
neg=0
neg_bad=0
for pair in "ir-v1-missing-type:E-IR-101" \
            "ir-v2-rvalue-assign:E-IR-102" \
            "ir-v3-unresolved-call:E-IR-103" \
            "ir-v4-open-instance:E-IR-104"; do
    key=${pair%%:*}
    code=${pair##*:}
    out="$work/neg-$key.c"
    rm -f "$out"
    CT_TIR_FAULT="$key" "$CT" test/cases/01_trait_basic.ct -o "$out" \
        >"$work/neg-$key.log" 2>&1
    rc=$?
    neg=$((neg + 1))
    if [ "$rc" -eq 0 ]; then
        bad "$key was accepted (expected a verifier failure)"
        neg_bad=$((neg_bad + 1))
    elif ! grep -q "$code" "$work/neg-$key.log"; then
        bad "$key did not report $code"
        neg_bad=$((neg_bad + 1))
    elif [ -f "$out" ]; then
        bad "$key left a .c behind"
        neg_bad=$((neg_bad + 1))
    fi
done
if [ "$neg_bad" -eq 0 ]; then ok; else bad "a verifier negative did not behave"; fi

# ---------------------------------------------------------------------------
# D. multi-unit build: same shadow, same C tree
# ---------------------------------------------------------------------------
modfail=0
mods=0
for spec in "test/modules/split/main.ct:split" \
            "test/modules/autodrop/prog.ct:autodrop"; do
    src=${spec%%:*}
    name=${spec##*:}
    [ -f "$src" ] || continue
    mb="$work/mod-$name-base"
    ms="$work/mod-$name-shadow"
    rm -rf "$mb" "$ms"
    mkdir -p "$mb" "$ms"
    if ! "$CT" build --emit-c -I "$(dirname "$src")" "$src" -o "$mb" >"$work/mb.log" 2>&1; then
        bad "build baseline failed: $name"
        modfail=$((modfail + 1))
        continue
    fi
    if ! CT_TIR=1 "$CT" build --emit-c -I "$(dirname "$src")" "$src" -o "$ms" \
            >"$work/ms.log" 2>&1; then
        bad "build shadow failed: $name ($(head -2 "$work/ms.log" | tr '\n' ' '))"
        modfail=$((modfail + 1))
        continue
    fi
    mods=$((mods + 1))
    if ! diff -r "$mb" "$ms" >"$work/md.log" 2>&1; then
        bad "build shadow changed the C tree: $name"
        modfail=$((modfail + 1))
    fi
done
if [ "$modfail" -eq 0 ]; then ok; else bad "a module build differs under the shadow"; fi
printf 'ir: module builds %d\n' "$mods"

# ---------------------------------------------------------------------------
# E. the compiler's own source (70 units) under the shadow
# ---------------------------------------------------------------------------
selfhost=0
if [ "${CT_IR_SELFHOST:-1}" != "0" ]; then
    sb="$work/self-base"
    ss="$work/self-shadow"
    rm -rf "$sb" "$ss"
    mkdir -p "$sb" "$ss"
    if ! "$CT" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct \
            -o "$sb" >"$work/sb.log" 2>&1; then
        bad "self-host baseline failed"
    elif ! CT_TIR=1 CT_TIR_REPORT=1 "$CT" build --emit-c \
            -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$ss" \
            >"$work/ss.log" 2>"$work/ss.err"; then
        bad "self-host shadow failed ($(grep -m1 'error' "$work/ss.err" 2>/dev/null | tr '\n' ' '))"
    elif ! diff -r "$sb" "$ss" >"$work/sd.log" 2>&1; then
        bad "self-host tree differs under the shadow ($(head -2 "$work/sd.log" | tr '\n' ' '))"
    else
        selfhost=1
        ok
        units=$(grep -c '^tir: unit=' "$work/ss.err" 2>/dev/null || true)
        case "$units" in ''|*[!0-9]*) units=0 ;; esac
        printf 'ir: self-host %d units, C tree byte-identical\n' "$units"
    fi
else
    printf 'ir: self-host section skipped (CT_IR_SELFHOST=0)\n'
fi

# ---------------------------------------------------------------------------
# F. the report is opt-in and carries coverage + time
# ---------------------------------------------------------------------------
if CT_TIR=1 CT_TIR_REPORT=1 "$CT" examples/53_match_adt/prog.ct -o "$work/r.c" \
        >"$work/r.out" 2>"$work/r.err" \
   && grep -q '^tir: unit=.*exprs=.*time_ms=' "$work/r.err"; then
    ok
    grep -m1 '^tir: unit=' "$work/r.err" | sed 's/^/ir: report /' >&2
else
    bad "the coverage/timing report is missing"
fi
if "$CT" examples/53_match_adt/prog.ct -o "$work/r2.c" >"$work/r2.out" 2>"$work/r2.err" \
   && ! grep -q '^tir:' "$work/r2.err"; then
    ok
else
    bad "the shadow is not off by default"
fi

echo
if [ "$fail" -eq 0 ]; then
    printf 'ir: OK (%d corpus byte-identical, %d verifier negatives, %d module builds, selfhost=%d, %d checks)\n' \
        "$corpus" "$neg" "$mods" "$selfhost" "$pass"
else
    printf 'ir: FAIL (%d failure(s), %d checks passed)\n' "$fail" "$pass"
fi
[ "$fail" -eq 0 ]
