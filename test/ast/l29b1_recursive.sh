#!/usr/bin/env bash
# LANG-29 S1 / B1 probe: the ADT layout closure.
#
# An ADT payload is laid out by value, so a concrete generic instance it names
# (`Vec<N>`, `Map<String, N>`) must be a complete type when the union is
# written. The emitter pre-emits exactly those instance shells before the ADT,
# in dependency order, and leaves the instance bodies and `MapEntry_*` after
# it. A by-value cycle (self or mutual reference) and a nesting deeper than the
# limit are refused instead of leaving invalid C.
#
# Usage: bash test/ast/l29b1_recursive.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: l29b1_recursive.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/l29b1.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL l29b1: $1" >&2; }
dump() { sed 's/^/    /' "$tmp/o" >&2; }
has() { grep -qF -- "$2" "$1"; }
no()  { ! grep -qF -- "$2" "$1"; }
line_of() { grep -nF -- "$2" "$1" | head -1 | cut -d: -f1; }

# ---- the positive fixture: shells before the ADT, bodies after it -----------
src="$root/test/ast/299_adt_recursive/prog.ct"
if ! "$CT" "$src" -o "$tmp/rec.c" >"$tmp/o" 2>&1; then
    bad "the recursive ADT did not compile"
    dump
else
    ok
fi

if [ -f "$tmp/rec.c" ]; then
    c="$tmp/rec.c"
    vline=$(line_of "$c" "struct Vec_N {")
    mline=$(line_of "$c" "struct Map_String_N {")
    nline=$(line_of "$c" "struct N {")
    eline=$(line_of "$c" "struct MapEntry_String_N {")
    if [ -n "$vline" ] && [ -n "$mline" ] && [ -n "$nline" ] \
       && [ "$vline" -lt "$nline" ] && [ "$mline" -lt "$nline" ]; then
        ok
    else
        bad "an instance shell is not written before the ADT layout"
    fi
    if [ -n "$eline" ] && [ -n "$nline" ] && [ "$eline" -gt "$nline" ]; then
        ok
    else
        bad "the MapEntry payload row moved before the ADT (it names N by value)"
    fi
    if [ "$(grep -c '^struct Vec_N {' "$c")" -eq 1 ] \
       && [ "$(grep -c '^struct Map_String_N {' "$c")" -eq 1 ] \
       && [ "$(grep -c '^struct N {' "$c")" -eq 1 ]; then
        ok
    else
        bad "an instance layout is defined more than once"
    fi
    if has "$c" "struct Vec_N {" && has "$c" "struct N {" \
       && has "$c" "struct Vec_N;" && has "$c" "struct ct_buf * h;"; then
        ok
    else
        bad "a pre-emitted shell is not the handle layout"
    fi
    # the ADT itself still carries its four ABI assertions
    if [ "$(grep -c '^_Static_assert(' "$c")" -eq 4 ] && has "$c" "int tag;"; then
        ok
    else
        bad "the ADT layout lost its ABI assertions"
    fi
    # the instance bodies stay where they were: after the ADT and its hooks
    if has "$c" "Vec_N_len(void *self)" && has "$c" "Map_String_N_put(void *self"; then
        ok
    else
        bad "the instance bodies did not stay after the ADT"
    fi
    if "$CC" -Wall -Wextra -std=c99 "$c" -o "$tmp/rec.bin" >"$tmp/o" 2>&1; then
        ok
    else
        bad "the generated C warns or fails under -Wall -Wextra"
        dump
    fi
    if [ -x "$tmp/rec.bin" ] && "$tmp/rec.bin" >"$tmp/rec.out" 2>&1 \
       && cmp -s "$tmp/rec.out" "$root/test/ast/299_adt_recursive/prog.expected.out"; then
        ok
    else
        bad "the recursive ADT output differs: $(cat "$tmp/rec.out" 2>/dev/null)"
    fi
fi

# ---- a non-recursive ADT with an instance payload keeps working -------------
cat >"$tmp/plain.ct" <<'CT'
#include <stdio.h>

enum Bag {
    Empty(),
    Items(Vec<int> v),
}

int main(void)
{
    Vec<int> v;
    Bag b;
    v.h = 0;
    v.push(7);
    b = Bag.Items(v);
    match (b) {
        Bag.Items(x) => { printf("%d\n", x.len()); }
        _ => { printf("empty\n"); }
    }
    return 0;
}
CT
if ! "$CT" "$tmp/plain.ct" -o "$tmp/plain.c" >"$tmp/o" 2>&1; then
    bad "a non-recursive ADT with a Vec payload did not compile"
    dump
elif ! "$CC" -Wall -Wextra -std=c99 "$tmp/plain.c" -o "$tmp/plain.bin" >"$tmp/o" 2>&1 \
     || ! "$tmp/plain.bin" >"$tmp/plain.out" 2>&1 \
     || [ "$(cat "$tmp/plain.out")" != "1" ]; then
    bad "a non-recursive ADT with a Vec payload did not build and run"
    dump
else
    ok
fi

# ---- negative: a by-value self reference ------------------------------------
cat >"$tmp/self.ct" <<'CT'
enum N {
    Nil(),
    Cons(N next),
}

int main(void)
{
    N n = N.Nil();
    return n.tag;
}
CT
if "$CT" "$tmp/self.ct" -o "$tmp/self.c" >"$tmp/o" 2>&1; then
    bad "a by-value self reference was accepted"
elif ! grep -qF "recursive by value" "$tmp/o"; then
    bad "the self reference diagnostic is missing"
    dump
else
    ok
fi

# ---- negative: a by-value mutual reference ----------------------------------
cat >"$tmp/mutual.ct" <<'CT'
enum A {
    A0(),
    Mk(B b),
}

enum B {
    B0(),
    MkA(A a),
}

int main(void)
{
    A a = A.A0();
    return a.tag;
}
CT
if "$CT" "$tmp/mutual.ct" -o "$tmp/mutual.c" >"$tmp/o" 2>&1; then
    bad "a by-value mutual reference was accepted"
elif ! grep -qF "recursive by value" "$tmp/o"; then
    bad "the mutual reference diagnostic is missing"
    dump
else
    ok
fi

# ---- negative: a payload chain past the depth limit -------------------------
{
    i=0
    while [ "$i" -le 33 ]; do
        if [ "$i" -eq 33 ]; then
            printf 'enum A%s { End%s() }\n' "$i" "$i"
        else
            printf 'enum A%s { E%s(), V%s(A%s next) }\n' "$i" "$i" "$i" "$((i + 1))"
        fi
        i=$((i + 1))
    done
    printf '\nint main(void)\n{\n    A0 a = A0.E0();\n    return a.tag;\n}\n'
} >"$tmp/deep.ct"
if "$CT" "$tmp/deep.ct" -o "$tmp/deep.c" >"$tmp/o" 2>&1; then
    bad "a payload chain past the depth limit was accepted"
elif ! grep -qF "nests deeper than" "$tmp/o"; then
    bad "the depth-limit diagnostic is missing"
    dump
else
    ok
fi

echo "l29b1: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK l29b1"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
