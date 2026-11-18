#!/bin/sh
# PH-68-R1: array dimensions must survive the initializer check.
# `static char s[] = "x"` (test/ast/234_err_return_contract) and
# `char s[2] = "x"` must pass `ct check --types`; before the fix the
# declarator's dimension is dropped and the literal looks like `char *`.
#
# Usage: sh test/ast/p68_typebuf.sh <ct-ast>
set -u
ctast=${1:?usage: p68_typebuf.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p68buf.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0

run_case() {
    name=$1; file=$2
    out=$tmp/$name.out
    ( cd "$root" && "$ctast" check --types "$file" ) >"$out" 2>&1
    rc=$?
    if [ $rc -ne 0 ] || grep -q 'initializer:' "$out"; then
        echo "FAIL p68/typebuf: $name (rc=$rc)" >&2
        sed 's/^/  /' "$out" | head -5 >&2
        fail=1
    fi
}

run_case 234 test/ast/234_err_return_contract/prog.ct

cat > "$tmp/dim2.ct" <<'CT'
static char s[2] = "x";
int main(void) { return 0; }
CT
run_case dim2 "$tmp/dim2.ct"

[ "$fail" -eq 0 ] || exit 1
echo "OK p68/typebuf (234 green)"
