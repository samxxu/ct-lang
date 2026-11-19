#!/bin/sh
# PH-73-R2: two units defining the same struct name with different fields are
# an ABI conflict; the build must refuse and name the duplicate.
#
# Usage: sh test/ast/p73_abi.sh <ct-ast>
set -u
ctast=${1:?usage: p73_abi.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p73abi.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

mkdir -p "$work/lib" "$work/out"
cat > "$work/lib/x.h.ct" <<'CT'
namespace lib;
pub struct T { pub int a; }
CT
cat > "$work/lib/y.h.ct" <<'CT'
namespace lib;
pub struct T { pub int a; pub int b; }
CT
cat > "$work/main.ct" <<'CT'
import lib::x;
import lib::y;
int main(void) { return 0; }
CT

out=$work/build.log
( cd "$work" && "$ctast" build -I . main.ct -o out/prog ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "duplicate struct 'T'" "$out"; then
    echo "FAIL p73/abi: conflicting struct layouts accepted" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p73/abi (duplicate struct refused)"
