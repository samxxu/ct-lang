#!/bin/sh
# PH-72-R5 (SH-76): when the builtin layer is missing (cwd has no lib/std),
# a generic type must name the cause, not report "expected a field name";
# a bare builtin generic is refused instead of emitting bad C.
#
# Usage: sh test/ast/p72_stdmissing.sh <ct-ast>
set -u
ctast=${1:?usage: p72_stdmissing.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p72sm.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/gen.ct" <<'CT'
struct A { Map<char *, int> *m; };
int main(void) { return 0; }
CT
cat > "$work/bare.ct" <<'CT'
struct A { Map *m; };
int main(void) { return 0; }
CT
cat > "$work/str.ct" <<'CT'
struct A { Str *s; };
int main(void) { return 0; }
CT

out=$work/gen.out
( cd "$work" && env -u CT_STD_DIR "$ctast" check "$work/gen.ct" ) >"$out" 2>&1
if ! grep -q "unresolved generic type 'Map'" "$out" \
        || ! grep -q "CT_STD_DIR" "$out" || grep -q "expected a field name" "$out"; then
    echo "FAIL p72/stdmissing: generic misdiagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/bare.out
( cd "$work" && env -u CT_STD_DIR "$ctast" check "$work/bare.ct" ) >"$out" 2>&1
if ! grep -q "needs type arguments in a type position" "$out"; then
    echo "FAIL p72/stdmissing: bare generic accepted" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/str.out
( cd "$work" && env -u CT_STD_DIR "$ctast" check "$work/str.ct" ) >"$out" 2>&1 || {
    echo "FAIL p72/stdmissing: non-generic type rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/stdmissing (builtin layer diagnostics)"
