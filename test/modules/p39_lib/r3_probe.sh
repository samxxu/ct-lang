#!/usr/bin/env bash
# R3 probe: <base>.abi.h contract. The byte golden lives in
# lib.expected.abi.h once R3 is implemented; before that the probe still
# rejects a missing header.
set -u
CT=${1:?usage: r3_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r3.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
hdr="$tmp/lib.abi.h"
( cd "$root" && "$CT" build --lib test/modules/p39_lib/lib.h.ct --outdir "$tmp" ) >"$tmp/out" 2>"$tmp/err"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL r3: build failed" >&2
    sed 's/^/  /' "$tmp/err" >&2
    exit 1
fi
fail=0
[ -f "$hdr" ] || { echo "FAIL r3: no lib.abi.h" >&2; fail=1; }
if [ -f "$hdr" ]; then
    grep -q '^#define LIB_ABI_VERSION 1$' "$hdr" || { echo "FAIL r3: version macro" >&2; fail=1; }
    grep -Eq '^#define LIB_ABI_HASH 0x[0-9a-f]{8}$' "$hdr" || { echo "FAIL r3: hash macro" >&2; fail=1; }
    grep -q '^struct Point;$' "$hdr" || { echo "FAIL r3: struct forward" >&2; fail=1; }
    grep -q '^int add(int, int);$' "$hdr" || { echo "FAIL r3: add prototype" >&2; fail=1; }
    grep -q '^const char \* name(void);$' "$hdr" || { echo "FAIL r3: name prototype" >&2; fail=1; }
    grep -q '^int point_x(struct Point \*);$' "$hdr" || { echo "FAIL r3: point_x prototype" >&2; fail=1; }
    if grep -Eq '_iface|_vtbl|Vec_|Map_|Str_' "$hdr"; then
        echo "FAIL r3: forbidden ABI spelling" >&2
        fail=1
    fi
fi
if [ -f "$root/test/modules/p39_lib/lib.expected.abi.h" ] && [ -f "$hdr" ] \
   && ! cmp -s "$hdr" "$root/test/modules/p39_lib/lib.expected.abi.h"; then
    echo "FAIL r3: header differs from lib.expected.abi.h" >&2
    diff -u "$root/test/modules/p39_lib/lib.expected.abi.h" "$hdr" | head -20 >&2
    fail=1
fi
if [ "$fail" -eq 0 ]; then echo "p39_r3: OK"; fi
exit "$fail"
