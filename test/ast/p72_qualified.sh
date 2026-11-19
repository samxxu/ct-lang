#!/bin/sh
# PH-72-R6 (SH-18 + LANG-15): qualified names work in both positions --
# `ns::Type` in a type position and `Type::Member` as a value. These were
# fixed in v0.59.0; the probe pins the fixtures and the absence of the old
# "qualified type names are not supported" diagnostic.
#
# Usage: sh test/ast/p72_qualified.sh <ct-ast>
set -u
ctast=${1:?usage: p72_qualified.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p72q.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

for d in 271_qualified_enum 272_qualified_enum_xunit 273_qualified_type; do
    out=$work/$d.out
    ( cd "$root" && "$ctast" check "test/ast/$d/prog.ct" ) >"$out" 2>&1 || {
        echo "FAIL p72/qualified: $d rejected" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
        continue
    }
    if grep -q "qualified type names are not supported" "$out"; then
        echo "FAIL p72/qualified: $d hit the old diagnostic" >&2
        fail=1
    fi
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/qualified (type + value positions)"
