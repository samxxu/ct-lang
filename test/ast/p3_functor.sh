#!/bin/sh
# D-029 / v1-PH-2 S3: functor signature sugar `(A, B) => R`.
#
# The sugar is only another spelling of the function-pointer type `R (*)(A, B)`.
# This probe pins the four things the ADR promises:
#
#   * every malformed shape gets a positioned diagnostic of its own
#     (missing parenthesis, void mix, nested function pointer, function return);
#   * the type checker judges arity and return type when the actual signature
#     is deducible, in declarations, assignments and at file scope;
#   * the generated C is byte-identical to the same program written with the
#     hand-spelled function pointer (`cmp`), and no wrapper symbol appears;
#   * the LIR path prints the same bytes as the AST path, including a
#     function-pointer array.
#
# Usage: sh test/ast/p3_functor.sh <ct-ast>
set -u
# these fixtures write free `#include`s; this probe is not about the boundary.
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p3_functor.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in
    /*) ;;
    *) ctast="$root/$ctast" ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p3fun.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

bad() { echo "FAIL p3/functor: $*" >&2; fail=1; }
ok()  { echo "ok   p3/functor $1"; }

# compile_expect <name> <file> <message-substring>
compile_expect() {
    name=$1
    src=$2
    pat=$3
    out="$work/$name.out"
    if ( cd "$root" && "$ctast" "$src" -o "$work/$name.c" ) >"$out" 2>&1; then
        bad "$name: accepted a malformed / mismatched functor"
        return
    fi
    if ! grep -Fq "$pat" "$out"; then
        bad "$name: diagnostic missing: $pat"
        sed 's/^/  /' "$out" | head -3 >&2
        return
    fi
    ok "$name"
}

# ---------------------------------------------------------------------------
# 1. syntax and signature diagnostics
# ---------------------------------------------------------------------------
cat >"$work/missing_paren.ct" <<'CT'
static int add(int a, int b) { return a + b; }
int main(void)
{
    (int, int => int) f = add;
    return f(1, 2);
}
CT
compile_expect missing_paren "$work/missing_paren.ct" \
    "a functor type needs a '(A, B) => R' shape"

cat >"$work/void_mix.ct" <<'CT'
int main(void)
{
    (void, int) => int f = 0;
    (void)f;
    return 0;
}
CT
compile_expect void_mix "$work/void_mix.ct" \
    "a 'void' functor parameter must be the only parameter"

cat >"$work/nested.ct" <<'CT'
int main(void)
{
    (int, (int) => int) => int f = 0;
    (void)f;
    return 0;
}
CT
compile_expect nested "$work/nested.ct" \
    "nested function pointers are not supported"

cat >"$work/return_position.ct" <<'CT'
static int add(int a, int b) { return a + b; }
(int, int) => int make(void)
{
    return add;
}
int main(void) { return 0; }
CT
compile_expect return_position "$work/return_position.ct" \
    "a function cannot return a function pointer"

cat >"$work/array_param.ct" <<'CT'
static int run((int, int) => int f[2], int i) { return f[i](1, 2); }
int main(void) { return run(0, 0); }
CT
compile_expect array_param "$work/array_param.ct" \
    "function-pointer arrays are not supported as parameters"

cat >"$work/arity_init.ct" <<'CT'
static int one(int a) { return a; }
int main(void)
{
    (int, int) => int f = one;
    return f(1, 2);
}
CT
compile_expect arity_init "$work/arity_init.ct" \
    "function pointer arity mismatch"

cat >"$work/return_init.ct" <<'CT'
static int add(int a, int b) { return a + b; }
int main(void)
{
    (int, int) => char *f = add;
    (void)f;
    return 0;
}
CT
compile_expect return_init "$work/return_init.ct" \
    "function pointer type mismatch: expected 'char * (*)(int, int)', got 'int (*)(int, int)': return type differs"

cat >"$work/arity_assign.ct" <<'CT'
static int add(int a, int b) { return a + b; }
static int one(int a) { return a; }
int main(void)
{
    (int, int) => int f = add;
    f = one;
    return f(1, 2);
}
CT
compile_expect arity_assign "$work/arity_assign.ct" \
    "function pointer arity mismatch"

cat >"$work/arity_global.ct" <<'CT'
static int one(int a) { return a; }
static (int, int) => int g = one;
int main(void) { return g(1, 2); }
CT
compile_expect arity_global "$work/arity_global.ct" \
    "function pointer arity mismatch"

# ---------------------------------------------------------------------------
# 2. zero runtime cost: the sugar and the hand-written pointer emit one C
# ---------------------------------------------------------------------------
mkdir -p "$work/sugar" "$work/plain"
cat >"$work/sugar/a.ct" <<'CT'
#include <stdio.h>
static int add(int a, int b) { return a + b; }
static int apply((int, int) => int f, int a, int b) { return f(a, b); }
int main(void)
{
    (int, int) => int f = add;
    printf("%d\n", apply(f, 2, 3));
    return 0;
}
CT
sed 's/(int, int) => int f/int (*f)(int, int)/g' \
    "$work/sugar/a.ct" >"$work/plain/a.ct"
( cd "$work/sugar" && "$ctast" a.ct -o a.c ) >"$work/sugar.log" 2>&1
sugar_rc=$?
( cd "$work/plain" && "$ctast" a.ct -o a.c ) >"$work/plain.log" 2>&1
plain_rc=$?
if [ "$sugar_rc" -eq 0 ] && [ "$plain_rc" -eq 0 ]; then
    if cmp -s "$work/sugar/a.c" "$work/plain/a.c"; then
        ok "zero_cost (generated C is byte-identical)"
    else
        bad "zero_cost: the sugar emits different C from the hand-written pointer"
        diff "$work/sugar/a.c" "$work/plain/a.c" | head -6 >&2
    fi
    if grep -Eq '__ct_functor|functor_' "$work/sugar/a.c"; then
        bad "zero_cost: a functor-specific symbol appeared"
    fi
    if grep -Fq 'int (*f)(int, int)' "$work/sugar/a.c" \
       && grep -Fq '(*f)(a, b)' "$work/sugar/a.c"; then
        ok "zero_cost (canonical type and direct call)"
    else
        bad "zero_cost: the canonical function-pointer spelling / direct call is missing"
    fi
    if "$CC" -std=c99 -Wall -Wextra "$work/sugar/a.c" -o "$work/sugar.bin" >/dev/null 2>&1 \
       && [ "$("$work/sugar.bin")" = 5 ]; then
        ok "zero_cost (program runs)"
    else
        bad "zero_cost: the generated C did not build/run"
    fi
else
    bad "zero_cost: the sugar or the hand-written source did not compile"
    sed 's/^/  /' "$work/sugar.log" "$work/plain.log" | head -6 >&2
fi

# ---------------------------------------------------------------------------
# 3. LIR parity (the S1b path must print the same bytes, array included)
# ---------------------------------------------------------------------------
fixture="test/ast/p3_functor_forms/prog.ct"
( cd "$root" && "$ctast" "$fixture" -o "$work/ast.c" ) >"$work/ast.log" 2>&1
ast_rc=$?
( cd "$root" && "$ctast" --ir=on "$fixture" -o "$work/lir.c" ) >"$work/lir.log" 2>&1
lir_rc=$?
if [ "$ast_rc" -eq 0 ] && [ "$lir_rc" -eq 0 ]; then
    if cmp -s "$work/ast.c" "$work/lir.c"; then
        ok "LIR (--ir=on prints the AST bytes)"
    else
        bad "LIR: --ir=on differs from the AST path"
        diff "$work/ast.c" "$work/lir.c" | head -6 >&2
    fi
else
    bad "LIR: the functor fixture did not compile on one of the two paths"
    sed 's/^/  /' "$work/ast.log" "$work/lir.log" | head -6 >&2
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p3/functor (sugar, diagnostics, zero cost, LIR)"
