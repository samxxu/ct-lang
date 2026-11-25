#!/bin/sh
# S1a-0 C1: parser / emitter / layout counting caps grow past their old
# fixed limits. Each case builds a source whose count is over the old cap,
# compiles it with ct-ast, builds the generated C with the host cc and runs it.
#
# Usage: sh test/ast/cap_grow.sh <ct-ast>
set -u
ct=${1:?usage: cap_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/capgrow.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}
fail=0

# run_case <name> <source> [expected exit]
run_case()
{
    name=$1
    src=$2
    want=${3:-0}
    if ! "$ct" "$src" -o "$w/$name.c" >"$w/$name.log" 2>&1; then
        echo "FAIL $name: ct-ast rejected the source: $(tail -1 "$w/$name.log")"
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$w/$name.c" -o "$w/$name.bin" \
            >"$w/$name.cc.log" 2>&1; then
        echo "FAIL $name: generated C did not build: $(tail -1 "$w/$name.cc.log")"
        return 1
    fi
    "$w/$name.bin"
    got=$?
    if [ "$got" -ne "$want" ]; then
        echo "FAIL $name: program returned $got (want $want)"
        return 1
    fi
    echo "ok   $name"
}

# MAX_CALLS: 9000 calls in one function (old cap 8192).
{
    echo 'int f(int x) { return x; }'
    echo 'int main(void)'
    echo '{'
    i=0
    while [ "$i" -lt 9000 ]; do
        echo "    f($i);"
        i=$((i + 1))
    done
    echo '    return 0;'
    echo '}'
} >"$w/calls.ct"
run_case calls "$w/calls.ct" 0 || fail=1

# MAX_LABELS: 100 labels and 100 gotos in one function (old cap 64 each).
{
    echo 'int main(void)'
    echo '{'
    echo '    int x = 0;'
    echo '    goto L0;'
    i=100
    echo "L$i: return x == 100 ? 0 : 1;"
    i=0
    while [ "$i" -lt 100 ]; do
        echo "L$i: x++; goto L$((i + 1));"
        i=$((i + 1))
    done
} >"$w/labels.ct"
echo '}' >>"$w/labels.ct"
run_case labels "$w/labels.ct" 0 || fail=1

[ "$fail" -eq 0 ] || exit 1
echo "OK S1a-0 cap growth"
