#!/bin/sh
# PH-70-R2: a non-void function whose body has neither `return` nor a loop
# falls off the end; `ct check --semantics` reports it. A loop (e.g.
# `while (1)`) or an explicit return stays silent.
#
# Usage: sh test/ast/p70_return.sh <ct-ast>
set -u
ctast=${1:?usage: p70_return.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p70r.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/bad.ct" <<'CT'
int f(void) { int x = 1; }
int main(void) { return f(); }
CT
cat > "$work/loop.ct" <<'CT'
int g(void) { while (1) { } }
int main(void) { return 0; }
CT
cat > "$work/ok.ct" <<'CT'
int h(void) { return 1; }
int main(void) { return h(); }
CT

out=$work/bad.out
( cd "$root" && "$ctast" check --semantics "$work/bad.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "non-void function may not return a value" "$out"; then
    echo "FAIL p70/return: missing return not diagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

for c in loop ok; do
    out=$work/$c.out
    ( cd "$root" && "$ctast" check --semantics "$work/$c.ct" ) >"$out" 2>&1 || {
        echo "FAIL p70/return: $c rejected" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    }
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p70/return (missing return)"
