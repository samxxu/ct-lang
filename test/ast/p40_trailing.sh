#!/usr/bin/env bash
# R5 probe: trailing declaration binding, $ alias, 4 shape negatives.
set -u
CT=${1:?usage: p40_trailing.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p40-r5.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
"$CT" build "$root/test/ast/p40_trailing/prog.ct" --outdir "$tmp" -o "$tmp/prog" >"$tmp/build.out" 2>"$tmp/build.err"
if [ "$?" -ne 0 ]; then
    echo "FAIL p40/r5: build failed" >&2
    sed 's/^/  /' "$tmp/build.err" >&2
    exit 1
fi
"$tmp/prog" >"$tmp/actual" 2>"$tmp/run.err"
if [ "$?" -ne 0 ] || ! diff -u "$root/test/ast/p40_trailing/prog.expected.out" "$tmp/actual" >"$tmp/diff"; then
    echo "FAIL p40/r5: output differs" >&2
    cat "$tmp/diff" 2>/dev/null >&2
    fail=1
fi
neg() {
    if [ -f "$root/test/ast/errors/$1" ]; then
        f="$root/test/ast/errors/$1"
    else
        f="$root/test/ast/errors/$1/prog.ct"
    fi
    msg=$2
    "$CT" check "$f" >"$tmp/n.out" 2>"$tmp/n.err"
    if [ "$?" -eq 0 ] || ! grep -Fq -- "$msg" "$tmp/n.err"; then
        echo "FAIL p40/r5 $1: missing '$msg'" >&2
        sed 's/^/  /' "$tmp/n.err" >&2
        fail=1
    fi
}
neg p40_trailing_multi 'a trailing defer needs a single declaration'
neg p40_trailing_assign 'a trailing defer needs a single declaration'
neg p40_trailing_for 'a trailing defer needs a single declaration'
neg p40_trailing_dollar "'\$' is read-only and only valid in the trailing block"
neg p40_trailing_nested 'an errdefer block cannot transfer control'
neg p40_trailing_header/prog.h.ct 'errdefer is not allowed here'
neg p40_trailing_switch 'errdefer is not allowed here'
neg p40_trailing_shadow "a trailing block cannot shadow the '\$' name"
if [ "$fail" -eq 0 ]; then echo "p40_r5: OK"; fi
exit "$fail"
