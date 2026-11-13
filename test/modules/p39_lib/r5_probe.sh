#!/usr/bin/env bash
# R5 probe: lib<base>.a exists; nm -g --defined-only normalised equals the
# export set plus expected.internal (D-002 default A).
set -u
CT=${1:?usage: r5_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r5.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( cd "$root" && "$CT" build --lib -o "$tmp/libtest.a" --outdir "$tmp" test/modules/p39_lib/lib.h.ct ) >"$tmp/out" 2>"$tmp/err"
rc=$?
fail=0
if [ "$rc" -ne 0 ]; then
    echo "FAIL r5: build failed" >&2
    sed 's/^/  /' "$tmp/err" >&2
    exit 1
fi
[ -f "$tmp/libtest.a" ] || { echo "FAIL r5: no archive" >&2; exit 1; }
"${NM:-nm}" -g --defined-only "$tmp/libtest.a" 2>"$tmp/nm.err" \
    | awk 'NF >= 3 && $2 ~ /^[TDBR]$/ { print $3 }' \
    | sed 's/^_//' | sort -u > "$tmp/actual"
{ printf 'add\nname\npoint_x\n'; cat "$root/test/modules/p39_lib/expected.internal"; } | sort -u > "$tmp/want"
if ! diff -u "$tmp/want" "$tmp/actual" > "$tmp/diff"; then
    echo "FAIL r5: symbol surface differs" >&2
    head -30 "$tmp/diff" >&2
    fail=1
fi
if [ "$fail" -eq 0 ]; then echo "p39_r5: OK"; fi
exit "$fail"
