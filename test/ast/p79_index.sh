#!/bin/sh
# PH-79 S3b: `s[i]` is a checked place.
#
#   - read / write / borrow act on the underlying element;
#   - an out-of-range subscript traps at run time (stderr + non-zero exit);
#   - `s.get(i)` is the soft access (0 outside the range);
#   - `const T[]` elements are read-only (write and ref/out are hard errors);
#   - a C array keeps C's unchecked subscript.
#
# Usage: sh test/ast/p79_index.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p79_index.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p79index.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p79/index: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

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
expect_trap() {
    if ! build "$1"; then bad "$2" "the trap fixture did not compile"
    elif "$work/$1.bin" >/dev/null 2>&1; then bad "$2" "out-of-range access did not trap"
    else ok "$2"; fi
}

cat >"$work/rw.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2, 3 };
    int[] s = a;
    if (s[1] != 2) return 1;
    s[1] = 21;
    if (s[1] != 21 || a[1] != 21) return 2;
    s[0] = s[2] + 1;
    if (a[0] != 4) return 3;
    return 0;
}
EOF
run_ok rw "E79-3: s[i] reads and writes the underlying element"

cat >"$work/elemtype.ct" <<'EOF'
struct P { int x; }
int main(void)
{
    struct P a[] = { { 1 }, { 2 } };
    struct P[] s = a;
    s[0].x = 7;
    if (a[0].x != 7 || s[1].x != 2) return 1;
    return 0;
}
EOF
run_ok elemtype "E79-3: s[i] carries the element type (struct member)"

cat >"$work/param.ct" <<'EOF'
int second(int[] s) { return s[1]; }
int main(void)
{
    int a[] = { 4, 5, 6 };
    return second(a) - 5;
}
EOF
run_ok param "E79-3: a slice parameter is indexed through the same checked place"

cat >"$work/trap_hi.ct" <<'EOF'
int main(void)
{
    int a[] = { 1 };
    int[] s = a;
    return s[2];
}
EOF
expect_trap trap_hi "E79-3: s[i] above the length traps at run time"

cat >"$work/trap_neg.ct" <<'EOF'
int main(void)
{
    int a[] = { 1 };
    int[] s = a;
    return s[-1];
}
EOF
expect_trap trap_neg "E79-3: s[i] below zero traps at run time"

cat >"$work/trap_runtime.ct" <<'EOF'
int main(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    int i = 2;
    return s[i];
}
EOF
expect_trap trap_runtime "E79-3: a run-time index is checked too (no constant folding)"

cat >"$work/get.ct" <<'EOF'
int main(void)
{
    int a[] = { 3, 4 };
    int[] s = a;
    if (*s.get(1) != 4) return 1;
    if (s.get(2) != 0) return 2;
    if (s.get(-1) != 0) return 3;
    return 0;
}
EOF
run_ok get "E79-3: s.get(i) is the soft access (0 outside the range)"

cat >"$work/const_write.ct" <<'EOF'
int main(void)
{
    int a[2] = { 1, 2 };
    const int[] ro = a;
    ro[0] = 9;
    return 0;
}
EOF
expect_err const_write "E79-4: const T[] element write is a hard error" \
    "cannot write to an element of a const slice"

cat >"$work/const_borrow.ct" <<'EOF'
void bump(ref int x) { x = x + 1; }
int main(void)
{
    int a[] = { 1, 2 };
    const int[] ro = a;
    bump(ro[1]);
    return 0;
}
EOF
expect_err const_borrow "E79-4: const T[] element is not a writable place" \
    "ref/out argument must be an assignable place"

cat >"$work/carray.ct" <<'EOF'
int main(void)
{
    int a[2] = { 1, 2 };
    if (a[1] != 2) return 1;
    return a[0] - 1;
}
EOF
run_ok carray "E79-4: a C array keeps C's unchecked subscript"

exit $fail
