#!/bin/sh
# S1a-0 C2a: the raw block text cap is the formal TEXT_LIMIT (65536 bytes),
# not the old fixed 32768. A block is stored in the growable literal pool, so
# the only remaining bound is the resource guard; a block over the old cap must
# compile and reach the generated C byte for byte.
#
# Usage: sh test/ast/cap_text.sh <ct-ast>
set -u
ct=${1:?usage: cap_text.sh <ct-ast>}
# the fixtures are host C programs, not package sources under test
CT_C_BOUNDARY=allow
export CT_C_BOUNDARY
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/captext.XXXXXX") || exit 1
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
        echo "FAIL $name: ct-ast rejected the source: $(grep 'error: ' "$w/$name.log" | head -1)"
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

# MAX_RAW_BLOCK: one block of 40000 bytes (old cap 32768). The sentinel at the
# end of the block proves the whole text reached the emitted C; the function
# after the block proves the lexer resumed on the closing line's successor.
{
    printf '#include <stdio.h>\n\n#ct-raw\n/* '
    awk 'BEGIN { for (i = 0; i < 39990; i++) printf "x" }'
    printf ' */\nstatic int raw_tail(void) { return 7; }\n#ct-endraw\n\n'
    printf 'int main(void) { return raw_tail() == 7 ? 0 : 1; }\n'
} >"$w/raw_big.ct"
if run_case raw_big "$w/raw_big.ct" 0; then
    if grep -Fq 'xxxxxxxxxx */' "$w/raw_big.c"; then
        echo "ok   raw_big (40000-byte block reached the generated C)"
    else
        echo "FAIL raw_big: the block tail was truncated or dropped"
        fail=1
    fi
else
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "cap_text: OK (raw block)"
    exit 0
fi
echo "cap_text: FAIL"
exit 1
