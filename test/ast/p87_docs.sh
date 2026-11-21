#!/usr/bin/env bash
# PH-87 S87d probe: the parser/checker section in the spec and the tutorial,
# plus the metrics report.
#
# E87-7 asks for the line/time report and for spec + tutorial to describe the
# same rewrite. This probe checks the needles, re-measures both line counts
# against the report, and compiles + runs the tutorial §20 snippet.
#
# Usage: bash test/ast/p87_docs.sh <ct-ast>
set -u
CT=${1:?usage: p87_docs.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p87doc.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p87docs: $1" >&2; }
need() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok; else bad "$1 is missing '$2'"; fi; }

spec=docs/language-spec.md
tut=docs/tutorial.md
metrics=docs/design/p87_metrics.md
dogfood=docs/design/p87_dogfood.md

# ---- 1) the spec section -------------------------------------------------
need "$spec" "### 4.74 解析器/检查器的判别式切片（PH-87，实现内部）"
need "$spec" "ctype_*"
need "$spec" "tc_expr_*"
need "$spec" "battle/p87-kind-match"
need "$spec" "345"
need "$spec" "自举不动点"

# ---- 2) the tutorial section and its runnable example --------------------
need "$tut" "## 20. 解析器/检查器的判别式：先切片，再换 \`match\`（PH-87，v0.87.0）"
need "$tut" "match does not cover variant 'Shape.Rect'"
need "$tut" "PH-88"
awk '/^## 20\./{f=1} f && /^```ct$/{b=1; next} b && /^```$/{exit} b{print}' "$tut" >"$tmp/snippet.ct"
if [ -s "$tmp/snippet.ct" ]; then
    if CT_C_BOUNDARY=allow "$CT" "$tmp/snippet.ct" -o "$tmp/snippet.c" >"$tmp/snip.out" 2>"$tmp/snip.err" \
       && "${CC:-cc}" -std=c99 "$tmp/snippet.c" -o "$tmp/snippet.bin" >"$tmp/snip.cc" 2>&1 \
       && [ "$("$tmp/snippet.bin")" = "$(printf '12\n12\n11')" ]; then
        ok
    else
        bad "tutorial §20 snippet failed: $(head -2 "$tmp/snip.err" "$tmp/snip.cc" 2>/dev/null | tr '\n' ' ')"
    fi
else
    bad "tutorial §20 has no ct code block"
fi

# ---- 3) the metrics report and its measured numbers ----------------------
if [ -s "$metrics" ]; then ok; else bad "$metrics is missing"; fi
need "$metrics" "0.81"
need "$metrics" "8710"
need "$metrics" "8814"
need "$metrics" "1082"
need "$metrics" "1149"
need "$metrics" "+171"
need "$metrics" "66"
need "$metrics" "345"
need "$metrics" "p87-kind-match"
# PH-88: the metrics report is a v0.87.0 snapshot, and PH-88 changed the
# emitter plus a capacity comment in Expr.h.ct. Re-derive the numbers from the
# PH-87 closeout commit, not from the live tree (same pattern as
# p85_inventory's frozen snapshot).
p87_base=${P87_BASELINE:-11961895}
expr_lines=$(git show "$p87_base:selfhost/ct-ast/frontend/parse/Expr.h.ct" 2>/dev/null | wc -l | tr -d ' ')
tc_lines=$(git show "$p87_base:selfhost/ct-ast/frontend/type/TypeCheck.h.ct" 2>/dev/null | wc -l | tr -d ' ')
if [ -z "$expr_lines" ] || [ "$expr_lines" = "0" ]; then
    bad "cannot read Expr.h.ct from baseline $p87_base"
fi
if grep -qF "| \`frontend/parse/Expr.h.ct\` | 8710 | $expr_lines |" "$metrics"; then
    ok
else
    bad "metrics no longer records the current Expr.h.ct line count ($expr_lines)"
fi
if grep -qF "| \`frontend/type/TypeCheck.h.ct\` | 1082 | $tc_lines |" "$metrics"; then
    ok
else
    bad "metrics no longer records the current TypeCheck.h.ct line count ($tc_lines)"
fi

# ---- 4) the dogfood report is linked and says 10 / FP --------------------
if [ -s "$dogfood" ] && grep -Fq "10" "$dogfood" && grep -Fq "误报" "$dogfood"; then
    ok
else
    bad "$dogfood is missing the S87c counts"
fi

echo "p87docs: $pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then echo "OK p87docs"; fi
[ "$fail" -eq 0 ]
