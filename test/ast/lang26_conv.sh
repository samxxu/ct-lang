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

exit $fail
