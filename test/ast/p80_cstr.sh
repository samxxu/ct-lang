#!/bin/sh
# PH-80 S5a-4: the C boundary (E80-5, D-013 §2).
#
#   - `.data` is the read-only raw view, indexable only, with no NUL guarantee;
#   - `cstr()` is the only C-boundary exit and appends the terminator;
#   - `printf("%s", s.data)` is a hard error, as is letting `.data` escape as a
#     value, and writing through it;
#   - a sub-view's `.data` never gains a terminator of its own.
#
# Usage: sh test/ast/p80_cstr.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p80_cstr.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p80cstr.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/cstr: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

if ! "$ctast" --allow-c-boundary test/ast/p80_cstr/prog.ct -o "$work/c.c" \
        >"$work/c.log" 2>&1; then
    bad "cstr compile" "$(sed -n '1,4p' "$work/c.log")"
elif ! "$cc" -Wall -Wextra -std=c99 "$work/c.c" -o "$work/c" 2>"$work/c.cc.err"; then
    bad "cstr cc" "$(sed -n '1,4p' "$work/c.cc.err")"
elif [ -s "$work/c.cc.err" ]; then
    bad "cstr warning-free cc" "$(head -2 "$work/c.cc.err")"
elif ! "$work/c" >"$work/c.out" 2>"$work/c.err"; then
    bad "cstr run" "$(head -2 "$work/c.err")"
elif ! cmp -s "$work/c.out" test/ast/p80_cstr/prog.expected.out; then
    bad "cstr behaviour" "$(diff -u test/ast/p80_cstr/prog.expected.out "$work/c.out" | head -8)"
else
    ok "cstr (.data byte view, cstr() terminator, sub-view has no NUL)"
fi

neg() {
    name=$1; pattern=$2
    if "$ctast" --allow-c-boundary "test/ast/p80_cstr/$name.ct" -o "$work/$name.c" \
            >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a negative"
    elif grep -Fq "$pattern" "$work/$name.log"; then
        ok "$name (rejected: $pattern)"
    else
        bad "$name" "missing diagnostic '$pattern': $(head -2 "$work/$name.log")"
    fi
}
neg neg_printf_data "read-only raw view without a NUL guarantee"
neg neg_data_value "read-only raw view without a NUL guarantee"
neg neg_data_write "immutable"
# P-3.5 (SH-117): a by-value String / Str handle is a 16-byte struct, never a
# `char *`. The declaration initialiser, the return position and a variadic
# position each used to accept it and emit invalid C (`char *p = s;`,
# `char *__ct_sret = s;`, `printf("%s", s)`).
neg neg_ptr_assign "cannot convert 'String' to"
neg neg_ptr_str_assign "cannot convert 'Str' to"
neg neg_ptr_return "cannot convert 'String' to"
neg neg_ptr_vararg "cannot pass a 'String' handle to C function"

[ "$fail" -eq 0 ] && echo "p80_cstr: OK"
exit "$fail"
