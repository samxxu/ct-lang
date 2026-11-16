#!/bin/sh
# Can this C compiler link a program with -fsanitize=address,undefined?
#
# Ubuntu's `clang` package does not ship the sanitizer runtime; it lives in
# `libclang-rt-<major>-dev`. A probe that needs ASAN must skip (and say so)
# rather than report a compiler defect -- CI installs the runtime package so
# the skip never hides coverage there.
#
# Usage: sh test/ast/sanitizer_ok.sh <cc>
set -u
cc=${1:-cc}
w=$(mktemp -d "${TMPDIR:-/tmp}/san-ok.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT
printf 'int main(void) { return 0; }\n' >"$w/t.c"
if "$cc" -fsanitize=address,undefined "$w/t.c" -o "$w/t" >"$w/log" 2>&1; then
    exit 0
fi
exit 1
