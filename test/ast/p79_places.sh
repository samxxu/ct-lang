#!/bin/sh
# PH-79 S3c: slice placement whitelist and the escape lint.
#
# `T[]` is a non-owning view: it may be a parameter, a local, an expression
# temporary and a return value. Every other placement is a hard error. The
# direct `return` of a local view (a slice variable, a subslice or a whole
# local array) lints; a view of a global or a static array does not.
#
# Usage: sh test/ast/p79_places.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p79_places.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p79places.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p79/places: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

build() {
    rm -rf "$work/.ctbuild" "$work/.ctcache"
    ( cd "$work" && "$ctast" build "$1.ct" -o "$work/$1.bin" ) >"$work/$1.log" 2>&1
}
run_ok() {
    if ! build "$1"; then bad "$2" "$(sed -n '1,4p' "$work/$1.log")"
    elif ! "$work/$1.bin"; then bad "$2" "the built program exited non-zero"
    else ok "$2"; fi
}
expect_err() {
    if build "$1"; then bad "$2" "accepted (expected a hard error)"
    elif ! grep -Fq "$3" "$work/$1.log"; then bad "$2" "wrong diagnostic: $(sed -n '1,3p' "$work/$1.log")"
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

# --- positive placements: parameter, local, temporary, return ---------------
cat >"$work/allowed.ct" <<'EOF'
int[] id(int[] s) { return s; }
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] s = a;
    int[] t = id(s[1..]);
    return (t[0] == 2) ? 0 : 1;
}
EOF
run_ok allowed "E79-5: slice as parameter/local/temporary/return is allowed"

# --- the ten placement negatives -------------------------------------------
cat >"$work/field.ct" <<'EOF'
struct S { int[] s; };
int main(void) { return 0; }
EOF
expect_err field "E79-5: slice as a struct field is a hard error" "cannot be a struct field"

cat >"$work/global.ct" <<'EOF'
int[] g;
int main(void) { return 0; }
EOF
expect_err global "E79-5: slice as a global is a hard error" "cannot be a file-scope variable"

cat >"$work/iface.ct" <<'EOF'
trait T { int n(void); }
struct S { int x; } use T;
impl T for S { int n(void) { return self->x; } }
int main(void)
{
    int a[] = { 1 };
    int[] s = a;
    T t = s;
    return 0;
}
EOF
expect_err iface "E79-5: slice as an interface value is a hard error" \
    "cannot be stored in interface"

cat >"$work/box.ct" <<'EOF'
int main(void)
{
    box<int[]> b;
    return 0;
}
EOF
expect_err box "E79-5: slice in Box<T> is a hard error" "cannot be stored in Box<T>"

cat >"$work/option.ct" <<'EOF'
int main(void)
{
    Option<int[]> o;
    return 0;
}
EOF
expect_err option "E79-5: slice in Option is a hard error" "cannot be a generic type argument"

cat >"$work/result.ct" <<'EOF'
int main(void)
{
    Result<int[], int> r;
    return 0;
}
EOF
expect_err result "E79-5: slice in Result is a hard error" "cannot be a generic type argument"

cat >"$work/vec.ct" <<'EOF'
int main(void)
{
    Vec<int[]> v;
    return 0;
}
EOF
expect_err vec "E79-5: slice as a Vec element is a hard error" \
    "cannot be a generic type argument"

cat >"$work/map.ct" <<'EOF'
int main(void)
{
    Map<char *, int[]> m;
    return 0;
}
EOF
expect_err map "E79-5: slice as a Map value is a hard error" \
    "cannot be a generic type argument"

cat >"$work/arrelem.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2 };
    int b[] = { 3, 4 };
    int[] xs[] = { a, b };
    return 0;
}
EOF
expect_err arrelem "E79-5: slice as an array element is a hard error" \
    "cannot be an array element"

cat >"$work/generic.ct" <<'EOF'
struct B<T> { T v; }
int main(void)
{
    B<int[]> b;
    return 0;
}
EOF
expect_err generic "E79-5: slice as a generic argument is a hard error" \
    "cannot be a generic type argument"

cat >"$work/closure.ct" <<'EOF'
trait Each { int each(int (*f)(void *env, int x), void *env); }
struct B { int total; } use Each;
impl Each for B { int each(int (*f)(void *env, int x), void *env) { return f(env, 3); } }
int main(void)
{
    struct B b = { 7 };
    int a[] = { 1, 2 };
    int[] s = a;
    int r = b.each((int x) => s[0] + x);
    return r;
}
EOF
expect_err closure "E79-5: a closure cannot capture a slice" "cannot capture the slice"

# --- E79-6 escape lint ------------------------------------------------------
cat >"$work/ret_slice.ct" <<'EOF'
int[] f(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    return s;
}
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
expect_warn ret_slice "E79-6: returning a local slice view lints" "slice escape"

cat >"$work/ret_sub.ct" <<'EOF'
int[] f(void)
{
    int a[] = { 1, 2, 3 };
    return a[1..];
}
int main(void) { int[] r = f(); return r[0] - 2; }
EOF
expect_warn ret_sub "E79-6: returning a subslice of a local array lints" "slice escape"

# SH-100: the direct `return a;` conversion must also reach the lint.
cat >"$work/ret_array.ct" <<'EOF'
int[] f(void)
{
    int a[] = { 1, 2 };
    return a;
}
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
expect_warn ret_array "E79-6: returning a local array (converted) lints" "slice escape"

cat >"$work/ret_global.ct" <<'EOF'
int g_arr[] = { 1, 2 };
int[] f(void) { return g_arr; }
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
expect_silent ret_global "E79-6: a view of a global array does not lint" "slice escape"

cat >"$work/ret_static.ct" <<'EOF'
int[] f(void)
{
    static int a[] = { 1, 2 };
    return a;
}
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
expect_silent ret_static "E79-6: a view of a static array does not lint" "slice escape"

exit $fail
