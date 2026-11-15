#!/bin/sh
# PH-49 probe: the `own` initializer accepts a factory call whose Symbols row
# returns the literal `struct X *` (E49-1), a zero initializer owns nothing
# (E49-2), other pointer expressions stay L49-1 (E49-3), a return-position
# `own` stays rejected with L49-3 (E49-4), and the `?` cleanup order is the
# PH-40 one (E49-6).
set -u
ctast=${1:?usage: p49_own.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p49-own.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

run_mode() {
    name=$1
    src=$2
    exp=$3
    build=$4
    out="$tmp/$name"
    mkdir -p "$out"
    if [ "$build" = build ]; then
        if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" build --emit-c \
                "$src" -o "$out" ) >"$out.out" 2>"$out.err"; then
            fail_msg "$name: ct-ast build failed:"; sed 's/^/  /' "$out.err" >&2
            return 1
        fi
        if ! "$cc" -Wall -Wextra -std=c99 -I "$out" "$out"/*.c -o "$out.bin" \
                2>"$out.cc"; then
            fail_msg "$name: generated C did not build:"; sed 's/^/  /' "$out.cc" >&2
            return 1
        fi
        cfile="$out/prog.c"
    else
        if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" "$src" \
                -o "$out/prog.c" ) >"$out.out" 2>"$out.err"; then
            fail_msg "$name: ct-ast failed:"; sed 's/^/  /' "$out.err" >&2
            return 1
        fi
        if ! "$cc" -Wall -Wextra -std=c99 "$out/prog.c" -o "$out.bin" \
                2>"$out.cc"; then
            fail_msg "$name: generated C did not build:"; sed 's/^/  /' "$out.cc" >&2
            return 1
        fi
        cfile="$out/prog.c"
    fi
    if ! "$out.bin" >"$out.txt" 2>&1; then
        fail_msg "$name: the program exited non-zero"
        return 1
    fi
    if ! ( cd "$root" && diff -u "$exp" "$out.txt" ) >"$out.diff"; then
        fail_msg "$name: output drifted:"; head -12 "$out.diff" >&2
        return 1
    fi
    return 0
}

# --- E49-1: factory initializer, one allocation and one Drop ----------------
if run_mode factory test/ast/245_own_factory/prog.ct \
        test/ast/245_own_factory/prog.expected.out compile; then
    if grep -Fq 'if (p) { P_Drop_drop(p); free(p); p = 0; }' "$tmp/factory/prog.c"; then
        ok_msg "E49-1 factory initializer (allocs=1 drops=1, guarded release)"
    else
        fail_msg "E49-1: the factory release is not the guarded AutoDrop shape"
    fi
fi

# --- E49-1 cross-unit: the owner's Drop body is reached ---------------------
if run_mode factory_cross test/ast/248_own_factory_cross/prog.ct \
        test/ast/248_own_factory_cross/prog.expected.out build; then
    if grep -Fq 'if (p) { P_Drop_drop(p); free(p); p = 0; }' "$tmp/factory_cross/prog.c" \
       && grep -Fq 'void P_Drop_drop(void *self) {' "$tmp/factory_cross/p.c"; then
        ok_msg "E49-1 cross-unit factory (consumer release, owner Drop body)"
    else
        fail_msg "E49-1 cross-unit: missing guarded release or owner Drop body"
    fi
fi

# --- E49-2: zero owns nothing ----------------------------------------------
if run_mode null test/ast/246_own_null/prog.ct \
        test/ast/246_own_null/prog.expected.out compile; then
    n=$(grep -c 'if (p) { P_Drop_drop(p); free(p); p = 0; }' "$tmp/null/prog.c")
    if [ "$n" -ne 1 ]; then
        fail_msg "E49-2: expected exactly one guarded release, found $n"
    elif grep -Fq 'if (q) { P_Drop_drop' "$tmp/null/prog.c"; then
        fail_msg "E49-2: the zero initializer was registered and released"
    else
        ok_msg "E49-2 zero initializer (not registered, guarded factory null)"
    fi
fi

# --- E49-3 / E49-4: the rejected spellings --------------------------------
p49_neg() {
    name=$1
    wtext=$2
    wpos=$3
    if ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg.c" ) \
            >"$tmp/neg.out" 2>"$tmp/neg.err"; then
        fail_msg "$name: expected a diagnostic, got exit 0"
    elif ! grep -Fq "$wtext" "$tmp/neg.err"; then
        fail_msg "$name: $(cat "$tmp/neg.err")"
    elif grep -Fiq 'undeclared' "$tmp/neg.err"; then
        fail_msg "$name: fell back to 'undeclared': $(cat "$tmp/neg.err")"
    elif [ "$(grep -c 'error:' "$tmp/neg.err")" -ne 1 ]; then
        fail_msg "$name: expected exactly one diagnostic: $(cat "$tmp/neg.err")"
    elif ! grep -Fq "test/ast/errors/$name.ct:$wpos: error:" "$tmp/neg.err"; then
        fail_msg "$name: expected the diagnostic at $wpos: $(cat "$tmp/neg.err")"
    elif [ -e "$tmp/neg.c" ]; then
        fail_msg "$name: a rejected initializer still wrote a product"
    else
        ok_msg "$name ($wpos)"
    fi
}
p49_neg p49_own_addr "'own' requires a malloc, calloc or factory call returning 'struct P *'" 14:1
p49_neg p49_own_int_addr "'own' requires a malloc or calloc initialiser" 6:1
p49_neg p49_own_dup "duplicate 'own' binding for 'p'" 16:1
p49_neg p49_own_return "'own' in a return type is not supported; mark the call site instead: 'own struct <T> *p = factory();'" 10:1

# --- E49-6: `?` cleanup order with an owned factory value -------------------
if run_mode try test/ast/247_own_try/prog.ct \
        test/ast/247_own_try/prog.expected.out compile; then
    if [ "$(head -1 "$tmp/try.txt")" = "errdefer" ] \
       && [ "$(sed -n '2p' "$tmp/try.txt")" = "drop 7" ]; then
        ok_msg "E49-6 own + ? + errdefer (PH-40 order)"
    else
        fail_msg "E49-6: cleanup order changed: $(cat "$tmp/try.txt")"
    fi
fi

echo "p49/own: $fail failure(s)"
[ "$fail" -eq 0 ]
