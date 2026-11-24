#!/usr/bin/env bash
# LANG-29 S3 / B2 probe: enum ADT inherent methods, the custom subscript and
# multi-level chains.
#
# E-l29b2-1: `enum Cell { … } impl Cell { … }` is an inherent block (no trait).
#            The body may `match` the receiver, read fields and construct
#            variants; the call site is a plain `Cell_<method>(&recv, …)`.
# E-l29b2-2: an ADT with `get(K)` / `set(K, V)` supports `n[k]` and
#            `n[k] = v` (statement form), with the read/write diagnostics of
#            PH-52 (L52-1, L52-2, L52-5).
# E-l29b2-3: a chain rooted at a custom subscript works -- `n[k].field`,
#            `n[k].field.field`, `n[k].method()` -- and a chain rooted at a
#            call result does too.  Each temporary is named once: the index
#            expression and the `get` call appear exactly once in the product,
#            and no custom subscript is lowered to C pointer arithmetic.
# E-l29b2-4: an out-of-range key is answered by the protocol's own `get` (the
#            fixture returns its sentinel), and an out-of-range `set` is a
#            no-op; neither crashes.
# E-l29b2-5: the negatives keep their positioned text: an unknown ADT method,
#            a missing `get`, a missing `set` and a static `get`.
#
# Usage: bash test/ast/l29b2_methods.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: l29b2_methods.sh <ct-ast>}
CC=${CC:-cc}
abs_ct() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *) printf '%s/%s' "$PWD" "$1" ;;
    esac
}
CT=$(abs_ct "$CT")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/l29b2.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL l29b2: $1" >&2; }
dump() { sed 's/^/    /' "$tmp/o" >&2; }
has() { grep -qF -- "$2" "$1"; }
no()  { ! grep -qF -- "$2" "$1"; }

# ---- E-l29b2-1..4: the positive fixture ------------------------------------
src="test/ast/301_adt_methods/prog.ct"
if ! ( cd "$root" && "$CT" "$src" -o "$tmp/p.c" ) >"$tmp/o" 2>&1; then
    bad "the ADT-method fixture did not compile"
    dump
else
    ok
fi

c="$tmp/p.c"
if [ -f "$c" ]; then
    # the inherent definitions carry the ADT tag, no vtable
    if has "$c" "Cell_get(struct Cell *self, int i)" \
       && has "$c" "Cell_set(struct Cell *self, int i, struct Slot v)" \
       && has "$c" "Cell_value(struct Cell *self)" \
       && has "$c" "Cell_rebuilt(struct Cell *self)"; then
        ok
    else
        bad "an ADT inherent method is not emitted as <tag>_<method>(struct <tag> *)"
    fi
    if no "$c" "_vtable" && no "$c" "__Cell_vptr"; then
        ok
    else
        bad "the inherent ADT call still emits a vtable or vptr"
    fi

    # a `match` over the receiver dereferences it once and keeps the value form
    if has "$c" "struct Cell __ct_match" && has "$c" "*(_self)"; then
        ok
    else
        bad "match(self) is not lowered to a value match over the receiver"
    fi

    # a constructor inside a method body is ordinary code
    if has "$c" "struct Cell c = ((struct Cell){ .tag = 1, .u = { .Empty = { .z = (5) } } });"; then
        ok
    else
        bad "a variant constructor inside an ADT method body did not lower to a compound literal"
    fi

    # E-l29b2-3: subscript -> field -> field; call result -> field -> field
    if has "$c" "Cell_get(&c, 0).at.x" && has "$c" "make_slot(5).at.x"; then
        ok
    else
        bad "a multi-level field chain rooted at a subscript / call result is missing"
    fi
    # the subscript call is never turned into C pointer arithmetic
    if no "$c" "Cell_get(&c, 0)[" && no "$c" "(&c)[" && no "$c" "Cell_get(&c, 0)->"; then
        ok
    else
        bad "a custom subscript was lowered to C pointer arithmetic"
    fi
    # method on a temporary: one hoisted receiver, addressed in place
    if has "$c" "Slot_twice(&__ct_tmp" && has "$c" "Cell_get(&c, index())"; then
        ok
    else
        bad "a method call on a subscript result was not materialised once"
    fi
    if [ "$(grep -c 'index()' "$c")" -eq 1 ]; then
        ok
    else
        bad "the index expression was evaluated $(grep -c 'index()' "$c") times, expected 1"
    fi
    # write form: the statement lowers to set(key, value)
    if has "$c" "Cell_set(&c, 0, n);"; then
        ok
    else
        bad "the custom-subscript write form did not lower to set(k, v)"
    fi
else
    bad "no product was written"
fi

# E-l29b2-4: build warning-free, run, compare (out-of-range + one evaluation)
if [ -f "$c" ] && "$CC" -Wall -Wextra -std=c99 "$c" -o "$tmp/p.bin" \
        >"$tmp/cc.out" 2>"$tmp/cc.err"; then
    if [ -s "$tmp/cc.err" ]; then
        bad "the generated C is not warning-free:"; sed 's/^/    /' "$tmp/cc.err" >&2
    else
        ok
    fi
    if "$tmp/p.bin" >"$tmp/p.out" 2>&1 \
       && cmp -s "$tmp/p.out" "$root/test/ast/301_adt_methods/prog.expected.out"; then
        ok
    else
        bad "the program output drifted: $(cat "$tmp/p.out" 2>/dev/null)"
    fi
else
    bad "the generated C did not build: $(head -4 "$tmp/cc.err" 2>/dev/null)"
fi

# ---- E-l29b2-5: the negatives ---------------------------------------------
neg() {
    name=$1
    pos=$2
    msg=$3
    rm -f "$tmp/n.c"
    if ( cd "$root" && "$CT" "test/ast/errors/$name.ct" -o "$tmp/n.c" ) \
            >"$tmp/o" 2>&1; then
        bad "$name: expected a diagnostic, got exit 0"
    elif ! grep -qF "test/ast/errors/$name.ct:$pos: error: $msg" "$tmp/o"; then
        bad "$name: missing pinned diagnostic: $(head -2 "$tmp/o")"
    elif [ "$(grep -c 'error: ' "$tmp/o")" -ne 1 ]; then
        bad "$name: expected exactly one error: $(cat "$tmp/o")"
    elif [ -e "$tmp/n.c" ]; then
        bad "$name: a rejected program still wrote a product"
    else
        ok
    fi
}
neg l29b2_unknown_method 18:1  "no method 'nope' for type 'struct Cell'"
neg l29b2_no_get         16:14 "type 'Cell' has no subscript: declare 'V get(K)' in impl Cell"
neg l29b2_no_set         16:6  "type 'Cell' has a read-only subscript: declare 'void set(K, V)' in impl Cell"
neg l29b2_static_get     16:14 "type 'Cell' has no subscript: 'get' must be an instance method"

echo "l29b2: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK l29b2"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
