#!/bin/sh
# PH-71-R1: an owned object is released once. `delete` twice on the same
# variable is a hard error under `ct check`; a single delete stays clean.
#
# Usage: sh test/ast/p71_own.sh <ct-ast>
set -u
# PH-65: the fixtures write free `#include`s; this probe is not about the C
# boundary. SH-93 removed the cwd shortcut, so opt into allow explicitly.
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p71_own.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p71own.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/bad.ct" <<'CT'
#include <stdlib.h>
struct R { int x; } use Drop;
impl Drop for R { void drop() { } }
int main(void)
{
    own struct R *r = malloc(sizeof(struct R));
    delete r;
    delete r;
    return 0;
}
CT
cat > "$work/ok.ct" <<'CT'
#include <stdlib.h>
struct R { int x; } use Drop;
impl Drop for R { void drop() { } }
int main(void)
{
    own struct R *r = malloc(sizeof(struct R));
    delete r;
    return 0;
}
CT

out=$work/bad.out
( cd "$root" && "$ctast" check "$work/bad.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "double delete of an owned object" "$out"; then
    echo "FAIL p71/own: double delete not diagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/ok.out
( cd "$root" && "$ctast" check "$work/ok.ct" ) >"$out" 2>&1 || {
    echo "FAIL p71/own: single delete rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p71/own (double delete)"
