#!/bin/sh
# S1a-0 C1: the type table (and its kind/target parallel arrays) grows past
# MAX_TYPES (256). 300 typedefs used to be a hard "too many types" error.
set -u
ct=${1:?usage: types_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/types.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM

{
    i=0
    while [ "$i" -lt 300 ]; do
        echo "typedef int A$i;"
        i=$((i + 1))
    done
    echo 'int main(void)'
    echo '{'
    echo '    A299 x = 299;'
    echo '    return x == 299 ? 0 : 1;'
    echo '}'
} >"$w/prog.ct"

if ! "$ct" "$w/prog.ct" -o "$w/prog.c" >"$w/log" 2>&1; then
    echo "FAIL build stopped: $(tail -1 "$w/log")"
    exit 1
fi
cc=${CC:-cc}
if ! "$cc" -Wall -Wextra -std=c99 "$w/prog.c" -o "$w/prog" >"$w/cc.log" 2>&1; then
    echo "FAIL generated C did not build: $(tail -1 "$w/cc.log")"
    exit 1
fi
if "$w/prog"; then echo "ok   300 typedefs built and used"; else
    echo "FAIL program returned $?"; exit 1
fi
