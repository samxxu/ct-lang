#!/usr/bin/env bash
# R2 probe: root export classification, L39-1/1w/2..6. No ABI header or
# archive is expected yet (R3/R5 add them); negatives must write nothing.
set -u
CT=${1:?usage: r2_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p39-r2.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
n=0

neg() {
    d=$1
    msg=$2
    n=$((n + 1))
    out="$tmp/neg$n"
    rootfile="$root/test/modules/errors/$d/root.h.ct"
    "$CT" build --lib "$rootfile" --outdir "$out" >"$out.out" 2>"$out.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "FAIL $d: expected non-zero" >&2
        fail=1
    elif ! grep -Fq -- "$msg" "$out.err"; then
        echo "FAIL $d: missing '$msg'" >&2
        sed 's/^/  /' "$out.err" >&2
        fail=1
    elif find "$out" -type f \( -name '*.a' -o -name '*.abi.h' \) 2>/dev/null | grep -q .; then
        echo "FAIL $d: wrote an ABI artefact" >&2
        fail=1
    fi
}

pos() {
    d=$1
    msg=$2
    n=$((n + 1))
    out="$tmp/pos$n"
    rootfile="$root/test/modules/errors/$d/root.h.ct"
    "$CT" build --lib "$rootfile" --outdir "$out" >"$out.out" 2>"$out.err"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAIL $d: expected exit 0 (rc=$rc)" >&2
        sed 's/^/  /' "$out.err" >&2
        fail=1
    elif ! grep -Fq -- "$msg" "$out.err"; then
        echo "FAIL $d: missing warning '$msg'" >&2
        sed 's/^/  /' "$out.err" >&2
        fail=1
    fi
}

neg p39_export_byvalue "cannot be exported: by-value struct"
neg p39_export_trait "cannot be exported: trait value"
neg p39_export_vec "cannot be exported: std type"
neg p39_main "a --lib build cannot contain 'main'"
neg p39_pub_global "pub globals are not supported"
neg p39_shim "cannot include the C shim of"
# L39-2 uses the empty root from the main fixture directory.
n=$((n + 1))
out="$tmp/noexports"
"$CT" build --lib "$root/test/modules/p39_lib/empty.h.ct" --outdir "$out" >"$out.out" 2>"$out.err"
if [ "$?" -eq 0 ] || ! grep -Fq 'no exported functions in' "$out.err"; then
    echo "FAIL p39_no_exports: missing L39-2" >&2
    fail=1
fi

pos p39_generic_skip "not exported: generic template has no external symbol"
pos p39_imported_units "pub function(s) are not part of the ABI surface"

if [ "$fail" -eq 0 ]; then
    echo "p39_r2: OK"
fi
exit "$fail"
