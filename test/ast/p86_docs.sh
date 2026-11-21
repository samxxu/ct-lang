#!/usr/bin/env bash
# PH-86 S86d probe: the lexical-boundary documentation and the metrics report.
#
# E86-6 asks for the line-count / compile-time report next to the PH-85 spike;
# E86-7 asks the spec and the tutorial to describe the same lexical boundaries
# (identifier 159, single string literal 158, adjacent literals concatenate) and
# for the example to be runnable. This probe checks the needles, re-measures the
# lexer's line count against the report, and compiles + runs the tutorial
# snippet with the compiler under test.
#
# Usage: bash test/ast/p86_docs.sh <ct-ast>
set -u
CT=${1:?usage: p86_docs.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/p86doc.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p86docs: $1" >&2; }
need() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok; else bad "$1 is missing '$2'"; fi; }

spec=docs/language-spec.md
tut=docs/tutorial.md
metrics=docs/design/p86_metrics.md
evidence=test/probes/p86_metrics_evidence.txt

# ---- 1) the spec describes the token view and keeps the visible limits ----
need "$spec" "token 文本是实现内部的源缓冲视图"
need "$spec" "{ptr,len}"
need "$spec" "不保证 NUL 终止"
need "$spec" "159/158"

# ---- 2) the tutorial section and its exact diagnostics -------------------
need "$tut" "## 19. 词法边界：长名字、长字符串与相邻字面量"
need "$tut" "identifier is too long"
need "$tut" "string literal is too long (max 158 bytes; split it)"
need "$tut" 'const char *s = "hello, " "world";'
need "$tut" "language-spec §2"

# ---- 3) the tutorial's positive example compiles and runs -----------------
awk '/^## 19\./{f=1} f && /^```ct$/{b=1; next} b && /^```$/{exit} b{print}' "$tut" >"$work/snippet.ct"
if [ -s "$work/snippet.ct" ]; then
    if CT_C_BOUNDARY=allow "$CT" "$work/snippet.ct" -o "$work/snippet.c" >"$work/snip.out" 2>"$work/snip.err" \
       && "${CC:-cc}" -std=c99 "$work/snippet.c" -o "$work/snippet.bin" >"$work/snip.cc" 2>&1 \
       && [ "$("$work/snippet.bin")" = "hello, world" ]; then
        ok
    else
        bad "tutorial §19 snippet failed: $(head -2 "$work/snip.err" "$work/snip.cc" 2>/dev/null | tr '\n' ' ')"
    fi
else
    bad "tutorial §19 has no ct code block"
fi

# ---- 4) the metrics report is on disk and names the measured numbers ------
if [ -s "$metrics" ]; then ok; else bad "$metrics is missing"; fi
need "$metrics" "PH-85"
need "$metrics" "1053.2"
need "$metrics" "1080.2"
need "$metrics" "+67"
need "$metrics" "45717"
need "$metrics" "45817"
need "$metrics" "自举不动点"
need "$evidence" "median 1053.2"
need "$evidence" "median 1080.2"
need "$evidence" "diff -rq .temp/self86b .temp/self86b2"

# ---- 5) the report's lexer line count still matches the tree -------------
lex_lines=$(wc -l < selfhost/ct-ast/frontend/lex/Lexer.h.ct | tr -d ' ')
if grep -qF "| \`frontend/lex/Lexer.h.ct\` | 391 | $lex_lines |" "$metrics"; then
    ok
else
    bad "metrics no longer records the current Lexer.h.ct line count ($lex_lines)"
fi
if [ "$lex_lines" != "458" ]; then
    bad "Lexer.h.ct is $lex_lines lines, the S86d report froze 458"
else
    ok
fi

echo "p86docs: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
