#!/bin/sh
# PH-46 probe: `Map<K, user struct>` (D46-2 / D46-5).
#
# E46-1: compile mode (one unit) and build mode (the value type lives in
#        another unit) answer the same program output.
# E46-3: the entry struct is a C tag, so it contributes no link symbol.
# E46-4: the `MapEntry_*` body lands in the unit that names the instance and in
#        no product header; a cross-unit `--lib` root keeps it internal too.
set -u
ctast=${1:?usage: p46_map.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p46-map.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }

# --- E46-4: ownership of the entry-struct body -----------------------------
mkdir -p "$tmp/out"
if ! ( cd "$root" && "$ctast" build --emit-c test/ast/240_map_user_struct/prog.ct -o "$tmp/out" ) >"$tmp/build.out" 2>"$tmp/build.err"; then
    fail_msg "build failed:"; sed 's/^/  /' "$tmp/build.err" >&2
else
    if grep -Eq '^struct MapEntry_[A-Za-z0-9_]*[ ]*\{' "$tmp/out"/*.h; then
        fail_msg "a product header still defines a MapEntry body"
    fi
    defs=$(grep -hEc '^struct MapEntry_char_p_JsonRef[ ]*\{' "$tmp/out"/*.c | awk '{s+=$1} END {print s+0}')
    if [ "$defs" -ne 1 ]; then
        fail_msg "expected exactly one MapEntry body in the products, found $defs"
    elif ! grep -Eq '^struct MapEntry_char_p_JsonRef[ ]*\{' "$tmp/out/prog.c"; then
        fail_msg "the MapEntry body is not in the using unit (prog.c)"
    fi
fi

# --- E46-1: compile mode and build mode agree ------------------------------
cat >"$tmp/single.ct" <<'SINGLE'
#include <stdio.h>

struct JsonRef {
    int tag;
}

struct JsonRef jsonref_make(int tag)
{
    struct JsonRef r;
    r.tag = tag;
    return r;
}

struct Doc {
    Map<char *, JsonRef> slots;
}

int main(void)
{
    struct Doc d;
    Map<char *, JsonRef> view;
    JsonRef r;
    JsonRef *got;
    int ok;
    int removed;

    d.slots.h = 0;
    r = jsonref_make(7);
    ok = d.slots.put("a", r);
    got = d.slots.get("a");
    printf("put %d get %d tag %d len %d\n", ok, got != 0,
           got != 0 ? got->tag : -1, d.slots.len());

    d.slots.put("b", jsonref_make(8));
    view.h = d.slots.h;
    foreach (view) {
        printf("it %s %d\n", item.key, item.value.tag);
    }

    removed = d.slots.remove("a");
    printf("remove %d len %d\n", removed, d.slots.len());
    foreach (view) {
        printf("left %s %d\n", item.key, item.value.tag);
    }
    d.slots.release();

    Map<char *, JsonRef> built = { "x": jsonref_make(9) };
    got = built.get("x");
    printf("from %d tag %d\n", got != 0, got != 0 ? got->tag : -1);
    built.release();
    return 0;
}
SINGLE
if ! "$ctast" "$tmp/single.ct" -o "$tmp/single.c" >"$tmp/single.out" 2>"$tmp/single.err"; then
    fail_msg "compile mode failed:"; sed 's/^/  /' "$tmp/single.err" >&2
elif ! "$cc" -std=c99 "$tmp/single.c" -o "$tmp/single.bin" 2>"$tmp/single.cc"; then
    fail_msg "the compile-mode product did not build:"; sed 's/^/  /' "$tmp/single.cc" >&2
elif ! "$cc" -std=c99 -I "$tmp/out" "$tmp/out"/*.c -o "$tmp/build.bin" 2>"$tmp/build.cc"; then
    fail_msg "the build-mode products did not build:"; sed 's/^/  /' "$tmp/build.cc" >&2
elif ! "$tmp/single.bin" >"$tmp/single.txt" 2>&1 || ! "$tmp/build.bin" >"$tmp/build.txt" 2>&1; then
    fail_msg "a program exited non-zero"
elif ! cmp -s "$tmp/single.txt" "$tmp/build.txt"; then
    fail_msg "compile-mode and build-mode output differ: $(cat "$tmp/build.txt")"
fi

# --- E46-3 / D46-5: no link symbol for the entry type ----------------------
if [ -x "$tmp/build.bin" ] && command -v nm >/dev/null 2>&1 \
   && nm -g --defined-only "$tmp/build.bin" 2>/dev/null | grep -q 'MapEntry'; then
    fail_msg "the entry type leaked a link symbol"
fi

# --- `--lib` export surface: the value type crosses a unit boundary --------
mkdir -p "$tmp/liblib" "$tmp/libout"
cp -R "$root/test/ast/240_map_user_struct/lib" "$tmp/liblib/lib"
cat >"$tmp/liblib/root.h.ct" <<'LIB'
import lib::types;

pub int slots_len(void)
{
    Map<char *, JsonRef> m;
    JsonRef r;
    int n;
    m.h = 0;
    r.tag = 4;
    m.put("a", r);
    n = m.len();
    m.release();
    return n;
}
LIB
if ! ( cd "$root" && "$ctast" build --lib "$tmp/liblib/root.h.ct" --outdir "$tmp/libout" ) >"$tmp/lib.out" 2>"$tmp/lib.err"; then
    fail_msg "cross-unit --lib build failed:"; sed 's/^/  /' "$tmp/lib.err" >&2
else
    if [ ! -f "$tmp/libout/root.abi.h" ]; then
        fail_msg "--lib emitted no ABI header"
    elif grep -q 'MapEntry_' "$tmp/libout/root.abi.h"; then
        fail_msg "the ABI header exports the entry struct"
    fi
    defs=$(grep -hEc '^struct MapEntry_char_p_JsonRef[ ]*\{' "$tmp/libout"/*.c | awk '{s+=$1} END {print s+0}')
    if [ "$defs" -ne 1 ]; then
        fail_msg "--lib: expected one MapEntry body in the products, found $defs"
    fi
    if command -v nm >/dev/null 2>&1 && [ -f "$tmp/libout/libroot.a" ] \
       && nm -g --defined-only "$tmp/libout/libroot.a" 2>/dev/null | grep -q 'MapEntry'; then
        fail_msg "the archive exports a MapEntry symbol"
    fi
fi

echo "p46/map-user-struct: $fail failure(s)"
[ "$fail" -eq 0 ]
