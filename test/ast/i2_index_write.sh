#!/bin/sh
# D-034 (I2-4) / v1-PH-2 probe: interface-value subscript, stage two (write).
#
#   B1 shape   : `s[k] = v` and the explicit `s.set(k, v)` products are
#                byte-identical (banner line aside) and both run.
#   B2 no set  : a trait with an indexed `get` but no indexed `set` is a
#                COMPILE-TIME hard error (D034-8), not a run-time branch.
#   B3 key     : the write key matches the `set`'s first parameter by static
#                type; a mismatch lists the declared key types.
#   B4 own     : the write value's ownership follows the signature (D-013);
#                an `own` handle is the L52-9 refusal, `+=` the L52-6 one.
#
# B5 (stage two does not move stage one) is asserted by i2_index.sh's A1/A2
# still passing, and by comparing the stage-one products against the slices
# before this one (the commit carries that diff).
#
# Usage: sh test/ast/i2_index_write.sh <ct-ast> [cc]
set -u
ctast=${1:?usage: i2_index_write.sh <ct-ast> [cc]}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/i2-write.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export CT_C_BOUNDARY=allow
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok   $*"; }

compile() {
    name=$1
    src=$2
    if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$src" -o "$tmp/$name.c" ) \
            >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail_msg "$name: ct-ast failed: $(sed -n '1,3p' "$tmp/$name.err" | tr '\n' ' ')"
        return 1
    fi
    return 0
}

run_bin() {
    name=$1
    dir=$2
    if ! "$cc" -Wall -Wextra -std=c99 "$tmp/$name.c" -o "$tmp/$name.bin" \
            2>"$tmp/$name.cc"; then
        fail_msg "$name: generated C did not build: $(head -2 "$tmp/$name.cc")"
        return 1
    fi
    [ -s "$tmp/$name.cc" ] && { fail_msg "$name: generated C is not warning-free"; return 1; }
    if ! "$tmp/$name.bin" >"$tmp/$name.txt" 2>&1; then
        fail_msg "$name: the program exited non-zero"
        return 1
    fi
    if ! diff -u "$root/test/ast/$dir/prog.expected.out" "$tmp/$name.txt" \
            >"$tmp/$name.diff"; then
        fail_msg "$name: output drifted: $(head -4 "$tmp/$name.diff" | tr '\n' ' ')"
        return 1
    fi
    return 0
}

# --- B1: the write product is the explicit call product -------------------
if compile b1_sub test/ast/i2_index_write/prog.ct \
   && compile b1_exp test/ast/i2_index_write_explicit/prog.ct; then
    sed '1d' "$tmp/b1_sub.c" >"$tmp/b1_sub.norm"
    sed '1d' "$tmp/b1_exp.c" >"$tmp/b1_exp.norm"
    if diff -u "$tmp/b1_exp.norm" "$tmp/b1_sub.norm" >"$tmp/b1.diff"; then
        ok_msg "B1  s[k] = v and s.set(k, v) generate the same C"
    else
        fail_msg "B1: the write product differs from the explicit call:" \
                 "$(head -6 "$tmp/b1.diff" | tr '\n' ' ')"
    fi
    run_bin b1_sub i2_index_write || true
    if grep -Fq '.vt->set(' "$tmp/b1_sub.c"; then
        ok_msg "B1  the write is the interface vtable set slot"
    else
        fail_msg "B1: the product does not call the vtable set slot"
    fi
fi

# --- B2/B3/B4: the write-side diagnostics --------------------------------
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
        fail_msg "$label: a rejected write still wrote a product"
        return
    fi
    ok_msg "$label"
}

neg i2_no_index_set 26:6 \
    "trait 'Slot' declares no indexed set; 'o[k] = v' is not available" \
    "B2  a trait without an indexed set cannot be written"
neg i2_set_key_mismatch 31:6 \
    "trait 'Store' has no indexed 'set' matching key type 'int': candidates are 'char *'" \
    "B3  the write key lists the declared set key types"
neg i2_write_own 39:6 \
    "a custom subscript set cannot take an 'own' or 'borrow' value" \
    "B4  an own value keeps the L52-9 refusal"
neg i2_write_compound 30:6 \
    "a custom subscript supports only '='; use set(k, v)" \
    "B4  a compound write keeps the L52-6 refusal"
neg i2_write_incr 25:6 \
    "a custom subscript supports only '='; use set(k, v)" \
    "B4  ++ keeps the L52-6 refusal"

echo "i2/write: $fail failure(s)"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
