#!/bin/sh
# PH-75-R2 (SH-65/SH-67): a closure cannot be a method argument yet. The
# compiler must say so instead of exiting 0 (bound variable wrote an undeclared
# identifier; a literal reached an internal fallback).
#
# Usage: sh test/ast/p75_closure_neg.sh <ct-ast>
set -u
ctast=${1:?usage: p75_closure_neg.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p75n.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/lit.ct" <<'CT'
trait Runner { int run(int (*f)(int)); }
struct R { int z; } use Runner;
impl Runner for R { int run(int (*f)(int)) { return f(1); } }
int main(void) { struct R r; return r.run((int x) => x + 1); }
CT
cat > "$work/var.ct" <<'CT'
trait Runner { int run(int (*f)(int)); }
struct R { int z; } use Runner;
impl Runner for R { int run(int (*f)(int)) { return f(1); } }
int main(void) { struct R r; int (*f)(int) = (int x) => x + 1; return r.run(f); }
CT

for c in lit var; do
    out=$work/$c.out
    ( cd "$root" && "$ctast" check --types "$work/$c.ct" ) >"$out" 2>&1
    if [ $? -eq 0 ] || ! grep -q "cannot be passed to a method argument" "$out"; then
        echo "FAIL p75/closure-neg: $c not refused" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    fi
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p75/closure-neg (literal + bound variable)"
