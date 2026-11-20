#!/bin/sh
# PH-79 S3d: the `T a[]` migration warnings (E79-1).
#
#   - `T a[]` as a parameter or a record field warns and names both fixes;
#   - `T a[]` with no initializer warns, and `ct check` (strict) turns that
#     warning into an error;
#   - `T a[] = {...}` stays an inferred-length C array, silently;
#   - `T[]` (the slice spelling) is silent, and `T a[N]` is a plain C array.
#
# Usage: sh test/ast/p79_migrate.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p79_migrate.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p79migrate.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p79/migrate: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

build() {
    rm -rf "$work/.ctbuild" "$work/.ctcache"
    ( cd "$work" && "$ctast" build "$1.ct" -o "$work/$1.bin" ) >"$work/$1.log" 2>&1
}
check() {
    rm -rf "$work/.ctcache"
    ( cd "$work" && "$ctast" check "$1.ct" ) >"$work/$1.chk" 2>&1
}
run_ok() {
    if ! build "$1"; then bad "$2" "$(sed -n '1,4p' "$work/$1.log")"
    elif ! "$work/$1.bin"; then bad "$2" "the built program exited non-zero"
    else ok "$2"; fi
}
expect_warn() {
    if ! build "$1"; then bad "$2" "the warning fixture did not build: $(sed -n '1,3p' "$work/$1.log")"
    elif ! grep -Fq "$3" "$work/$1.log"; then bad "$2" "warning missing: $(sed -n '1,3p' "$work/$1.log")"
    else ok "$2"; fi
}
expect_silent() {
    if ! build "$1"; then bad "$2" "the fixture did not build: $(sed -n '1,3p' "$work/$1.log")"
    elif grep -Fq "$3" "$work/$1.log"; then bad "$2" "unexpected warning"
    else ok "$2"; fi
}

dep='is deprecated; write'

cat >"$work/param.ct" <<'EOF'
int total(int xs[], int n) { return n; }
int main(void) { return total(0, 0); }
EOF
expect_warn param "E79-1: a T a[] parameter warns" "'T a[]' $dep"

cat >"$work/field.ct" <<'EOF'
struct S { int xs[]; };
int main(void) { return 0; }
EOF
expect_warn field "E79-1: a T a[] field warns" "'T a[]' $dep"

cat >"$work/noinit.ct" <<'EOF'
int main(void)
{
    int xs[];
    return 0;
}
EOF
if check noinit; then
    bad "E79-1: ct check escalates the T a[] no-initializer warning"
elif ! grep -Fq "'T a[]' $dep" "$work/noinit.chk"; then
    bad "E79-1: ct check escalates the T a[] no-initializer warning" \
        "diagnostic missing: $(sed -n '1,3p' "$work/noinit.chk")"
else
    ok "E79-1: ct check escalates the T a[] no-initializer warning"
fi
build noinit || true
if ! grep -Fq "'T a[]' $dep" "$work/noinit.log"; then
    bad "E79-1: ct build still shows the T a[] no-initializer warning" \
        "warning missing: $(sed -n '1,3p' "$work/noinit.log")"
else
    ok "E79-1: ct build still shows the T a[] no-initializer warning"
fi

cat >"$work/infer.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2, 3 };
    return a[0] - 1;
}
EOF
expect_silent infer "E79-1: T a[] = {...} stays an inferred-length array" "'T a[]' $dep"

cat >"$work/explicit.ct" <<'EOF'
int main(void)
{
    int a[3] = { 1, 2, 3 };
    int[] s = a;
    return s[2] - 3;
}
EOF
expect_silent explicit "E79-1: T a[N] is a plain C array (silent)" "'T a[]' $dep"

cat >"$work/slice_spelling.ct" <<'EOF'
int sum(int[] s) { return s[0]; }
int[] id(int[] s) { return s; }
int main(void)
{
    int a[] = { 7 };
    int[] s = id(a);
    return sum(a) - 7;
}
EOF
expect_silent slice_spelling "E79-1: the T[] spelling is silent for parameter and return" \
    "'T a[]' $dep"

exit $fail
