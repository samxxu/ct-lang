#!/bin/sh
# S1a-0 C1: a trait may declare more than MAX_METHODS (64) methods.
# The old cap stopped parsing at method 65. The second case is a generic
# trait: its instance row owns a *copy* of the method block, so it must be
# able to grow too (no row may point into another row's block).
set -u
ct=${1:?usage: trait_methods_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/meth.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM

# gen <file> <trait-head> <use> <impl-head> <arg> <call-expr>
gen()
{
    {
        echo "$2"
        i=0
        while [ "$i" -lt 80 ]; do
            echo "    int m$i($5 x);"
            i=$((i + 1))
        done
        echo '}'
        echo "struct S { int v; } use $3;"
        echo "$4"
        i=0
        while [ "$i" -lt 80 ]; do
            echo "    int m$i(int x) { return x + $i; }"
            i=$((i + 1))
        done
        echo '}'
        echo 'int main(void)'
        echo '{'
        echo '    S s = { .v = 0 };'
        echo "    $3 b = s;"
        echo "    return $6;"
        echo '}'
    } >"$1"
}

gen "$w/plain.ct" 'trait Big {' 'Big' 'impl Big for S {' 'int' 'b.m79(1) == 80 ? 0 : 1'
gen "$w/generic.ct" 'trait Gen<T> {' 'Gen<int>' 'impl Gen<int> for S {' 'T' \
    'b.m79(1) == 80 ? 0 : 1'

for case in plain generic; do
    if ! "$ct" "$w/$case.ct" -o "$w/$case.c" >"$w/$case.log" 2>&1; then
        echo "FAIL $case: build stopped: $(tail -1 "$w/$case.log")"
        exit 1
    fi
    cc=${CC:-cc}
    if ! "$cc" -Wall -Wextra -std=c99 "$w/$case.c" -o "$w/$case.bin" \
            >"$w/$case.cc.log" 2>&1; then
        echo "FAIL $case: generated C did not build: $(tail -1 "$w/$case.cc.log")"
        exit 1
    fi
    if "$w/$case.bin"; then
        echo "ok   $case: 80-method trait built and dispatched"
    else
        echo "FAIL $case: dispatch returned $?"
        exit 1
    fi
done
