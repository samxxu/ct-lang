#!/bin/sh
# S1a-0 C2a/C2b/C2c: text caps move to on-demand buffers.
#
#   C2a  MAX_RAW_BLOCK 32768  -> TEXT_LIMIT 65536 bytes for one #ct-raw block
#        (the block already lives in the growable literal pool; the old policy
#        cap is gone).
#   C2b  MAX_KEY 768          -> one unit's incremental-cache key grows on
#        demand to TEXT_LIMIT; a long source path must still be cached and
#        reused, where the old compiler silently skipped the cache.
#   C2c  MAX_INIT_TEXT 16384  -> the rewritten brace-initializer text grows on
#        demand to TEXT_LIMIT; 9000 items must keep every element.
#
# Usage: sh test/ast/cap_text.sh <ct-ast>
set -u
ct=${1:?usage: cap_text.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
# the fixtures are host C programs / build inputs, not package sources
CT_C_BOUNDARY=allow
export CT_C_BOUNDARY
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

# MAX_KEY: build one unit whose source path alone is longer than the old
# 768-byte key cap. The emitted `.c` carries a marker appended by the test; a
# warm build that reuses the key leaves the marker in place (a miss rewrites
# the whole file).
d="$w/deep"
n=0
while [ $((${#d} + 14)) -lt 840 ] && [ "$n" -lt 20 ]; do
    d="$d/ddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"
    n=$((n + 1))
done
src="$d/longkey.ct"
if [ ${#src} -le 768 ]; then
    echo "FAIL key: could not make a source path over 768 bytes (got ${#src})"
    fail=1
else
    mkdir -p "$d" || exit 1
    printf 'int main(void)\n{\n    return 0;\n}\n' >"$src"
    outdir="$w/keyout"
    mkdir -p "$outdir" || exit 1
    if ! "$ct" build --emit-c "$src" -o "$outdir" >"$w/key.out" 2>"$w/key.err"; then
        echo "FAIL key: ct-ast build rejected a ${#src}-byte path: $(grep 'error: ' "$w/key.err" | head -1)"
        fail=1
    elif [ ! -f "$outdir/.ctcache/longkey.c.key" ]; then
        echo "FAIL key: no cache key written for a ${#src}-byte path"
        fail=1
    else
        klen=$(wc -c <"$outdir/.ctcache/longkey.c.key" | tr -d ' ')
        if [ "$klen" -le 768 ]; then
            echo "FAIL key: cache key is $klen bytes (want > 768)"
            fail=1
        else
            echo "ok   key ($klen-byte key for a ${#src}-byte path)"
        fi
        printf '\n/* warm-hit marker */\n' >>"$outdir/longkey.c"
        if ! "$ct" build --emit-c "$src" -o "$outdir" >"$w/key2.out" 2>"$w/key2.err"; then
            echo "FAIL key: the warm build failed: $(tail -1 "$w/key2.err")"
            fail=1
        elif grep -Fq 'warm-hit marker' "$outdir/longkey.c"; then
            echo "ok   key (the long key is reused on a warm build)"
        else
            echo "FAIL key: the long key was not reused"
            fail=1
        fi
    fi
fi

# MAX_INIT_TEXT: 9000 brace-initializer items rewrite to ~18000 bytes, over
# the old 16384-byte output buffer. The array must keep every element (the
# program checks sizeof) instead of the old generic rejection.
{
    printf 'char big[] = {'
    awk 'BEGIN { for (i = 0; i < 9000; i++) printf "1," }'
    printf '1};\nint main(void) { return sizeof big == 9001 ? 0 : 1; }\n'
} >"$w/init_big.ct"
run_case init_big "$w/init_big.ct" 0 || fail=1

if [ "$fail" -eq 0 ]; then
    echo "cap_text: OK (raw block, cache key, initializer text)"
    exit 0
fi
echo "cap_text: FAIL"
exit 1
