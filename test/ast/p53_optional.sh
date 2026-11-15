#!/bin/sh
# PH-53 probe: parser-level optional chain `?.` / `?[`.
# E53-1..E53-8 positives, E53-9..E53-15 diagnostics.
set -u
ctast=${1:?usage: p53_optional.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p53-opt.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

run_pos() {
    name=$1
    if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
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

# --- E53-1: p?.f ----------------------------------------------------------
if run_pos p53_ptr_field; then
    if grep -Fq '(p ? p->b : 0)' "$tmp/p53_ptr_field.c" \
       && grep -Fq '(q ? q->b : 0)' "$tmp/p53_ptr_field.c"; then
        ok_msg "E53-1 pointer field p?.b"
    else
        fail_msg "E53-1: the conditional shape is missing"
    fi
fi

# --- E53-2: a.b?.c, materialised once ------------------------------------
if run_pos p53_field_ptr; then
    if grep -Fq '__ct_opt0' "$tmp/p53_field_ptr.c" \
       && grep -Fq '? __ct_opt0->c : 0' "$tmp/p53_field_ptr.c"; then
        ok_msg "E53-2 value-obtained pointer field"
    else
        fail_msg "E53-2: no single-evaluation temporary"
    fi
fi

# --- E53-3: m["k"]?.c, get once ------------------------------------------
if run_pos p53_map_value; then
    n=$(grep -o 'Map_char_p_B_get(' "$tmp/p53_map_value.c" | wc -l | tr -d ' ')
    if [ "$n" -eq 3 ]; then       # one definition + one call per lookup
        ok_msg "E53-3 map value optional (get once per lookup)"
    else
        fail_msg "E53-3: expected 3 Map_char_p_B_get occurrences, got $n"
    fi
fi

# --- E53-4: m?["k"] -------------------------------------------------------
if run_pos p53_map_ptr_sub; then
    if grep -Fq 'Map_char_p_int_get(mp, "k")' "$tmp/p53_map_ptr_sub.c" \
       && grep -Fq 'np ? Map_char_p_int_get(np, "k") : 0' "$tmp/p53_map_ptr_sub.c"; then
        ok_msg "E53-4 map pointer subscript"
    else
        fail_msg "E53-4: the map-pointer conditional is missing"
    fi
fi

# --- E53-5: p?[i] ---------------------------------------------------------
if run_pos p53_ptr_sub; then
    if grep -Fq '(p ? p[1] : 0)' "$tmp/p53_ptr_sub.c" \
       && grep -Fq '(q ? q[1] : 0)' "$tmp/p53_ptr_sub.c"; then
        ok_msg "E53-5 pointer subscript"
    else
        fail_msg "E53-5: the pointer-subscript conditional is missing"
    fi
fi

# --- E53-6: chained short-circuit ----------------------------------------
if run_pos p53_chain; then
    ok_msg "E53-6 chained optional (missing / mid-null / full)"
fi

# --- E53-7: f()?.b evaluates f once --------------------------------------
if run_pos p53_eval_once; then
    if grep -Fq 'calls=1' "$tmp/p53_eval_once.txt"; then
        ok_msg "E53-7 receiver evaluated once"
    else
        fail_msg "E53-7: the call counter is not 1"
    fi
fi

# --- E53-8: c?.5 : 1.0 stays ternary -------------------------------------
if run_pos p53_ternary_dot5; then
    if grep -Fq '(c ? .5 : 1.0)' "$tmp/p53_ternary_dot5.c"; then
        ok_msg "E53-8 T1 conditional '.5' unchanged"
    else
        fail_msg "E53-8: the ternary spelling changed"
    fi
fi

# --- E53-9..E53-15: diagnostics ------------------------------------------
neg() {
    name=$1
    pos=$2
    msg=$3
    if ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg.c" ) \
            >"$tmp/neg.out" 2>"$tmp/neg.err"; then
        fail_msg "$name: expected a diagnostic, got exit 0"
    elif ! grep -Fq "test/ast/errors/$name.ct:$pos: error: $msg" "$tmp/neg.err"; then
        fail_msg "$name: $(cat "$tmp/neg.err")"
    elif [ "$(grep -c 'error:' "$tmp/neg.err")" -ne 1 ]; then
        fail_msg "$name: expected exactly one diagnostic: $(cat "$tmp/neg.err")"
    elif [ -e "$tmp/neg.c" ]; then
        fail_msg "$name: a rejected chain still wrote a product"
    else
        ok_msg "$name ($pos)"
    fi
}
neg p53_value_receiver 10:13 "optional chain '?.' requires a pointer receiver; a struct value has no empty state"
neg p53_value_subscript 10:13 "optional subscript '?[' requires a pointer receiver; a struct value has no empty state"
neg p53_struct_result 14:13 "optional chain result must be a pointer or scalar; 'B' has no NULL representation"
neg p53_struct_elem 10:13 "optional subscript result must be a pointer or scalar; 'B' has no NULL representation"
neg p53_map_vptr 13:19 "optional chain on a map lookup requires a value-typed V; got pointer value type; use a map of values or guard the inner pointer"
neg p53_lvalue 10:6 "optional chain/subscript is not an lvalue; it cannot be assigned or address-taken"
neg p53_method 18:13 "optional method calls are not supported; assign the receiver to a variable first"

echo "p53/optional: $fail failure(s)"
[ "$fail" -eq 0 ]
