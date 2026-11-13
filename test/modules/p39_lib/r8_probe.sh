#!/usr/bin/env bash
# R8 probe: --emit-c output is byte-identical to the S0 baseline after
# normalising the version token (the phase bump changes only that token).
# WRITE=1 rewrites baseline.sha; normal runs diff against it.
set -u
CT=${1:?usage: r8_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r8.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
base="$root/test/modules/p39_lib/baseline.sha"
actual="$tmp/actual.sha"
: > "$actual"
sha_norm() {
    sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/vX/g' "$1" | { if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi; } | awk '{print $1}'
}
run_one() {
    name=$1; shift
    out="$tmp/$name"
    mkdir -p "$out"
    ( cd "$root" && "$CT" build --emit-c "$@" -o "$out" ) >"$out.out" 2>"$out.err"
    if [ "$?" -ne 0 ]; then
        echo "FAIL r8: $name --emit-c failed" >&2
        sed 's/^/  /' "$out.err" >&2
        return 1
    fi
    for f in $(find "$out" -type f \( -name '*.c' -o -name '*.h' \) | sort); do
        rel=${f#"$out"/}
        printf '%s %s %s\n' "$name" "$rel" "$(sha_norm "$f")"
    done >> "$actual"
}
fail=0
run_one split test/modules/split/main.ct || fail=1
run_one p34_pub_generic test/modules/p34_pub_generic/main.ct || fail=1
run_one ns_dir --ns-root test/modules/ns_dir/src test/modules/ns_dir/src/main.ct test/modules/ns_dir/src/plain/extra.h.ct || fail=1
sort -o "$actual" "$actual"
if [ "${WRITE:-0}" = "1" ]; then
    cp "$actual" "$base"
    echo "wrote $base"
    exit 0
fi
if [ ! -f "$base" ]; then echo "FAIL r8: no baseline.sha" >&2; exit 1; fi
if ! diff -u "$base" "$actual" > "$tmp/diff"; then
    echo "FAIL r8: --emit-c output differs from baseline" >&2
    head -30 "$tmp/diff" >&2
    exit 1
fi
if [ "$fail" -eq 0 ]; then echo "p39_r8: OK"; fi
exit "$fail"
