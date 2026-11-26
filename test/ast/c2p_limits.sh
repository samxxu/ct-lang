#!/usr/bin/env bash
# v1-PH-2 S1a-0 C2p probe: the remaining one-shot text scratches are gone.
#
# C2p runs in batches of 4-6 units; this file grows one section per batch.
#
#   C2p-1 qualified path: the qpath/cname output buffers were `char[160]`, so a
#          qualified name whose underscore form was longer than 159 bytes was
#          refused with "qualified name is too long" even though every segment
#          was short. A qualified variable and a qualified call are compiled and
#          run, and the generated C must carry the whole mangled spelling.
#
#   C2p-4 persistent type texts: the rows a spelling outlives its parse call --
#          a trait method's parameter (MethodSig.ptype), a trait impl's return
#          (Symbols.ret_type), a closure literal's parameters, the map-binding
#          registry, the ADT variant/field rows, the type-alias expander -- are
#          pointer rows of interned texts. Each unit compiles a 2000-byte
#          spelling, runs it and checks the emitted C.
#
#   C2p-5 caller rows and keys: every `expr_type`/`expr_ctype` call now reads
#          through the pool-text form (no caller-sized out buffer); a closure's
#          capture list, the trait a default body / generic bound names, the
#          function-pointer declarator name and the ADT tag are pool texts; and
#          the comparison keys (`type_key` / `bind_conv_key` / `map_bind_key`)
#          compare the whole spelling, so two types that agree for 159 bytes no
#          longer collide. The 2000-byte fixtures run end to end.
#
#   C2p-6 map/generic host rows: the map type host, the generic argument, the
#          match result key and the `foreach` element are pool texts, and
#          `_Atomic` / `_Alignas` carry whole specifier spellings.
#
#   C2p-7 member / method / label / match-binding names: a member name
#          (`.` / `->` / `?.`), a trait impl method name, an enum member, a
#          C label / `goto` target and a `match` arm binding are pool texts,
#          so a 2000-byte name survives the symbol lookup and every emitted
#          spelling (prototype, definition, call, initialiser designator).
#
#   C2p-9 the remaining expression/statement/parser scratch rows: a map
#          binding's recipe, the receiver type of an inherent `as` and the
#          variable a diagnostic quotes are no longer cut at 159 bytes.
#
#   C2p-8 the emitter's remaining reader rows: the C base tag of a type,
#          the interned lifetime prefix, the lower-cased vptr field name, the
#          `Result` operand / column spellings, the map recipe parameter type
#          and suffix, the closure owner mangling and the Drop-glue field type
#          are pool texts or growable blocks rather than 160-byte rows.
#
#   C2p-11 the last fixed rows: a 2000-byte package name survives the manifest
#          reader (the index row is written whole), a 2000-byte struct boxes
#          correctly in an interface initialiser (the initialiser rewrite used
#          a 160-byte field-type row), a 2000-byte namespace maps to its
#          directory and mangles an exported global whole, and the `own`
#          diagnostic quotes a 2000-byte struct name whole.
#
# Usage: bash test/ast/c2p_limits.sh <ct-ast>
set -u
CT=${1:?usage: c2p_limits.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/c2p.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL c2p: $1" >&2; }
CC=${CC:-cc}
export CT_C_BOUNDARY=allow

# run_product <name> <source> [extra ct args...]
# one unit -> emitted C -> cc -> run; the caller checks the C separately when
# it needs to pin a full spelling.
run_product() {
    name=$1; src=$2; shift 2
    if ! "$CT" "$src" -o "$work/$name.c" "$@" >"$work/$name.log" 2>&1; then
        bad "$name: compile failed: $(head -2 "$work/$name.log" | tr '\n' ' ')"
        return 1
    fi
    if ! "$CC" -std=c99 "$work/$name.c" -o "$work/$name.bin" >"$work/$name.cc" 2>&1; then
        bad "$name: cc failed: $(head -2 "$work/$name.cc" | tr '\n' ' ')"
        return 1
    fi
    if "$work/$name.bin"; then return 0; fi
    bad "$name: program returned non-zero"
    return 1
}

# ---- C2p-1.1) qualified variable whose underscore form is >160 bytes --------
# Three 60-byte namespace segments: the qualifier joins to 181 bytes, which the
# old qpath[160] refused before the symbol lookup could even run.
seg=$(printf '%*s' 60 '' | tr ' ' a)
ns="$seg::$seg::$seg"
mangled="${ns//::/_}"
cat >"$work/qv.ct" <<CT
namespace $ns;
int h = 7;
int main(void) { return $ns::h == 7 ? 0 : 1; }
CT
if run_product qv "$work/qv.ct"; then
    if grep -qF "${mangled}_h" "$work/qv.c"; then
        ok; printf '  >160-byte qualified variable: resolved and emitted whole\n'
    else
        bad "the generated C cut the >160-byte qualified variable spelling"
    fi
fi

# ---- C2p-1.2) qualified call whose underscore form is >160 bytes -----------
cat >"$work/qc.ct" <<CT
namespace $ns;
pub int bump(void) { return 7; }
int main(void) { return $ns::bump() == 7 ? 0 : 1; }
CT
if run_product qc "$work/qc.ct"; then
    if grep -qF "${mangled}_bump" "$work/qc.c"; then
        ok; printf '  >160-byte qualified call: resolved and emitted whole\n'
    else
        bad "the generated C cut the >160-byte qualified call spelling"
    fi
fi

# ---- C2p-1.3) 200/1000-byte literals stay byte-exact (guard) ----------------
lit200=$(printf '%*s' 200 '' | tr ' ' x)
lit1000=$(printf '%*s' 1000 '' | tr ' ' y)
cat >"$work/lit.ct" <<CT
int main(void)
{
    const char *p = "$lit200";
    const char *q = "$lit1000";
    return (p[0] == 'x' && p[199] == 'x' && p[200] == 0
            && q[0] == 'y' && q[999] == 'y' && q[1000] == 0) ? 0 : 1;
}
CT
if run_product lit "$work/lit.ct"; then
    if grep -qF "$lit200" "$work/lit.c" && grep -qF "$lit1000" "$work/lit.c"; then
        ok; printf '  200/1000-byte literals: kept whole\n'
    else
        bad "the generated C cut a 200/1000-byte literal"
    fi
fi

# ---- C2p-2.1) a diagnostic that embeds a 150-byte struct name ---------------
# The message is "trait method 'g' is not implemented for struct '<name>'":
# with the 150-byte name it is past 160 bytes, so the old Parser.emsg[160] cut
# the name itself off.
sname=$(printf '%*s' 150 '' | tr ' ' s)
cat >"$work/diagtrait.ct" <<CT
trait T { int f(); int g(); }
struct $sname { int n; } use T;
impl T for $sname { int f() { return 1; } }
int main(void) { return 0; }
CT
"$CT" check "$work/diagtrait.ct" >"$work/diagtrait.out" 2>"$work/diagtrait.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF "$sname" "$work/diagtrait.err" \
   && grep -qF "trait method 'g' is not implemented for struct" "$work/diagtrait.err"; then
    ok; printf '  long diagnostic: the 150-byte struct name is kept whole\n'
else
    bad "diag-trait: the 150-byte struct name is missing from the diagnostic (the message was cut at 160 bytes)"
fi

# ---- C2p-2.2) an arity warning naming a 300-byte callee --------------------
# Warn.var was a 160-byte row, so the warning named a truncated function.
fname=$(printf '%*s' 300 '' | tr ' ' f)
cat >"$work/diagwarn.ct" <<CT
int $fname(int a) { return a; }
int main(void) { return $fname(1, 2); }
CT
"$CT" compile "$work/diagwarn.ct" -o "$work/diagwarn.c" >"$work/diagwarn.out" 2>"$work/diagwarn.err"
if grep -qF "warning: arity mismatch" "$work/diagwarn.err" \
   && grep -qF "$fname" "$work/diagwarn.err"; then
    ok; printf '  arity warning: the 300-byte callee name is kept whole\n'
else
    bad "diag-warn: the 300-byte callee name is missing from the arity warning (Warn.var was cut at 160 bytes)"
fi

# ---- C2p-3.1) a 2000-byte struct name as a type, whole chain --------------
# The old `parse_type` caller rows, the type table's MAX_TEXT stride and the
# instance arg rows all cut at 160. This one unit exercises a local, a field,
# a parameter, a return type, an inherent method receiver and the method call.
long=$(printf '%*s' 2000 '' | tr ' ' s)
cat >"$work/long_struct.ct" <<CT
struct $long { int n; };
struct W { struct $long x; };
struct $long mk(int x) { struct $long v; v.n = x; return v; }
int add(struct $long a, struct $long b) { return a.n + b.n; }
impl $long { int get() { return self->n; } }
int main(void) {
    struct $long v; struct $long w; struct W box;
    v = mk(2); w = mk(3); box.x = v;
    return add(box.x, w) - 5 + v.get() - 2;
}
CT
if run_product long_struct "$work/long_struct.ct"; then
    if grep -qF "$long" "$work/long_struct.c"; then
        ok; printf '  2000-byte struct type: local/field/param/return/receiver kept whole\n'
    else
        bad "the generated C cut the 2000-byte struct type"
    fi
fi

# ---- C2p-3.2) a 2000-byte type as a generic struct argument ---------------
cat >"$work/long_inst_arg.ct" <<CT
struct $long { int n; };
struct Holder<T> { T x; };
int main(void) {
    struct Holder<struct $long> h;
    h.x.n = 4;
    return h.x.n - 4;
}
CT
if run_product long_inst_arg "$work/long_inst_arg.ct"; then
    if grep -qF "$long" "$work/long_inst_arg.c"; then
        ok; printf '  2000-byte generic argument: instance field kept whole\n'
    else
        bad "the generated C cut the 2000-byte generic argument"
    fi
fi

# ---- C2p-3.3) a 2000-byte generic template name ---------------------------
tmpl=$(printf '%*s' 2000 '' | tr ' ' t)
cat >"$work/long_tmpl.ct" <<CT
struct $tmpl<T> { T x; };
int main(void) {
    struct $tmpl<int> h;
    h.x = 9;
    return h.x - 9;
}
CT
if run_product long_tmpl "$work/long_tmpl.ct"; then
    ok; printf '  2000-byte template name: instance encoded from the whole spelling\n'
fi

# ---- C2p-3.4) a trait receiver / interface box with a 2000-byte struct ----
# The vptr writer's `type_needs_init` and `maybe_box`'s concrete-struct lookup
# were 160-byte rows, so the long-named struct never got its `__x_vptr`
# initialiser and boxing failed. This exercises impl receiver, vtable dispatch
# and the implicit box.
cat >"$work/long_trait.ct" <<CT
trait Getter { int get(); }
struct $long { int n; } use Getter;
impl Getter for $long { int get() { return self->n; } }
int main(void) {
    struct $long v = { .n = 4 };
    Getter g = v;
    return v.get() + g.get() - 8;
}
CT
if run_product long_trait "$work/long_trait.ct"; then
    ok; printf '  2000-byte trait receiver: vptr initialiser and interface box kept whole\n'
fi

# ===========================================================================
# C2p-4: the remaining persistent type spells (S1a-0 C2p-4)
#
# Every unit below stores the spelling past the parse call -- a trait method's
# parameter row, a closure literal, the map-binding registry, the ADT registry,
# the parser's `ret_type`, the type-alias expander -- so a 160-byte row there
# is a silent cut in emitted C even when the reader itself accepts the text.
# ===========================================================================

# ---- C2p-4.1) a 2000-byte parameter type on a trait method -----------------
# `MethodSig.ptype` was a `char *` block at MAX_TEXT stride; the trait reader's
# `ptype[MAX_TEXT]` local stopped first. The impl and the interface call must
# both see the whole type.
cat >"$work/c2p4_trait_param.ct" <<CT
trait Big { int id(struct $long x); }
struct $long { int n; } use Big;
impl Big for $long { int id(struct $long x) { return x.n; } }
int main(void) {
    struct $long v = { .n = 4 };
    Big b = v;
    return b.id(v) - 4;
}
CT
if run_product c2p4_trait_param "$work/c2p4_trait_param.ct"; then
    if grep -qF "$long" "$work/c2p4_trait_param.c"; then
        ok; printf '  2000-byte trait method parameter: kept whole in the signature\n'
    else
        bad "the generated C cut the 2000-byte trait method parameter type"
    fi
fi

# ---- C2p-4.2) a 2000-byte return type on a trait impl method ---------------
# The impl writes the return type into `Symbols.ret_type[160]` with a checked
# snprintf, so the old row refused it outright; the return statement then reads
# that spelling back for coercion and boxing.
cat >"$work/c2p4_trait_ret.ct" <<CT
trait Big { struct $long id(int x); }
struct $long { int n; } use Big;
impl Big for $long { struct $long id(int x) { struct $long r; r.n = x; return r; } }
int main(void) {
    struct $long v = { .n = 4 };
    Big b = v;
    struct $long w = b.id(4);
    return w.n - 4;
}
CT
if run_product c2p4_trait_ret "$work/c2p4_trait_ret.ct"; then
    ok; printf '  2000-byte trait method return: impl body and return kept whole\n'
fi

# ---- C2p-4.3) a closure literal with a 2000-byte parameter type ------------
# `Closure.ptype/pname` were `char[16][160]` rows filled by `closure_copy`,
# which refused a type at the 160-byte limit. The trampoline must spell the
# whole type in both the cast and the definition.
cat >"$work/c2p4_closure.ct" <<CT
struct $long { int n; };
int main(void) {
    int base = 2;
    struct $long v = { .n = 3 };
    int (*f)(struct $long) = (struct $long x) => x.n + base;
    return f(v) - 5;
}
CT
if run_product c2p4_closure "$work/c2p4_closure.ct"; then
    if grep -qF "$long" "$work/c2p4_closure.c"; then
        ok; printf '  2000-byte closure parameter: trampoline kept whole\n'
    else
        bad "the generated C cut the 2000-byte closure parameter type"
    fi
fi

# ---- C2p-4.4) a `map binding` whose source type is 2000 bytes --------------
# MapBuild.parse_binding read both sides into `char[MAX_TEXT]`; the persistent
# `host_type` / `bind_dst` rows were already pool texts, but the reader refused
# the spelling before it got there. The pair must match at the call site and
# the recipe must expand.
mbd="$work/mb"
mkdir -p "$mbd"
cat >"$mbd/shapes.h.ct" <<CT
pub struct $long { int v; }
pub struct Num { int n; }
pub struct Num long_to_num(struct $long x)
{
    Num r = { x.v + 7 };
    return r;
}
CT
cat >"$mbd/ops.m.ct" <<CT
map binding struct $long -> struct Num {
    from(x) -> long_to_num(x);
}
CT
cat >"$mbd/prog.ct" <<CT
import shapes;
import ops;
int main(void)
{
    struct $long node = { 5 };
    struct Num a = node;
    return a.n - 12;
}
CT
if mkdir -p "$work/mbout" \
   && "$CT" build --emit-c -I "$mbd" "$mbd/prog.ct" -o "$work/mbout" >"$work/mb.log" 2>&1; then
    if "$CC" -std=c99 -I "$work/mbout" "$work/mbout"/*.c -o "$work/mb.bin" >"$work/mb.cc" 2>&1 \
       && "$work/mb.bin"; then
        if grep -qF "$long" "$work/mbout/prog.c"; then
            ok; printf '  2000-byte map binding: host pair and recipe kept whole\n'
        else
            bad "the generated C cut the 2000-byte map binding host type"
        fi
    else
        bad "c2p4_map_binding: cc failed: $(head -2 "$work/mb.cc" | tr '\n' ' ')"
    fi
else
    bad "c2p4_map_binding: compile failed: $(head -2 "$work/mb.log" | tr '\n' ' ')"
fi

# ---- C2p-4.5) a 2000-byte ADT variant name --------------------------------
# The constructor lookahead stopped at MAX_TEXT and the match arm copied the
# name into a 160-byte row, so the variant read as an unknown member.
vn=$(printf '%*s' 2000 '' | tr ' ' v)
cat >"$work/c2p4_adt_variant.ct" <<CT
enum Shape { $vn(int r), Empty() }
int area(Shape s)
{
    match (s) {
        Shape.$vn(r) => { return r; }
        Shape.Empty() => { return 0; }
    }
}
int main(void)
{
    Shape c = Shape.$vn(7);
    return area(c) - 7;
}
CT
if run_product c2p4_adt_variant "$work/c2p4_adt_variant.ct"; then
    if grep -qF "$vn" "$work/c2p4_adt_variant.c"; then
        ok; printf '  2000-byte ADT variant name: constructor and match arm kept whole\n'
    else
        bad "the generated C cut the 2000-byte ADT variant name"
    fi
fi

# ---- C2p-4.6) a 2000-byte ADT payload field name --------------------------
# `AdtField.name` was a 160-byte row and the field reader copied the token into
# `char fname[MAX_TEXT]`, so the generated union member was silently shortened.
fn=$(printf '%*s' 2000 '' | tr ' ' f)
cat >"$work/c2p4_adt_field.ct" <<CT
enum Shape { V(int $fn), Empty() }
int area(Shape s)
{
    match (s) {
        Shape.V(r) => { return r; }
        Shape.Empty() => { return 0; }
    }
}
int main(void)
{
    Shape c = Shape.V(7);
    return area(c) - 7;
}
CT
if run_product c2p4_adt_field "$work/c2p4_adt_field.ct"; then
    if grep -qF "$fn" "$work/c2p4_adt_field.c"; then
        ok; printf '  2000-byte ADT field name: union member kept whole\n'
    else
        bad "the generated C cut the 2000-byte ADT field name"
    fi
fi

# ---- C2p-4.7) a type alias whose target is a 2000-byte type ---------------
# `expand_type_text`'s `id`/`eb` rows and its output cap stopped the expansion
# at 160 bytes; the alias was reported as "type alias is too long".
ad="$work/alias"
mkdir -p "$ad"
cat >"$ad/lib.h.ct" <<CT
pub struct $long { int n; };
pub type Big = struct $long;
pub Big ident(Big x) { return x; }
CT
cat >"$ad/prog.ct" <<CT
import lib;
int main(void)
{
    struct $long v = { .n = 3 };
    Big b = ident(v);
    return b.n - 3;
}
CT
if mkdir -p "$work/adout" \
   && "$CT" build --emit-c -I "$ad" "$ad/prog.ct" -o "$work/adout" >"$work/ad.log" 2>&1; then
    if "$CC" -std=c99 -I "$work/adout" "$work/adout"/*.c -o "$work/ad.bin" >"$work/ad.cc" 2>&1 \
       && "$work/ad.bin"; then
        if grep -qF "$long" "$work/adout/prog.c"; then
            ok; printf '  2000-byte type alias target: expanded and emitted whole\n'
        else
            bad "the generated C cut the 2000-byte type alias target"
        fi
    else
        bad "c2p4_type_alias: cc failed: $(head -2 "$work/ad.cc" | tr '\n' ' ')"
    fi
else
    bad "c2p4_type_alias: compile failed: $(head -2 "$work/ad.log" | tr '\n' ' ')"
fi

# ===========================================================================
# C2p-5: the last 160-byte caller rows (S1a-0 C2p-5)
#
# `expr_type` / `expr_ctype` used to be called with a `char[160]` out buffer at
# 38 sites, and a handful of rows outlived their parse call (the closure
# capture list, the trait a default body belongs to, the function-pointer
# declarator name, the generic bound, the ADT tag). The comparison keys
# (`type_key` / `bind_conv_key` / `map_bind_key`) were also cut at 160, so two
# spellings that agreed for 159 bytes collided.
# ===========================================================================

# ---- C2p-5.0) no expr_type/expr_ctype call passes a caller-sized row ------
# The migration's mechanical half: every call goes through the pool-text form.
nscratch=$(grep -rEn 'expr_(type|ctype)\([^;]*\(int\)[[:space:]]*sizeof|expr_(type|ctype)\([^;]*[[:space:]]sizeof[[:space:]]+[A-Za-z_]' \
              selfhost/ct-ast --include='*.h.ct' | wc -l | tr -d ' ')
if [ "$nscratch" -eq 0 ]; then
    ok; printf '  expr_type/expr_ctype: no caller-sized out buffer is passed\n'
else
    bad "$nscratch expr_type/expr_ctype call(s) still pass a caller-sized out buffer"
fi

# ---- C2p-5.1) a closure captures a 2000-byte name and a 2000-byte type ----
# `Closure.cap_name` / `.cap_type` were `char[16][160]` rows and `closure_copy`
# refused a spelling at the 160-byte limit.
capn=$(printf '%*s' 2000 '' | tr ' ' v)
cat >"$work/c2p5_closure_cap.ct" <<CT
struct $long { int n; };
int main(void) {
    int $capn = 3;
    struct $long a = { .n = 4 };
    int (*f)(void) = () => $capn + a.n;
    return f() - 7;
}
CT
if run_product c2p5_closure_cap "$work/c2p5_closure_cap.ct"; then
    if grep -qF "$capn" "$work/c2p5_closure_cap.c"; then
        ok; printf '  2000-byte closure capture: name and type kept whole\n'
    else
        bad "the generated C cut the 2000-byte captured name"
    fi
fi

# ---- C2p-5.2) a 2000-byte ADT tag (constructor and match arm) -------------
# The tag read as "not an ADT" once the declaration lookahead resolved it
# through a 160-byte row.
cat >"$work/c2p5_adt_tag.ct" <<CT
enum $long { Pay(int r), Empty() }
int area($long s)
{
    match (s) {
        $long.Pay(r) => { return r; }
        $long.Empty() => { return 0; }
    }
}
int main(void) { $long c = $long.Pay(7); return area(c) - 7; }
CT
if run_product c2p5_adt_tag "$work/c2p5_adt_tag.ct"; then
    if grep -qF "$long" "$work/c2p5_adt_tag.c"; then
        ok; printf '  2000-byte ADT tag: subject, constructor and arm kept whole\n'
    else
        bad "the generated C cut the 2000-byte ADT tag"
    fi
fi

# ---- C2p-5.3) a 2000-byte function-pointer declarator name ----------------
# `Expr.fnptr_name` was `char[160]`; the call named a function that did not
# exist under the cut spelling.
fpname=$(printf '%*s' 2000 '' | tr ' ' q)
cat >"$work/c2p5_fnptr_name.ct" <<CT
int inc(int x) { return x + 1; }
int main(void) { int (*$fpname)(int) = inc; return $fpname(2) - 3; }
CT
if run_product c2p5_fnptr_name "$work/c2p5_fnptr_name.ct"; then
    if grep -qF "$fpname" "$work/c2p5_fnptr_name.c"; then
        ok; printf '  2000-byte function-pointer name: declarator and call kept whole\n'
    else
        bad "the generated C cut the 2000-byte function-pointer name"
    fi
fi

# ---- C2p-5.4) a 2000-byte trait name in a default body and a bound --------
# `Symbols.trait_default` and `Expr.in_generic_bound` were 160-byte rows;
# `method_trait` answered into a caller row, so the dispatch fell through to a
# type-host map and reported "no method".
ttrait=$(printf '%*s' 2000 '' | tr ' ' t)
cat >"$work/c2p5_trait_name.ct" <<CT
trait $ttrait { int get(); int twice() { return self->get() * 2; } }
struct S { int n; } use $ttrait;
impl $ttrait for S { int get() { return self->n; } }
T pick<T: $ttrait>(T x) { return x; }
int main(void) {
    S s = { .n = 5 };
    S r = pick<S>(s);
    return r.twice() - 10;
}
CT
if run_product c2p5_trait_name "$work/c2p5_trait_name.ct"; then
    ok; printf '  2000-byte trait name: default body, adoption and bound kept whole\n'
fi

# ---- C2p-5.5) two long type keys that differ only after byte 159 ----------
# The two sources below are identical for the first 1000 bytes; the old
# `bind_conv_key`/`map_bind_key` rows produced one key, so the second
# conversion reported "ambiguous map binding". Each type must select its own.
kB=$(printf '%*s' 1000 '' | tr ' ' b)
tA="struct ${kB}X"
tB="struct ${kB}Y"
kbd="$work/c2p5_keys"
mkdir -p "$kbd"
cat >"$kbd/shapes.h.ct" <<CT
pub struct ${kB}X { int n; }
pub struct ${kB}Y { int n; }
pub struct Num { int n; }
pub struct Num from_a($tA x) { Num r = { x.n + 1 }; return r; }
pub struct Num from_b($tB x) { Num r = { x.n + 100 }; return r; }
CT
cat >"$kbd/ops.m.ct" <<CT
import shapes;
map binding $tA -> struct Num {
    from(x) -> from_a(x);
}
map binding $tB -> struct Num {
    from(x) -> from_b(x);
}
CT
cat >"$kbd/prog.ct" <<CT
import shapes;
import ops;
int main(void) {
    $tA a = { 1 };
    $tB b = { 2 };
    struct Num na = a;
    struct Num nb = b;
    return na.n * 1000 + nb.n - 2102;
}
CT
if mkdir -p "$work/c2p5_keys_out" \
   && "$CT" build --emit-c -I "$kbd" "$kbd/prog.ct" -o "$work/c2p5_keys_out" >"$work/c2p5_keys.log" 2>&1; then
    if "$CC" -std=c99 -I "$work/c2p5_keys_out" "$work/c2p5_keys_out"/*.c \
            -o "$work/c2p5_keys.bin" >"$work/c2p5_keys.cc" 2>&1 \
       && "$work/c2p5_keys.bin"; then
        if grep -qF "from_a" "$work/c2p5_keys_out/prog.c" \
           && grep -qF "from_b" "$work/c2p5_keys_out/prog.c"; then
            ok; printf '  long keys: the two bindings differ past byte 159 and each is chosen\n'
        else
            bad "the generated C lost one of the two long-key conversions"
        fi
    else
        bad "c2p5_keys: cc failed: $(head -2 "$work/c2p5_keys.cc" | tr '\n' ' ')"
    fi
else
    bad "c2p5_keys: compile failed: $(head -2 "$work/c2p5_keys.log" | tr '\n' ' ')"
fi


# ===========================================================================
# C2p-6: the last 160-byte host/argument rows (S1a-0 C2p-6)
#
# The map reader kept the host spellings in `char[MAX_TEXT]` rows, so
# `map trait T for type struct <2000-byte name>` was refused with
# "type is too long"; the emitter's `gtarg`/`gtparam` rows cut a 2000-byte
# generic argument, and the instance row kept the template's `T` in the
# emitted prototype. The secondary rows below (`match` result key, `foreach`
# element, `_Atomic` / `_Alignas` specifier) had the same 160-byte cut.
# ===========================================================================

# ---- C2p-6.1) a 2000-byte type host in one `map trait` unit ----------------
cat >"$work/c2p6_shapes.h.ct" <<CT
pub struct $long { int v; }
pub int big_get(struct $long x) { return x.v; }
CT
cat >"$work/c2p6_ops.m.ct" <<CT
import c2p6_shapes;
pub trait Getter { int get(); }
map trait Getter for type struct $long {
    get(x) -> big_get(x);
}
CT
cat >"$work/c2p6_map.ct" <<CT
import c2p6_shapes;
import c2p6_ops;
int main(void)
{
    struct $long node = { 5 };
    return node.get() - 5;
}
CT
if mkdir -p "$work/c2p6_map_out" \
   && "$CT" build --emit-c -I "$work" "$work/c2p6_map.ct" -o "$work/c2p6_map_out" \
        >"$work/c2p6_map.log" 2>&1; then
    if "$CC" -std=c99 -I "$work/c2p6_map_out" "$work/c2p6_map_out"/*.c \
            -o "$work/c2p6_map.bin" >"$work/c2p6_map.cc" 2>&1 \
       && "$work/c2p6_map.bin"; then
        if grep -qF "$long" "$work/c2p6_map_out/c2p6_map.c"; then
            ok; printf '  2000-byte map type host: the whole receiver type is kept\n'
        else
            bad "the generated C cut the 2000-byte map type host"
        fi
    else
        bad "c2p6_map: cc failed: $(head -2 "$work/c2p6_map.cc" | tr '\n' ' ')"
    fi
else
    bad "c2p6_map: compile failed: $(head -2 "$work/c2p6_map.log" | tr '\n' ' ')"
fi

# ---- C2p-6.2) a 2000-byte generic function argument -----------------------
cat >"$work/c2p6_gen.ct" <<CT
struct $long { int n; };
T ident<T>(T x) { return x; }
int main(void)
{
    struct $long v = { .n = 4 };
    struct $long w = ident<struct $long>(v);
    return w.n - 4;
}
CT
if run_product c2p6_gen "$work/c2p6_gen.ct"; then
    if grep -qF "$long" "$work/c2p6_gen.c" && ! grep -qE '(^|[^A-Za-z_/])T([^A-Za-z_/]|$)' "$work/c2p6_gen.c"; then
        ok; printf '  2000-byte generic argument: prototype and definition carry the whole type\n'
    else
        bad "the generated C kept the template parameter T or cut the 2000-byte argument"
    fi
fi

# ---- C2p-6.3) an expression match yielding a 2000-byte struct -------------
cat >"$work/c2p6_match.ct" <<CT
struct $long { int n; };
enum N { A(), B() }
struct $long pick(N x)
{
    struct $long a = { .n = 1 };
    struct $long b = { .n = 2 };
    return match (x) { N.A() => a, N.B() => b };
}
int main(void)
{
    N x = N.A();
    return pick(x).n - 1;
}
CT
if run_product c2p6_match "$work/c2p6_match.ct"; then
    if grep -qF "__ct_mres" "$work/c2p6_match.c" && grep -qF "$long" "$work/c2p6_match.c"; then
        ok; printf '  2000-byte match result type: the key and the temporary are whole\n'
    else
        bad "the generated C cut the 2000-byte match result type"
    fi
fi

# ---- C2p-6.4) foreach over an array of a 2000-byte struct -----------------
cat >"$work/c2p6_foreach.ct" <<CT
struct $long { int n; };
int main(void)
{
    struct $long a[2] = {{1}, {2}};
    int s = 0;
    foreach (a) { s = s + item.n; }
    return s - 3;
}
CT
if run_product c2p6_foreach "$work/c2p6_foreach.ct"; then
    ok; printf '  2000-byte foreach element: the item binding is whole\n'
fi

# ---- C2p-6.5) `_Atomic(<2000-byte typedef>)` and `_Alignas(...)` ---------
cat >"$work/c2p6_atomic.ct" <<CT
typedef int $long;
int main(void)
{
    _Atomic($long) n;
    n = 5;
    return n - 5;
}
CT
if run_product c2p6_atomic "$work/c2p6_atomic.ct"; then
    ok; printf '  2000-byte _Atomic specifier: kept whole\n'
fi
cat >"$work/c2p6_alignas.ct" <<CT
typedef int $long;
int main(void)
{
    _Alignas($long) int x = 3;
    return x - 3;
}
CT
if run_product c2p6_alignas "$work/c2p6_alignas.ct"; then
    ok; printf '  2000-byte _Alignas specifier: kept whole\n'
fi

# ===========================================================================
# C2p-7: the remaining name rows in the parser and the emitted spellings
#
# `parse_postfix` copied a member name into a 160-byte row, so a 2000-byte
# struct field resolved to a cut name: the declaration emitted whole, but every
# `s.<field>` access named a member that did not exist. `parse_impl` copied the
# method name the same way, so a 2000-byte trait method never matched the
# trait's row ("not implemented"); a `match` arm binding name was copied into a
# `calloc(nbind, MAX_TEXT)` block and declared under the cut spelling. The
# tests below pin the whole-chain spellings (prototype / definition / call) for
# a long field, a long trait method and a long match binding, and keep the long
# label and long `foreach` element as guards.
# ===========================================================================

# ---- C2p-7.1) a 2000-byte struct field name through declaration/access ----
fld=$(printf '%*s' 2000 '' | tr ' ' w)
cat >"$work/c2p7_field.ct" <<CT
struct S { int $fld; };
int main(void)
{
    struct S s;
    s.$fld = 3;
    return s.$fld - 3;
}
CT
if run_product c2p7_field "$work/c2p7_field.ct"; then
    if grep -qF "$fld" "$work/c2p7_field.c"; then
        ok; printf '  2000-byte struct field: declaration and access kept whole\n'
    else
        bad "the generated C cut the 2000-byte struct field name"
    fi
fi

# ---- C2p-7.1b) a 2000-byte struct field designator in an initialiser ----
cat >"$work/c2p7_field_designator.ct" <<CT
struct S { int $fld; };
int main(void)
{
    struct S s = { .$fld = 3 };
    return s.$fld - 3;
}
CT
if run_product c2p7_field_designator "$work/c2p7_field_designator.ct"; then
    if grep -qF "$fld" "$work/c2p7_field_designator.c"; then
        ok; printf '  2000-byte field designator: initialiser kept whole\n'
    else
        bad "the generated C cut the 2000-byte field designator"
    fi
fi

# ---- C2p-7.2) a 2000-byte trait method name (prototype/impl/call) --------
mth=$(printf '%*s' 2000 '' | tr ' ' m)
cat >"$work/c2p7_method.ct" <<CT
trait T { int $mth(); }
struct S { int n; } use T;
impl T for S { int $mth() { return self->n; } }
int main(void)
{
    S s = { .n = 4 };
    T t = s;
    return t.$mth() - 4;
}
CT
if run_product c2p7_method "$work/c2p7_method.ct"; then
    if [ "$(grep -oF "$mth" "$work/c2p7_method.c" | wc -l | tr -d ' ')" -ge 3 ]; then
        ok; printf '  2000-byte trait method: vtable prototype, definition and call whole\n'
    else
        bad "the generated C did not spell the 2000-byte trait method in all three places"
    fi
fi

# ---- C2p-7.3) a 2000-byte match arm binding name -------------------------
bnd=$(printf '%*s' 2000 '' | tr ' ' b)
cat >"$work/c2p7_match_bind.ct" <<CT
enum E { A(int x), B() }
int pick(E e)
{
    match (e) {
        E.A($bnd) => { return $bnd; }
        E.B() => { return 0; }
    }
}
int main(void)
{
    E e = E.A(9);
    return pick(e) - 9;
}
CT
if run_product c2p7_match_bind "$work/c2p7_match_bind.ct"; then
    if grep -qF "$bnd" "$work/c2p7_match_bind.c"; then
        ok; printf '  2000-byte match binding: the declared variable is whole\n'
    else
        bad "the generated C cut the 2000-byte match binding name"
    fi
fi

# ---- C2p-7.4) a 2000-byte C label (guard) -------------------------------
lab=$(printf '%*s' 2000 '' | tr ' ' z)
cat >"$work/c2p7_label.ct" <<CT
int main(void)
{
    int s = 0;
    goto $lab;
    s = 9;
$lab:
    s = s + 3;
    return s - 3;
}
CT
if run_product c2p7_label "$work/c2p7_label.ct"; then
    if grep -qF "$lab" "$work/c2p7_label.c"; then
        ok; printf '  2000-byte label: goto and definition kept whole\n'
    else
        bad "the generated C cut the 2000-byte label"
    fi
fi

# ---- C2p-7.5) a 2000-byte foreach element type (guard) -------------------
cat >"$work/c2p7_foreach.ct" <<CT
struct $long { int n; };
int main(void)
{
    struct $long a[2] = {{1}, {2}};
    int s = 0;
    foreach (a) { s = s + item.n; }
    return s - 3;
}
CT
if run_product c2p7_foreach "$work/c2p7_foreach.ct"; then
    ok; printf '  2000-byte foreach element: kept whole\n'
fi


# ===========================================================================
# C2p-8: the emitter's remaining 160-byte reader rows
#
# The emitter still copied several *readers* through `char[MAX_TEXT]` local
# rows: the C base tag of a type (`adt_base_type` / `Box_type_owns`), the
# interned lifetime prefix, the lower-cased vptr field name, the `Result`
# operand / column spellings, the map recipe parameter type and suffix, the
# closure owner mangling, and the Drop-glue field type. Each unit below is a
# 2000-byte spelling that reaches the corresponding reader, so the old rows
# either produced a different C spelling or refused the input.
# ===========================================================================

# ---- C2p-8.1) a 2000-byte trait name: the vptr field is whole ------------
# `inst_emit_one` / `em_decl_struct` copied the lower-cased trait name into a
# 160-byte row, so the struct field and every access were both cut: the C
# compiled, but the emitted spelling was not the user's. Assert the whole
# lower-cased name appears in the field declaration and the access.
tr8=$(printf '%*s' 2000 '' | tr ' ' t)
tr8low=$(printf '%s' "$tr8" | tr 'A-Z' 'a-z')
cat >"$work/c2p8_trait_vptr.ct" <<CT
trait $tr8 { int get(); }
struct S { int n; } use $tr8;
impl $tr8 for S { int get() { return self->n; } }
int main(void) { S s = { .n = 4 }; S r = s; return s.get() + r.get() - 8; }
CT
if run_product c2p8_trait_vptr "$work/c2p8_trait_vptr.ct"; then
    n=$(grep -oF "__${tr8low}_vptr" "$work/c2p8_trait_vptr.c" | wc -l | tr -d ' ')
    if [ "$n" -ge 2 ]; then
        ok; printf '  2000-byte trait name: whole vptr field and access\n'
    else
        bad "the generated C cut the 2000-byte vptr field name ($n whole occurrences)"
    fi
fi

# ---- C2p-8.2) a 2000-byte map host type in `sizeof p` -------------------
# `map_param_type` copied the host type into a 160-byte row and
# `map_clean_type` copied it again, so `sizeof(struct <2000>)` named a
# truncated, incomplete type. The recipe must carry the whole spelling.
cat >"$work/c2p8_shapes.h.ct" <<CT
pub struct $long { int v; }
pub int sizeof_long(unsigned long n) { return n > 0; }
CT
cat >"$work/c2p8_ops.m.ct" <<CT
import c2p8_shapes;
pub trait Peek { int peek(); }
map trait Peek for type struct $long {
    peek(x) -> sizeof_long(sizeof x);
}
CT
cat >"$work/c2p8_map.ct" <<CT
import c2p8_shapes;
import c2p8_ops;
int main(void)
{
    struct $long node = { 5 };
    return node.peek() - 1;
}
CT
if mkdir -p "$work/c2p8_map_out" \
   && "$CT" build --emit-c -I "$work" "$work/c2p8_map.ct" -o "$work/c2p8_map_out" \
        >"$work/c2p8_map.log" 2>&1; then
    if "$CC" -std=c99 -I "$work/c2p8_map_out" "$work/c2p8_map_out"/*.c \
            -o "$work/c2p8_map.bin" >"$work/c2p8_map.cc" 2>&1 \
       && "$work/c2p8_map.bin"; then
        if grep -qF "sizeof(struct $long)" "$work/c2p8_map_out/c2p8_map.c"; then
            ok; printf '  2000-byte map host type: sizeof carries the whole spelling\n'
        else
            bad "the generated C cut the 2000-byte map host type"
        fi
    else
        bad "c2p8_map: cc failed: $(head -2 "$work/c2p8_map.cc" | tr '\n' ' ')"
    fi
else
    bad "c2p8_map: compile failed: $(head -2 "$work/c2p8_map.log" | tr '\n' ' ')"
fi

# ---- C2p-8.3) a 2000-byte ADT variant with an owning payload ------------
# `adt_emit_variant_life` built `self->u.<variant>.<field>` in a 160-byte row,
# so the generated retain/release referenced a member that did not exist.
ad8v=$(printf '%*s' 2000 '' | tr ' ' v)
cat >"$work/c2p8_adt_life.ct" <<CT
#include <stdlib.h>
enum Shape { $ad8v(String s), Empty() }
int main(void)
{
    Shape x = Shape.$ad8v(str_dup("hi"));
    return 0;
}
CT
if run_product c2p8_adt_life "$work/c2p8_adt_life.ct"; then
    if grep -qF "u.$ad8v.s" "$work/c2p8_adt_life.c"; then
        ok; printf '  2000-byte ADT variant: retain/release member kept whole\n'
    else
        bad "the generated C cut the 2000-byte ADT variant in the lifetime glue"
    fi
fi

# ---- C2p-8.4) a 2000-byte Drop-glue field type --------------------------
# The Drop field glue copied the field type into a 160-byte row before
# `find_struct`, so the long type was not recognised and its Drop call was
# dropped. The outer struct's glue must call `<long>_Drop_drop(&_self->b)`.
dg8=$(printf '%*s' 2000 '' | tr ' ' s)
cat >"$work/c2p8_drop_glue.ct" <<CT
#include <stdlib.h>
struct $dg8 { int n; } use Drop;
impl Drop for $dg8 { void drop(void) { } }
struct Outer { struct $dg8 b; int n; } use Drop;
int main(void)
{
    Outer *p = malloc(sizeof(Outer));
    p->n = 1;
    delete p;
    return 0;
}
CT
if run_product c2p8_drop_glue "$work/c2p8_drop_glue.ct"; then
    if grep -qF "${dg8}_Drop_drop(&_self->b)" "$work/c2p8_drop_glue.c"; then
        ok; printf '  2000-byte Drop field type: the field Drop call is whole\n'
    else
        bad "the generated Drop glue lost the 2000-byte field type"
    fi
fi

# ---- C2p-8.5) a long namespace around a closure ------------------------
# `closure_owned` joined the namespace prefix and the function name in a
# 160-byte row; with a 2000-byte namespace the join never matched, so the
# closure's struct and trampoline were not emitted.
ns8=$(printf '%*s' 2000 '' | tr ' ' n)
cat >"$work/c2p8_closure_ns.ct" <<CT
namespace $ns8;
pub int apply(int x)
{
    int base = 2;
    int (*f)(int) = (int y) => y + base;
    return f(x);
}
int main(void) { return $ns8::apply(3) - 5; }
CT
if run_product c2p8_closure_ns "$work/c2p8_closure_ns.ct"; then
    ok; printf '  long namespace closure: owner join kept whole\n'
fi

# ===========================================================================
# C2p-9: the remaining expression / statement / parser scratch rows
#
# The units this batch covers still copied user text into `char[160]` local
# rows: a map binding's recipe was refused once it passed 159 bytes, an
# inherent `as` looked the receiver up under a cut spelling (so a 2000-byte
# struct had "no conversion"), and a diagnostic naming a 2000-byte variable
# was truncated to 159 bytes. The fixtures below pin the whole recipe, the
# whole conversion receiver and the whole diagnostic; the long label /
# pattern / foreach guards from C2p-7 stay in place above.
# ===========================================================================

# ---- C2p-9.1) a map binding recipe whose callee is 2000 bytes -----------
# `parse_binding` captured the recipe into a 160-byte row and refused
# anything longer, so a legal recipe naming a long function could not be
# written at all.
rc9=$(printf '%*s' 2000 '' | tr ' ' r)
mkdir -p "$work/c2p9_recipe"
cat >"$work/c2p9_recipe/shapes.h.ct" <<CT
pub struct A9 { int v; }
pub struct Num9 { int n; }
pub struct Num9 ${rc9}_to_num(struct A9 x)
{
    Num9 r = { x.v + 7 };
    return r;
}
CT
cat >"$work/c2p9_recipe/ops.m.ct" <<CT
map binding struct A9 -> struct Num9 {
    from(x) -> ${rc9}_to_num(x);
}
CT
cat >"$work/c2p9_recipe/prog.ct" <<CT
import shapes;
import ops;
int main(void)
{
    struct A9 node = { 5 };
    struct Num9 a = node;
    return a.n - 12;
}
CT
if mkdir -p "$work/c2p9_recipe_out" \
   && "$CT" build --emit-c -I "$work/c2p9_recipe" "$work/c2p9_recipe/prog.ct" \
        -o "$work/c2p9_recipe_out" >"$work/c2p9_recipe.log" 2>&1; then
    if "$CC" -std=c99 -I "$work/c2p9_recipe_out" "$work/c2p9_recipe_out"/*.c \
            -o "$work/c2p9_recipe.bin" >"$work/c2p9_recipe.cc" 2>&1 \
       && "$work/c2p9_recipe.bin"; then
        if grep -qF "${rc9}_to_num" "$work/c2p9_recipe_out/prog.c"; then
            ok; printf '  2000-byte map recipe callee: captured and emitted whole\n'
        else
            bad "the generated C cut the 2000-byte map recipe callee"
        fi
    else
        bad "c2p9_recipe: cc failed: $(head -2 "$work/c2p9_recipe.cc" | tr '\n' ' ')"
    fi
else
    bad "c2p9_recipe: compile failed: $(head -2 "$work/c2p9_recipe.log" | tr '\n' ' ')"
fi

# ---- C2p-9.2) an inherent `as` on a 2000-byte struct --------------------
# `bind_conv_ibase` copied the receiver type into a 160-byte row before
# `find_struct`, so the inherent block was never found and a legal binding
# site reported "no conversion from".
as9=$(printf '%*s' 2000 '' | tr ' ' a)
cat >"$work/c2p9_as.ct" <<CT
struct NumA { int v; }
struct $as9 { int v; }
impl $as9 {
    NumA as() {
        NumA n = { self->v + 1 };
        return n;
    }
}
int main(void)
{
    struct $as9 node = { 5 };
    NumA a = node;
    return a.v - 6;
}
CT
if run_product c2p9_as "$work/c2p9_as.ct"; then
    if grep -qF "${as9}_as" "$work/c2p9_as.c"; then
        ok; printf '  2000-byte conversion receiver: inherent as resolved whole\n'
    else
        bad "the generated C cut the 2000-byte conversion receiver"
    fi
fi

# ---- C2p-9.3) a diagnostic naming a 2000-byte variable ------------------
# The foreach diagnostics formatted the variable name into a 160-byte row,
# so the error named a cut variable. A diagnostic must quote the spelling
# the user wrote.
fg9=$(printf '%*s' 2000 '' | tr ' ' f)
cat >"$work/c2p9_diag.ct" <<CT
int main(void)
{
    int $fg9 = 1;
    foreach ($fg9) { }
    return 0;
}
CT
"$CT" "$work/c2p9_diag.ct" -o "$work/c2p9_diag.c" >"$work/c2p9_diag.log" 2>&1
if [ $? -eq 0 ]; then
    bad "c2p9_diag: an array-less foreach over an int was accepted"
elif grep -qF "'$fg9'" "$work/c2p9_diag.log"; then
    ok; printf '  2000-byte variable name: the diagnostic quotes it whole\n'
else
    bad "the foreach diagnostic cut the 2000-byte variable name"
fi


# ===========================================================================
# C2p-10: the static-type chain (S1a-0 C2p-10)
#
# `static_ctype` wrote its answer into a caller `char[MAX_TEXT]` row. Every
# 2000-byte struct spelling was therefore cut at 159 bytes before the lookup
# or comparison that follows: `?.` / `?[` reported "cannot resolve the
# receiver type", and a user subscript on a long struct fell back to a C
# subscript the host cc rejects. The family now answers interned pool texts
# (`static_ctype_text` / `ctype_expand_text` / `fnptr_ret_text` /
# `peel_ptr_text`) and every caller reads that form.
# ===========================================================================
lt10=$(printf '%*s' 2000 '' | tr ' ' x)

# ---- C2p-10.1) `?.field` on a 2000-byte struct pointer --------------------
# `opt_field` resolved the receiver through the 160-byte row, so the pointer
# to the long struct never matched its symbol row.
cat >"$work/c2p10_opt_field.ct" <<CT
struct $lt10 { int n; };
int main(void)
{
    struct $lt10 obj;
    struct $lt10 *p = &obj;
    obj.n = 7;
    return p?.n - 7;
}
CT
if run_product c2p10_opt_field "$work/c2p10_opt_field.ct"; then
    if grep -qF "$lt10" "$work/c2p10_opt_field.c"; then
        ok; printf '  2000-byte optional field receiver: resolved and emitted whole\n'
    else
        bad "the generated C cut the 2000-byte optional field receiver"
    fi
fi

# ---- C2p-10.2) `?[0]` on a 2000-byte pointer-to-pointer -------------------
cat >"$work/c2p10_opt_sub.ct" <<CT
struct $lt10 { int n; };
int main(void)
{
    struct $lt10 a;
    struct $lt10 *pa = &a;
    struct $lt10 **pp = &pa;
    a.n = 1;
    return pp?[0]->n - 1;
}
CT
if run_product c2p10_opt_sub "$work/c2p10_opt_sub.ct"; then
    if grep -qF "$lt10" "$work/c2p10_opt_sub.c"; then
        ok; printf '  2000-byte optional subscript receiver: resolved whole\n'
    else
        bad "the generated C cut the 2000-byte optional subscript receiver"
    fi
fi

# ---- C2p-10.3) user subscript on a 2000-byte struct value ----------------
# The sugar is recognised from the base's static type; a cut spelling made the
# base "unresolved" and emitted `x[0]` on a C struct, which the host cc rejects.
cat >"$work/c2p10_user_sub.ct" <<CT
struct $lt10 { int v; }
impl $lt10 {
    int get(int k) { return self->v + k; }
    void set(int k, int n) { self->v = n; }
}
int main(void)
{
    struct $lt10 x;
    x.v = 1;
    x[0] = 9;
    return x[0] - 9;
}
CT
if run_product c2p10_user_sub "$work/c2p10_user_sub.ct"; then
    if grep -qF "${lt10}_get" "$work/c2p10_user_sub.c" \
       && grep -qF "${lt10}_set" "$work/c2p10_user_sub.c"; then
        ok; printf '  2000-byte user subscript: get/set sugar emitted whole\n'
    else
        bad "the generated C did not spell the 2000-byte subscript methods"
    fi
fi

# ---- C2p-10.4) user subscript through a 2000-byte field type -------------
# The base is a member expression, so `ctype_member_or_arrow` has to expand the
# long field type to find the inherent `get`.
cat >"$work/c2p10_member_sub.ct" <<CT
struct $lt10 { int v; }
impl $lt10 {
    int get(int k) { return self->v + k; }
}
struct Outer10 { struct $lt10 inner; }
int main(void)
{
    struct Outer10 o;
    o.inner.v = 4;
    return o.inner[0] - 4;
}
CT
if run_product c2p10_member_sub "$work/c2p10_member_sub.ct"; then
    if grep -qF "${lt10}_get" "$work/c2p10_member_sub.c"; then
        ok; printf '  2000-byte field-type subscript: get sugar emitted whole\n'
    else
        bad "the generated C did not spell the 2000-byte field-type subscript method"
    fi
fi


# ---- C2p-10.5) `ct check --types` on a 2000-byte Result payload --------
# `chk_type`'s NK_TRY arm wrote the operand's payload spelling into 160-byte
# rows before `result_tag` / `result_cols` read it, so the `--types` pass saw a
# cut `Result<...>` and rejected a legal `?` with "'?' needs a Result operand".
cat >"$work/c2p10_types.ct" <<CT
struct $lt10 { int n; };
Result<struct $lt10, char *> f(int n)
{
    if (n < 0) return err: (Result<struct $lt10, char *>){ 0, 0, "neg" };
    return (Result<struct $lt10, char *>){ 1, (struct $lt10){ .n = n }, 0 };
}
Result<struct $lt10, char *> g(int n)
{
    struct $lt10 v = f(n)?;
    return (Result<struct $lt10, char *>){ 1, v, 0 };
}
int main(void)
{
    struct $lt10 r = g(4).value;
    return r.n - 4;
}
CT
"$CT" check --types "$work/c2p10_types.ct" >"$work/c2p10_types.log" 2>&1
if [ $? -eq 0 ]; then
    ok; printf '  2000-byte Result payload: `ct check --types` keeps the `?` legal\n'
else
    bad "c2p10_types: ct check --types rejected the 2000-byte Result: $(head -2 "$work/c2p10_types.log" | tr '\n' ' ')"
fi


# ---- C2p-10.6) a slice initialised from a 2000-byte-named array ---------
# The slice initializer spells the array's C name into its `{ptr,len}` compound
# literal through a 160-byte row, so the emitted name was cut and the host cc
# rejected the undeclared identifier.
cat >"$work/c2p10_slice.ct" <<CT
int main(void)
{
    int $lt10 [2] = {1, 2};
    int[] s = $lt10;
    return s[0] - 1;
}
CT
if run_product c2p10_slice "$work/c2p10_slice.ct"; then
    if grep -qF "$lt10" "$work/c2p10_slice.c"; then
        ok; printf '  2000-byte array name in a slice view: emitted whole\n'
    else
        bad "the generated C cut the 2000-byte array name in the slice view"
    fi
fi

# ---- C2p-10.7) a duplicate 2000-byte Map key in the diagnostic ----------
# `map_dup_key` decoded the key into a 160-byte row (and the caller formatted
# the message into 256 bytes), so the error quoted 159 k's of a 2000-byte key.
dk10=$(printf '%*s' 2000 '' | tr ' ' k)
cat >"$work/c2p10_dupkey.ct" <<CT
int main(void)
{
    Map<char *, int> m = { "$dk10": 1, "$dk10": 2 };
    return 0;
}
CT
"$CT" "$work/c2p10_dupkey.ct" -o "$work/c2p10_dupkey.c" >"$work/c2p10_dupkey.log" 2>&1
if [ $? -eq 0 ]; then
    bad "c2p10_dupkey: a duplicate Map key was accepted"
elif grep -qF "'$dk10'" "$work/c2p10_dupkey.log"; then
    ok; printf '  2000-byte duplicate Map key: the diagnostic quotes it whole\n'
else
    bad "the duplicate-key diagnostic cut the 2000-byte key"
fi


# ---- C2p-10.8) a `$` target with a 2000-byte variable name --------------
# The `$` suffix copied the target name through `tok_copy(…, 160)`, so a
# 2000-byte declared variable never matched its row and the hop was refused
# with "'$' target must be a declared variable".
cat >"$work/c2p10_dollar.ct" <<CT
struct S10 { int n; };
impl S10 { int m() { return self->n + 1; } }
int main(void)
{
    struct S10 s = { 1 };
    int $lt10 = 0;
    s.m()\$$lt10;
    return $lt10 - 2;
}
CT
if run_product c2p10_dollar "$work/c2p10_dollar.ct"; then
    if grep -qF "$lt10" "$work/c2p10_dollar.c"; then
        ok; printf '  2000-byte "\\$" target: materialised whole\n'
    else
        bad "the generated C cut the 2000-byte \$ target name"
    fi
fi

# ---- C2p-10.9) `_Generic` over a 2000-byte typedef ----------------------
# `_Generic` copies its selection verbatim into the pool through a 160-byte
# token row, so the long typedef name was cut and the host cc rejected the
# emitted selection.
cat >"$work/c2p10_generic.ct" <<CT
typedef int $lt10;
int main(void)
{
    int v = 3;
    return _Generic(v, $lt10: 1, default: 0) - 1;
}
CT
if run_product c2p10_generic "$work/c2p10_generic.ct"; then
    if grep -qF "$lt10" "$work/c2p10_generic.c"; then
        ok; printf '  2000-byte _Generic selection: copied whole\n'
    else
        bad "the generated C cut the 2000-byte _Generic selection"
    fi
fi

# ---- C2p-10.10) a C-boundary diagnostic naming a 2000-byte function -----
# `cannot pass a '<T>' handle to C function '<name>'` formatted the callee
# into a 160-byte row, so the error named a cut function.
fn10=$(printf '%*s' 2000 '' | tr ' ' f)
cat >"$work/c2p10_cfunc.ct" <<CT
int main(void)
{
    String s = "x";
    $fn10(s);
    return 0;
}
CT
"$CT" "$work/c2p10_cfunc.ct" -o "$work/c2p10_cfunc.c" >"$work/c2p10_cfunc.log" 2>&1
if [ $? -eq 0 ]; then
    bad "c2p10_cfunc: passing a String handle to an undeclared C function was accepted"
elif grep -qF "'$fn10'" "$work/c2p10_cfunc.log"; then
    ok; printf '  2000-byte C-boundary callee: the diagnostic quotes it whole\n'
else
    bad "the C-boundary diagnostic cut the 2000-byte callee"
fi


# ---- C2p-10.11) a duplicate member whose name is 2000 bytes ------------
# `register_field` formatted the duplicate-member error into a 160-byte row,
# so the diagnostic quoted 159 bytes of the 2000-byte field name.
fm10=$(printf '%*s' 2000 '' | tr ' ' w)
cat >"$work/c2p10_dupfield.ct" <<CT
struct S10 { int $fm10; int $fm10; };
int main(void) { return 0; }
CT
"$CT" "$work/c2p10_dupfield.ct" -o "$work/c2p10_dupfield.c" >"$work/c2p10_dupfield.log" 2>&1
if [ $? -eq 0 ]; then
    bad "c2p10_dupfield: a duplicate member was accepted"
elif grep -qF "'$fm10'" "$work/c2p10_dupfield.log"; then
    ok; printf '  2000-byte duplicate member: the diagnostic quotes it whole\n'
else
    bad "the duplicate-member diagnostic cut the 2000-byte name"
fi

# ---- C2p-10.12) a duplicate struct tag whose name is 2000 bytes ---------
tm10=$(printf '%*s' 2000 '' | tr ' ' x)
cat >"$work/c2p10_dupstruct.ct" <<CT
struct $tm10 { int n; };
struct $tm10 { int m; };
int main(void) { return 0; }
CT
"$CT" "$work/c2p10_dupstruct.ct" -o "$work/c2p10_dupstruct.c" >"$work/c2p10_dupstruct.log" 2>&1
if [ $? -eq 0 ]; then
    bad "c2p10_dupstruct: a duplicate struct tag was accepted"
elif grep -qF "'$tm10'" "$work/c2p10_dupstruct.log"; then
    ok; printf '  2000-byte duplicate struct tag: the diagnostic quotes it whole\n'
else
    bad "the duplicate-struct diagnostic cut the 2000-byte tag"
fi


# ---- C2p-11.1) a 2000-byte package name through the manifest reader -------
# `ct index refresh` reads one ct.pkg per package-list row and writes the
# refreshed row back. The name comes from the manifest, so a 2000-byte name
# proves `read_manifest` (and the row that receives it) kept it whole.
pn11=$(printf '%*s' 2000 '' | tr ' ' p)
mkdir -p "$work/c211pkg/deep" || exit 1
printf 'name = %s\npublisher = ct\nversion = 0.1.0\nns-root = .\n' "$pn11" \
    >"$work/c211pkg/deep/ct.pkg"
printf 'pub int c211_val(void);\nint c211_val(void) { return 3; }\n' \
    >"$work/c211pkg/deep/deep.h.ct"
printf '%s https://example.invalid/c211 v0.1.0\n' "$work/c211pkg/deep" \
    >"$work/c211_packages.list"
if "$CT" index refresh --packages "$work/c211_packages.list" \
        --out "$work/c211.index" >"$work/c211_idx.log" 2>&1; then
    if grep -qF "$pn11" "$work/c211.index"; then
        ok; printf '  2000-byte package name: the index row carries it whole\n'
    else
        bad "c211_pkg: the refreshed index row cut the 2000-byte package name"
    fi
else
    bad "c211_pkg: index refresh rejected the 2000-byte package name: $(head -2 "$work/c211_idx.log" | tr '\n' ' ')"
fi

# ---- C2p-11.2) a 2000-byte struct in an interface initialiser -------------
# The initialiser rewrite used fixed field-type / struct-name rows, so the
# boxing test failed to see the value type and left `.t = v` unboxed; the
# emitted C then did not compile. The whole pipeline (emit + cc + run) is the
# assertion.
tm11=$(printf '%*s' 2000 '' | tr ' ' s)
cat >"$work/c211_iface.ct" <<CT
trait C211T { int c211_get(); }
struct $tm11 { int x; } use C211T;
impl C211T for $tm11 { int c211_get() { return 7; } }
struct C211Holder { C211T *t; }
int main(void) { struct $tm11 v; struct C211Holder h = { .t = &v }; return h.t->c211_get() == 7 ? 0 : 1; }
CT
if run_product c211_iface "$work/c211_iface.ct"; then
    if grep -qF 'C211T_iface){ (void *)&v' "$work/c211_iface.c"; then
        ok; printf '  2000-byte struct: interface initialiser boxes and runs\n'
    else
        bad "c211_iface: the initialiser was not boxed (the 2000-byte value type was cut)"
    fi
fi

# ---- C2p-11.3) a long module path (namespace + nested directories) -------
# A module path is a filesystem path, and the host caps one at 1024 bytes, so
# the fixture is as long as the platform allows (~800 bytes): eight 100-byte
# segments, six times the old 160-byte row. The namespace matches the
# directories (`-I` root), so the ns-dir check, the `::`/`/` candidate walk and
# the import resolver all have to carry the whole spelling.
mdir="$work/c211moddeep"
mns=""
md="$mdir"
for _ in 1 2 3 4 5 6 7 8; do
    mseg=$(printf '%*s' 100 '' | tr ' ' m)
    md="$md/$mseg"
    if [ -n "$mns" ]; then mns="$mns::$mseg"; else mns="$mseg"; fi
done
mkdir -p "$md" || exit 1
printf 'namespace %s;\npub int c211_g = 5;\n' "$mns" >"$md/c211ns.h.ct"
printf 'import %s::c211ns;\nint main(void) { return c211_g - 5; }\n' "$mns" \
    >"$mdir/main.ct"
if "$CT" build -I "$mdir" "$mdir/main.ct" -o "$work/c211mod.bin" \
        >"$work/c211_mod.log" 2>&1; then
    if "$work/c211mod.bin"; then
        ok; printf '  %s-byte module path: resolved, built and run\n' "${#mns}"
    else
        bad "c211_mod: the program built from the long module path returned non-zero"
    fi
else
    bad "c211_mod: a long module path was rejected: $(head -2 "$work/c211_mod.log" | tr '\n' ' ')"
fi

# ---- C2p-11.4) the `own` diagnostic quotes a 2000-byte struct whole ------
cat >"$work/c211_own.ct" <<CT
#include <stdlib.h>
struct $tm11 { int x; };
int main(void) { own struct $tm11 *p = malloc(sizeof(struct $tm11)); p->x = 1; return 0; }
CT
"$CT" "$work/c211_own.ct" -o "$work/c211_own.c" >"$work/c211_own.log" 2>&1
if [ $? -eq 0 ]; then
    bad "c211_own: a struct that does not use Drop was accepted as 'own'"
elif grep -qF "'$tm11'" "$work/c211_own.log"; then
    ok; printf '  2000-byte struct: the own diagnostic quotes it whole\n'
else
    bad "the own diagnostic cut the 2000-byte struct name"
fi

printf 'c2p: %d passed, %d failed\n' "$pass" "$fail"

[ "$fail" -eq 0 ]
