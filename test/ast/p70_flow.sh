#!/bin/sh
# PH-70-R1: statement-level flow context under `ct check --semantics`:
# break/continue outside their construct is an error; the legal spellings
# (loop, switch) stay silent.
#
# Usage: sh test/ast/p70_flow.sh <ct-ast>
set -u
ctast=${1:?usage: p70_flow.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p70f.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/pos.ct" <<'CT'
int main(void)
{
    int i;
    for (i = 0; i < 3; i++) { if (i == 1) break; }
    for (i = 0; i < 3; i++) { if (i == 1) continue; }
    switch (i) { case 0: break; default: break; }
    return 0;
}
CT
cat > "$work/brk.ct" <<'CT'
int main(void) { break; return 0; }
CT
cat > "$work/cont.ct" <<'CT'
int main(void) { continue; return 0; }
CT

out=$work/pos.out
( cd "$root" && "$ctast" check --semantics "$work/pos.ct" ) >"$out" 2>&1 || {
    echo "FAIL p70/flow: legal flow rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

for c in brk cont; do
    out=$work/$c.out
    ( cd "$root" && "$ctast" check --semantics "$work/$c.ct" ) >"$out" 2>&1
    if [ $? -eq 0 ] || ! grep -q "only allowed in a loop" "$out"; then
        echo "FAIL p70/flow: $c not diagnosed" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    fi
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p70/flow (break/continue context)"
