#!/bin/sh
# PH-73-R3: the language spec documents field-level visibility and the ABI
# consequences (the behaviour R1 implements).
#
# Usage: sh test/ast/p73_docs.sh <ct-ast>
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
spec="$root/docs/language-spec.md"
fail=0

grep -q "字段级可见性" "$spec" || { echo "FAIL p73/docs: section missing" >&2; fail=1; }
grep -q "CT_UNIT_PRIVATE" "$spec" || { echo "FAIL p73/docs: internal macro undocumented" >&2; fail=1; }
grep -q "pub struct Conn;" "$spec" || { echo "FAIL p73/docs: opaque handle missing" >&2; fail=1; }
grep -q "ABI：" "$spec" || { echo "FAIL p73/docs: ABI note missing" >&2; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "OK p73/docs (field visibility documented)"
