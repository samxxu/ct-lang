#!/bin/sh
# PH-83 / S83c: the package conformance suite (E83-5).
#
# The versioned data under test/conformance/pkg/v1/ is fed to both the CT
# binary and an independent shell reference; every manifest case, index row and
# digest vector must agree with the expected row. A known difference must be
# registered in test/conformance/pkg/differences.md; the runner never silently
# skips one.
#
# This probe also pins the data's shape: v1 has 12 manifest cases, 3 digest
# vectors and the two index files, so an accidental deletion cannot turn the
# suite green with fewer cases.
#
# Usage: sh test/ast/p83_conformance.sh <ct-ast>
set -u
ctast=${1:?usage: p83_conformance.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p83conf.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p83/conformance: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

if ! command -v sha256sum >/dev/null 2>&1 && ! command -v shasum >/dev/null 2>&1; then
    echo "skip p83/conformance: no sha256sum/shasum for the shell reference" >&2
    exit 77
fi

data=test/conformance/pkg/v1
runner=test/conformance/pkg/run.sh
[ -f "$runner" ] || { bad "runner missing: $runner"; exit 1; }
[ -f test/conformance/pkg/differences.md ] || bad "differences.md missing"
[ -f "$data/README.md" ] || bad "data README missing"

# The data's own shape: 12 manifest cases, 3 digest vectors, 2 index files.
nman=$(grep -vc '^#' "$data/manifests/cases.tsv" 2>/dev/null || echo 0)
ndig=$(grep -vc '^#' "$data/digest/expect.tsv" 2>/dev/null || echo 0)
[ "$nman" = "12" ] && ok "v1 has 12 manifest cases" || bad "manifest case count" "$nman"
[ "$ndig" = "3" ] && ok "v1 has 3 digest vectors" || bad "digest vector count" "$ndig"
[ -f "$data/index/legal.index" ] && [ -f "$data/index/illegal.index" ] \
    && ok "v1 has the legal/illegal index files" || bad "index files"

if sh "$runner" --ct "$ctast" >"$work/run.out" 2>&1; then
    sed 's/^/  /' "$work/run.out"
    ok "CT and the shell reference agree on every case"
else
    bad "conformance failures" "$(grep -E '^FAIL|^conformance:' "$work/run.out" | head -8)"
fi

[ "$fail" -eq 0 ] && echo "p83_conformance: OK"
exit "$fail"
