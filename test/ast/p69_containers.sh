#!/bin/sh
# PH-69-R4: builtin container methods are judged through their struct instance
# (`Vec<int>` -> `struct Vec_int`), so `push` on the wrong element type errors.
#
# Usage: sh test/ast/p69_containers.sh <ct-ast>
set -u
ctast=${1:?usage: p69_containers.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p69ct.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/neg.ct" <<'CT'
int main(void) { Vec<int> v = {1, 2}; v.push("x"); return 0; }
CT
cat > "$work/pos.ct" <<'CT'
int main(void) { Vec<int> v = {1, 2}; v.push(3); return 0; }
CT

out=$work/neg.out
( cd "$root" && "$ctast" check --types "$work/neg.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "argument 1: expected 'int', got 'char \\*'" "$out"; then
    echo "FAIL p69/containers: wrong element type not diagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/pos.out
( cd "$root" && "$ctast" check --types "$work/pos.ct" ) >"$out" 2>&1 || {
    echo "FAIL p69/containers: legal push rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p69/containers (builtin container args)"
