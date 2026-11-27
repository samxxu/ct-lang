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
#   F  the coverage / timing report is emitted only when asked for;
#   G  the S1b-S2b LIR seam: --ir=on prints covered bodies from LIR, the
#      generated C is byte-identical for the fixtures and the whole pinned
#      corpus, V5-V10 reject malformed LIR without writing a `.c`, and a
#      multi-unit build gets the same seam.
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

# S8r2: the single-file path is LIR by default. Every corpus file is compared
# against the `CT_LIR=0` oracle (not against the default, which is also LIR).
# Functions the lowerer cannot prove (D-013 owning glue, vptr arrays, `into`
# chains, static for-init, >256-byte names, ...) stay on the AST body seam by
# construction, so the byte comparison below is still meaningful; the coverage
# print separates "lowered" from "total".
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
    "selfhost/ct-ast/backend/tir/TGraph.h.ct",
    "selfhost/ct-ast/backend/lir/LModule.h.ct",
    "selfhost/ct-ast/backend/lir/Lower.h.ct",
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
print("ir: %d mirrored defines agree across the TIR/LIR units" % len(seen))
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
    if ! CT_LIR=0 "$CT" "$f" -o "$base" >"$work/b.log" 2>&1; then
        bad "baseline compile failed: $f"
        continue
    fi
    if ! CT_LIR=0 CT_TIR=1 "$CT" "$f" -o "$shad" >"$work/s.log" 2>&1; then
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
    CT_LIR=0 CT_TIR_FAULT="$key" "$CT" test/cases/01_trait_basic.ct -o "$out" \
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
    if ! CT_LIR=0 "$CT" build --emit-c -I "$(dirname "$src")" "$src" -o "$mb" >"$work/mb.log" 2>&1; then
        bad "build baseline failed: $name"
        modfail=$((modfail + 1))
        continue
    fi
    if ! CT_LIR=0 CT_TIR=1 "$CT" build --emit-c -I "$(dirname "$src")" "$src" -o "$ms" \
            >"$work/ms.log" 2>&1; then
        bad "build shadow failed: $name ($(head -2 "$work/ms.log" | tr '\n' ' '))"
        modfail=$((modfail + 1))
        continue
    fi
    mods=$((mods + 1))
    if ! diff -r -x .ctcache "$mb" "$ms" >"$work/md.log" 2>&1; then
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
    if ! CT_LIR=0 "$CT" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct \
            -o "$sb" >"$work/sb.log" 2>&1; then
        bad "self-host baseline failed"
    elif ! CT_LIR=0 CT_TIR=1 CT_TIR_REPORT=1 "$CT" build --emit-c \
            -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$ss" \
            >"$work/ss.log" 2>"$work/ss.err"; then
        bad "self-host shadow failed ($(grep -m1 'error' "$work/ss.err" 2>/dev/null | tr '\n' ' '))"
    elif ! diff -r -x .ctcache "$sb" "$ss" >"$work/sd.log" 2>&1; then
        bad "self-host tree differs under the shadow ($(head -2 "$work/sd.log" | tr '\n' ' '))"
    else
        selfhost=1
        ok
        units=$(grep -c '^tir: unit=' "$work/ss.err" 2>/dev/null || true)
        case "$units" in ''|*[!0-9]*) units=0 ;; esac
        printf 'ir: self-host %d units, TIR shadow C tree byte-identical\n' "$units"
    fi
    # S1b-S2b: the same tree through the LIR seam. Every unit's declarations
    # and signatures stay with the emitter; covered bodies come from LIR. The
    # requirement is the same: byte-identical to the unswitched build.
    if [ "$selfhost" -eq 1 ]; then
        sl="$work/self-lir"
        rm -rf "$sl"
        mkdir -p "$sl"
        if ! CT_LIR_REPORT=1 "$CT" build --emit-c --ir=on -I selfhost/ct-ast \
                selfhost/ct-ast/main.ct -o "$sl" >"$work/sl.log" 2>"$work/sl.err"; then
            bad "self-host LIR build failed ($(grep -m1 'error' "$work/sl.err" 2>/dev/null | tr '\n' ' '))"
        elif ! diff -r -x .ctcache "$sb" "$sl" >"$work/sld.log" 2>&1; then
            bad "self-host tree differs under --ir=on ($(head -2 "$work/sld.log" | tr '\n' ' '))"
        else
            ok
            lunits=$(find "$sl" -name '*.c' -type f | wc -l | tr -d ' ')
            lready=$(grep -c 'ready=1' "$work/sl.err" 2>/dev/null || true)
            case "$lready" in ''|*[!0-9]*) lready=0 ;; esac
            printf 'ir: self-host LIR %d units, %d ready, C tree byte-identical\n' \
                "$lunits" "$lready"
        fi
    fi
else
    printf 'ir: self-host section skipped (CT_IR_SELFHOST=0)\n'
fi

# ---------------------------------------------------------------------------
# F. the report is opt-in and carries coverage + time
# ---------------------------------------------------------------------------
if CT_LIR=0 CT_TIR=1 CT_TIR_REPORT=1 "$CT" examples/53_match_adt/prog.ct -o "$work/r.c" \
        >"$work/r.out" 2>"$work/r.err" \
   && grep -q '^tir: unit=.*exprs=.*time_ms=' "$work/r.err"; then
    ok
    grep -m1 '^tir: unit=' "$work/r.err" | sed 's/^/ir: report /' >&2
else
    bad "the coverage/timing report is missing"
fi
if CT_LIR=0 "$CT" examples/53_match_adt/prog.ct -o "$work/r2.c" >"$work/r2.out" 2>"$work/r2.err" \
   && ! grep -q '^tir:' "$work/r2.err"; then
    ok
else
    bad "the shadow is not off by default"
fi

# ---------------------------------------------------------------------------
# G. the LIR path: --ir=on prints covered bodies from LIR, byte for byte
# ---------------------------------------------------------------------------
# G1: the six cleanup-edge fixtures and the AutoDrop model are fully covered
# (ready=1), print every body from LIR, and stay byte-identical.
lirn=0
lirbad=0
for f in test/ir/lir/*.ct; do
    [ -f "$f" ] || continue
    lirn=$((lirn + 1))
    base="$work/lir-base.c"
    lir="$work/lir-on.c"
    rm -f "$base" "$lir"
    if ! CT_LIR=0 "$CT" "$f" -o "$base" >"$work/lirb.log" 2>&1; then
        bad "LIR baseline compile failed: $f"
        lirbad=$((lirbad + 1))
        continue
    fi
    if ! CT_LIR_REPORT=1 "$CT" "$f" -o "$lir" --ir=on >"$work/lirl.log" 2>"$work/lire.log"; then
        bad "LIR compile failed: $f ($(head -2 "$work/lire.log" | tr '\n' ' '))"
        lirbad=$((lirbad + 1))
        continue
    fi
    if ! cmp -s "$base" "$lir"; then
        bad "LIR changed the generated C: $f"
        lirbad=$((lirbad + 1))
        continue
    fi
    if ! grep -q '^lir: unit=.*ready=' "$work/lire.log"; then
        bad "LIR coverage report missing: $f"
        lirbad=$((lirbad + 1))
        continue
    fi
    if ! grep -q 'ready=1' "$work/lire.log"; then
        bad "the fixture is not printed from LIR: $f"
        lirbad=$((lirbad + 1))
    fi
    if ! grep -q 'bodies printed=[1-9][0-9]* skipped=0' "$work/lire.log"; then
        bad "the fixture did not print its bodies from LIR: $f"
        lirbad=$((lirbad + 1))
    fi
    if ! grep -Eq 'cleanups=[1-9]' "$work/lire.log"; then
        bad "no cleanup entry reached LIR: $f"
        lirbad=$((lirbad + 1))
    fi
done
if [ "$lirbad" -eq 0 ] && [ "$lirn" -ge 6 ]; then ok; else bad "the LIR subset is not byte-identical"; fi
printf 'ir: LIR %d fixtures, %d failures\n' "$lirn" "$lirbad"

# G2: the full corpus. Every file must compile under --ir=on and the generated
# C must be byte-identical to the unswitched path. Coverage is reported, and
# the aggregate function ratio is printed so a regression in the seam shows up.
c2n=0
c2bad=0
c2ready=0
c2ok=0
c2tot=0
c2printed=0
c2skipped=0
for f in test/cases/*.ct examples/*/*.ct; do
    case "$f" in *07_dialect*|*ct-dialects*) continue ;; esac
    c2n=$((c2n + 1))
    base="$work/lirc-base.c"
    lir="$work/lirc-on.c"
    rm -f "$base" "$lir"
    if ! CT_LIR=0 "$CT" "$f" -o "$base" >"$work/lircb.log" 2>&1; then
        bad "LIR corpus baseline failed: $f"
        c2bad=$((c2bad + 1))
        continue
    fi
    if ! CT_LIR_REPORT=1 "$CT" "$f" -o "$lir" --ir=on >/dev/null 2>"$work/lirce.log"; then
        bad "LIR corpus compile failed: $f"
        c2bad=$((c2bad + 1))
        continue
    fi
    if ! cmp -s "$base" "$lir"; then
        bad "LIR changed the generated C: $f"
        c2bad=$((c2bad + 1))
        continue
    fi
    line=$(grep -m1 '^lir: unit=' "$work/lirce.log")
    case "$line" in *ready=1*) c2ready=$((c2ready + 1)) ;; esac
    ratio=$(printf '%s\n' "$line" | sed -n 's/.*funcs=\([0-9]*\)\/\([0-9]*\).*/\1 \2/p')
    if [ -n "$ratio" ]; then
        c2ok=$((c2ok + ${ratio% *}))
        c2tot=$((c2tot + ${ratio#* }))
    fi
    # The seam's own count: a lowered body that still fell back would hide a
    # byte difference behind the AST writer, so require printed == lowered.
    pline=$(grep -m1 '^lir: bodies ' "$work/lirce.log")
    pr=$(printf '%s\n' "$pline" | sed -n 's/.*printed=\([0-9]*\) skipped=\([0-9]*\).*/\1 \2/p')
    if [ -z "$pr" ]; then
        bad "LIR body count missing: $f"
        c2bad=$((c2bad + 1))
    else
        c2printed=$((c2printed + ${pr% *}))
        c2skipped=$((c2skipped + ${pr#* }))
        if [ "${pr#* }" -ne 0 ]; then
            bad "a lowered body was not printed from LIR: $f"
            c2bad=$((c2bad + 1))
        elif [ -n "$ratio" ] && [ "${pr% *}" -ne "${ratio% *}" ]; then
            bad "LIR printed ${pr% *} bodies but lowered ${ratio% *}: $f"
            c2bad=$((c2bad + 1))
        fi
    fi
done
if [ "$c2bad" -eq 0 ] && [ "$c2n" -ge 70 ]; then ok; else bad "the corpus is not byte-identical under --ir=on"; fi
printf 'ir: LIR corpus %d files, %d failures, %d unit-ready, functions %d/%d, bodies printed %d\n' \
    "$c2n" "$c2bad" "$c2ready" "$c2ok" "$c2tot" "$c2printed"
# V5-V10 negatives: E-IR-105..110, non-zero exit, no `.c`
lneg=0
lnegbad=0
for spec in "ir-v5-temp-cross-scope:E-IR-105:c1_return_defer" \
            "ir-v6-cleanup-mismatch:E-IR-106:c2_break" \
            "ir-v7-errdefer-normal:E-IR-107:c1_return_defer" \
            "ir-v8-double-drop:E-IR-108:c2_break" \
            "ir-v9-dangling-jump:E-IR-109:c1_return_defer" \
            "ir-v10-raw-local:E-IR-110:c1_return_defer"; do
    key=${spec%%:*}
    rest=${spec#*:}
    code=${rest%%:*}
    fixture=${rest##*:}
    out="$work/lneg-$key.c"
    rm -f "$out"
    CT_LIR_FAULT="$key" "$CT" "test/ir/lir/$fixture.ct" -o "$out" --ir=on \
        >"$work/lneg-$key.log" 2>&1
    rc=$?
    lneg=$((lneg + 1))
    if [ "$rc" -eq 0 ]; then
        bad "LIR $key was accepted"
        lnegbad=$((lnegbad + 1))
    elif ! grep -q "$code" "$work/lneg-$key.log"; then
        bad "LIR $key did not report $code"
        lnegbad=$((lnegbad + 1))
    elif [ -f "$out" ]; then
        bad "LIR $key left a .c behind"
        lnegbad=$((lnegbad + 1))
    fi
done
if [ "$lnegbad" -eq 0 ]; then ok; else bad "a LIR verifier negative did not behave"; fi

# `--ir=off` is the oracle: no LIR line, and the C bytes equal the AST path
if CT_LIR=0 "$CT" test/ir/lir/c1_return_defer.ct -o "$work/lir-off-base.c" \
        >/dev/null 2>&1 \
   && "$CT" test/ir/lir/c1_return_defer.ct -o "$work/lir-off.c" --ir=off \
        >"$work/lir-off.out" 2>"$work/lir-off.err" \
   && ! grep -q '^lir:' "$work/lir-off.err" \
   && cmp -s "$work/lir-off-base.c" "$work/lir-off.c"; then
    ok
else
    bad "the LIR switch did not honour --ir=off"
fi

# G3: build mode (multi-unit) gets the same seam; the C tree is identical.
ldn=0
ldbad=0
for spec in "test/modules/split/main.ct:split" \
            "test/modules/autodrop/prog.ct:autodrop"; do
    src=${spec%%:*}
    name=${spec##*:}
    [ -f "$src" ] || continue
    lb="$work/lirbuild-$name-base"
    ls="$work/lirbuild-$name-on"
    rm -rf "$lb" "$ls"
    mkdir -p "$lb" "$ls"
    if ! CT_LIR=0 "$CT" build --emit-c -I "$(dirname "$src")" "$src" -o "$lb" >"$work/lbb.log" 2>&1; then
        bad "LIR build baseline failed: $name"
        ldbad=$((ldbad + 1))
        continue
    fi
    if ! "$CT" build --emit-c --ir=on -I "$(dirname "$src")" "$src" -o "$ls" \
            >"$work/lbs.log" 2>&1; then
        bad "LIR build failed: $name ($(head -2 "$work/lbs.log" | tr '\n' ' '))"
        ldbad=$((ldbad + 1))
        continue
    fi
    ldn=$((ldn + 1))
    if ! diff -r -x .ctcache "$lb" "$ls" >"$work/lbd.log" 2>&1; then
        bad "LIR build changed the C tree: $name"
        ldbad=$((ldbad + 1))
    fi
done
if [ "$ldbad" -eq 0 ] && [ "$ldn" -ge 1 ]; then ok; else bad "a LIR build differs"; fi
printf 'ir: LIR builds %d\n' "$ldn"

# ---------------------------------------------------------------------------
# H. S8: `ct build` prints from LIR by default; `--ir=off` is the AST oracle
# ---------------------------------------------------------------------------
default_lir="$work/default-lir"
rm -rf "$default_lir"
mkdir -p "$default_lir"
# H uses a corpus file the LIR seam covers.
lir_build_probe="examples/22_foreach_map/foreach_map.ct"
if env -u CT_LIR -u CT_TIR CT_LIR_REPORT=1 "$CT" build --emit-c \
        -I "$(dirname "$lir_build_probe")" "$lir_build_probe" \
        -o "$default_lir" >"$work/dl.out" 2>"$work/dl.err" \
   && grep -q 'bodies printed=[1-9]' "$work/dl.err"; then
    ok
    printf 'ir: build defaults to LIR (%s)\n' "$(grep -m1 'bodies printed=[1-9]' "$work/dl.err")"
else
    bad "a plain build did not print from LIR by default"
fi
default_off="$work/default-off"
rm -rf "$default_off"
mkdir -p "$default_off"
if env -u CT_TIR CT_LIR=0 CT_LIR_REPORT=1 "$CT" build --emit-c \
        -I "$(dirname "$lir_build_probe")" "$lir_build_probe" \
        -o "$default_off" >"$work/do.out" 2>"$work/do.err" \
   && ! grep -q 'bodies printed=[1-9]' "$work/do.err" \
   && diff -r -x .ctcache "$default_lir" "$default_off" >"$work/dod.log" 2>&1; then
    ok
else
    bad "CT_LIR=0 did not stay on the AST oracle / changed the C tree"
fi

echo
if [ "$fail" -eq 0 ]; then
    printf 'ir: OK (%d corpus byte-identical, %d TIR negatives, %d LIR negatives, %d LIR fixtures, %d module builds, selfhost=%d, %d checks)\n' \
        "$corpus" "$neg" "$lneg" "$lirn" "$mods" "$selfhost" "$pass"
else
    printf 'ir: FAIL (%d failure(s), %d checks passed)\n' "$fail" "$pass"
fi
[ "$fail" -eq 0 ]
