#!/bin/sh
# PH-74-R3 (SH-79): `--lib --emit-map` writes the file; a build map's `file`
# names the entry unit rather than the builtin layer.
#
# Usage: sh test/ast/p74_map.sh <ct-ast>
set -u
ctast=${1:?usage: p74_map.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p74map.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

mkdir -p "$work/lib" "$work/out"
cat > "$work/lib/lib.h.ct" <<'CT'
namespace lib;
pub struct Box { int n; }
pub int box_get(struct Box *b) { return b->n; }
CT
( cd "$work" && "$ctast" build --lib --emit-map libmap.json -I . lib/lib.h.ct -o out/lib.a ) >"$work/lib.log" 2>&1
if [ ! -s "$work/libmap.json" ]; then
    echo "FAIL p74/map: --lib --emit-map wrote no file" >&2
    sed 's/^/  /' "$work/lib.log" | head -4 >&2
    fail=1
fi

cat > "$work/main.ct" <<'CT'
import lib::lib;
int main(void) { return 0; }
CT
( cd "$work" && "$ctast" build --emit-map nb.json -I . main.ct -o out/prog ) >"$work/b.log" 2>&1
if ! grep -q '"file":"main.ct"' "$work/nb.json" 2>/dev/null; then
    echo "FAIL p74/map: build map file is not the entry unit" >&2
    grep -o '"file":"[^"]*"' "$work/nb.json" 2>/dev/null | head -2 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p74/map (lib facet + entry file)"
