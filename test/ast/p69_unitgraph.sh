#!/bin/sh
# PH-69-R1: `ct check` must accept import-bearing units, reuse the build unit
# graph, report cross-unit findings and write nothing.
#
# Usage: sh test/ast/p69_unitgraph.sh <ct-ast>
set -u
ctast=${1:?usage: p69_unitgraph.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p69ug.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
tmp=$work/src
fail=0

mkdir -p "$tmp/extra"
cat > "$tmp/extra/lib.h.ct" <<'CT'
pub int add(int a, int b) { return a + b; }
CT
cat > "$tmp/prog.ct" <<'CT'
import extra::lib;
int main(void) { return add(1, 2); }
CT
before=$(cd "$tmp" && ls -R | sort)

out=$work/pos.out
( cd "$root" && "$ctast" check --types "$tmp/prog.ct" ) >"$out" 2>&1 || {
    echo "FAIL p69/unitgraph: legal multi-unit check rejected" >&2
    sed 's/^/  /' "$out" | head -5 >&2
    fail=1
}
after=$(cd "$tmp" && ls -R | sort)
[ "$before" = "$after" ] || {
    echo "FAIL p69/unitgraph: ct check wrote files" >&2
    printf '%s\n' "$after" | head -10 >&2
    fail=1
}

cat > "$tmp/prog.ct" <<'CT'
import extra::lib;
int main(void) { return add("x", 1); }
CT
out=$work/neg.out
( cd "$root" && "$ctast" check --types "$tmp/prog.ct" ) >"$out" 2>&1
rc=$?
[ "$rc" -ne 0 ] || { echo "FAIL p69/unitgraph: cross-unit mismatch not fatal" >&2; fail=1; }
grep -q 'argument 1' "$out" || {
    echo "FAIL p69/unitgraph: no cross-unit argument diagnostic" >&2
    sed 's/^/  /' "$out" | head -5 >&2
    fail=1
}

( cd "$root" && "$ctast" check --types examples/08_map_binding/src/main.ct ) >"$work/real.out" 2>&1 || {
    echo "FAIL p69/unitgraph: examples/08 multi-unit check rejected" >&2
    sed 's/^/  /' "$work/real.out" | head -5 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p69/unitgraph (multi-unit check, no artifacts)"
