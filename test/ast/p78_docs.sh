#!/bin/sh
# PH-78 S2c: the language reference and the tutorial document `ref` / `out`.
#
# The gate that matters is behavioural (p78_basic / p78_method / p78_types);
# this probe keeps the written contract from drifting: the spec section must
# name the context keyword, the place whitelist, definite assignment and the
# boundaries, and the tutorial must show a runnable example.
#
# Usage: sh test/ast/p78_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
spec=$root/docs/language-spec.md
tut=$root/docs/tutorial.md
fail=0

ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p78/docs: $1" >&2; fail=1; }

[ -f "$spec" ] || { bad "docs/language-spec.md missing"; exit 1; }
[ -f "$tut" ] || { bad "docs/tutorial.md missing"; exit 1; }

if grep -q '^### 4\.68 .*`ref`.*`out`' "$spec"; then
    ok "spec has the ref/out section (4.68)"
else
    bad "spec section 4.68 (ref/out) missing"
fi
for needle in '上下文关键字' 'lvalue' '定值' '边界'; do
    if grep -q "$needle" "$spec"; then
        ok "spec mentions $needle"
    else
        bad "spec does not mention $needle"
    fi
done
if grep -q 'ref/out parameters cannot be arrays or function pointers' "$spec"; then
    ok "spec records the array/function-pointer boundary"
else
    bad "spec does not record the array/function-pointer boundary"
fi

if grep -q '^## 15\. .*`ref` / `out`' "$tut"; then
    ok "tutorial has the ref/out section (15)"
else
    bad "tutorial section 15 (ref/out) missing"
fi
if grep -q 'ref int' "$tut" && grep -q 'out int' "$tut" && grep -q '(\*name)' "$tut"; then
    ok "tutorial shows the ref/out spelling and the emitted pointer form"
else
    bad "tutorial does not show ref/out spelling"
fi

[ "$fail" -eq 0 ] && echo "p78_docs: OK"
exit "$fail"
