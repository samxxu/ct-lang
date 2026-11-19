#!/bin/sh
# PH-70-R3: code after return/break/continue cannot execute; `ct check
# --semantics` reports it. Labels and empty statements stay legal.
#
# Usage: sh test/ast/p70_unreach.sh <ct-ast>
set -u
ctast=${1:?usage: p70_unreach.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p70u.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/bad.ct" <<'CT'
int main(void) { return 0; int x = 1; return x; }
CT
cat > "$work/ok.ct" <<'CT'
int main(void)
{
    int i = 0;
    while (i < 3) { i = i + 1; if (i == 2) break; }
    return i;
}
CT

out=$work/bad.out
( cd "$root" && "$ctast" check --semantics "$work/bad.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "unreachable code after a jump" "$out"; then
    echo "FAIL p70/unreach: unreachable code not diagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/ok.out
( cd "$root" && "$ctast" check --semantics "$work/ok.ct" ) >"$out" 2>&1 || {
    echo "FAIL p70/unreach: legal code rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p70/unreach (unreachable after jump)"
