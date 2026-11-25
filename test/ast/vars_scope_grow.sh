#!/bin/sh
# S1a-0 C1: the variable table grows past its old cap (MAX_VARS = 4096).
# 4100 locals used to be a hard "too many variables" error.
set -u
ct=${1:?usage: vars_scope_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/vs.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}

# --- 4100 locals -----------------------------------------------------------
{
    echo 'int main(void)'
    echo '{'
    i=0
    while [ "$i" -lt 4100 ]; do
        echo "    int v$i = $i;"
        i=$((i + 1))
    done
    echo '    return v4099 == 4099 ? 0 : 1;'
    echo '}'
} >"$w/vars.ct"

if ! "$ct" "$w/vars.ct" -o "$w/vars.c" >"$w/vars.log" 2>&1; then
    echo "FAIL vars: build stopped: $(tail -1 "$w/vars.log")"
    exit 1
fi
if ! "$cc" -std=c99 "$w/vars.c" -o "$w/vars.bin" >"$w/vars.cc.log" 2>&1; then
    echo "FAIL vars: generated C did not build: $(tail -1 "$w/vars.cc.log")"
    exit 1
fi
if "$w/vars.bin"; then echo "ok   vars: 4100 locals built and read back"; else
    echo "FAIL vars: program returned $?"; exit 1
fi
