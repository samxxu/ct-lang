#!/bin/sh
# PH-70-R2: a local declared without an initializer, never assigned and read is
# an uninitialized read; assigning it (or taking its address) is enough.
#
# Usage: sh test/ast/p70_uninit.sh <ct-ast>
set -u
ctast=${1:?usage: p70_uninit.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p70i.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/bad.ct" <<'CT'
int main(void) { int x; return x; }
CT
cat > "$work/ok.ct" <<'CT'
int main(void) { int x; x = 1; return x; }
CT
cat > "$work/addr.ct" <<'CT'
int scan(int *p) { return *p; }
int main(void) { int x; scan(&x); return 0; }
CT

out=$work/bad.out
( cd "$root" && "$ctast" check --semantics "$work/bad.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "read of uninitialized variable" "$out"; then
    echo "FAIL p70/uninit: uninitialized read not diagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

for c in ok addr; do
    out=$work/$c.out
    ( cd "$root" && "$ctast" check --semantics "$work/$c.ct" ) >"$out" 2>&1 || {
        echo "FAIL p70/uninit: $c rejected" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    }
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p70/uninit (uninitialized read)"
