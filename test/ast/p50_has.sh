#!/bin/sh
# PH-50 probe: `Vec::has` / `Vec::at` and `Map::has` (E50-1/2/3/5/6).
#
# E50-1: an in-range zero value is present (`has=1`, `*at=0`), an out-of-range
#        index is `has=0 && at=0`.
# E50-2: `Map::has` agrees with `get` for int / char * keys; a present zero
#        value still reports `has=1`.
# E50-3: the fixed 32-row `id,has,hit,val` table is byte-compared.
# E50-5: a `Str` key with an embedded NUL hashes/compares like `get`.
# E50-6: `at` returns a borrow; reading it and releasing the container must not
#        double-free (runs under ASAN/UBSAN).
set -u
ctast=${1:?usage: p50_has.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p50-has.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

report() { grep -Eq 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' "$@"; }

run_one() {
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
    if ! "$tmp/$name.bin" >"$tmp/$name.txt" 2>&1; then
        fail_msg "$name: the program exited non-zero"
        return 1
    fi
    if ! ( cd "$root" && diff -u "test/ast/$name/prog.expected.out" "$tmp/$name.txt" ) \
            >"$tmp/$name.diff"; then
        fail_msg "$name: output drifted:"; head -16 "$tmp/$name.diff" >&2
        return 1
    fi
    return 0
}

# --- E50-1: Vec ------------------------------------------------------------
if run_one p50_vec_has; then
    if grep -qx 'oob has=0 at=1' "$tmp/p50_vec_has.txt" \
       && grep -qx 'zero has=1 hit=1 val=0' "$tmp/p50_vec_has.txt" \
       && grep -qx 'neg has=0 at=1' "$tmp/p50_vec_has.txt" \
       && grep -qx 'empty has=0 at=1' "$tmp/p50_vec_has.txt"; then
        ok_msg "E50-1 Vec::has / Vec::at (zero value present, miss has at=0)"
    else
        fail_msg "E50-1: a required line is missing"
    fi
fi

# --- E50-2: Map<int> / Map<char *> -----------------------------------------
if run_one p50_map_has; then
    if grep -qx 'int hit=1 has=1 get=1 val=0' "$tmp/p50_map_has.txt" \
       && grep -qx 'int miss=1 has=0 get=1' "$tmp/p50_map_has.txt" \
       && grep -qx 'str hit=1 has=1 val=0' "$tmp/p50_map_has.txt" \
       && grep -qx 'str miss=1 has=0 get=1' "$tmp/p50_map_has.txt"; then
        ok_msg "E50-2 Map::has (int / char *, zero value present)"
    else
        fail_msg "E50-2: a required line is missing"
    fi
fi

# --- E50-3: the 32-row table ------------------------------------------------
if run_one p50_table; then
    n=$(wc -l <"$tmp/p50_table.txt" | tr -d ' ')
    if [ "$n" -ne 32 ]; then
        fail_msg "E50-3: expected 32 rows, got $n"
    else
        ok_msg "E50-3 32-row has/at/get consistency table"
    fi
fi

# --- E50-5: Str keys with an embedded NUL ----------------------------------
if run_one p50_str_has; then
    if grep -qx 'nul-a has=1 hit=1 val=0' "$tmp/p50_str_has.txt" \
       && grep -qx 'nul-b has=1 hit=1 val=2' "$tmp/p50_str_has.txt" \
       && grep -qx 'longer=0 prefix=0 plain=0' "$tmp/p50_str_has.txt"; then
        ok_msg "E50-5 Str key has (embedded NUL, length-sensitive misses)"
    else
        fail_msg "E50-5: a required line is missing"
    fi
fi

# --- E50-6: the borrowed pointer is not released ---------------------------
san="-fsanitize=address,undefined -fno-omit-frame-pointer"
if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
        test/ast/p50_sanitize/prog.ct -o "$tmp/san.c" ) \
        >"$tmp/san.out" 2>"$tmp/san.err"; then
    fail_msg "E50-6: the sanitizer fixture did not compile:"; sed 's/^/  /' "$tmp/san.err" >&2
elif ! "$cc" -Wall -Wextra -std=c99 $san "$tmp/san.c" -o "$tmp/san.bin" \
        2>"$tmp/san.cc"; then
    fail_msg "E50-6: the sanitizer product did not build:"; sed 's/^/  /' "$tmp/san.cc" >&2
elif ! ASAN_OPTIONS=detect_leaks=0 UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1 \
        "$tmp/san.bin" >"$tmp/san.txt" 2>"$tmp/san.stderr"; then
    fail_msg "E50-6: the sanitizer program exited non-zero"
elif report "$tmp/san.stderr"; then
    fail_msg "E50-6: a sanitizer report appeared:"; head -12 "$tmp/san.stderr" >&2
elif ! ( cd "$root" && diff -u test/ast/p50_sanitize/prog.expected.out "$tmp/san.txt" ) \
        >"$tmp/san.diff"; then
    fail_msg "E50-6: sanitizer output drifted:"; head -12 "$tmp/san.diff" >&2
else
    ok_msg "E50-6 borrowed at pointer + container release (ASAN/UBSAN clean)"
fi

echo "p50/has: $fail failure(s)"
[ "$fail" -eq 0 ]
