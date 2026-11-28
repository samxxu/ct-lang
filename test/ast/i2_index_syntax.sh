#!/bin/sh
# D-034 (I2-1) / v1-PH-2 probe: the `index` context modifier's syntax position.
#
#   ident    : `index` stays an ordinary field / variable / method name, and a
#              marked `get` keeps its explicit call (the marker adds no syntax
#              anywhere else).
#   prefix   : `index int get(...)`            -> D034-7 at the marker
#   twice    : `int get(...) index index`      -> D034-7 at the second marker
#   after-;  : `int get(...); index`           -> D034-7 at the stray marker
#   impl     : `impl … { int get(...) index; }`-> D034-3 at the marker
#   dup      : two indexed `get(char *)`       -> D034-5 at the second marker
#   dupmix   : indexed + unindexed same key    -> duplicate-method hard error
#   setret   : `int set(char *, int) index`    -> D034-6 at `set`
#
# Every negative must be exactly one diagnostic, positioned, and must write no
# product. Usage: sh test/ast/i2_index_syntax.sh <ct-ast> [cc]
set -u
ctast=${1:?usage: i2_index_syntax.sh <ct-ast> [cc]}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/i2-syntax.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export CT_C_BOUNDARY=allow
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok   $*"; }

# --- positive: `index` is still an ordinary identifier --------------------
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
        test/ast/i2_index_ident/prog.ct -o "$tmp/ident.c" ) \
        >"$tmp/ident.out" 2>"$tmp/ident.err"; then
    if ! "$cc" -Wall -Wextra -std=c99 "$tmp/ident.c" -o "$tmp/ident.bin" \
            2>"$tmp/ident.cc"; then
        fail_msg "ident: the generated C did not build: $(head -2 "$tmp/ident.cc")"
    elif [ -s "$tmp/ident.cc" ]; then
        fail_msg "ident: the generated C is not warning-free"
    elif ! "$tmp/ident.bin" >"$tmp/ident.txt" 2>&1; then
        fail_msg "ident: the program exited non-zero"
    elif ! diff -u "$root/test/ast/i2_index_ident/prog.expected.out" "$tmp/ident.txt" \
            >"$tmp/ident.diff"; then
        fail_msg "ident: output drifted"
    else
        ok_msg "I2-1_ident  \`index\` is an identifier outside the marker position"
    fi
else
    fail_msg "ident: ct-ast failed: $(head -2 "$tmp/ident.err")"
fi

# --- negatives ------------------------------------------------------------
# neg <fixture> <line:col> <message> <label>
neg() {
    name=$1
    pos=$2
    want=$3
    label=$4
    if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg-$name.c" ) \
            >"$tmp/neg-$name.out" 2>"$tmp/neg-$name.err"; then
        fail_msg "$label: expected a diagnostic, got exit 0"
        return
    fi
    if ! grep -Fq -- "$pos: error: $want" "$tmp/neg-$name.err"; then
        fail_msg "$label: $(sed -n '1,3p' "$tmp/neg-$name.err" | tr '\n' ' ')"
        return
    fi
    if [ "$(grep -c 'error:' "$tmp/neg-$name.err")" -ne 1 ]; then
        fail_msg "$label: expected exactly one diagnostic"
        return
    fi
    if [ -e "$tmp/neg-$name.c" ]; then
        fail_msg "$label: a rejected declaration still wrote a product"
        return
    fi
    ok_msg "$label"
}

neg i2_index_prefix 4:5 \
    "the 'index' marker goes after the parameter list and before ';'" \
    "I2-1_prefix  prefix spelling is D034-7"
neg i2_index_twice 4:28 \
    "the 'index' marker goes after the parameter list and before ';'" \
    "I2-1_twice  a repeated marker is D034-7"
neg i2_index_after_semi 5:5 \
    "the 'index' marker goes after the parameter list and before ';'" \
    "I2-1_after_semi  a marker after ';' is D034-7"
neg i2_impl_index 12:22 \
    "the 'index' marker belongs to the trait declaration, not the impl" \
    "I2-1_impl  an impl-side marker is D034-3"
neg i2_index_dup 6:25 \
    "trait 'Store' marks more than one indexed 'get' for key type 'char *'" \
    "I2-1_dup  a duplicate key type is D034-5"
neg i2_index_set_nonvoid 4:9 \
    "an indexed 'set' must return void: 'int set(char *, int)'" \
    "I2-1_setret  a non-void indexed set is D034-6"
neg i2_dup_method 5:9 \
    "trait 'Store' declares duplicate method 'get' with the same parameter types" \
    "I2-1_dupmix  indexed + unindexed same key is rejected (F1)"
neg i2_dup_generic 8:15 \
    "trait 'Vat_int' declares duplicate method 'get' with the same parameter types" \
    "I2-1_dupgeneric  generic instantiation collapsing two keys is rejected (F1-g)"

echo "i2/syntax: $fail failure(s)"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
