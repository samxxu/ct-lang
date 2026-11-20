#!/bin/sh
# PH-78 S2b: `ref` / `out` on methods and traits.
#
# The same rules as a free function: the vtable slot and the impl definition
# spell `T *`, the body spells `(*name)`, the call site takes the address, and
# `out` must be assigned on every path. Covers a trait method, a generic impl,
# a trait default body, an inherent method, a generic inherent method, a static
# inherent method, and the trait/impl annotation consistency error.
#
# Usage: sh test/ast/p78_method.sh <ct-ast>
set -u
ctast=${1:?usage: p78_method.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
work=$(mktemp -d "${TMPDIR:-/tmp}/p78method.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p78/method: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

build() {
    rm -rf "$work/.ctbuild"
    ( cd "$work" && "$ctast" build "$1.ct" -o "$work/$1.bin" ) >"$work/$1.log" 2>&1
}
run_ok() {
    if ! build "$1"; then
        bad "$2" "$(sed -n '1,4p' "$work/$1.log")"
    elif "$work/$1.bin"; then
        ok "$2"
    else
        bad "$2" "the built program exited non-zero"
    fi
}
expect_err() {
    build "$1"
    if [ $? -eq 0 ]; then
        bad "$2" "accepted (expected a hard error)"
    elif ! grep -Fq "$3" "$work/$1.log"; then
        bad "$2" "wrong diagnostic: $(sed -n '1,3p' "$work/$1.log")"
    else
        ok "$2"
    fi
}

# --------------------------------------------------------- trait + impl
cat >"$work/methods.ct" <<'CT'
trait Touch {
    void bump(ref int x, out int y);
}
struct Box { int v; } use Touch;
impl Touch for Box {
    void bump(ref int x, out int y) {
        x = x + self->v;
        y = x * 2;
    }
}
int main(void)
{
    Box b = { 3 };
    int n = 1;
    int r;
    b.bump(n, r);
    return (n == 4 && r == 8) ? 0 : 1;
}
CT
run_ok methods "E78-6 trait method ref/out (dispatch, run)"
if ( cd "$work" && "$ctast" methods.ct -o methods.c ) >"$work/methods.c.log" 2>&1; then
    if grep -Fq 'void (*bump)(void *, int *, int *);' "$work/methods.c" \
       && grep -Fq 'void Box_Touch_bump(void *self, int * x, int * y)' "$work/methods.c" \
       && grep -Fq '(*x) = ((*x) + _self->v);' "$work/methods.c" \
       && grep -Fq 'bump(&b, &n, &r);' "$work/methods.c"; then
        ok "E78-6 vtable slot, definition, body and call site"
    else
        bad "E78-6 method emission shape" "$(sed -n '4,20p' "$work/methods.c")"
    fi
else
    bad "E78-6 method emission" "$(sed -n '1,4p' "$work/methods.c.log")"
fi

# --------------------------------------------------------- generic impl
cat >"$work/methods_generic.ct" <<'CT'
trait Touch {
    void bump(ref int x, out int y);
}
struct Box<T> { T v; }
impl<T> Box<T> use Touch {
    void bump(ref int x, out int y) {
        x = x + self->v;
        y = x * 2;
    }
}
int main(void)
{
    Box<int> b = { 3 };
    int n = 1;
    int r;
    b.bump(n, r);
    return (n == 4 && r == 8) ? 0 : 1;
}
CT
run_ok methods_generic "E78-6 generic trait impl ref/out (run)"

# --------------------------------------------------------- default body
cat >"$work/default.ct" <<'CT'
trait Touch {
    void bump(ref int x, out int y) {
        x = x + 1;
        y = x * 2;
    }
}
struct Box { int v; } use Touch;
impl Touch for Box { }
int main(void)
{
    Box b = { 1 };
    int n = 1;
    int r;
    b.bump(n, r);
    return (n == 2 && r == 4) ? 0 : 1;
}
CT
run_ok default "E78-6 trait default body ref/out (run)"

# --------------------------------------------------------- inherent
cat >"$work/inherent.ct" <<'CT'
struct Box { int v; }
impl Box {
    void bump(ref int x, out int y) {
        x = x + self->v;
        y = x * 2;
    }
}
int main(void)
{
    Box b = { 3 };
    int n = 1;
    int r;
    b.bump(n, r);
    return (n == 4 && r == 8) ? 0 : 1;
}
CT
run_ok inherent "E78-6 inherent method ref/out (run)"

# --------------------------------------------------------- generic inherent
cat >"$work/inherent_generic.ct" <<'CT'
struct Box<T> { T v; }
impl<T> Box<T> {
    void bump(ref int x, out int y) {
        x = x + self->v;
        y = x * 2;
    }
}
int main(void)
{
    Box<int> b = { 3 };
    int n = 1;
    int r;
    b.bump(n, r);
    return (n == 4 && r == 8) ? 0 : 1;
}
CT
run_ok inherent_generic "E78-6 generic inherent method ref/out (run)"

# --------------------------------------------------------- static inherent
cat >"$work/inherent_static.ct" <<'CT'
struct Box { int v; }
impl Box {
    static int bump(ref int x) {
        x = x + 1;
        return x;
    }
}
int main(void)
{
    int n = 1;
    int r = Box.bump(n);
    return (n == 2 && r == 2) ? 0 : 1;
}
CT
run_ok inherent_static "E78-6 static inherent method ref/out (run)"

# SH-96: `self` is already the receiver pointer; it must not be addressed.
cat >"$work/self_ref.ct" <<'CT'
struct S { int v; }
impl S {
    void bump(ref S s) { s.v = 1; }
    void go(void) { self.bump(self); }
}
int main(void) { struct S s = { 0 }; s.go(); return (s.v == 1) ? 0 : 1; }
CT
run_ok self_ref "SH-96 method self passed to ref without & (run)"
# SH-98: the *receiver* side of `self.bump(self)` must also pass `_self`,
# not the address of the local slot (`&_self` would be `struct S **`).
if build self_ref && grep -Fq 'S_bump(&_self' "$work/.ctbuild/self_ref.c"; then
    bad "SH-98 method self receiver is not addressed" "$(grep -F 'S_bump' "$work/.ctbuild/self_ref.c" | head -1)"
elif grep -Fq 'S_bump(_self, _self)' "$work/.ctbuild/self_ref.c"; then
    ok "SH-98 method self receiver is not addressed"
else
    bad "SH-98 method self receiver is not addressed" "expected S_bump(_self, _self)"
fi

# --------------------------------------------------------- negatives
cat >"$work/bad_out.ct" <<'CT'
trait Touch { void bump(ref int x, out int y); }
struct Box { int v; } use Touch;
impl Touch for Box {
    void bump(ref int x, out int y) {
        x = x + self->v;
        if (x > 0) { y = 1; }
    }
}
int main(void) { Box b = { 3 }; int n = 1; int r; b.bump(n, r); return 0; }
CT
expect_err bad_out "E78-6 method out must be assigned on every path" "out parameter 'y' is not assigned on every path"
cat >"$work/bad_literal.ct" <<'CT'
trait Touch { void bump(ref int x, out int y); }
struct Box { int v; } use Touch;
impl Touch for Box { void bump(ref int x, out int y) { x = x + 1; y = 2; } }
int main(void) { Box b = { 3 }; int r; b.bump(1, r); return 0; }
CT
expect_err bad_literal "E78-6 method actual must be a place" "ref/out argument must be an assignable place"
cat >"$work/bad_type.ct" <<'CT'
trait Touch { void bump(ref int x, out int y); }
struct Box { int v; } use Touch;
impl Touch for Box { void bump(ref int x, out int y) { x = x + 1; y = 2; } }
int main(void) { Box b = { 3 }; Box o = { 1 }; int r; b.bump(o, r); return 0; }
CT
expect_err bad_type "E78-6 method actual base type is checked" "type mismatch"
cat >"$work/bad_impl_ann.ct" <<'CT'
trait Touch { void bump(ref int x, out int y); }
struct Box { int v; } use Touch;
impl Touch for Box { void bump(int x, out int y) { x = x + 1; y = 2; } }
int main(void) { Box b = { 3 }; int n = 1; int r; b.bump(n, r); return 0; }
CT
expect_err bad_impl_ann "E78-6 impl annotation must match the trait" "ref/out annotation does not match the trait"
cat >"$work/bad_default_out.ct" <<'CT'
trait Touch {
    void bump(ref int x, out int y) {
        if (x > 0) { y = 1; }
    }
}
struct Box { int v; } use Touch;
impl Touch for Box { }
int main(void) { Box b = { 1 }; int n = 1; int r; b.bump(n, r); return 0; }
CT
expect_err bad_default_out "E78-6 default body obeys out L1" "out parameter 'y' is not assigned on every path"

[ "$fail" -eq 0 ] && echo "p78_method: OK"
exit "$fail"
