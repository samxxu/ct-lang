#!/bin/sh
# PH-47 probe: `Map<Str, V>` -- len+bytes key comparison, a deep-copied key,
# one release per entry, borrowed keys through `foreach`, and the four-key
# diagnostic (E47-1 / E47-2 / E47-4 / E47-5).
#
# E47-1: embedded NUL keys stay distinct; releasing the caller's source handle
#        leaves the entry usable; compile mode and build mode print the same.
# E47-2: the counted allocator in test/ast/242_map_str_release/prog.ct pins one
#        key copy per `put`, one release on overwrite / remove / final release,
#        and a zero live count (explicit leak evidence: LeakSanitizer is not
#        available on this platform, and check-sanitizers.sh disables it anyway).
# E47-4: the negative diagnostic lists the four key types, is positioned, is the
#        single error, and leaves no `.c`; both older key probes keep the new
#        wording.
# E47-5: `foreach` reads the borrowed key; the std documentation says it must
#        not be released.
# The `char *` probe pins that borrowing did not change (E47-3 semantics).
set -u
ctast=${1:?usage: p47_map.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p47-map.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

# --- E47-1 / E47-5: compile mode and build mode agree with expected output ---
src=test/ast/241_map_str_key/prog.ct
exp=test/ast/241_map_str_key/prog.expected.out
if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" "$src" -o "$tmp/c.c" ) \
        >"$tmp/c.out" 2>"$tmp/c.err"; then
    fail_msg "compile mode failed:"; sed 's/^/  /' "$tmp/c.err" >&2
elif ! "$cc" -Wall -Wextra -std=c99 "$tmp/c.c" -o "$tmp/c.bin" 2>"$tmp/c.cc"; then
    fail_msg "the compile-mode product did not build:"; sed 's/^/  /' "$tmp/c.cc" >&2
elif ! "$tmp/c.bin" >"$tmp/c.txt" 2>&1; then
    fail_msg "the compile-mode product exited non-zero"
elif ! ( cd "$root" && diff -u "$exp" "$tmp/c.txt" ) >"$tmp/c.diff"; then
    fail_msg "compile-mode output drifted:"; head -12 "$tmp/c.diff" >&2
else
    ok_msg "E47-1/E47-5 compile mode (embedded NUL, source release, foreach)"
fi

mkdir -p "$tmp/build"
if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" build --emit-c "$src" -o "$tmp/build" ) \
        >"$tmp/b.out" 2>"$tmp/b.err"; then
    fail_msg "build mode failed:"; sed 's/^/  /' "$tmp/b.err" >&2
elif ! "$cc" -std=c99 -I "$tmp/build" "$tmp/build"/*.c -o "$tmp/b.bin" 2>"$tmp/b.cc"; then
    fail_msg "the build-mode products did not build:"; sed 's/^/  /' "$tmp/b.cc" >&2
elif ! "$tmp/b.bin" >"$tmp/b.txt" 2>&1; then
    fail_msg "the build-mode product exited non-zero"
elif ! cmp -s "$tmp/c.txt" "$tmp/b.txt"; then
    fail_msg "compile-mode and build-mode output differ: $(cat "$tmp/b.txt")"
else
    ok_msg "E47-1 compile/build modes agree"
fi

# The key block is the one that runs: the entry spells `Str` by value and the
# comparison reads `len` plus `memcmp`, never a NUL-terminated `strcmp`.
if grep -Fq 'Map_Str_int_put(void *self, struct Str k' "$tmp/c.c" \
   && grep -Fq 'memcmp(es[i].key.data, k.data' "$tmp/c.c"; then
    ok_msg "E47-1 the Str key block owns put (len + memcmp)"
else
    fail_msg "the Str key block is missing from the product"
fi

# --- E47-2: one key copy per put, one release per entry ---------------------
rsrc=test/ast/242_map_str_release/prog.ct
rexp=test/ast/242_map_str_release/prog.expected.out
if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" "$rsrc" -o "$tmp/r.c" ) \
        >"$tmp/r.out" 2>"$tmp/r.err"; then
    fail_msg "the release fixture did not compile:"; sed 's/^/  /' "$tmp/r.err" >&2
elif ! "$cc" -std=c99 "$tmp/r.c" -o "$tmp/r.bin" 2>"$tmp/r.cc"; then
    fail_msg "the release fixture did not build:"; sed 's/^/  /' "$tmp/r.cc" >&2
elif ! "$tmp/r.bin" >"$tmp/r.txt" 2>&1; then
    fail_msg "the release fixture exited non-zero"
elif ! ( cd "$root" && diff -u "$rexp" "$tmp/r.txt" ) >"$tmp/r.diff"; then
    fail_msg "the key release counts drifted:"; head -12 "$tmp/r.diff" >&2
else
    ok_msg "E47-2 key release counts (one copy per put, live=0)"
fi

# --- E47-3 semantics: a `char *` key still borrows its pointer --------------
cat >"$tmp/borrow.ct" <<'BORROW'
#include <stdio.h>
#include <string.h>

int main(void)
{
    Map<char *, int> m;
    char buf[8];
    m.h = 0;
    strcpy(buf, "key1");
    m.put(buf, 1);
    strcpy(buf, "key2");
    printf("old=%d new=%d\n", m.get("key1") == 0, *m.get("key2"));
    m.release();
    return 0;
}
BORROW
if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" "$tmp/borrow.ct" -o "$tmp/borrow.c" ) \
        >"$tmp/borrow.out" 2>"$tmp/borrow.err"; then
    fail_msg "the char * borrow probe did not compile:"; sed 's/^/  /' "$tmp/borrow.err" >&2
elif ! "$cc" -std=c99 "$tmp/borrow.c" -o "$tmp/borrow.bin" 2>"$tmp/borrow.cc" \
      || ! "$tmp/borrow.bin" >"$tmp/borrow.txt" 2>&1; then
    fail_msg "the char * borrow probe did not run"
elif ! grep -qx 'old=1 new=1' "$tmp/borrow.txt"; then
    fail_msg "the char * key no longer borrows: $(cat "$tmp/borrow.txt")"
else
    ok_msg "E47-3 char * keys still borrow the caller's pointer"
fi

# --- E47-4: the diagnostic and the two older key probes ---------------------
p47_neg() {
    name=$1
    wtext=$2
    wpos=$3
    if ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg.c" ) \
            >"$tmp/neg.out" 2>"$tmp/neg.err"; then
        fail_msg "L47-1 $name: expected a diagnostic, got exit 0"
    elif ! grep -Fq "$wtext" "$tmp/neg.err"; then
        fail_msg "L47-1 $name: $(cat "$tmp/neg.err")"
    elif grep -Fiq 'undeclared' "$tmp/neg.err"; then
        fail_msg "L47-1 $name: fell back to 'undeclared': $(cat "$tmp/neg.err")"
    elif [ "$(grep -c 'error:' "$tmp/neg.err")" -ne 1 ]; then
        fail_msg "L47-1 $name: expected exactly one diagnostic: $(cat "$tmp/neg.err")"
    elif ! grep -Fq "test/ast/errors/$name.ct:$wpos: error:" "$tmp/neg.err"; then
        fail_msg "L47-1 $name: expected the diagnostic at $wpos: $(cat "$tmp/neg.err")"
    elif [ -e "$tmp/neg.c" ]; then
        fail_msg "L47-1 $name: a rejected key still wrote a product"
    else
        ok_msg "L47-1 $name ($wpos)"
    fi
}
p47_neg p47_map_struct_key "Map does not support key type 'struct Key' (key types: int, long, char *, Str)" 9:26
p47_neg map_key_bad "Map does not support key type 'char' (key types: int, long, char *, Str)" 6:20
p47_neg L31_nested_map_key "Map does not support key type 'struct Vec_int' (key types: int, long, char *, Str)" 7:24

# --- E47-5: the documentation states the borrowed-key rule ------------------
if ( cd "$root" && grep -Fq '不得 release 键' lib/std/README.md ); then
    ok_msg "E47-5 the std README says a foreach key must not be released"
else
    fail_msg "lib/std/README.md does not state the borrowed-key release rule"
fi

echo "p47/map-str-key: $fail failure(s)"
[ "$fail" -eq 0 ]
