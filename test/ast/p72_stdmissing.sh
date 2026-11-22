#!/bin/sh
# PH-72-R5 (SH-76) + DOC-87 Stage 1: the built-in layer lookup.
#
# When the builtin layer is missing (cwd has no lib/core and no env var), a
# generic type must name the cause, not report "expected a field name"; a bare
# builtin generic is refused instead of emitting bad C.
#
# DOC-87 Stage 1 renames the directory to lib/core and the key to CT_CORE_DIR.
# This is also the compatibility-window test: CT_STD_DIR still resolves (with one
# deprecation warning), a CT_CORE_DIR that points at a missing directory is a
# hard error (never a silent fallback), and the old lib/std path still resolves
# with a warning.
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

# 1. Neither variable set and no ./lib/core: the diagnostic names the new key
#    (and the legacy one) instead of blaming the field syntax.
out=$work/gen.out
( cd "$work" && env -u CT_CORE_DIR -u CT_STD_DIR "$ctast" check "$work/gen.ct" ) >"$out" 2>&1
if ! grep -q "unresolved generic type 'Map'" "$out" \
        || ! grep -q "CT_CORE_DIR" "$out" \
        || ! grep -q "CT_STD_DIR" "$out" \
        || grep -q "expected a field name" "$out"; then
    echo "FAIL p72/stdmissing: generic misdiagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 2. CT_CORE_DIR is the new key: it finds the layer and prints no deprecation.
out=$work/core.out
if ! ( cd "$work" && env -u CT_STD_DIR CT_CORE_DIR="$root/lib/core" "$ctast" check "$work/gen.ct" ) \
        >"$out" 2>&1; then
    echo "FAIL p72/stdmissing: CT_CORE_DIR did not find the layer" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
elif grep -q "deprecated" "$out"; then
    echo "FAIL p72/stdmissing: CT_CORE_DIR run printed a deprecation warning" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 3. Compatibility window: CT_STD_DIR=<repo>/lib/core still resolves, with one
#    warning.
out=$work/legacy.out
if ! ( cd "$work" && env -u CT_CORE_DIR CT_STD_DIR="$root/lib/core" "$ctast" check "$work/gen.ct" ) \
        >"$out" 2>&1; then
    echo "FAIL p72/stdmissing: CT_STD_DIR compatibility window is closed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
elif ! grep -q "CT_STD_DIR is deprecated; use CT_CORE_DIR" "$out"; then
    echo "FAIL p72/stdmissing: CT_STD_DIR was accepted silently" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 4. Both set and different: CT_CORE_DIR wins; the legacy key still warns.
out=$work/both.out
if ! ( cd "$work" && CT_CORE_DIR="$root/lib/core" CT_STD_DIR="$work/nosuchlay" \
        "$ctast" check "$work/gen.ct" ) >"$out" 2>&1; then
    echo "FAIL p72/stdmissing: CT_CORE_DIR did not win over CT_STD_DIR" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
elif ! grep -q "CT_STD_DIR is deprecated; use CT_CORE_DIR" "$out"; then
    echo "FAIL p72/stdmissing: conflicting keys warned about nothing" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 5. CT_CORE_DIR pointing at a missing directory is a hard error, not a silent
#    fallback to the working tree.
out=$work/badcore.out
( cd "$root" && env -u CT_STD_DIR CT_CORE_DIR="$work/nosuchlay" \
        "$ctast" check "$work/gen.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "CT_CORE_DIR points to a missing directory" "$out"; then
    echo "FAIL p72/stdmissing: a bogus CT_CORE_DIR was not a hard error" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 6. The old lib/std path still resolves in the window, with a warning.
mkdir -p "$work/old/lib" && ln -s "$root/lib/core" "$work/old/lib/std"
out=$work/oldpath.out
if ! ( cd "$work/old" && env -u CT_CORE_DIR -u CT_STD_DIR "$ctast" check "$work/gen.ct" ) \
        >"$out" 2>&1; then
    echo "FAIL p72/stdmissing: lib/std compatibility window is closed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
elif ! grep -q "lib/std is deprecated" "$out"; then
    echo "FAIL p72/stdmissing: lib/std was accepted silently" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 7. A bare builtin generic is still refused.
out=$work/bare.out
( cd "$work" && env -u CT_CORE_DIR -u CT_STD_DIR "$ctast" check "$work/bare.ct" ) >"$out" 2>&1
if ! grep -q "needs type arguments in a type position" "$out"; then
    echo "FAIL p72/stdmissing: bare generic accepted" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

# 8. A non-generic builtin type is still accepted.
out=$work/str.out
( cd "$work" && env -u CT_CORE_DIR CT_CORE_DIR="$root/lib/core" \
        "$ctast" check "$work/str.ct" ) >"$out" 2>&1 || {
    echo "FAIL p72/stdmissing: non-generic type rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/stdmissing (builtin layer diagnostics, CT_CORE_DIR and fallbacks)"
