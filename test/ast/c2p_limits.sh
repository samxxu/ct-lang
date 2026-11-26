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

printf 'c2p: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
