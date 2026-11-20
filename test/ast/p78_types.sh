#!/bin/sh
# PH-78 S2c: ref/out type matching and preserved semantics.
#
#   - a ref/out actual's base type must match the formal (a struct is not an
#     int, and an int is not a struct);
#   - array and function-pointer forms are refused;
#   - prototype and definition must agree on the annotation (the C signature
#     would otherwise be two conflicting declarations);
#   - ref/out do not change pointer, `defer` or `own` behaviour.
#
# Usage: sh test/ast/p78_types.sh <ct-ast>
set -u
# the own/AutoDrop fixture includes <stdlib.h>; this probe owns that
# boundary exception (check-ast exports it for every probe too).
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p78_types.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
work=$(mktemp -d "${TMPDIR:-/tmp}/p78types.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p78/types: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

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

# --------------------------------------------------------- base types
cat >"$work/ref_type.ct" <<'CT'
struct P { int x; }
void inc(ref int x) { x = x + 1; }
int main(void) { struct P p = { 1 }; inc(p); return 0; }
CT
expect_err ref_type "ref base type mismatch" "type mismatch"
cat >"$work/out_type.ct" <<'CT'
struct P { int x; }
void set(out int x) { x = 1; }
int main(void) { struct P p = { 1 }; set(p); return 0; }
CT
expect_err out_type "out base type mismatch" "type mismatch"
cat >"$work/ref_struct.ct" <<'CT'
struct P { int x; }
struct Q { int y; }
void set(ref struct P p) { p.x = 1; }
int main(void) { struct Q q = { 0 }; set(q); return 0; }
CT
expect_err ref_struct "struct base type mismatch" "type mismatch"

# --------------------------------------------------------- shapes
cat >"$work/array_param.ct" <<'CT'
void inc(ref int a[3]) { a[0] = a[0] + 1; }
int main(void) { int a[3] = {1, 2, 3}; inc(a); return 0; }
CT
expect_err array_param "ref array parameter refused" "ref/out parameters cannot be arrays or function pointers"
cat >"$work/fnptr_param.ct" <<'CT'
void call(ref int (*cb)(int)) { cb = 0; }
int main(void) { int (*p)(int) = 0; call(p); return 0; }
CT
expect_err fnptr_param "ref function-pointer parameter refused" "ref/out parameters cannot be arrays or function pointers"

# --------------------------------------------------------- redeclaration
cat >"$work/redecl.ct" <<'CT'
void inc(ref int x);
void inc(int x) { x = x + 1; }
int main(void) { int v = 1; inc(v); return 0; }
CT
expect_err redecl "prototype/definition annotation must agree" "redeclaration"

# --------------------------------------------------------- preserved semantics
cat >"$work/pointer_sem.ct" <<'CT'
void retarget(ref int *p, int *n) { p = n; }
int main(void)
{
    int a = 1;
    int b = 2;
    int *q = &a;
    retarget(q, &b);
    return (*q == 2) ? 0 : 1;
}
CT
run_ok pointer_sem "ref of a pointer keeps pointer semantics"
cat >"$work/defer_sem.ct" <<'CT'
struct P { int x; }
void inc(ref int x) { x = x + 1; }
int main(void)
{
    struct P p = { 1 };
    defer { p.x = 9; }
    inc(p.x);
    return 0;
}
CT
run_ok defer_sem "ref does not disturb defer release points"
cat >"$work/own_sem.ct" <<'CT'
#include <stdlib.h>
struct P { int x; } use Drop;
void set(out int x, int v) { x = v; }
int main(void)
{
    own P *q = malloc(sizeof(P));
    int n;
    set(n, 4);
    q->x = n;
    return (q->x == 4) ? 0 : 1;
}
CT
run_ok own_sem "out does not disturb own/AutoDrop"

[ "$fail" -eq 0 ] && echo "p78_types: OK"
exit "$fail"
