#!/bin/sh
# PH-68-R2: the expression type table must cover binary, unary, ternary and
# cast nodes. Positive cases stay silent; negative cases only diagnose when
# the node is actually typed (an untyped node is silently skipped).
#
# Usage: sh test/ast/p68_exprtypes.sh <ct-ast>
set -u
ctast=${1:?usage: p68_exprtypes.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p68expr.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0

cat > "$tmp/pos.ct" <<'CT'
int main(void)
{
    int a = 1 + 2;
    int b = 1 ? 2 : 3;
    int c = -1;
    int d = !0;
    int e = (int)3.5;
    return a + b + c + d + e;
}
CT
cat > "$tmp/neg.ct" <<'CT'
int main(void)
{
    int *p = 1 + 2;
    int *q = 1 ? 2 : 3;
    int *r = -1;
    return p != q && q != r;
}
CT

out=$tmp/pos.out
( cd "$root" && "$ctast" check --types "$tmp/pos.ct" ) >"$out" 2>&1 || {
    echo "FAIL p68/exprtypes: positive fixture rejected" >&2
    sed 's/^/  /' "$out" | head -5 >&2
    fail=1
}
if grep -q 'initializer:' "$out"; then
    echo "FAIL p68/exprtypes: positive fixture diagnosed" >&2
    sed 's/^/  /' "$out" | head -5 >&2
    fail=1
fi

out=$tmp/neg.out
( cd "$root" && "$ctast" check --types "$tmp/neg.ct" ) >"$out" 2>&1
n=$(grep -c 'initializer:' "$out")
[ "$n" -ge 3 ] || {
    echo "FAIL p68/exprtypes: negative cases skipped (diagnostics=$n, want >=3)" >&2
    sed 's/^/  /' "$out" | head -8 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p68/exprtypes"
