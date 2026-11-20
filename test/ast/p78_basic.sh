#!/bin/sh
# PH-78 S2a: `ref` / `out` on free functions.
#
#   E78-1 contextual keyword: only the first token of a parameter is the
#          annotation; `int out;` and `time_t *ref;` stay declarations.
#   E78-2 signature/emission: prototype, definition and ABI header spell `T *`;
#          reads/writes spell `(*name)`; the call site takes the address; a
#          hand-written pointer C program behaves the same.
#   E78-3 call-site place: variable / field / `*p` / array / Vec / Map element
#          pass; literal, expression, call result and cast are hard errors.
#   E78-4 caller initialisation: trivial may be uninitialised, owning must hold
#          a value, a non-owning pointer may be uninitialised.
#   E78-5 L1 definite assignment: if/else exact, return checked, loops/switch/
#          goto conservative, and `ct check` uses the same rule.
#
# Usage: sh test/ast/p78_basic.sh <ct-ast>
set -u
# the contextual-keyword fixture includes <time.h>; this probe owns that
# boundary exception (check-ast exports it for every probe too).
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p78_basic.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p78basic.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p78/basic: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

build() { # <name> [bin]
    bin=${2:-$1.bin}
    rm -rf "$work/.ctbuild"
    ( cd "$work" && "$ctast" build "$1.ct" -o "$work/$bin" ) >"$work/$1.log" 2>&1
}
run_ok() { # <name> <label>
    if ! build "$1"; then
        bad "$2" "$(sed -n '1,4p' "$work/$1.log")"
    elif "$work/$1.bin"; then
        ok "$2"
    else
        bad "$2" "the built program exited non-zero"
    fi
}
expect_err() { # <name> <label> <pattern> [check]
    cmd=${4:-build}
    if [ "$cmd" = check ]; then
        rm -rf "$work/.ctbuild"
        ( cd "$work" && "$ctast" check "$1.ct" ) >"$work/$1.log" 2>&1
    else
        build "$1"
    fi
    if [ $? -eq 0 ]; then
        bad "$2" "accepted (expected a hard error)"
    elif ! grep -Fq "$3" "$work/$1.log"; then
        bad "$2" "wrong diagnostic: $(sed -n '1,3p' "$work/$1.log")"
    else
        ok "$2"
    fi
}

# ---------------------------------------------------------------- E78-1
cat >"$work/ctx.ct" <<'CT'
#include <time.h>

time_t *ref;
int out = 3;

int same(int out)
{
    int ref = out;
    return ref;
}

int main(void)
{
    time_t now;
    ref = &now;
    now = 7;
    return (out == 3 && same(4) == 4 && *ref == 7) ? 0 : 1;
}
CT
run_ok ctx "E78-1 contextual keyword (int out; time_t *ref; parameter named out)"

# ---------------------------------------------------------------- E78-2
cat >"$work/prog.ct" <<'CT'
void inc(ref int x);
int read(out int y);

void inc(ref int x)
{
    x = x + 1;
}

int read(out int y)
{
    y = 7;
    return y;
}

int main(void)
{
    int v = 1;
    int n;
    int r;
    inc(v);
    r = read(n);
    return (v == 2 && n == 7 && r == 7) ? 0 : 1;
}
CT
run_ok prog "E78-2 ref/out free function (run)"
if ( cd "$work" && "$ctast" prog.ct -o prog.c ) >"$work/prog.c.log" 2>&1; then
    if grep -Fq 'void inc(int *);' "$work/prog.c" \
       && grep -Fq 'int read(int *);' "$work/prog.c" \
       && grep -Fq 'void inc(int * x)' "$work/prog.c" \
       && grep -Fq '(*x) = ((*x) + 1);' "$work/prog.c" \
       && grep -Fq 'inc(&v);' "$work/prog.c" \
       && grep -Fq 'r = read(&n);' "$work/prog.c"; then
        ok "E78-2 signature T *, body (*name), call &"
    else
        bad "E78-2 emission shape" "$(sed -n '4,22p' "$work/prog.c")"
    fi
else
    bad "E78-2 emission" "$(sed -n '1,4p' "$work/prog.c.log")"
fi
cat >"$work/hand.c" <<'C'
static void inc(int *x) { (*x) = (*x) + 1; }
static int read(int *y) { (*y) = 7; return (*y); }
int main(void)
{
    int v = 1, n, r;
    inc(&v);
    r = read(&n);
    return (v == 2 && n == 7 && r == 7) ? 0 : 1;
}
C
if "${CC:-cc}" "$work/hand.c" -o "$work/hand" >"$work/hand.log" 2>&1 && "$work/hand"; then
    ok "E78-2 hand-written pointer C behaves the same"
else
    bad "E78-2 hand-written pointer C" "$(cat "$work/hand.log")"
fi

# ABI header: a pub ref parameter is a pointer in the exported surface.
cat >"$work/abi.h.ct" <<'CT'
pub int bump(ref int x) { x = x + 1; return x; }
CT
rm -rf "$work/.ctbuild" "$work/abiout"
mkdir -p "$work/abiout"
if ( cd "$work" && "$ctast" build --lib abi.h.ct --outdir abiout ) >"$work/abi.log" 2>&1 \
   && grep -Eq '^int bump\(int \*\);$' "$work/abiout/abi.abi.h"; then
    ok "E78-2 ABI header spells T *"
else
    bad "E78-2 ABI header" "$(sed -n '1,4p' "$work/abi.log"; sed -n '1,8p' "$work/abiout/abi.abi.h")"
fi

# ---------------------------------------------------------------- E78-3
cat >"$work/places.ct" <<'CT'
struct P { int x; }
void inc(ref int x) { x = x + 1; }
int main(void)
{
    P p = { 1 };
    int a[2] = { 1, 2 };
    int v = 1;
    int *q = &v;
    Vec<int> vec = {1, 2};
    Map<char *, int> m = {"a": 1};
    inc(p.x);
    inc(a[0]);
    inc(*q);
    inc(vec[1]);
    inc(*m["a"]);
    return (p.x == 2 && a[0] == 2 && *q == 2 && vec[1] == 3 && *m["a"] == 2) ? 0 : 1;
}
CT
run_ok places "E78-3 places: variable/field/*p/array/Vec/Map element"

cat >"$work/bad_literal.ct" <<'CT'
void inc(ref int x) { x = x + 1; }
int main(void) { inc(1); return 0; }
CT
expect_err bad_literal "E78-3 literal rejected" "ref/out argument must be an assignable place"
cat >"$work/bad_expr.ct" <<'CT'
void inc(ref int x) { x = x + 1; }
int main(void) { int v = 1; inc(v + 1); return 0; }
CT
expect_err bad_expr "E78-3 expression rejected" "ref/out argument must be an assignable place"
cat >"$work/bad_call.ct" <<'CT'
int id(int x) { return x; }
void inc(ref int x) { x = x + 1; }
int main(void) { inc(id(3)); return 0; }
CT
expect_err bad_call "E78-3 call result rejected" "ref/out argument must be an assignable place"
cat >"$work/bad_cast.ct" <<'CT'
void inc(ref int x) { x = x + 1; }
int main(void) { inc((int)3); return 0; }
CT
expect_err bad_cast "E78-3 cast rejected" "ref/out argument must be an assignable place"

# SH-95: the place check must reach the base, a bit-field and top-level const.
cat >"$work/bad_member_rvalue.ct" <<'CT'
struct P { int x; }
struct P mk(void) { struct P p = { 1 }; return p; }
void inc(ref int x) { x = x + 1; }
int main(void) { inc(mk().x); return 0; }
CT
expect_err bad_member_rvalue "SH-95 call-result member rejected" "ref/out argument must be an assignable place"
cat >"$work/bad_bitfield.ct" <<'CT'
struct S { int x : 3; }
void inc(ref int x) { x = x + 1; }
int main(void) { struct S s = { 0 }; inc(s.x); return 0; }
CT
expect_err bad_bitfield "SH-95 bit-field member rejected" "ref/out argument must be an assignable place"
cat >"$work/bad_const_var.ct" <<'CT'
const int g = 1;
void inc(ref int x) { x = x + 1; }
int main(void) { inc(g); return 0; }
CT
expect_err bad_const_var "SH-95 const variable rejected" "ref/out argument must be an assignable place"

# ---------------------------------------------------------------- E78-4
cat >"$work/out_trivial.ct" <<'CT'
struct P { int x; }
struct P g = { 2 };
void set(out int n, out struct P p)
{
    n = 1;
    p = g;
}
int main(void) { int n; struct P p; set(n, p); return (n == 1 && p.x == 2) ? 0 : 1; }
CT
run_ok out_trivial "E78-4 trivial out actual may be uninitialised"
cat >"$work/out_owning_ok.ct" <<'CT'
struct R { int x; } use Drop;
R g = { 1 };
void set(out R r) { r = g; }
int main(void) { R r = { 0 }; set(r); return 0; }
CT
run_ok out_owning_ok "E78-4 owning out actual initialised"
cat >"$work/out_owning_later.ct" <<'CT'
struct R { int x; } use Drop;
R g = { 1 };
void set(out R r) { r = g; }
int main(void) { R r; r = g; set(r); return 0; }
CT
run_ok out_owning_later "E78-4 owning actual initialised by assignment"
cat >"$work/bad_owning.ct" <<'CT'
struct R { int x; } use Drop;
R g = { 1 };
void set(out R r) { r = g; }
int main(void) { R r; set(r); return 0; }
CT
expect_err bad_owning "E78-4 owning actual uninitialised rejected" "out owning argument must be initialized"
cat >"$work/out_ptr.ct" <<'CT'
struct R { int x; } use Drop;
void set(out struct R *p) { static struct R r = { 2 }; p = &r; }
int main(void) { struct R *p; set(p); return (p->x == 2) ? 0 : 1; }
CT
run_ok out_ptr "E78-4 non-owning pointer actual may be uninitialised"

# ---------------------------------------------------------------- E78-5
cat >"$work/good_ifelse.ct" <<'CT'
int read(out int y)
{
    if (1) { y = 7; } else { y = 8; }
    return y;
}
int main(void) { int n; return (read(n) == 7 || read(n) == 8) ? 0 : 1; }
CT
run_ok good_ifelse "E78-5 if/else assigns on both paths"
cat >"$work/good_return.ct" <<'CT'
int read(out int y)
{
    y = 7;
    return y;
}
int main(void) { int n; return (read(n) == 7) ? 0 : 1; }
CT
run_ok good_return "E78-5 assignment before return"
cat >"$work/bad_if.ct" <<'CT'
int read(out int y)
{
    if (1) { y = 7; }
    return y;
}
int main(void) { int n; return read(n); }
CT
expect_err bad_if "E78-5 one if path leaves out unset" "out parameter 'y' is not assigned on every path"
cat >"$work/bad_early.ct" <<'CT'
int read(out int y, int c)
{
    if (c) { return 0; }
    y = 7;
    return y;
}
int main(void) { int n; return read(n, 1); }
CT
expect_err bad_early "E78-5 early return before assignment" "out parameter 'y' is not assigned on every path"
cat >"$work/bad_loop.ct" <<'CT'
int read(out int y, int n)
{
    for (int i = 0; i < n; i = i + 1) { y = i; }
    return y;
}
int main(void) { int v; return read(v, 2); }
CT
expect_err bad_loop "E78-5 loop is conservative" "out parameter 'y' is not assigned on every path"
cat >"$work/bad_switch.ct" <<'CT'
int read(out int y, int k)
{
    switch (k) { case 1: y = 1; break; default: y = 2; }
    return y;
}
int main(void) { int v; return read(v, 1); }
CT
expect_err bad_switch "E78-5 switch is conservative" "out parameter 'y' is not assigned on every path"
cat >"$work/bad_goto.ct" <<'CT'
int read(out int y, int c)
{
    if (c) { goto out; }
    y = 1;
out:
    return y;
}
int main(void) { int v; return read(v, 1); }
CT
expect_err bad_goto "E78-5 goto is conservative" "out parameter 'y' is not assigned on every path"
expect_err bad_if "E78-5 ct check uses the same rule" "out parameter 'y' is not assigned on every path" check

[ "$fail" -eq 0 ] && echo "p78_basic: OK"
exit "$fail"
