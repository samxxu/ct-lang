#!/bin/sh
# D-034 (I2-2 / I2-3) / v1-PH-2 probe: interface-value subscript, stage one.
#
#   A1 shape    : `s["name"]` and the explicit `s.get("name")` products are
#                 byte-identical (banner line aside).
#   A2 keys     : two indexed `get`s with different key types dispatch by the
#                 key's static type and name two distinct vtable slots.
#   A3 cross    : trait in a `.h.ct` unit, impl in a second, call in a third;
#                 `ct build` recompiles the closure, so an edited impl changes
#                 the run (no stale vtable).
#   A4 D-028    : a concrete type's inherent subscript keeps its direct call.
#   A5..A9 +    : the frozen D034 diagnostics, positioned at `[`, one each, no
#   misuse        product.
#
# Usage: sh test/ast/i2_index.sh <ct-ast> [cc]
set -u
ctast=${1:?usage: i2_index.sh <ct-ast> [cc]}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/i2-index.XXXXXX")
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

# --- A1: the subscript product is the explicit call product ---------------
if compile a1_sub test/ast/i2_index_read/prog.ct \
   && compile a1_exp test/ast/i2_index_explicit/prog.ct; then
    sed '1d' "$tmp/a1_sub.c" >"$tmp/a1_sub.norm"
    sed '1d' "$tmp/a1_exp.c" >"$tmp/a1_exp.norm"
    if diff -u "$tmp/a1_exp.norm" "$tmp/a1_sub.norm" >"$tmp/a1.diff"; then
        ok_msg "A1  s[k] and s.get(k) generate the same C"
    else
        fail_msg "A1: the subscript product differs from the explicit call:" \
                 "$(head -6 "$tmp/a1.diff" | tr '\n' ' ')"
    fi
    run_bin a1_sub i2_index_read || true
    if grep -Fq '.vt->get(' "$tmp/a1_sub.c"; then
        ok_msg "A1  the call is the interface vtable slot"
    else
        fail_msg "A1: the product does not call the vtable slot"
    fi
fi

# --- A2: two key types, two slots ----------------------------------------
if compile a2 test/ast/i2_index_read_keys/prog.ct; then
    if grep -Fq 'vt->get$char_2a(' "$tmp/a2.c" \
       && grep -Fq 'vt->get$int(' "$tmp/a2.c"; then
        ok_msg "A2  s[k] / s[0] name two distinct slots by key type"
    else
        fail_msg "A2: the two key types did not select two slots"
    fi
    run_bin a2 i2_index_read_keys || true
fi

# --- A3: cross-unit build, and a rebuilt impl is not stale ---------------
xu="$tmp/xu"
rm -rf "$xu"
mkdir -p "$xu"
cp "$root"/test/ast/i2_cross_unit/*.ct "$xu/" || fail_msg "A3: cannot stage the fixture"
if ( cd "$xu" && CT_CORE_DIR="$root/lib/core" "$ctast" build prog.ct -o "$xu/bin" ) \
        >"$tmp/a3.out" 2>"$tmp/a3.err"; then
    if ! "$xu/bin" >"$tmp/a3.txt" 2>&1; then
        fail_msg "A3: the cross-unit program exited non-zero"
    elif ! diff -u "$root/test/ast/i2_cross_unit/prog.expected.out" "$tmp/a3.txt" \
            >"$tmp/a3.diff"; then
        fail_msg "A3: cross-unit output drifted"
    elif ! grep -Fq '.vt->get(' "$xu"/.ctbuild/*.c 2>/dev/null; then
        fail_msg "A3: the call unit did not spell the vtable slot"
    else
        # change the impl and rebuild: a stale product would still print 42.
        # The cache compares mtimes, so let the clock move past the edit.
        sleep 1
        sed 's/self->n + 1/self->n + 2/' "$xu/mem.h.ct" >"$xu/mem.h.ct.new"
        mv "$xu/mem.h.ct.new" "$xu/mem.h.ct"
        if ( cd "$xu" && CT_CORE_DIR="$root/lib/core" "$ctast" build prog.ct -o "$xu/bin2" ) \
                >"$tmp/a3b.out" 2>"$tmp/a3b.err" \
           && "$xu/bin2" >"$tmp/a3b.txt" 2>&1 \
           && [ "$(cat "$tmp/a3b.txt")" = "43" ]; then
            ok_msg "A3  trait/impl/call cross three units; a rebuild sees the new impl"
        else
            fail_msg "A3: a rebuilt impl did not reach the call (stale vtable): $(cat "$tmp/a3b.txt" 2>/dev/null)"
        fi
    fi
else
    fail_msg "A3: ct build failed: $(sed -n '1,3p' "$tmp/a3.err" | tr '\n' ' ')"
fi

# --- A4: D-028's inherent path is unchanged ------------------------------
if compile a4 test/ast/index_overload_both/prog.ct; then
    if grep -Fq 'Vault_get(&b, 2)' "$tmp/a4.c"; then
        ok_msg "A4  a concrete type's [] still calls its inherent get"
    else
        fail_msg "A4: the inherent subscript shape changed"
    fi
    run_bin a4 index_overload_both || true
fi

# --- A5..A9 and the misuse pair ------------------------------------------
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
        fail_msg "$label: a rejected subscript still wrote a product"
        return
    fi
    ok_msg "$label"
}

neg i2_no_index 26:13 \
    "trait 'Env' declares no indexed get; 'o[k]' is not available" \
    "A5  an unmarked get leaves o[k] unavailable"
neg i2_key_mismatch 26:13 \
    "trait 'Slot' has no indexed 'get' matching key type 'int': candidates are 'char *'" \
    "A6  a mismatched key lists the declared key types"
neg i2_write_phase1 25:6 \
    "interface subscript is read-only in this phase; declare 'void set(K, V) index' (stage 2)" \
    "A8  stage one refuses the write form before resolving get"
neg i2_write_incr 25:6 \
    "interface subscript is read-only in this phase; declare 'void set(K, V) index' (stage 2)" \
    "A8  stage one refuses ++ with the same diagnostic"
neg i2_non_iface 27:13 \
    "type 'Json' has no subscript: declare 'V get(K)' in impl Json" \
    "A9  the interface rule does not reach a concrete type"
neg i2_struct_key_mismatch 21:13 \
    "type 'Vault' has no subscript matching 'get(int)': candidates are 'int get(char *)'" \
    "A9  the concrete type keeps D-028's candidate list"

echo "i2/index: $fail failure(s)"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
