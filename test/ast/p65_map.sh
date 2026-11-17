#!/usr/bin/env bash
# PH-65 R4 probe: a `.m.ct` is the C boundary, so it may `#include` and define
# object-like constants, but a function-like macro would let a consumer pull
# arbitrary C in through expansion (D65-4).
# Usage: bash test/ast/p65_map.sh <ct-ast>
set -u
CT=${1:?usage: p65_map.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65map.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

cat >"$tmp/bad.m.ct" <<'CT'
#include <stdint.h>
#define F(x) ((x) + 1)
CT
cat >"$tmp/ok.m.ct" <<'CT'
#include <stdint.h>
#define K 3
CT

( cd "$tmp" && "$CT" check bad.m.ct ) >"$tmp/bad.out" 2>"$tmp/bad.err"
rc=$?
if [ "$rc" -ne 1 ]; then
    echo "FAIL p65/map: a function-like macro was accepted (rc=$rc)" >&2
    fail=1
elif ! grep -qF "a strict .m.ct allows #include and object-like macros only" "$tmp/bad.err"; then
    echo "FAIL p65/map: wrong message" >&2
    sed 's/^/  /' "$tmp/bad.err" | head -3 >&2
    fail=1
fi

if ! ( cd "$tmp" && "$CT" check ok.m.ct ) >"$tmp/ok.out" 2>"$tmp/ok.err"; then
    echo "FAIL p65/map: include + object-like macro was rejected" >&2
    sed 's/^/  /' "$tmp/ok.err" | head -3 >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p65/map"
exit "$fail"
