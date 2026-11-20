#!/bin/sh
# PH-80 S5a-2: literals and conversions (E80-2).
#
#   - `String s = "x"` binds an L1 immortal literal (`refs = -1`);
#   - `Str v = "x"` binds a borrowed view over the same read-only bytes;
#   - a file-scope initialiser and a `return "x"` bind the same way;
#   - `as_str` / `to_string` convert without copying the wrong direction;
#   - UTF-16 values only come from an explicit factory (implicit literal is a
#     hard error for both `U16String` and `U16Str`).
#
# Usage: sh test/ast/p80_literal.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p80_literal.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p80literal.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/literal: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

if ! "$ctast" --allow-c-boundary test/ast/p80_literal/literal.ct -o "$work/l.c" \
        >"$work/l.log" 2>&1; then
    bad "literal compile" "$(sed -n '1,4p' "$work/l.log")"
elif ! "$cc" -Wall -Wextra -std=c99 "$work/l.c" -o "$work/l" 2>"$work/l.cc.err"; then
    bad "literal cc" "$(sed -n '1,4p' "$work/l.cc.err")"
elif [ -s "$work/l.cc.err" ]; then
    bad "literal warning-free cc" "$(head -2 "$work/l.cc.err")"
elif ! "$work/l" >"$work/l.out" 2>"$work/l.err"; then
    bad "literal run" "$(head -2 "$work/l.err")"
elif ! cmp -s "$work/l.out" test/ast/p80_literal/expected.literal.out; then
    bad "literal behaviour" "$(diff -u test/ast/p80_literal/expected.literal.out "$work/l.out" | head -8)"
else
    ok "literal (immortal String, borrowed Str, conversions, UTF-16 factories)"
fi

neg() {
    name=$1
    if "$ctast" --allow-c-boundary "test/ast/p80_literal/$name.ct" -o "$work/$name.c" \
            >"$work/$name.log" 2>&1; then
        bad "$name" "accepted an implicit UTF-16 literal"
    elif grep -Fq "UTF-16 string literal is not implicit" "$work/$name.log"; then
        ok "$name (rejected: UTF-16 string literal is not implicit)"
    else
        bad "$name" "missing diagnostic: $(head -2 "$work/$name.log")"
    fi
}
neg neg_utf16_literal
neg neg_u16str_literal

[ "$fail" -eq 0 ] && echo "p80_literal: OK"
exit "$fail"
