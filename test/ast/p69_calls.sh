#!/bin/sh
# PH-69-R2 (LANG-19): a call through a function-pointer variable is judged
# against the pointer's prototype: wrong argument type and extra arguments are
# errors under `ct check`; a legal call and a variadic tail stay silent.
#
# Usage: sh test/ast/p69_calls.sh <ct-ast>
set -u
ctast=${1:?usage: p69_calls.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p69calls.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

check() {
    name=$1; expect=$2; file=$3
    out=$work/$name.out
    ( cd "$root" && "$ctast" check --types "$file" ) >"$out" 2>&1
    rc=$?
    if [ "$expect" = ok ]; then
        if [ $rc -ne 0 ] || [ -s "$out" ]; then
            echo "FAIL p69/calls: $name should be clean (rc=$rc)" >&2
            sed 's/^/  /' "$out" | head -4 >&2
            fail=1
        fi
    else
        if [ $rc -eq 0 ] || ! grep -q "$expect" "$out"; then
            echo "FAIL p69/calls: $name missing '$expect' (rc=$rc)" >&2
            sed 's/^/  /' "$out" | head -4 >&2
            fail=1
        fi
    fi
}

cat > "$work/neg_type.ct" <<'CT'
int main(void) { int (*fp)(int) = 0; return fp("x"); }
CT
cat > "$work/neg_extra.ct" <<'CT'
int main(void) { int (*fp)(int) = 0; return fp(1, 2); }
CT
cat > "$work/pos.ct" <<'CT'
int main(void) { int (*fp)(int) = 0; return fp(1); }
CT
cat > "$work/vararg.ct" <<'CT'
int main(void) { int (*vp)(const char *, ...) = 0; return vp("%d", 1); }
CT

check neg_type "argument 1" "$work/neg_type.ct"
check neg_extra "arity mismatch" "$work/neg_extra.ct"
check pos ok "$work/pos.ct"
check vararg ok "$work/vararg.ct"

[ "$fail" -eq 0 ] || exit 1
echo "OK p69/calls (fnptr prototype)"
