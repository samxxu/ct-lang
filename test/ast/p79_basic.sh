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
    rm -rf "$work/.ctbuild"
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

exit $fail
