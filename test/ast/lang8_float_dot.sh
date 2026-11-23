#!/usr/bin/env bash
# LANG-8: a numeric literal immediately followed by `.` is a float, not a
# method call. The lexer keeps C's rule (`5.` is a float literal), so the
# parser sees the identifier `foo` where a suffix was expected; the diagnostic
# must say so instead of the generic `unexpected token`, and the spaced form
# `5 . foo()` must still reach method resolution.
#
# Usage: bash test/ast/lang8_float_dot.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: lang8_float_dot.sh <ct-ast>}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/lang8.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL lang8: %s\n' "$1" >&2; }

run() { # name, source, expected-rc, expected-substring
    name=$1
    src=$2
    want_rc=$3
    want=$4
    printf '%s\n' "$src" >"$tmp/$name.ct"
    "$CT" "$tmp/$name.ct" -o "$tmp/$name.c" >"$tmp/$name.out" 2>&1
    rc=$?
    if [ "$rc" -ne "$want_rc" ]; then
        bad "$name: exit $rc, want $want_rc ($(head -1 "$tmp/$name.out"))"
        return
    fi
    if [ -n "$want" ] && ! grep -Fq "$want" "$tmp/$name.out"; then
        bad "$name: missing '$want' ($(head -1 "$tmp/$name.out"))"
        return
    fi
    ok "$name"
}

run no_space 'int main(void) { int n = 5.foo(); return n; }' 1 \
    "a numeric literal followed by '.' is a float; add a space for a method call"
run spaced 'int main(void) { int n = 5 . foo(); return n; }' 1 \
    "no method 'foo' for type 'int'"
run float 'int main(void) { double d = 5.0; return (int)d; }' 0 ""
run range 'int main(void) { int a[] = 0..5($); return a[1]; }' 0 ""

printf 'lang8_float_dot: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
