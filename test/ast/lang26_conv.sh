#!/usr/bin/env bash
# LANG-26 / D-020 probe: the binding-site conversion's safety net.
#
#   1. control group: a bare binding-site conversion emits byte-for-byte the
#      same C as the explicit `x.as<T>()` call (D-020 §1 "生成 C");
#   2. the strict tier `to<T>()` refuses a method that answers some other
#      Option;
#   3. two imported mapping traits make the call ambiguous, and the diagnostic
#      lists both candidates;
#   4. a missing mapping import is reported as a missing conversion with an
#      actionable import hint, not as an undeclared identifier.
#
# Usage: bash test/ast/lang26_conv.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: lang26_conv.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/lang26conv.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL lang26/conv: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

# ---- 1. control group -------------------------------------------------------
cat >"$work/bare.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node {
    Num as() {
        Num n = { self->v + 1 };
        return n;
    }
}
int main(void) {
    Node node = { 5 };
    Num a = node;
    return a.v;
}
CT
sed 's/Num a = node;/Num a = node.as<Num>();/' "$work/bare.ct" >"$work/expl.ct"
mkdir -p "$work/ctl"
cp "$work/bare.ct" "$work/ctl/prog.ct"
if ! "$CT" "$work/ctl/prog.ct" -o "$work/c1.c" >"$work/c1.log" 2>&1; then
    bad "control: the bare form did not compile" "$(cat "$work/c1.log")"
elif ! cp "$work/expl.ct" "$work/ctl/prog.ct" \
     || ! "$CT" "$work/ctl/prog.ct" -o "$work/c2.c" >"$work/c2.log" 2>&1; then
    bad "control: the explicit form did not compile" "$(cat "$work/c2.log")"
elif ! diff -u "$work/c1.c" "$work/c2.c" >"$work/diff" 2>&1; then
    bad "control: bare and explicit C differ" "$(head -20 "$work/diff")"
else
    ok "control: bare binding site == explicit .as<T>() byte for byte"
fi

# ---- 2. strict tier mismatch ----------------------------------------------
cat >"$work/strict.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
struct Other { int v; }
impl Node {
    Option<Num> to() {
        Option<Num> o = Option<Num>::none();
        return o;
    }
}
int main(void) {
    Node node = { 5 };
    Option<Other> o = node.to<Other>();
    return 0;
}
CT
if "$CT" "$work/strict.ct" -o "$work/strict.c" >"$work/strict.log" 2>&1; then
    bad "strict: a mismatched to<T>() target was accepted"
elif ! grep -qF "no strict conversion" "$work/strict.log"; then
    bad "strict: missing the strict diagnostic" "$(cat "$work/strict.log")"
else
    ok "strict: to<T>() names a wrong Option result"
fi

# ---- 3/4. mapping traits: ambiguity and a missing import --------------------
mkdir -p "$work/mod/lib"
cat >"$work/mod/lib/types.h.ct" <<'CT'
pub struct Node { int v; }
pub struct Num  { int v; }
pub struct Num node_to_num(struct Node n) {
    Num r = { n.v + 7 };
    return r;
}
CT
cat >"$work/mod/lib/ops1.m.ct" <<'CT'
namespace lib;
pub trait NodeOps1 { struct Num as(); }
map trait NodeOps1 for type struct Node {
    as(n) -> node_to_num(n);
}
CT
sed 's/NodeOps1/NodeOps2/g' "$work/mod/lib/ops1.m.ct" >"$work/mod/lib/ops2.m.ct"
cat >"$work/mod/bare.ct" <<'CT'
import lib::types;
import lib::ops1;
struct Num make(struct Node n) { return n; }
int main(void) {
    struct Node node = { 5 };
    struct Num a = node;
    return a.v;
}
CT
cat >"$work/mod/amb.ct" <<'CT'
import lib::types;
import lib::ops1;
import lib::ops2;
int main(void) {
    struct Node node = { 5 };
    struct Num a = node;
    return a.v;
}
CT
cat >"$work/mod/nomap.ct" <<'CT'
import lib::types;
int main(void) {
    struct Node node = { 5 };
    struct Num a = node;
    return a.v;
}
CT
mkdir -p "$work/mod/out" "$work/mod/outa" "$work/mod/outn"
if ! "$CT" build --emit-c -I "$work/mod" "$work/mod/bare.ct" -o "$work/mod/out" >"$work/mod/bare.log" 2>&1; then
    bad "mapping: the imported trait did not convert" "$(cat "$work/mod/bare.log")"
elif ! grep -qF "node_to_num((node))" "$work/mod/out/bare.c"; then
    bad "mapping: the recipe was not expanded" "$(head -5 "$work/mod/out/bare.c")"
else
    ok "mapping: an imported trait expands to its recipe"
fi
if "$CT" build --emit-c -I "$work/mod" "$work/mod/amb.ct" -o "$work/mod/outa" >"$work/mod/amb.log" 2>&1; then
    bad "ambiguity: two imported traits were accepted"
elif ! grep -qF "ambiguous" "$work/mod/amb.log" \
     || ! grep -qF "NodeOps1" "$work/mod/amb.log" \
     || ! grep -qF "NodeOps2" "$work/mod/amb.log"; then
    bad "ambiguity: the candidates are not both named" "$(cat "$work/mod/amb.log")"
else
    ok "ambiguity: both candidate traits are named"
fi
if "$CT" build --emit-c -I "$work/mod" "$work/mod/nomap.ct" -o "$work/mod/outn" >"$work/mod/nomap.log" 2>&1; then
    bad "unimported: a missing mapping was accepted"
elif ! grep -qF "no conversion from 'struct Node' to 'struct Num'" "$work/mod/nomap.log" \
     || ! grep -qF "import a mapping trait" "$work/mod/nomap.log"; then
    bad "unimported: the diagnostic is not actionable" "$(cat "$work/mod/nomap.log")"
else
    ok "unimported: the diagnostic names the missing conversion and the import"
fi

# ---- 5. --types stays clean on the positive fixture -------------------------
if ! "$CT" check --types test/ast/296_binding_conv_as/prog.ct >"$work/types.log" 2>&1; then
    bad "--types: the positive fixture is not clean" "$(cat "$work/types.log")"
else
    ok "--types: the four binding positions stay FP-free"
fi

# ---- 6. `out` write-back: both directions convert through a temporary ------
cat >"$work/outconv.ct" <<'CT'
#include <stdio.h>

struct Node { int v; }
struct Num  { int v; }

impl Node {
    Num as() {
        Num n = { self->v + 1 };
        return n;
    }
}

impl Num {
    Node as() {
        Node n = { self->v + 2 };
        return n;
    }
}

int take(out Num n)
{
    Num t = { 9 };
    n = t;
    return 1;
}

int main(void)
{
    Node node = { 5 };
    int ok = take(node);
    printf("%d %d\n", ok, node.v);
    return 0;
}
CT
mkdir -p "$work/outconv"
if ! "$CT" build --emit-c "$work/outconv.ct" -o "$work/outconv" >"$work/outconv.log" 2>&1; then
    bad "out: the convertible out actual did not compile" "$(cat "$work/outconv.log")"
elif ! grep -qF "Node_as(&node)" "$work/outconv/outconv.c" \
     || ! grep -qF "Num_as(&_ct_outconv" "$work/outconv/outconv.c"; then
    bad "out: the generated C is not the two explicit conversions" \
        "$(grep -n 'Node_as\|Num_as' "$work/outconv/outconv.c" | head -3)"
elif ! "${CC:-cc}" -Wall -Wextra -std=c99 "$work/outconv/outconv.c" \
        -o "$work/outconv/outconv.bin" >"$work/outconv.cc.log" 2>&1; then
    bad "out: the generated C does not build" "$(head -3 "$work/outconv.cc.log")"
elif [ "$("$work/outconv/outconv.bin")" != "1 11" ]; then
    bad "out: the call did not write the converted value back" \
        "$("$work/outconv/outconv.bin")"
else
    ok "out: a convertible out actual converts both ways and writes back"
fi

# ---- 7. failure paths keep the write-back (false / err:) --------------------
cat >"$work/outfail.ct" <<'CT'
#include <stdio.h>

struct Node { int v; }
struct Num  { int v; }

impl Node { Num as() { Num n = { self->v + 1 }; return n; } }
impl Num  { Node as() { Node n = { self->v + 2 }; return n; } }

int fail_false(out Num n) { Num t = { 8 }; n = t; return 0; }
Result<int, int> fail_err(out Num n) {
    Num t = { 7 };
    n = t;
    return err: (Result<int, int>){ 0, 0, -1 };
}

int main(void)
{
    Node a = { 5 };
    int f = fail_false(a);
    Node b = { 5 };
    Result<int, int> r = fail_err(b);
    printf("%d %d %d %d\n", f, a.v, r.ok, b.v);
    return 0;
}
CT
mkdir -p "$work/outfail"
if ! "$CT" build --emit-c "$work/outfail.ct" -o "$work/outfail" >"$work/outfail.log" 2>&1; then
    bad "out/fail: the failure-path fixture did not compile" "$(cat "$work/outfail.log")"
elif ! "${CC:-cc}" -Wall -Wextra -std=c99 "$work/outfail"/*.c \
        -o "$work/outfail/outfail.bin" >"$work/outfail.cc.log" 2>&1; then
    bad "out/fail: the generated C does not build" "$(head -3 "$work/outfail.cc.log")"
elif [ "$("$work/outfail/outfail.bin")" != "0 10 0 9" ]; then
    bad "out/fail: a failed call rolled the converted value back" \
        "$("$work/outfail/outfail.bin")"
else
    ok "out/fail: false and err: exits keep the callee's write-back"
fi

# ---- 8. an unwritten out is a hard error, so 'keep the old value' cannot be
#         a silently reachable state of a conforming callee ------------------
cat >"$work/outunwritten.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node { Num as() { Num n = { self->v + 1 }; return n; } }
int take(out Num n) { return 0; }
int main(void) { Node node = { 5 }; return take(node); }
CT
if "$CT" check "$work/outunwritten.ct" >"$work/outunwritten.log" 2>&1; then
    bad "out/unwritten: a callee that never assigns its out formal was accepted"
elif ! grep -qF "out parameter 'n' is not assigned on every path" "$work/outunwritten.log"; then
    bad "out/unwritten: wrong diagnostic" "$(cat "$work/outunwritten.log")"
else
    ok "out/unwritten: L1 rejects the only shape that could skip the write-back"
fi

# ---- 9. neither direction may be missing -----------------------------------
cat >"$work/outirreversible.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node { Num as() { Num n = { self->v + 1 }; return n; } }
int take(out Num n) { Num t = { 9 }; n = t; return 1; }
int main(void) { Node node = { 5 }; return take(node); }
CT
if "$CT" check "$work/outirreversible.ct" >"$work/outirreversible.log" 2>&1; then
    bad "out/irreversible: a one-way conversion was accepted"
elif ! grep -qF "no conversion from 'struct Num' to 'struct Node'" "$work/outirreversible.log"; then
    bad "out/irreversible: wrong diagnostic" "$(cat "$work/outirreversible.log")"
else
    ok "out/irreversible: the missing formal -> actual direction is a hard error"
fi

# ---- 10. two imported traits on one direction are ambiguous ----------------
mkdir -p "$work/amb/lib" "$work/amb/lib2" "$work/amb/out"
cat >"$work/amb/lib/types.h.ct" <<'CT'
pub struct Node { int v; }
pub struct Num  { int v; }
CT
cat >"$work/amb/lib/fns.h.ct" <<'CT'
pub struct Node node_to_num(struct Node n) { struct Node r = { n.v + 1 }; return r; }
pub struct Num num_to_node(struct Num n) { struct Num r = { n.v + 2 }; return r; }
CT
cat >"$work/amb/lib/ops1.m.ct" <<'CT'
import lib::fns;
namespace lib;
pub trait ToNum1 { struct Num as(); }
map trait ToNum1 for type struct Node {
    as(n) -> node_to_num(n);
}
pub trait ToNode { struct Node as(); }
map trait ToNode for type struct Num {
    as(n) -> num_to_node(n);
}
CT
cat >"$work/amb/lib2/ops2.m.ct" <<'CT'
import lib::fns;
namespace lib2;
pub trait ToNum2 { struct Num as(); }
map trait ToNum2 for type struct Node {
    as(n) -> node_to_num(n);
}
CT
cat >"$work/amb/main.ct" <<'CT'
import lib::types;
import lib::fns;
import lib::ops1;
import lib2::ops2;
int take(out struct Num n) { struct Num t = { 9 }; n = t; return 1; }
int main(void) { struct Node node = { 5 }; return take(node); }
CT
if "$CT" build --emit-c -I "$work/amb" "$work/amb/main.ct" -o "$work/amb/out" \
        >"$work/amb/amb.log" 2>&1; then
    bad "out/ambiguity: two imported forward conversions were accepted"
elif ! grep -qF "ambiguous" "$work/amb/amb.log" \
     || ! grep -qF "ToNum1" "$work/amb/amb.log" \
     || ! grep -qF "ToNum2" "$work/amb/amb.log"; then
    bad "out/ambiguity: the candidates are not both named" "$(cat "$work/amb/amb.log")"
else
    ok "out/ambiguity: the two candidates are named"
fi

# ---- 11. an unimported mapping is still a missing conversion ----------------
cat >"$work/amb/nomap.ct" <<'CT'
import lib::types;
import lib::fns;
int take(out struct Num n) { struct Num t = { 9 }; n = t; return 1; }
int main(void) { struct Node node = { 5 }; return take(node); }
CT
mkdir -p "$work/amb/outn"
if "$CT" build --emit-c -I "$work/amb" "$work/amb/nomap.ct" -o "$work/amb/outn" \
        >"$work/amb/nomap.log" 2>&1; then
    bad "out/unimported: a missing out conversion was accepted"
elif ! grep -qF "no conversion from 'struct Node' to 'struct Num'" "$work/amb/nomap.log" \
     || ! grep -qF "import a mapping trait" "$work/amb/nomap.log"; then
    bad "out/unimported: the diagnostic is not actionable" "$(cat "$work/amb/nomap.log")"
else
    ok "out/unimported: the diagnostic names the conversion and the import"
fi

# ---- 12. CT_BINDING_CONVERSION=0: four sites are v1.0 again -----------------
cat >"$work/offdecl.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node { Num as() { Num n = { self->v + 1 }; return n; } }
int main(void) { Node node = { 5 }; Num a = node; return a.v; }
CT
if CT_BINDING_CONVERSION=0 "$CT" check --types "$work/offdecl.ct" >"$work/offdecl.log" 2>&1; then
    bad "switch: a declaration converted while CT_BINDING_CONVERSION=0"
elif ! grep -qF "initializer: expected 'struct Num', got 'struct Node'" "$work/offdecl.log"; then
    bad "switch: the declaration diagnostic is not the v1.0 text" "$(cat "$work/offdecl.log")"
elif ! CT_BINDING_CONVERSION=0 "$CT" check "$work/outconv.ct" >"$work/offout.log" 2>&1; then
    if grep -qF "type mismatch: 'take' argument 1: expected 'struct Num', got 'struct Node'" \
            "$work/offout.log"; then
        ok "switch: off restores the v1.0 declaration and out diagnostics"
    else
        bad "switch: the out diagnostic is not the v1.0 mismatch" "$(cat "$work/offout.log")"
    fi
else
    bad "switch: an out conversion ran while CT_BINDING_CONVERSION=0"
fi
cat >"$work/offexplicit.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node { Num as() { Num n = { self->v + 1 }; return n; } }
int main(void) { Node node = { 5 }; Num a = node.as<Num>(); return a.v; }
CT
if CT_BINDING_CONVERSION=0 "$CT" check "$work/offexplicit.ct" >"$work/offexplicit.log" 2>&1; then
    ok "switch: an explicit .as<T>() is unaffected"
else
    bad "switch: off also disabled the explicit .as<T>()" "$(cat "$work/offexplicit.log")"
fi
if CT_BINDING_CONVERSION=1 "$CT" check "$work/outconv.ct" >"$work/onout.log" 2>&1; then
    ok "switch: the default-on value keeps the out conversion"
else
    bad "switch: CT_BINDING_CONVERSION=1 did not keep the conversion" "$(cat "$work/onout.log")"
fi

# ---- 13. decode<T> boundary: a bare binding never calls decode --------------
cat >"$work/decode.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node {
    Num as() { Num n = { self->v + 1 }; return n; }
    Num decode() { Num n = { self->v + 99 }; return n; }
}
Num make(Node n) { return n; }
int main(void) { Node node = { 5 }; Num a = make(node); return a.v; }
CT
mkdir -p "$work/decode"
if ! "$CT" build --emit-c "$work/decode.ct" -o "$work/decode" >"$work/decode.log" 2>&1; then
    bad "decode: the fixture did not compile" "$(cat "$work/decode.log")"
elif ! grep -qF "return Node_as(&n)" "$work/decode/decode.c" \
     || grep -qF "Node_decode(&n)" "$work/decode/decode.c"; then
    bad "decode: a binding site called decode" \
        "$(grep -n 'Node_as\|Node_decode' "$work/decode/decode.c" | head -3)"
else
    ok "decode: a bare binding site calls as, never decode"
fi
cat >"$work/decodeonly.ct" <<'CT'
struct Node { int v; }
struct Num  { int v; }
impl Node { Num decode() { Num n = { self->v + 99 }; return n; } }
Num make(Node n) { return n; }
int main(void) { Node node = { 5 }; Num a = make(node); return a.v; }
CT
if "$CT" check "$work/decodeonly.ct" >"$work/decodeonly.log" 2>&1; then
    bad "decode: decode() was accepted as a binding-site conversion"
elif ! grep -qF "no conversion from 'struct Node' to 'struct Num'" "$work/decodeonly.log"; then
    bad "decode: wrong diagnostic" "$(cat "$work/decodeonly.log")"
else
    ok "decode: a decode-only type is a missing conversion, not an implicit call"
fi

# ---- 14. the same write-back on inherent / trait method calls ---------------
cat >"$work/outmethod.ct" <<'CT'
#include <stdio.h>

struct Num { int v; }
trait Taker { int take(out Num n); }
struct Node { int v; } use Taker;

impl Node {
    Num as() { Num n = { self->v + 1 }; return n; }
    int own(out Num n) { Num t = { 9 }; n = t; return 2; }
}

impl Num {
    Node as() { Node n = { self->v + 2 }; return n; }
}

impl Taker for Node {
    int take(out Num n) { Num t = { 9 }; n = t; return 3; }
}

int main(void)
{
    Node node = { 5 };
    int a = node.own(node);
    int b = node.take(node);
    printf("%d %d %d %d\n", a, node.v, b, node.v);
    return 0;
}
CT
mkdir -p "$work/outmethod"
if ! "$CT" build --emit-c "$work/outmethod.ct" -o "$work/outmethod" >"$work/outmethod.log" 2>&1; then
    bad "out/method: the method-call fixture did not compile" "$(cat "$work/outmethod.log")"
elif ! "${CC:-cc}" -Wall -Wextra -std=c99 "$work/outmethod"/*.c \
        -o "$work/outmethod/outmethod.bin" >"$work/outmethod.cc.log" 2>&1; then
    bad "out/method: the generated C does not build" "$(head -3 "$work/outmethod.cc.log")"
elif [ "$("$work/outmethod/outmethod.bin")" != "2 11 3 11" ]; then
    bad "out/method: the method write-back is missing" \
        "$("$work/outmethod/outmethod.bin")"
else
    ok "out/method: inherent and trait calls write the converted value back"
fi

exit $fail
