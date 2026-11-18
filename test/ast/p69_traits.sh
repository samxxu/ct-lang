#!/bin/sh
# PH-69-R3: trait method selection is deterministic when one trait declares the
# method, and ambiguous when two used traits declare it. Ambiguity is an error
# under `ct check` (strict findings).
#
# Usage: sh test/ast/p69_traits.sh <ct-ast>
set -u
ctast=${1:?usage: p69_traits.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p69tr.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/one.ct" <<'CT'
trait A { int f(void); }
struct S { int x; } use A;
impl A for S { int f(void) { return 1; } }
int main(void) { struct S s; return s.f(); }
CT
cat > "$work/two.ct" <<'CT'
trait A { int f(void); }
trait B { int f(void); }
struct S { int x; } use A, B;
impl A for S { int f(void) { return 1; } }
impl B for S { int f(void) { return 2; } }
int main(void) { struct S s; return s.f(); }
CT

out=$work/one.out
( cd "$root" && "$ctast" check "$work/one.ct" ) >"$out" 2>&1 || {
    echo "FAIL p69/traits: single-trait dispatch rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

out=$work/two.out
( cd "$root" && "$ctast" check "$work/two.ct" ) >"$out" 2>&1
rc=$?
if [ "$rc" -eq 0 ] || ! grep -q "ambiguous method" "$out"; then
    echo "FAIL p69/traits: two-trait dispatch not rejected (rc=$rc)" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p69/traits (single + ambiguous trait dispatch)"
