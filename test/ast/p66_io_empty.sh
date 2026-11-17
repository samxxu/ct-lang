#!/usr/bin/env bash
# PH-66 R3 probe: an empty program carries no system header in EITHER mode.
# Compile mode used to splice the whole built-in layer, which brought
# <stdio.h>/<stdlib.h>/<string.h> (and the layer's code) into every product.
# Usage: bash test/ast/p66_io_empty.sh <ct-ast>
set -u
CT=${1:?usage: p66_io_empty.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p66emp.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/o"

cat >"$tmp/empty.ct" <<'CT'
int main(void)
{
    return 0;
}
CT
cat >"$tmp/vec.ct" <<'CT'
int main(void)
{
    Vec<int> v;
    v.h = 0;
    v.push(1);
    return v.len();
}
CT

n_sys() { grep -c '#include *<' "$1" 2>/dev/null || true; }

# compile mode, with the layer discoverable: the discriminating case.
CT_STD_DIR="$root/lib/std" "$CT" "$tmp/empty.ct" -o "$tmp/o/empty.c" >"$tmp/e1.log" 2>"$tmp/e1.err" || {
    echo "FAIL p66/io-empty: compile mode failed" >&2; sed 's/^/  /' "$tmp/e1.err" | head -3 >&2; exit 1; }
n=$(n_sys "$tmp/o/empty.c")
[ "$n" = "0" ] || { echo "FAIL p66/io-empty: compile mode empty program has $n system header(s)" >&2; grep -n '#include *<' "$tmp/o/empty.c" >&2; fail=1; }

# build mode: already pruned before PH-66; keep it from regressing.
( cd "$root" && env -u CT_C_BOUNDARY "$CT" build --emit-c "$tmp/empty.ct" -o "$tmp/o" ) >"$tmp/b.log" 2>"$tmp/b.err" || {
    echo "FAIL p66/io-empty: build mode failed" >&2; sed 's/^/  /' "$tmp/b.err" | head -3 >&2; exit 1; }
n=$(n_sys "$tmp/o/empty.c")
[ "$n" = "0" ] || { echo "FAIL p66/io-empty: build mode empty program has $n system header(s)" >&2; fail=1; }

# A program that uses a container must still get the layer.
CT_STD_DIR="$root/lib/std" "$CT" "$tmp/vec.ct" -o "$tmp/o/vec.c" >"$tmp/v.log" 2>"$tmp/v.err" || {
    echo "FAIL p66/io-empty: the Vec program no longer compiles" >&2; sed 's/^/  /' "$tmp/v.err" | head -3 >&2; exit 1; }
if ! grep -q 'Vec_int_push' "$tmp/o/vec.c"; then
    echo "FAIL p66/io-empty: the Vec layer was pruned away from a Vec program" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p66/io-empty"
exit "$fail"
