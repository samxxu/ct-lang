#!/bin/sh
# S1a-0 C1: the per-unit struct table and trait table grow past MAX_STRUCTS
# (128) and MAX_TRAITS (64).
set -u
ct=${1:?usage: decl_tables_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/decl.XXXXXX") || exit 1
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

# 140 plain structs (MAX_STRUCTS = 128)
{
    i=0
    while [ "$i" -lt 140 ]; do
        echo "struct S$i { int x; };"
        i=$((i + 1))
    done
    echo 'int main(void)'
    echo '{'
    echo '    struct S139 s = { .x = 139 };'
    echo '    return s.x == 139 ? 0 : 1;'
    echo '}'
} >"$w/structs.ct"

# 70 declared traits (MAX_TRAITS = 64)
{
    i=0
    while [ "$i" -lt 70 ]; do
        echo "trait T$i { int m(); }"
        i=$((i + 1))
    done
    echo 'int main(void) { return 0; }'
} >"$w/traits.ct"

run_case structs || exit 1
run_case traits || exit 1
