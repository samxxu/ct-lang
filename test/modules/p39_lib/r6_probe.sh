#!/usr/bin/env bash
# R6 probe: root + imported unit form a library; a pure C consumer includes
# only <base>.abi.h, links the archive and runs. Imported `pub` stays out of
# the ABI surface (L39-6 warning).
set -u
CT=${1:?usage: r6_probe.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r6.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( cd "$root" && "$CT" build --lib -o "$tmp/libconsumer.a" --outdir "$tmp" test/modules/p39_lib/consumer/root.h.ct ) >"$tmp/build.out" 2>"$tmp/build.err"
rc=$?
fail=0
if [ "$rc" -ne 0 ]; then
    echo "FAIL r6: build failed" >&2
    sed 's/^/  /' "$tmp/build.err" >&2
    exit 1
fi
[ -f "$tmp/libconsumer.a" ] || { echo "FAIL r6: no archive" >&2; fail=1; }
if [ -f "$tmp/root.abi.h" ]; then
    if grep -q 'helper' "$tmp/root.abi.h"; then
        echo "FAIL r6: imported helper leaked into the ABI header" >&2
        fail=1
    fi
else
    echo "FAIL r6: no root.abi.h" >&2; fail=1
fi
if [ -f "$tmp/libconsumer.a" ]; then
    "$CC" -std=c99 -I "$tmp" "$root/test/modules/p39_lib/consumer/consumer.c" "$tmp/libconsumer.a" -o "$tmp/consumer" >"$tmp/link.out" 2>"$tmp/link.err"
    if [ "$?" -ne 0 ]; then
        echo "FAIL r6: C consumer did not link" >&2
        sed 's/^/  /' "$tmp/link.err" >&2
        fail=1
    elif ! "$tmp/consumer" >"$tmp/run.out" 2>"$tmp/run.err"; then
        echo "FAIL r6: C consumer failed to run" >&2
        fail=1
    elif ! diff -u "$root/test/modules/p39_lib/consumer/expected.out" "$tmp/run.out" >"$tmp/diff"; then
        echo "FAIL r6: output differs" >&2
        cat "$tmp/diff" >&2
        fail=1
    fi
fi
grep -Fq 'not part of the ABI surface' "$tmp/build.err" || { echo "FAIL r6: missing L39-6 warning" >&2; fail=1; }
if [ "$fail" -eq 0 ]; then echo "p39_r6: OK"; fi
exit "$fail"
