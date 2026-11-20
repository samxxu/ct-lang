#!/bin/sh
# PH-79 S3: `T[]` slices, checked places, get, const, migration warning.
#
# Usage: sh test/ast/p79_basic.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p79_basic.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p79basic.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p79/basic: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

build() {
    rm -rf "$work/.ctbuild" "$work/.ctcache"
    ( cd "$work" && "$ctast" build "$1.ct" -o "$work/$1.bin" ) >"$work/$1.log" 2>&1
}
run_ok() {
    if ! build "$1"; then bad "$2" "$(sed -n '1,4p' "$work/$1.log")"
    elif "$work/$1.bin"; then ok "$2"
    else bad "$2" "the built program exited non-zero"; fi
}
expect_err() {
    if build "$1"; then bad "$2" "accepted (expected a hard error)"
    elif ! grep -Fq "$3" "$work/$1.log"; then bad "$2" "wrong diagnostic: $(sed -n '1,3p' "$work/$1.log")"
    else ok "$2"; fi
}
expect_trap() {
    if ! build "$1"; then bad "$2" "the trap fixture did not compile"
    elif "$work/$1.bin" >/dev/null 2>&1; then bad "$2" "out-of-range access did not trap"
    else ok "$2"; fi
}
expect_warn() {
    if ! build "$1"; then bad "$2" "the warning fixture did not build"
    elif ! grep -Fq "$3" "$work/$1.log"; then bad "$2" "warning missing: $(sed -n '1,3p' "$work/$1.log")"
    else ok "$2"; fi
}
expect_silent() {
    if ! build "$1"; then bad "$2" "the fixture did not build"
    elif grep -Fq "$3" "$work/$1.log"; then bad "$2" "unexpected warning"
    else ok "$2"; fi
}

cat >"$work/basic.ct" <<'EOF'
struct P { int x; }
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] s = a;
    s[1] = 21;
    const int[] ro = a;
    int[] t = s[1..];
    int sum = 0;
    foreach (s) { sum = sum + item; }
    P ps[] = { { 1 }, { 2 } };
    P[] pv = ps;
    pv[0].x = 7;
    if (s[0] != 1 || s[1] != 21 || t[0] != 21) return 1;
    if (*s.get(2) != 3 || s.get(9) != 0) return 2;
    if (ro[0] != 1 || sum != 25) return 3;
    if (ps[0].x != 7 || pv[1].x != 2) return 4;
    return 0;
}
EOF
run_ok basic "E79-2/3: array->slice, write, subslice, foreach, get, const read, struct element"

cat >"$work/const_write.ct" <<'EOF'
int main(void)
{
    int a[2] = { 1, 2 };
    const int[] ro = a;
    ro[0] = 9;
    return 0;
}
EOF
expect_err const_write "E79-4: const T[] write is a hard error" "cannot write to an element of a const slice"

cat >"$work/trap.ct" <<'EOF'
int main(void)
{
    int a[] = { 1 };
    int[] s = a;
    return s[2];
}
EOF
expect_trap trap "E79-3: s[i] out of range traps at run time"

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

cat >"$work/generic.ct" <<'EOF'
struct B<T> { T v; }
int main(void)
{
    B<int[]> b;
    return 0;
}
EOF
expect_err generic "E79-5: slice as a generic argument is a hard error" "cannot be a generic type argument"

cat >"$work/migrate_param.ct" <<'EOF'
int total(int xs[], int n) { return n; }
int main(void) { return total(0, 0); }
EOF
expect_warn migrate_param "E79-1: T a[] parameter warns" "'T a[]' is deprecated"

cat >"$work/migrate_infer.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2, 3 };
    return a[0] - 1;
}
EOF
expect_silent migrate_infer "E79-1: T a[] = {...} stays an inferred-length array" "'T a[]' is deprecated"

cat >"$work/container.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    Vec<int[]> v;
    return 0;
}
EOF
expect_err container "E79-5: slice as a container element is a hard error" "cannot be a generic type argument"

cat >"$work/option.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    Option<int[]> o;
    return 0;
}
EOF
expect_err option "E79-5: slice in Option is a hard error" "cannot be a generic type argument"

cat >"$work/result.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    Result<int[], int> r;
    return 0;
}
EOF
expect_err result "E79-5: slice in Result is a hard error" "cannot be a generic type argument"

cat >"$work/arrelem.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2 };
    int b[] = { 3, 4 };
    int[] xs[] = { a, b };
    return 0;
}
EOF
expect_err arrelem "E79-5: slice as an array element is a hard error" "cannot be an array element"

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
expect_err iface "E79-5: slice as an interface value is a hard error" "cannot be stored in interface"

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

cat >"$work/ret.ct" <<'EOF'
int[] f(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    return s;
}
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
expect_warn ret "E79-6: returning a view of a local array lints" "slice escape"

# SH-99: the array base of an open-ended subslice emits a valid `{ptr,len}`.
cat >"$work/a1open.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] t = a[1..];
    if (t[0] != 2 || t[1] != 3) return 1;
    return 0;
}
EOF
run_ok a1open "E79-2/SH-99: array-base open subslice a[1..] is half-open and valid C"

cat >"$work/a1range.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2, 3, 4 };
    int[] t = a[1..3];
    return (t[0] == 2 && t[1] == 3) ? 0 : 1;
}
EOF
run_ok a1range "E79-2: array-base bounded subslice a[1..3] stays half-open"

# SH-100: an array actual/return is converted to a `{ptr,len}` view.
cat >"$work/arr_arg.ct" <<'EOF'
int sum(int[] s) { return s[0] + s[1]; }
int main(void)
{
    int a[] = { 3, 4 };
    return sum(a) - 7;
}
EOF
run_ok arr_arg "E79-2/SH-100: an array actual fills a T[] parameter"

cat >"$work/arr_ret.ct" <<'EOF'
int g_arr[] = { 1, 2 };
int[] f(void) { return g_arr; }
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
run_ok arr_ret "E79-2/SH-100: an array return fills a T[] result"

cat >"$work/arr_ret_local.ct" <<'EOF'
int[] f(void)
{
    int a[] = { 1, 2 };
    return a;
}
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
expect_warn arr_ret_local "E79-6/SH-100: a converted local-array return lints" "slice escape"

cat >"$work/field_arg.ct" <<'EOF'
struct S { int xs[2]; };
int sum(int[] s) { return s[0] + s[1]; }
int main(void)
{
    struct S o = {{ 3, 4 }};
    return sum(o.xs) - 7;
}
EOF
run_ok field_arg "E79-2/SH-100: a struct's array field fills a T[] parameter"

# SH-101: a slice element is a checked place for ref/out.
cat >"$work/borrow_elem.ct" <<'EOF'
void bump(ref int x) { x = x + 1; }
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    bump(s[1]);
    return (a[1] == 3) ? 0 : 1;
}
EOF
run_ok borrow_elem "E79-3/SH-101: a slice element is a ref/out actual"

cat >"$work/borrow_member.ct" <<'EOF'
struct P { int x; }
void bump(ref int v) { v = v + 1; }
int main(void)
{
    struct P a[] = { { 1 }, { 2 } };
    struct P[] s = a;
    bump(s[0].x);
    return (a[0].x == 2) ? 0 : 1;
}
EOF
run_ok borrow_member "E79-3/SH-101: a slice element's member is a ref/out actual"

cat >"$work/borrow_trap.ct" <<'EOF'
void bump(ref int x) { x = x + 1; }
int main(void)
{
    int a[] = { 1 };
    int[] s = a;
    bump(s[2]);
    return 0;
}
EOF
expect_trap borrow_trap "E79-3/SH-101: a borrow keeps the bounds trap"

exit $fail
