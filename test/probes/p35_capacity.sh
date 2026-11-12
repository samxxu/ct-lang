#!/bin/sh
# Phase 35 S8c: templates and instances share the MAX_TRAITS rows (D35-9).
# 62 trivial templates plus `Iter` fill 63 rows, `Iter<int>` is the 64th, and
# a second instance would be the 65th -- which must be refused.
#
# Usage: test/probes/p35_capacity.sh [ct-ast-binary]
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
ct=${1:-${CT_AST:-/tmp/ct-ast}}
out="$root/test/probes/p35_capacity.txt"
work=${TMPDIR:-/tmp}/p35-capacity

if [ ! -x "$ct" ]; then
    echo "p35_capacity: no ct-ast binary at $ct" >&2
    exit 2
fi

rm -rf "$work"
mkdir -p "$work"
i=0
while [ "$i" -lt 62 ]; do
    printf 'trait T%d {\n    int f(void);\n}\n' "$i"
    i=$((i + 1))
done >"$work/cap.ct"
cat >>"$work/cap.ct" <<'SOURCE'

trait Iter<T> {
    T next(void);
}

struct A {
    int v;
} use Iter<int>;

impl Iter<int> for A {
    int next(void) { return self->v; }
}

struct B {
    int v;
} use Iter<char *>;

int main(void)
{
    A a = { .v = 1 };
    B b;
    b.v = 2;
    return a.next();
}
SOURCE

{
    echo "# 62 templates + Iter = 63 rows; Iter<int> is row 64; Iter<char *> is row 65"
    "$ct" compile "$work/cap.ct" -o "$work/cap.c" 2>&1
    echo "rc=$?"
} >"$out"

if ! grep -q "too many traits" "$out"; then
    echo "p35_capacity: expected 'too many traits'" >&2
    cat "$out" >&2
    exit 1
fi
echo "p35_capacity: OK (the 65th trait row is refused)"
