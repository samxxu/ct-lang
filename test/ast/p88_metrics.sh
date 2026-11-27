#!/usr/bin/env bash
# PH-88 S88c probe: the metrics report matches the tree it describes.
#
# S88c asks for line counts, build time and sharp edges in `docs/history/`,
# checked against the PH-85 spike. This probe re-derives every machine-checkable
# number in `docs/history/p88_metrics.md`:
#   * the emitter's before/after line count (baseline `47a8f786` vs HEAD);
#   * the slice inventory per dispatcher (76 total);
#   * the emitted-C line count for the baseline tree and the HEAD tree, both
#     emitted by the same compiler (so the delta is the source change);
#   * the distinct-callee capacity the rewrite forced (2048 after v1-PH-2 S5);
# and it requires the sharp-edge section to keep the entries a reviewer needs
# (the fall-through arm, the String verdict, the MAX_FUNCS headroom).
#
# Usage: bash test/ast/p88_metrics.sh <ct-ast>
set -u
CT=${1:?usage: p88_metrics.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p88met.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p88metrics: $1" >&2; }

doc=docs/history/p88_metrics.md
src=selfhost/ct-ast/backend/emit/Emitter.h.ct
base=47a8f786
if [ ! -f "$doc" ]; then
    echo "FAIL p88metrics: $doc is missing" >&2
    exit 1
fi

read_field() { sed -n "s/.*$1=\([0-9][0-9]*\).*/\1/p" "$doc" | head -1; }

emitter_before=$(read_field emitter_before)
emitter_after=$(read_field emitter_after)
slices=$(read_field total_slices)
expr_s=$(read_field expr_slices)
node_s=$(read_field node_slices)
decl_s=$(read_field decl_slices)
inline_s=$(read_field inline_slices)
field_s=$(read_field field_slices)
emitted_before=$(read_field emitted_before)
emitted_after=$(read_field emitted_after)
io_cap=$(read_field io_cap)

# ---- 1) line counts and slice inventory ---------------------------------
actual_before=$(git show "$base:$src" | wc -l | tr -d ' ')
actual_after=$(wc -l <"$src" | tr -d ' ')
if [ "$emitter_before" = "$actual_before" ] && [ "$emitter_after" = "$actual_after" ]; then
    ok; echo "  p88metrics: Emitter.h.ct $emitter_before -> $emitter_after"
else
    bad "Emitter.h.ct lines are $actual_before -> $actual_after, doc says $emitter_before -> $emitter_after"
fi

actual_slices=$(( $(grep -c '^static int em_expr_' "$src") \
                 + $(grep -c '^static int em_node_' "$src") \
                 + $(grep -c '^static int em_decl_' "$src") \
                 + $(grep -c '^static int em_inline_' "$src") \
                 + $(grep -c '^static int em_field_' "$src") ))
if [ "$slices" = "76" ] && [ "$actual_slices" = "76" ] \
   && [ "$expr_s" -eq 34 ] && [ "$node_s" -eq 26 ] && [ "$decl_s" -eq 6 ] \
   && [ "$inline_s" -eq 8 ] && [ "$field_s" -eq 2 ]; then
    ok; echo "  p88metrics: 76 slices (34/26/6/8/2)"
else
    bad "slice inventory is $actual_slices (doc $slices; 34/26/6/8/2 expected)"
fi

# ---- 2) emitted-C line counts, one compiler for both trees --------------
git archive "$base" | tar -x -C "$tmp" 2>/dev/null || bad "cannot extract baseline $base"
mkdir -p "$tmp/out-base" "$tmp/out-head"
case "$CT" in /*) ctabs="$CT" ;; *) ctabs="$root/$CT" ;; esac
# The baseline tree is a historical snapshot: its lib/std (or lib/core) still
# carries direct includes and predates the v1.2 strict default, so it is
# emitted with the explicit allow that its own era had.
( cd "$tmp" && CT_C_BOUNDARY=allow "$ctabs" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct \
      -o "$tmp/out-base" >/dev/null 2>"$tmp/base.err" )
"$ctabs" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct \
      -o "$tmp/out-head" >/dev/null 2>"$tmp/head.err"
if [ -z "$(ls "$tmp/out-base"/*.c 2>/dev/null)" ] || [ -z "$(ls "$tmp/out-head"/*.c 2>/dev/null)" ]; then
    bad "the emit step failed: $(head -2 "$tmp/base.err" "$tmp/head.err" 2>/dev/null | tr '\n' ' ')"
else
    got_before=$(cat "$tmp/out-base"/*.c | wc -l | tr -d ' ')
    got_after=$(cat "$tmp/out-head"/*.c | wc -l | tr -d ' ')
    if [ "$emitted_before" = "$got_before" ] && [ "$emitted_after" = "$got_after" ]; then
        ok; echo "  p88metrics: emitted C $emitted_before -> $emitted_after"
    else
        bad "emitted C is $got_before -> $got_after, doc says $emitted_before -> $emitted_after"
    fi
fi

# ---- 3) the capacity the rewrite forced ---------------------------------
if [ "$io_cap" = "2048" ] \
   && grep -rq 'char io_names\[2048\]\[64\];' selfhost/ct-ast/frontend/parse/ \
   && grep -rq 'e->nio >= 2048' selfhost/ct-ast/frontend/parse/; then
    ok; echo "  p88metrics: distinct-callee capacity is 2048"
else
    bad "the distinct-callee capacity is not the documented 2048"
fi

# ---- 4) the sharp-edge entries a reviewer needs -------------------------
need() { if grep -qF -- "$2" "$1"; then ok; else bad "$1 is missing '$2'"; fi; }
need "$doc" "fall-through"
need "$doc" "String"
need "$doc" "MAX_FUNCS"
need "$doc" "PH-85 spike"
need "$doc" "v1-PH-0"

echo "p88metrics: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
