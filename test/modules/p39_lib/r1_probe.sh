#!/usr/bin/env bash
# R1 red/green probe: --lib is accepted only by `ct build`; a root with no
# exports reports L39-2 and leaves no executable, archive or ABI header.
set -u
CT=${1:?usage: r1_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r1.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
empty="$root/test/modules/p39_lib/empty.h.ct"

"$CT" build --lib "$empty" --outdir "$tmp/out" >"$tmp/b.out" 2>"$tmp/b.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    echo "FAIL build --lib: expected L39-2 failure" >&2
    fail=1
elif ! grep -Fq 'no exported functions in' "$tmp/b.err"; then
    echo "FAIL build --lib: missing L39-2 message" >&2
    sed 's/^/  /' "$tmp/b.err" >&2
    fail=1
elif find "$tmp/out" -type f \( -name '*.a' -o -name '*.abi.h' -o -name 'a.out' \) 2>/dev/null | grep -q .; then
    echo "FAIL build --lib: wrote an artefact" >&2
    fail=1
fi

"$CT" compile --lib "$empty" >"$tmp/c.out" 2>"$tmp/c.err"
if [ "$?" -eq 0 ]; then
    echo "FAIL compile --lib: expected usage error" >&2
    fail=1
fi

"$CT" build --lib --emit-c "$empty" >"$tmp/e.out" 2>"$tmp/e.err"
if [ "$?" -eq 0 ]; then
    echo "FAIL --lib --emit-c: expected usage error" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "p39_r1: OK"
fi
exit "$fail"
