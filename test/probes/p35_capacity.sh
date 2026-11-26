#!/bin/sh
# S1a-0 C4: templates and instances share the trait rows (D35-9), but the row
# table is no longer capped at 64. 62 trivial templates plus `Iter<T>` fill 63
# rows; `Iter<int>` and `Iter<char *>` are rows 64 and 65, so the old fixed
# table refused the 65th. The table now starts at 64 and doubles, so the same
# source must compile, build and run.
#
# Usage: test/probes/p35_capacity.sh [ct-ast-binary]
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
ct=${1:-${CT_AST:-/tmp/ct-ast}}
work=${TMPDIR:-/tmp}/p35-capacity
out="$work/p35_capacity.txt"
cc=${CC:-cc}

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

impl Iter<char *> for B {
    char *next(void) { return "b"; }
}

int main(void)
{
    A a = { .v = 1 };
    B b;
    b.v = 2;
    return a.next() == 1 && b.next()[0] == 'b' ? 0 : 1;
}
SOURCE

{
    echo "# 62 templates + Iter = 63 rows; Iter<int> is row 64; Iter<char *> is row 65"
    "$ct" compile "$work/cap.ct" -o "$work/cap.c" 2>&1
    echo "rc=$?"
} >"$out"

if ! grep -q '^rc=0$' "$out"; then
    echo "p35_capacity: the 65th trait row was refused (S1a-0 C4 expects growth)" >&2
    cat "$out" >&2
    exit 1
fi
if ! "$cc" -Wall -Wextra -std=c99 "$work/cap.c" -o "$work/cap.bin" \
        >>"$out" 2>&1; then
    echo "p35_capacity: the generated C did not build" >&2
    tail -3 "$out" >&2
    exit 1
fi
if ! "$work/cap.bin"; then
    echo "p35_capacity: the program returned non-zero" >&2
    exit 1
fi
echo "p35_capacity: OK (the 65th trait row grows and runs)"
