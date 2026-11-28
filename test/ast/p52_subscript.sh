#!/bin/sh
# PH-52 probe: the user-type subscript protocol (scheme A: name + arity).
#
# E52-1 read      : `x["k"]` -> `get(k)`, product compiles/runs.
# E52-2 generic   : `Box<int>` resolves to `Box_int_get`, no `Box<` residue.
# E52-3 write     : `x["k"] = 9;` -> `set(k, 9)` and reads back.
# E52-4 errors    : L52-1..L52-9 exact position/text, no product.
# E52-5 C passthrough: array / pointer / pointer-to-struct keep C subscripts.
# E52-6 visibility: a private `get` is L52-10 in build mode.
# E52-7 str-only  : a single-layer string key compiles and runs.
set -u
ctast=${1:?usage: p52_subscript.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p52-sub.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

run_pos() {
    name=$1
    if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
            "test/ast/$name/prog.ct" -o "$tmp/$name.c" ) \
            >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail_msg "$name: ct-ast failed:"; sed 's/^/  /' "$tmp/$name.err" >&2
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$tmp/$name.c" -o "$tmp/$name.bin" \
            2>"$tmp/$name.cc"; then
        fail_msg "$name: generated C did not build:"; sed 's/^/  /' "$tmp/$name.cc" >&2
        return 1
    fi
    if [ -s "$tmp/$name.cc" ]; then
        fail_msg "$name: generated C is not warning-free:"; sed 's/^/  /' "$tmp/$name.cc" >&2
    fi
    if ! "$tmp/$name.bin" >"$tmp/$name.txt" 2>&1; then
        fail_msg "$name: the program exited non-zero"
        return 1
    fi
    if ! ( cd "$root" && diff -u "test/ast/$name/prog.expected.out" "$tmp/$name.txt" ) \
            >"$tmp/$name.diff"; then
        fail_msg "$name: output drifted:"; head -12 "$tmp/$name.diff" >&2
        return 1
    fi
    return 0
}

# --- E52-1: read ----------------------------------------------------------
if run_pos p52_read; then
    if grep -Fq 'X_get(&x, "a")' "$tmp/p52_read.c" \
       && grep -Fq 'X_get(&x, "z")' "$tmp/p52_read.c"; then
        ok_msg "E52-1 read x[\"k\"] -> get(k)"
    else
        fail_msg "E52-1: the read sugar is missing from the product"
    fi
fi

# --- E52-2: generic instance ---------------------------------------------
if run_pos p52_generic; then
    if grep -Fq 'Box_int_get(&b, "k")' "$tmp/p52_generic.c" \
       && ! grep -Fq 'Box<' "$tmp/p52_generic.c"; then
        ok_msg "E52-2 generic Box<int> (no template residue)"
    else
        fail_msg "E52-2: generic product names or template residue are wrong"
    fi
fi

# --- E52-3: write ---------------------------------------------------------
if run_pos p52_write; then
    if grep -Fq 'X_set(&x, "k", 9);' "$tmp/p52_write.c"; then
        ok_msg "E52-3 write x[\"k\"] = 9 -> set(k, 9)"
    else
        fail_msg "E52-3: the write sugar is missing from the product"
    fi
fi

# --- E52-7: single-layer string key --------------------------------------
if run_pos p52_str_only; then
    ok_msg "E52-7 single-layer string key"
fi

# --- E52-5: C passthrough ------------------------------------------------
if run_pos p52_c_passthrough; then
    if grep -Fq 'arr[1]' "$tmp/p52_c_passthrough.c" \
       && grep -Fq 'p[2]' "$tmp/p52_c_passthrough.c" \
       && grep -Fq 'px[0].n' "$tmp/p52_c_passthrough.c"; then
        ok_msg "E52-5 C array / pointer / pointer-to-struct passthrough"
    else
        fail_msg "E52-5: a C subscript was rewritten"
    fi
fi

# --- E52-4: L52-1..L52-9 -------------------------------------------------
neg() {
    name=$1
    pos=$2
    msg=$3
    if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg.c" ) \
            >"$tmp/neg.out" 2>"$tmp/neg.err"; then
        fail_msg "$name: expected a diagnostic, got exit 0"
    elif ! grep -Fq "test/ast/errors/$name.ct:$pos: error: $msg" "$tmp/neg.err"; then
        fail_msg "$name: $(cat "$tmp/neg.err")"
    elif [ "$(grep -c 'error:' "$tmp/neg.err")" -ne 1 ]; then
        fail_msg "$name: expected exactly one diagnostic: $(cat "$tmp/neg.err")"
    elif [ -e "$tmp/neg.c" ]; then
        fail_msg "$name: a rejected subscript still wrote a product"
    else
        ok_msg "$name ($pos)"
    fi
}
# D-031: a literal key on a struct with no `get` is now the field-oriented
# error (it lists the fields) instead of L52-1.
neg p52_no_get      11:13 "type 'X' has no field 'k': candidates are 'n'"
neg p52_no_set      16:6  "type 'X' has a read-only subscript: declare 'void set(K, V)' in impl X"
neg p52_get_arity   17:13 "type 'X' has no subscript: 'get' must take 1 parameter"
neg p52_set_arity   20:6  "type 'X' has no writable subscript: 'set' must take 2 parameters"
neg p52_static_get  17:13 "type 'X' has no subscript: 'get' must be an instance method"
neg p52_compound    22:6  "a custom subscript supports only '='; use set(k, v)"
neg p52_addr        17:16 "cannot take the address of a custom subscript; bind it to a local first"
neg p52_rvalue_write 26:11 "a custom subscript write needs a statement and an lvalue receiver"
neg p52_own_write   32:6  "a custom subscript set cannot take an 'own' or 'borrow' value"

# --- E52-6: L52-10 cross-unit private get --------------------------------
if ( cd "$root/test/ast/p52_private" && CT_CORE_DIR="$root/lib/core" "$ctast" \
        build --emit-c consumer.ct -o "$tmp/priv" ) \
        >"$tmp/priv.out" 2>"$tmp/priv.err"; then
    fail_msg "E52-6: a private 'get' was accepted across units"
elif ! grep -Fq "consumer.ct:10:21: error: type 'X' has no subscript: 'get' is private to its unit" \
        "$tmp/priv.err"; then
    fail_msg "E52-6: $(cat "$tmp/priv.err")"
elif ls "$tmp"/priv/*.c >/dev/null 2>&1; then
    fail_msg "E52-6: a rejected cross-unit subscript still wrote a product"
else
    ok_msg "E52-6 private get is L52-10"
fi

echo "p52/subscript: $fail failure(s)"
[ "$fail" -eq 0 ]
