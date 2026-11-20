#!/bin/sh
# PH-79 S3e: the written slice contract does not drift.
#
# The behavioural gates are p79_basic / p79_index / p79_places / p79_migrate;
# this probe only pins the documentation the card lists as the S3e deliverable:
# the language reference section (4.69) and the package-guide boundary (7.6).
#
# Usage: sh test/ast/p79_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
spec=$root/docs/language-spec.md
guide=$root/docs/package-guide.md
fail=0

ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p79/docs: $1" >&2; fail=1; }

[ -f "$spec" ] || { bad "docs/language-spec.md missing"; exit 1; }
[ -f "$guide" ] || { bad "docs/package-guide.md missing"; exit 1; }

if grep -q '^### 4\.69 .*切片.*`T\[\]`' "$spec"; then
    ok "spec has the slice section (4.69)"
else
    bad "spec section 4.69 (T[] slices) missing"
fi
for needle in '拼写' '表示' '下标' '只读' '位置白名单' '返回' '边界'; do
    if grep -q "$needle" "$spec"; then
        ok "spec mentions $needle"
    else
        bad "spec does not mention $needle"
    fi
done
if grep -q 'is deprecated; write' "$spec"; then
    ok "spec records the T a[] migration warning"
else
    bad "spec does not record the T a[] migration warning"
fi
if grep -q '带边界检查的 place' "$spec" && grep -q '半开区间' "$spec"; then
    ok "spec records the checked place and the half-open subslice"
else
    bad "spec does not record the checked place / half-open subslice"
fi
if grep -q 's.get(i)' "$spec"; then
    ok "spec records the soft access"
else
    bad "spec does not record s.get(i)"
fi
if grep -q 'a\[1\.\.\]\|a\[lo\.\.hi\]' "$spec"; then
    ok "spec records the subslice spellings"
else
    bad "spec does not record the subslice spellings"
fi

if grep -q '^#### 7\.6 .*切片.*`T\[\]`' "$guide"; then
    ok "package-guide has the slice boundary section (7.6)"
else
    bad "package-guide section 7.6 (slice boundary) missing"
fi
if grep -q '借用视图' "$guide" && grep -q 'ABI' "$guide"; then
    ok "package-guide records the non-owning view and the ABI boundary"
else
    bad "package-guide does not record the view / ABI boundary"
fi
if grep -q 'T\[\]' "$guide" && grep -q 'T a\[N\]' "$guide"; then
    ok "package-guide names both slice and array spellings"
else
    bad "package-guide does not name both spellings"
fi

[ "$fail" -eq 0 ] && echo "p79_docs: OK"
exit "$fail"
