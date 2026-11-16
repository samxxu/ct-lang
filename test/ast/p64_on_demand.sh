#!/usr/bin/env bash
# PH-64-T2 probe: `ct build --emit-c` emits only the built-in layer units the
# program can reach. A bare program gets no container unit; `Option<int>` gets
# `Option` and nothing else. The layer is discovered from the repo root, so the
# probe runs `ct` from there.
#
# Usage: bash test/ast/p64_on_demand.sh <ct-ast>
set -u
CT=${1:?usage: p64_on_demand.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p64ond.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/min" "$tmp/opt"

cat >"$tmp/min/m.ct" <<'CT'
int main(void)
{
    return 0;
}
CT

cat >"$tmp/opt/o.ct" <<'CT'
#include <stdio.h>

int main(void)
{
    Option<int> a = { 1, 3 };
    printf("%d\n", a.has);
    return 0;
}
CT

fail=0
( cd "$root" && "$CT" build --emit-c "$tmp/min/m.ct" -o "$tmp/min" ) >"$tmp/min.log" 2>"$tmp/min.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the bare program did not build: $(head -2 "$tmp/min.err")" >&2
    fail=1
else
    for u in Vec Option Result Str; do
        if [ -e "$tmp/min/$u.c" ] || [ -e "$tmp/min/$u.h" ]; then
            echo "FAIL p64ond: the bare program still emits $u" >&2
            fail=1
        fi
    done
    [ -e "$tmp/min/m.c" ] || { echo "FAIL p64ond: m.c is missing" >&2; fail=1; }
fi

( cd "$root" && "$CT" build --emit-c "$tmp/opt/o.ct" -o "$tmp/opt" ) >"$tmp/opt.log" 2>"$tmp/opt.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the Option program did not build: $(head -2 "$tmp/opt.err")" >&2
    fail=1
else
    [ -e "$tmp/opt/Option.c" ] || { echo "FAIL p64ond: Option.c is missing" >&2; fail=1; }
    for u in Vec Result Str; do
        if [ -e "$tmp/opt/$u.c" ]; then
            echo "FAIL p64ond: Option<int> also pulled $u" >&2
            fail=1
        fi
    done
    if ! "$CC" -Wall -Wextra -std=c99 "$tmp/opt"/*.c -o "$tmp/opt.bin" 2>"$tmp/opt.cc"; then
        echo "FAIL p64ond: the Option product did not link: $(head -3 "$tmp/opt.cc")" >&2
        fail=1
    elif [ "$("$tmp/opt.bin" 2>&1)" != "1" ]; then
        echo "FAIL p64ond: the Option program printed '$( "$tmp/opt.bin" 2>&1 )'" >&2
        fail=1
    fi
fi

[ "$fail" -eq 0 ] && echo "OK p64ond"
exit "$fail"
