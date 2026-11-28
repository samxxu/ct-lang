#!/bin/sh
# LANG-31 / D-031 probe: the constant-key fold `p["x"]` -> `p.x`.
#
# E31-1 positive : a string-literal key naming a field folds to a field access
#                  on both paths (default LIR and `--ir=off`); the C carries no
#                  `get` call and no `__ct_*` temporary, and both products are
#                  byte-identical;
# E31-2 receiver : field chain / array element / user generic instance roots;
# E31-3 fallback : a literal key that names no field still goes through the
#                  existing D-028 `get` path (p52_read is byte-identical);
# E31-4 errors   : unknown field / renamed field / field+get ambiguity, exact
#                  position (`[`) and text, one diagnostic, no product;
# E31-5 write    : a constant-key write does not fold (D-028 write path owns it);
# E31-6 built-in : a Box implementation field cannot be reached by a key.
#
# Conditional probes from D-031 section 8 (C1-C4):
# E31-7 C1 call  : a call result is not a place, so it does not fold; the old
#                  L52-1 wording is kept and D031-2 never appears;
# E31-8 C2 addr  : `&p["x"]` is a read position and folds to the field address
#                  `&p.x` before the L52-7 address rule is consulted;
# E31-9 C3 fwd   : a forward-declared struct (fields unknown at the use point)
#                  neither folds nor reports D031-2 -- it keeps L52-1; a forward
#                  declaration followed by the definition does fold;
# E31-10 C4 type : a `get` with a different parameter type is not a match, so
#                  it is not a D031-1 ambiguity and the field folds;
# E31-11 C4 priv : a `get(char *)` private to another unit is not a visible
#                  match either -- the field folds;
# E31-12 C4 fld  : a private field folds exactly like the handwritten `p.x`
#                  and is refused by the public header at the C stage, with no
#                  new D031 diagnostic.
set -u
ctast=${1:?usage: lang31_const_key.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
# The cross-unit probes below run inside a temporary project, so the compiler
# path must not depend on the caller's working directory.
ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast")
tmp=$(mktemp -d "${TMPDIR:-/tmp}/lang31-fold.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

compile() { # <out> <source> [extra args...]
    out=$1
    src=$2
    shift 2
    ( cd "$root" && CT_C_BOUNDARY=allow "$ctast" "$@" "$src" -o "$out" ) \
        >"$out.out" 2>"$out.err"
}

run_pos() { # <dir-name> <expected.stdout>
    name=$1
    want=$2
    for mode in lir ast; do
        flag=
        [ "$mode" = ast ] && flag=--ir=off
        if ! compile "$tmp/$name.$mode.c" "test/ast/$name/prog.ct" $flag; then
            fail_msg "$name ($mode): ct-ast failed: $(cat "$tmp/$name.$mode.c.err")"
            return 1
        fi
        if ! "$cc" -Wall -Wextra -std=c99 "$tmp/$name.$mode.c" \
                -o "$tmp/$name.$mode.bin" 2>"$tmp/$name.$mode.cc"; then
            fail_msg "$name ($mode): generated C did not build: $(cat "$tmp/$name.$mode.cc")"
            return 1
        fi
        if [ -s "$tmp/$name.$mode.cc" ]; then
            fail_msg "$name ($mode): generated C is not warning-free: $(cat "$tmp/$name.$mode.cc")"
        fi
        if ! "$tmp/$name.$mode.bin" >"$tmp/$name.$mode.txt" 2>&1; then
            fail_msg "$name ($mode): the program exited non-zero"
            return 1
        fi
        if ! printf '%s' "$want" | diff -u - "$tmp/$name.$mode.txt" \
                >"$tmp/$name.$mode.diff"; then
            fail_msg "$name ($mode): output drifted: $(cat "$tmp/$name.$mode.diff")"
            return 1
        fi
        if grep -Eq '\bget[[:space:]]*\(|__ct_' "$tmp/$name.$mode.c"; then
            fail_msg "$name ($mode): the product still names get / a temporary"
            return 1
        fi
    done
    if ! cmp -s "$tmp/$name.lir.c" "$tmp/$name.ast.c"; then
        fail_msg "$name: the default (LIR) and --ir=off products differ"
        diff -u "$tmp/$name.ast.c" "$tmp/$name.lir.c" | head -12 >&2
        return 1
    fi
}

# --- E31-1: the plain fold, both paths ------------------------------------
if run_pos 320_const_key_fold 'x=7 y=9
'; then
    if grep -Fq 'p.x' "$tmp/320_const_key_fold.lir.c" \
       && grep -Fq 'p.y' "$tmp/320_const_key_fold.lir.c"; then
        ok_msg "E31-1 literal key folds to a field access (LIR + AST, no get/temp)"
    else
        fail_msg "E31-1: the field access is missing from the product"
    fi
fi

# --- E31-2: field chain / array element / generic instance ---------------
if run_pos 321_const_key_fold_chain '5 6 8
'; then
    if grep -Fq 'h.p.x' "$tmp/321_const_key_fold_chain.lir.c" \
       && grep -Fq 'ps[0].x' "$tmp/321_const_key_fold_chain.lir.c" \
       && grep -Fq 'g.v' "$tmp/321_const_key_fold_chain.lir.c"; then
        ok_msg "E31-2 field chain / array element / generic instance folds"
    else
        fail_msg "E31-2: a receiver form did not fold"
    fi
fi

# --- E31-8 / E31-9 / E31-10: conditional positives (D-031 C2 / C3 / C4) ---
if run_pos 322_const_key_fold_addr '42 42
'; then
    if grep -Fq '&p.x' "$tmp/322_const_key_fold_addr.lir.c"; then
        ok_msg "E31-8 &p[\"x\"] folds to the field address &p.x (LIR + AST)"
    else
        fail_msg "E31-8: the field address is missing from the product"
    fi
fi

if run_pos 323_const_key_fold_fwd '12 30
'; then
    if grep -Fq 'p.x' "$tmp/323_const_key_fold_fwd.lir.c" \
       && grep -Fq 'p.y' "$tmp/323_const_key_fold_fwd.lir.c"; then
        ok_msg "E31-9 a forward declaration followed by the definition folds"
    else
        fail_msg "E31-9: the field access is missing from the product"
    fi
fi

if run_pos 324_const_key_fold_get_type '4
'; then
    if grep -Fq 'p.x' "$tmp/324_const_key_fold_get_type.lir.c"; then
        ok_msg "E31-10 a get with another parameter type is not an ambiguity"
    else
        fail_msg "E31-10: the field did not fold beside the non-matching get"
    fi
fi

# --- E31-3: the get fallback stays byte-identical ------------------------
if compile "$tmp/fallback.c" test/ast/p52_read/prog.ct; then
    if grep -Fq 'X_get(&x, "a")' "$tmp/fallback.c" \
       && grep -Fq 'X_get(&x, "z")' "$tmp/fallback.c"; then
        ok_msg "E31-3 a literal key that names no field keeps the get path"
    else
        fail_msg "E31-3: the get fallback is missing from the product"
    fi
else
    fail_msg "E31-3: p52_read failed: $(cat "$tmp/fallback.c.err")"
fi

# --- E31-4 / E31-5 / E31-6: exact negatives ------------------------------
neg() { # <fixture> <line:col> <message>
    name=$1
    pos=$2
    msg=$3
    if compile "$tmp/neg-$name.c" "test/ast/errors/$name.ct"; then
        fail_msg "$name: expected a diagnostic, got exit 0"
    elif ! grep -Fq "test/ast/errors/$name.ct:$pos: error: $msg" \
            "$tmp/neg-$name.c.err"; then
        fail_msg "$name: $(cat "$tmp/neg-$name.c.err")"
    elif [ "$(grep -c 'error:' "$tmp/neg-$name.c.err")" -ne 1 ]; then
        fail_msg "$name: expected exactly one diagnostic: $(cat "$tmp/neg-$name.c.err")"
    elif [ -e "$tmp/neg-$name.c" ]; then
        fail_msg "$name: a rejected fold still wrote a product"
    else
        ok_msg "$name ($pos)"
    fi
}
neg lang31_unknown_field 12:13 \
    "type 'Point' has no field 'nope': candidates are 'x', 'y'"
neg lang31_renamed_field 12:13 \
    "type 'Record' has no field 'old_name': candidates are 'kept', 'new_name'"
neg lang31_ambiguous 19:13 \
    "type 'Pair' has an ambiguous constant-key subscript: both field 'x' and 'get(char *)' match; write the field access or 'get(\"x\")'"
neg lang31_write_form 11:6 \
    "type 'Point' has a read-only subscript: declare 'void set(K, V)' in impl Point"
neg lang31_box_internal 8:14 \
    "type 'Box<struct Point>' has no subscript: declare 'V get(K)' in impl Box<struct Point>"
# E31-7 / E31-9: the receiver and forward-declaration negatives keep the
# existing L52-1 wording; neither may fall through to D031-2.
neg lang31_call_receiver 19:18 \
    "type 'Point' has no subscript: declare 'V get(K)' in impl Point"
neg lang31_forward_field 8:16 \
    "type 'P' has no subscript: declare 'V get(K)' in impl P"

# E31-7 control: the ordinary field access on a call result stays legal; only
# the constant-key form on that temporary is refused (the receiver rule).
cat > "$tmp/call_control.ct" <<'CT'
struct Point { int x; int y; }
Point make(void)
{
    Point p;
    p.x = 3;
    p.y = 5;
    return p;
}
int main(void)
{
    return make().x;
}
CT
if compile "$tmp/call_control.c" "$tmp/call_control.ct" \
   && grep -Fq 'make().x' "$tmp/call_control.c"; then
    ok_msg "E31-7 make().x stays legal; make()[\"x\"] is refused"
else
    fail_msg "E31-7: the field-access control failed: $(cat "$tmp/call_control.c.err")"
fi

# --- E31-11 / E31-12: cross-unit visibility (D-031 C4) -------------------
# A private `get(char *)` in the defining unit is not a visible match, so the
# field folds (no D031-1). A private field folds exactly like `p.x`; the public
# header, not the fold, is what refuses it.
priv_get() {
    d="$tmp/private-get"
    mkdir -p "$d/lib" "$d/out" || { fail_msg "E31-11: cannot create the fixture"; return 1; }
    cat > "$d/lib/pair.h.ct" <<'CT'
namespace lib;
pub struct Pair {
    pub int x;
}
impl Pair {
    int get(char *k)
    {
        (void)k;
        return 0;
    }
}
CT
    cat > "$d/prog.ct" <<'CT'
import lib::pair;
int main(void)
{
    Pair p;
    p.x = 5;
    return p["x"];
}
CT
    if ! ( cd "$d" && CT_C_BOUNDARY=allow "$ctast" build --emit-c -I . prog.ct -o out ) \
            >"$d/build.log" 2>&1; then
        fail_msg "E31-11: the private-get project did not build: $(cat "$d/build.log")"
        return 1
    fi
    if ! grep -Fq 'p.x' "$d/out/prog.c"; then
        fail_msg "E31-11: the key did not fold beside a private get"
        return 1
    fi
    if grep -Fq 'Pair_get' "$d/out/prog.c"; then
        fail_msg "E31-11: the product calls the private get"
        return 1
    fi
    ok_msg "E31-11 a private get(char *) in another unit is not an ambiguity"
}

priv_field() {
    d="$tmp/private-field"
    mkdir -p "$d/lib" || { fail_msg "E31-12: cannot create the fixture"; return 1; }
    cat > "$d/lib/conn.h.ct" <<'CT'
namespace lib;
pub struct Conn {
    pub int fd;
    int secret;
}
impl Conn {
    pub int get_secret(void)
    {
        return self->secret;
    }
}
pub Conn *conn_new(int fd);
CT
    cat > "$d/lib/conn.ct" <<'CT'
namespace lib;
Conn *conn_new(int fd)
{
    Conn *c = new Conn;
    c->fd = fd;
    c->secret = 99;
    return c;
}
CT
    cat > "$d/key.ct" <<'CT'
import lib::conn;
int main(void)
{
    Conn *c = lib::conn_new(1);
    return (*c)["secret"];
}
CT
    cat > "$d/direct.ct" <<'CT'
import lib::conn;
int main(void)
{
    Conn *c = lib::conn_new(1);
    return (*c).secret;
}
CT
    for n in key direct; do
        mkdir -p "$d/out-$n" || { fail_msg "E31-12 ($n): cannot create the output"; return 1; }
        if ! ( cd "$d" && CT_C_BOUNDARY=allow "$ctast" build --emit-c -I . "$n.ct" -o "out-$n" ) \
                >"$d/$n.build.log" 2>&1; then
            fail_msg "E31-12 ($n): the project did not reach the C stage: $(cat "$d/$n.build.log")"
            return 1
        fi
        if grep -Fq 'has no field' "$d/$n.build.log"; then
            fail_msg "E31-12 ($n): the fold invented a field diagnostic"
            return 1
        fi
        if ! grep -Fq '(*c).secret' "$d/out-$n/$n.c"; then
            fail_msg "E31-12 ($n): the emitted field access is missing"
            return 1
        fi
        if "$cc" -std=c99 -I "$d/out-$n" "$d"/out-$n/*.c -o "$d/$n.bin" \
                >"$d/$n.cc.log" 2>&1; then
            fail_msg "E31-12 ($n): the public header exposed the private field"
            return 1
        fi
        if ! grep -Fq 'secret' "$d/$n.cc.log"; then
            fail_msg "E31-12 ($n): the C refusal does not name the private field"
            return 1
        fi
    done
    # The two products differ only in the source name the banner / #line carry.
    sed -e '/^\/\* Generated by ct/d' -e '/^#line/d' \
        "$d/out-key/key.c" > "$d/key.norm"
    sed -e '/^\/\* Generated by ct/d' -e '/^#line/d' \
        "$d/out-direct/direct.c" > "$d/direct.norm"
    if ! cmp -s "$d/key.norm" "$d/direct.norm"; then
        fail_msg "E31-12: the folded access differs from the handwritten p.x"
        return 1
    fi
    ok_msg "E31-12 a private field folds like p.x and is refused by the header"
}

priv_get
priv_field

if [ "$fail" -eq 0 ]; then
    echo "lang31/const-key: ok"
    exit 0
fi
echo "lang31/const-key: $fail failure(s)" >&2
exit 1
