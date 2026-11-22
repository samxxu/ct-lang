#!/bin/sh
# PH-80 S5a-3: the method set and the read-only subscript (E80-3, E80-4, E80-6).
#
#   - UTF-8: `len` / `char_len` / `byte_at` / `codepoint_at` / `get` / `s[i]` /
#     `char_at` / `byte_slice` / `byte_index_of(_from)` / `slice` / `as_str` /
#     `cstr`, each with its out-of-range branch;
#   - UTF-16: the JS core subset in snake_case (31 rows), every one a positive
#     case with its boundary branch;
#   - `String` is immutable: `s[0] = ...` and `u[0] = ...` are hard errors.
#
# Usage: sh test/ast/p80_methods.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p80_methods.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p80methods.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/methods: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

if ! "$ctast" --allow-c-boundary test/ast/p80_methods/prog.ct -o "$work/m.c" \
        >"$work/m.log" 2>&1; then
    bad "methods compile" "$(sed -n '1,4p' "$work/m.log")"
elif ! "$cc" -Wall -Wextra -std=c99 "$work/m.c" -o "$work/m" 2>"$work/m.cc.err"; then
    bad "methods cc" "$(sed -n '1,4p' "$work/m.cc.err")"
elif [ -s "$work/m.cc.err" ]; then
    bad "methods warning-free cc" "$(head -2 "$work/m.cc.err")"
elif ! "$work/m" >"$work/m.out" 2>"$work/m.err"; then
    bad "methods run" "$(head -2 "$work/m.err")"
elif ! cmp -s "$work/m.out" test/ast/p80_methods/prog.expected.out; then
    bad "methods behaviour" "$(diff -u test/ast/p80_methods/prog.expected.out "$work/m.out" | head -10)"
else
    ok "methods (UTF-8 codepoint/byte API + UTF-16 JS core subset)"
fi

neg() {
    name=$1
    if "$ctast" --allow-c-boundary "test/ast/p80_methods/$name.ct" -o "$work/$name.c" \
            >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a write to an immutable string"
    elif grep -Fq "read-only" "$work/$name.log"; then
        ok "$name (rejected: read-only subscript)"
    else
        bad "$name" "missing diagnostic: $(head -2 "$work/$name.log")"
    fi
}
neg neg_write_index
neg neg_u16_write

[ "$fail" -eq 0 ] && echo "p80_methods: OK"
exit "$fail"
