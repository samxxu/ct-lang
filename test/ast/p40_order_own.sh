#!/usr/bin/env bash
# R4 probe: defer/errdefer run before own release; own reference inside
# errdefer is a hard error.
set -u
CT=${1:?usage: p40_order_own.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p40-r4.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
"$CT" build "$root/test/ast/p40_order_own/prog.ct" --outdir "$tmp" -o "$tmp/prog" >"$tmp/build.out" 2>"$tmp/build.err"
if [ "$?" -ne 0 ]; then
    echo "FAIL p40/r4: build failed" >&2
    sed 's/^/  /' "$tmp/build.err" >&2
    exit 1
fi
"$tmp/prog" >"$tmp/actual" 2>"$tmp/run.err"
if [ "$?" -ne 0 ]; then
    echo "FAIL p40/r4: run failed" >&2
    fail=1
elif ! diff -u "$root/test/ast/p40_order_own/prog.expected.out" "$tmp/actual" >"$tmp/diff"; then
    echo "FAIL p40/r4: order differs" >&2
    cat "$tmp/diff" >&2
    fail=1
fi
"$CT" check "$root/test/ast/errors/p40_errdefer_own_ref/prog.ct" >"$tmp/neg.out" 2>"$tmp/neg.err"
if [ "$?" -eq 0 ] || ! grep -Fq 'an own object cannot be rolled back by errdefer' "$tmp/neg.err"; then
    echo "FAIL p40/r4: own reference in errdefer not rejected" >&2
    sed 's/^/  /' "$tmp/neg.err" >&2
    fail=1
fi
if [ "$fail" -eq 0 ]; then echo "p40_r4: OK"; fi
exit "$fail"
