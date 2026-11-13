#!/usr/bin/env bash
# R4 probe: non-pub definitions/prototypes are static; each root export carries
# exactly one visibility("default") attribute; cc is called with hidden
# visibility. R5 adds the archive, not this probe.
set -u
CT=${1:?usage: r4_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r4.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
( cd "$root" && "$CT" build --lib test/modules/p39_lib/lib.h.ct --outdir "$tmp" ) >"$tmp/out" 2>"$tmp/err"
rc=$?
fail=0
if [ "$rc" -ne 0 ]; then
    echo "FAIL r4: build failed" >&2
    sed 's/^/  /' "$tmp/err" >&2
    exit 1
fi
[ -f "$tmp/lib.c" ] || { echo "FAIL r4: no lib.c" >&2; fail=1; }
[ -f "$tmp/lib.o" ] || { echo "FAIL r4: no lib.o" >&2; fail=1; }
if [ -f "$tmp/lib.c" ]; then
    n=$(grep -c '__attribute__((visibility("default")))' "$tmp/lib.c")
    [ "$n" -eq 3 ] || { echo "FAIL r4: visibility count $n, expected 3" >&2; fail=1; }
    grep -q '^static int helper(int);$' "$tmp/lib.c" || { echo "FAIL r4: helper prototype not static" >&2; fail=1; }
    grep -q '^static int helper(int x) {' "$tmp/lib.c" || { echo "FAIL r4: helper definition not static" >&2; fail=1; }
fi
grep -Fq -- '-fvisibility=hidden' "$tmp/out" || { echo "FAIL r4: cc line lacks -fvisibility=hidden" >&2; fail=1; }
if [ "$fail" -eq 0 ]; then echo "p39_r4: OK"; fi
exit "$fail"
