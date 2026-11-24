#!/usr/bin/env bash
# LANG-29 S4 / B4 probe: `map binding` as the third lookup source of the
# D-020 binding-site conversion.
#
# E-l29b4-1: a `map binding <Source> -> <Target> { from(x) -> call; }` in an
#            imported `.m.ct` is found by the four binding sites (declaration,
#            assignment, `return`) and by the explicit `.as<T>()` spelling.
# E-l29b4-2: the recipe is expanded at the use site; no wrapper, vtable,
#            interface or runtime registry is emitted for the binding.
# E-l29b4-3: the lookup order is inherent `as` -> `map binding` -> imported
#            `map trait`; the earlier source wins when both exist.
# E-l29b4-4: a pair served by two imported bindings is a hard error naming
#            both units; the lookup is one hop only (A->B and B->C do not
#            convert A->C).
# E-l29b4-5: a binding that is not imported is reported as a missing
#            conversion with an actionable `map binding` hint, not as an
#            undeclared identifier or a C type error.
# E-l29b4-6: an imported but unused binding contributes no code (zero cost).
#
# Usage: bash test/ast/l29b4_binding.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: l29b4_binding.sh <ct-ast>}
abs_ct() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *) printf '%s/%s' "$PWD" "$1" ;;
    esac
}
CT=$(abs_ct "$CT")
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/l29b4.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL l29b4: $1" >&2; }
dump() { sed 's/^/    /' "$1" >&2; }
has() { grep -qF -- "$2" "$1"; }
count() { grep -cF -- "$2" "$1" 2>/dev/null || true; }

# ---- E-l29b4-1/2/6: the fixture -------------------------------------------
fix="$root/test/ast/303_map_binding"
md="$tmp/fix.mod"
mkdir -p "$md"
if ! "$CT" build --emit-c -I "$fix" "$fix/prog.ct" -o "$md" >"$tmp/fix.log" 2>&1; then
    bad "the map-binding fixture did not build"
    dump "$tmp/fix.log"
else
    ok
fi
pc="$md/prog.c"
if [ -f "$pc" ]; then
    if [ "$(count "$pc" "node_to_num((")" -eq 4 ]; then
        ok
    else
        bad "expected four expanded recipes, found $(count "$pc" "node_to_num((")"
    fi
    if ! grep -qE '(^|[^A-Za-z0-9_])(Node_Num|_vtable|_iface)' "$pc"; then
        ok
    else
        bad "the binding emitted a wrapper / vtable / interface"
    fi
else
    bad "no product was written for the fixture root"
fi
if [ -f "$pc" ] && "$CC" -Wall -Wextra -std=c99 -I "$md" "$md"/*.c -o "$tmp/fix.bin" \
        >"$tmp/fix.cc" 2>&1; then
    if [ -s "$tmp/fix.cc" ]; then
        bad "the fixture C is not warning-free:"; dump "$tmp/fix.cc"
    else
        ok
    fi
    if "$tmp/fix.bin" >"$tmp/fix.out" 2>&1 \
       && cmp -s "$tmp/fix.out" "$fix/prog.expected.out"; then
        ok
    else
        bad "the fixture output drifted: $(cat "$tmp/fix.out" 2>/dev/null | tr '\n' ' ')"
    fi
else
    bad "the fixture C did not build: $(head -4 "$tmp/fix.cc" 2>/dev/null)"
fi

# ---- the module tree every negative/order case reuses ---------------------
mod="$tmp/mod"
mkdir -p "$mod"
cat >"$mod/shapes.h.ct" <<'CT'
pub struct Node { int v; }
pub struct Num  { int n; }
pub struct A { int v; }
pub struct B { int v; }
pub struct C { int v; }

pub struct Num node_to_num(struct Node x) { Num r = { x.v + 7 }; return r; }
pub struct Num node_to_num2(struct Node x) { Num r = { x.v + 9 }; return r; }
pub struct Num node_to_trait(struct Node x) { Num r = { x.v + 100 }; return r; }
pub struct B a_to_b(struct A a) { B r = { a.v + 1 }; return r; }
pub struct C b_to_c(struct B b) { C r = { b.v + 2 }; return r; }
CT
cat >"$mod/ops.m.ct" <<'CT'
map binding struct Node -> struct Num {
    from(n) -> node_to_num(n);
}
CT
cat >"$mod/ops2.m.ct" <<'CT'
map binding struct Node -> struct Num {
    from(n) -> node_to_num2(n);
}
CT
cat >"$mod/ops_trait.m.ct" <<'CT'
pub trait NodeToNum { struct Num as(); }
map trait NodeToNum for type struct Node {
    as(n) -> node_to_trait(n);
}
CT
cat >"$mod/ab.m.ct" <<'CT'
map binding struct A -> struct B {
    from(a) -> a_to_b(a);
}
CT
cat >"$mod/bc.m.ct" <<'CT'
map binding struct B -> struct C {
    from(b) -> b_to_c(b);
}
CT

cat >"$mod/positive.ct" <<'CT'
import shapes;
import ops;
#include <stdio.h>
int main(void) {
    struct Node n = { 5 };
    struct Num a = n;
    printf("%d\n", a.n);
    return 0;
}
CT
cat >"$mod/unused.ct" <<'CT'
import shapes;
import ops;
int main(void) {
    struct Node n = { 5 };
    return n.v;
}
CT
cat >"$mod/nomap.ct" <<'CT'
import shapes;
int main(void) {
    struct Node n = { 5 };
    struct Num a = n;
    return a.n == 500 ? 0 : 1;
}
CT
cat >"$mod/amb.ct" <<'CT'
import shapes;
import ops;
import ops2;
int main(void) {
    struct Node n = { 5 };
    struct Num a = n;
    return a.n;
}
CT
cat >"$mod/order_trait.ct" <<'CT'
import shapes;
import ops;
import ops_trait;
#include <stdio.h>
int main(void) {
    struct Node n = { 5 };
    struct Num a = n;
    printf("%d\n", a.n);
    return 0;
}
CT
cat >"$mod/onehop.ct" <<'CT'
import shapes;
import ab;
import bc;
int main(void) {
    struct A a = { 5 };
    struct C c = a;
    return c.v;
}
CT
cat >"$mod/inherent.ct" <<'CT'
import ops;
struct Node { int v; }
struct Num  { int n; }
impl Node {
    Num as() { Num r = { self->v * 100 }; return r; }
}
int main(void) {
    struct Node n = { 5 };
    struct Num a = n;
    return a.n == 500 ? 0 : 1;
}
CT

build() { # name -> exit status; logs in $tmp/<name>.log, products in $tmp/<name>.mod
    n=$1
    rm -rf "$tmp/$n.mod"
    mkdir -p "$tmp/$n.mod"
    "$CT" build --emit-c -I "$mod" "$mod/$n.ct" -o "$tmp/$n.mod" \
        >"$tmp/$n.log" 2>&1
}

# E-l29b4-1: the imported binding converts
if build positive; then
    if has "$tmp/positive.mod/positive.c" "node_to_num((n))"; then
        ok
    else
        bad "the imported binding did not expand its recipe"
    fi
else
    bad "the imported binding did not convert: $(head -2 "$tmp/positive.log")"
fi

# E-l29b4-6: imported but unused -> no code from the binding
if build unused; then
    if [ "$(count "$tmp/unused.mod/unused.c" "node_to_num(")" -eq 0 ]; then
        ok
    else
        bad "an unused binding reached the generated C"
    fi
else
    bad "the unused-binding consumer did not build: $(head -2 "$tmp/unused.log")"
fi

# E-l29b4-3a: binding wins over an imported map trait
if build order_trait; then
    oc="$tmp/order_trait.mod/order_trait.c"
    if has "$oc" "node_to_num((n))" && ! has "$oc" "node_to_trait"; then
        ok
    else
        bad "the lookup order is not inherent -> binding -> map trait"
    fi
else
    bad "binding + trait consumer did not build: $(head -2 "$tmp/order_trait.log")"
fi

# E-l29b4-3b: an inherent `as` wins over the binding
if build inherent; then
    ic="$tmp/inherent.mod/inherent.c"
    if has "$ic" "Node_as(&n)" && ! has "$ic" "node_to_num"; then
        ok
    else
        bad "the inherent as method did not win over the binding"
    fi
    if "$CC" -Wall -Wextra -std=c99 "$tmp/inherent.mod"/*.c -o "$tmp/inherent.bin" \
            >"$tmp/inherent.cc" 2>&1 && "$tmp/inherent.bin"; then
        ok
    else
        bad "the inherent-wins program exited non-zero"
    fi
else
    bad "the inherent-wins consumer did not build: $(head -2 "$tmp/inherent.log")"
fi

# E-l29b4-5: not imported -> missing conversion with the map-binding hint
if build nomap; then
    bad "an unimported binding was accepted"
elif ! grep -qF "no conversion from 'struct Node' to 'struct Num'" "$tmp/nomap.log"; then
    bad "unimported: missing the conversion diagnostic: $(head -2 "$tmp/nomap.log")"
elif ! grep -qF "map binding" "$tmp/nomap.log"; then
    bad "unimported: the diagnostic is not actionable: $(head -2 "$tmp/nomap.log")"
else
    ok
fi

# E-l29b4-4a: two imported bindings for one pair -> ambiguity
if build amb; then
    bad "two imported bindings for one pair were accepted"
elif ! grep -qF "ambiguous map binding" "$tmp/amb.log"; then
    bad "ambiguity: missing the ambiguity diagnostic: $(head -3 "$tmp/amb.log")"
elif ! grep -qF "ops.m.ct" "$tmp/amb.log" || ! grep -qF "ops2.m.ct" "$tmp/amb.log"; then
    bad "ambiguity: both candidate units are not named: $(cat "$tmp/amb.log")"
else
    ok
fi

# E-l29b4-4b: one hop only -- A->B and B->C do not convert A->C
if build onehop; then
    bad "a two-hop binding chain was accepted"
elif ! grep -qF "no conversion from 'struct A' to 'struct C'" "$tmp/onehop.log"; then
    bad "one-hop: missing the conversion diagnostic: $(head -2 "$tmp/onehop.log")"
else
    ok
fi

if [ "$fail" -eq 0 ]; then
    echo "l29b4: $pass passed, 0 failed"
    echo "OK l29b4"
else
    echo "l29b4: $pass passed, $fail failed" >&2
    exit 1
fi
