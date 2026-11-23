#!/usr/bin/env bash
# PH-88 S88d probe: the spec/tutorial sections and the v1-pre evidence summary.
#
# E88-7 asks for the emitter rewrite to be documented and for the v1-pre
# evidence summary to be in the tree. This probe checks the needles, compiles
# and runs the tutorial §21 snippet (not just greps it), and confirms the
# evidence summary carries the承接 target the PH-87 review demanded.
#
# Usage: bash test/ast/p88_docs.sh <ct-ast>
set -u
CT=${1:?usage: p88_docs.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p88doc.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p88docs: $1" >&2; }
need() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok; else bad "$1 is missing '$2'"; fi; }

spec=docs/language-spec.md
tut=docs/tutorial.md
metrics=docs/history/p88_metrics.md
evidence=docs/history/v1-pre-evidence.md

# ---- 1) the spec section -------------------------------------------------
need "$spec" "### 4.75 发射器的判别式切片与自举不动点轮数（v0-PH-88，实现内部）"
need "$spec" "em_node_*"
need "$spec" "em_expr_*"
need "$spec" "76"
need "$spec" "CT_FIXPOINT_ROUNDS"
need "$spec" "MAX_FUNCS"
need "$spec" "battle/p88-emit-match"
need "$spec" "v1-PH-0"

# ---- 2) the tutorial section and its runnable example --------------------
need "$tut" "## 21. 发射器切片与自举不动点：日常 2 轮，tag 前 3 轮（v0-PH-88，v0.88.0）"
need "$tut" "CT_FIXPOINT_ROUNDS=3"
need "$tut" "p88-emit-match"
awk '/^## 21\./{f=1} f && /^```ct$/{b=1; next} b && /^```$/{exit} b{print}' "$tut" >"$tmp/snippet.ct"
if [ -s "$tmp/snippet.ct" ]; then
    if CT_C_BOUNDARY=allow "$CT" "$tmp/snippet.ct" -o "$tmp/snippet.c" >"$tmp/snip.out" 2>"$tmp/snip.err" \
       && "${CC:-cc}" -std=c99 "$tmp/snippet.c" -o "$tmp/snippet.bin" >"$tmp/snip.cc" 2>&1 \
       && [ "$("$tmp/snippet.bin")" = "$(printf '7\n5\n8')" ]; then
        ok; echo "  p88docs: tutorial §21 snippet runs (7/5/8)"
    else
        bad "tutorial §21 snippet failed: $(head -2 "$tmp/snip.err" "$tmp/snip.cc" 2>/dev/null | tr '\n' ' ')"
    fi
else
    bad "tutorial §21 has no ct code block"
fi

# ---- 3) metrics + v1-pre evidence summary --------------------------------
need "$metrics" "# v0-PH-88 S88c 度量与 sharp edge"
need "$metrics" "fall-through"
need "$metrics" "String"
need "$evidence" "# v1-pre 证据摘要（v0-PH-84…v0-PH-88，v0.84.0–v0.88.0）"
for ph in v0-PH-84 v0-PH-85 v0-PH-86 v0-PH-87 v0-PH-88; do
    need "$evidence" "| $ph |"
done
need "$evidence" "v1-PH-0"
need "$evidence" "expr_ctype"
need "$evidence" "maybe_box"
need "$evidence" "chk_type"
need "$evidence" "battle/p88-emit-match"

echo "p88docs: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
