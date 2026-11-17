#!/usr/bin/env bash
# PH-65 R5 probe: a `.h.ct` that owns `<base>.shim.h` publishes it in the
# generated header, `ct build` adds the shim directory to `-I`, and two units
# with the same base both publishing a shim is a hard error (L65-6).
# Usage: bash test/ast/p65_hdr_shim.sh <ct-ast>
set -u
CT=${1:?usage: p65_hdr_shim.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65hdr.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/out"

if ! ( cd "$root" && "$CT" build --lib test/modules/p65_hdr_shim/lib.h.ct --outdir "$tmp/out" ) \
        >"$tmp/b.log" 2>"$tmp/b.err"; then
    echo "FAIL p65/hdr-shim: the header unit did not build" >&2
    sed 's/^/  /' "$tmp/b.err" | head -4 >&2
    exit 1
fi
if ! grep -q '#include "lib.shim.h"' "$tmp/out/lib.h"; then
    echo "FAIL p65/hdr-shim: the public header does not include the shim" >&2
    fail=1
fi
if ! grep -q -- "-I" "$tmp/b.log" || ! grep -q "p65_hdr_shim" "$tmp/b.log"; then
    echo "FAIL p65/hdr-shim: the build did not add the shim directory to -I" >&2
    head -3 "$tmp/b.log" >&2
    fail=1
fi

if ( cd "$root" && "$CT" build test/modules/p65_hdr_shim/dup_a/lib.h.ct \
        test/modules/p65_hdr_shim/dup_b/lib.h.ct --outdir "$tmp/dup" ) \
        >"$tmp/d.log" 2>"$tmp/d.err"; then
    echo "FAIL p65/hdr-shim: two shims with the same base were accepted" >&2
    fail=1
elif ! grep -q "shim base name 'lib' is ambiguous" "$tmp/d.err"; then
    echo "FAIL p65/hdr-shim: wrong ambiguity message" >&2
    sed 's/^/  /' "$tmp/d.err" | head -3 >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p65/hdr-shim"
exit "$fail"
