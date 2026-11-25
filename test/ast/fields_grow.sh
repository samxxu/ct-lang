#!/bin/sh
# S1a-0 C1: one struct/template may carry more than MAX_FIELDS (64) fields.
set -u
ct=${1:?usage: fields_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/fields.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}

run_case()
{
    name=$1
    if ! "$ct" "$w/$name.ct" -o "$w/$name.c" >"$w/$name.log" 2>&1; then
        echo "FAIL $name: build stopped: $(tail -1 "$w/$name.log")"
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$w/$name.c" -o "$w/$name.bin" \
            >"$w/$name.cc.log" 2>&1; then
        echo "FAIL $name: generated C did not build: $(tail -1 "$w/$name.cc.log")"
        return 1
    fi
    if "$w/$name.bin"; then echo "ok   $name"; else
        echo "FAIL $name: program returned $?"
        return 1
    fi
}

# plain struct with 70 fields
{
    echo 'struct Wide {'
    i=0
    while [ "$i" -lt 70 ]; do echo "    int f$i;"; i=$((i + 1)); done
    echo '};'
    echo 'int main(void)'
    echo '{'
    echo '    struct Wide w = { .f69 = 69 };'
    echo '    return w.f69 == 69 ? 0 : 1;'
    echo '}'
} >"$w/plain.ct"

# generic template with 70 fields, instantiated (template row + instance row)
{
    echo 'struct Gen<T> {'
    i=0
    while [ "$i" -lt 70 ]; do echo "    T f$i;"; i=$((i + 1)); done
    echo '};'
    echo 'int main(void)'
    echo '{'
    echo '    Gen<int> g;'
    echo '    g.f69 = 69;'
    echo '    return g.f69 == 69 ? 0 : 1;'
    echo '}'
} >"$w/generic.ct"

run_case plain || exit 1
run_case generic || exit 1
