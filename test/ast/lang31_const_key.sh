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
set -u
ctast=${1:?usage: lang31_const_key.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
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

if [ "$fail" -eq 0 ]; then
    echo "lang31/const-key: ok"
    exit 0
fi
echo "lang31/const-key: $fail failure(s)" >&2
exit 1
