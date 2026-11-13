#!/usr/bin/env bash
# R7 probe: two independent builds produce byte-identical archives.
set -u
CT=${1:?usage: r7_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r7.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
sha() { if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'; else shasum -a 256 "$1" | awk '{print $1}'; fi; }
fail=0
for n in 1 2; do
    mkdir -p "$tmp/a$n"
    ( cd "$root" && "$CT" build --lib -o "$tmp/a$n/libtest.a" --outdir "$tmp/a$n" test/modules/p39_lib/lib.h.ct ) >"$tmp/a$n.out" 2>"$tmp/a$n.err"
    if [ "$?" -ne 0 ]; then
        echo "FAIL r7: build $n failed" >&2
        sed 's/^/  /' "$tmp/a$n.err" >&2
        fail=1
    elif [ ! -f "$tmp/a$n/libtest.a" ]; then
        echo "FAIL r7: build $n wrote no archive" >&2
        fail=1
    fi
done
if [ "$fail" -eq 0 ]; then
    h1=$(sha "$tmp/a1/libtest.a")
    h2=$(sha "$tmp/a2/libtest.a")
    if [ "$h1" != "$h2" ]; then
        echo "FAIL r7: archive differs across builds" >&2
        echo "  $h1" >&2
        echo "  $h2" >&2
        fail=1
    fi
fi
if [ "$fail" -eq 0 ]; then echo "p39_r7: OK"; fi
exit "$fail"
