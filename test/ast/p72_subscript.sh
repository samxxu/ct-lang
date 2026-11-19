#!/bin/sh
# PH-72-R2 (LANG-4): a user-type subscript must fit the declared key type.
# `char *get(char *)` receiving `j[0]` is an error; `j["k"]` is fine, and an
# `int get(int)` accepts `j[0]`.
#
# Usage: sh test/ast/p72_subscript.sh <ct-ast>
set -u
# PH-65: the fixtures write free `#include`s; this probe is not about the C
# boundary. SH-93 removed the cwd shortcut, so opt into allow explicitly.
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p72_subscript.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p72sub.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/bad.ct" <<'CT'
#include <stdio.h>
struct J { int n; }
impl J { char *get(char *k) { (void)k; return "empty"; } }
int main(void) { struct J j = { 1 }; printf("[%s]\n", j[0]); return 0; }
CT
cat > "$work/ok.ct" <<'CT'
#include <stdio.h>
struct J { int n; }
impl J { char *get(char *k) { (void)k; return "ok"; } }
int main(void) { struct J j = { 1 }; printf("[%s]\n", j["k"]); return 0; }
CT
cat > "$work/int.ct" <<'CT'
#include <stdio.h>
struct J { int n; }
impl J { char *get(int k) { (void)k; return "int"; } }
int main(void) { struct J j = { 1 }; printf("[%s]\n", j[0]); return 0; }
CT

out=$work/bad.out
( cd "$root" && "$ctast" check --types "$work/bad.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "argument 1: expected 'char \*', got 'int'" "$out"; then
    echo "FAIL p72/subscript: int index accepted by char* get" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

for c in ok int; do
    out=$work/$c.out
    ( cd "$root" && "$ctast" check --types "$work/$c.ct" ) >"$out" 2>&1 || {
        echo "FAIL p72/subscript: $c rejected" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    }
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/subscript (key type)"
