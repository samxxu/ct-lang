#!/bin/sh
# PH-48 probe: Drop semantics for pointer fields and across units
# (E48-1 / E48-2 / E48-5 / E48-6).
#
# E48-1: an automatic glue body passes a pointer field's child object, once:
#        `if (_self->leaf) Leaf_Drop_drop(_self->leaf);`.
# E48-2: a `pub struct ... use Drop` exports its body from the unit that
#        declares it; the owner's header carries the non-static prototype and
#        the consumer only declares `extern`.
# E48-5: an impl written outside the struct's header is L48-2: rc=1, the
#        positioned message, and no `.c` at all.
# E48-6: pointer glue has no `&_self->`, and value-field glue is unchanged.
set -u
# PH-65: the fixtures write free `#include`s; this probe is not about the C
# boundary. SH-93 removed the cwd shortcut, so opt into allow explicitly.
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p48_drop.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p48-drop.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

# --- E48-1 / E48-6: pointer field glue -------------------------------------
if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
        test/ast/243_ptr_field_glue/prog.ct -o "$tmp/ptr.c" ) \
        >"$tmp/ptr.out" 2>"$tmp/ptr.err"; then
    fail_msg "the pointer-field fixture did not compile:"; sed 's/^/  /' "$tmp/ptr.err" >&2
elif ! "$cc" -Wall -Wextra -std=c99 "$tmp/ptr.c" -o "$tmp/ptr.bin" 2>"$tmp/ptr.cc"; then
    fail_msg "the pointer-field product did not build:"; sed 's/^/  /' "$tmp/ptr.cc" >&2
elif ! "$tmp/ptr.bin" >"$tmp/ptr.txt" 2>&1; then
    fail_msg "the pointer-field product exited non-zero"
elif ! cmp -s "$root/test/ast/243_ptr_field_glue/prog.expected.out" "$tmp/ptr.txt"; then
    fail_msg "pointer-field output drifted: $(cat "$tmp/ptr.txt")"
elif ! grep -Fq 'if (_self->leaf) Leaf_Drop_drop(_self->leaf);' "$tmp/ptr.c"; then
    fail_msg "the pointer field glue is not the null-checked child call"
elif grep -Fq '&_self->leaf' "$tmp/ptr.c"; then
    fail_msg "the pointer field glue still takes the field's address"
elif grep -q '&_self->' "$tmp/ptr.c"; then
    fail_msg "a generated glue body still contains '&_self->': $(grep -n '&_self->' "$tmp/ptr.c" | head -2)"
else
    ok_msg "E48-1/E48-6 pointer glue (null check, child object, no '&_self->')"
fi

# A value field keeps the old `&_self->field` shape.
cat >"$tmp/value.ct" <<'VALUE'
#include <stdio.h>
#include <stdlib.h>

struct Inner {
    int id;
} use Drop;

impl Drop for Inner {
    void drop() { printf("inner drop %d\n", self->id); }
}

struct Outer {
    Inner inner;
} use Drop;

int main(void)
{
    own Outer *o = malloc(sizeof(struct Outer));
    o->inner.id = 9;
    delete o;
    return 0;
}
VALUE
if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$tmp/value.ct" -o "$tmp/value.c" ) \
        >"$tmp/value.out" 2>"$tmp/value.err"; then
    fail_msg "the value-field fixture did not compile:"; sed 's/^/  /' "$tmp/value.err" >&2
elif ! grep -Fq 'Inner_Drop_drop(&_self->inner);' "$tmp/value.c"; then
    fail_msg "value-field glue changed shape"
elif ! "$cc" -std=c99 "$tmp/value.c" -o "$tmp/value.bin" 2>"$tmp/value.cc" \
      || ! "$tmp/value.bin" >"$tmp/value.txt" 2>&1; then
    fail_msg "the value-field product did not run"
elif ! grep -qx 'inner drop 9' "$tmp/value.txt"; then
    fail_msg "value-field drop output drifted: $(cat "$tmp/value.txt")"
else
    ok_msg "E48-6 value-field glue unchanged"
fi

# --- E48-2: cross-unit Drop body -------------------------------------------
mkdir -p "$tmp/out"
if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" build --emit-c \
        test/ast/244_cross_unit_drop/prog.ct -o "$tmp/out" ) \
        >"$tmp/x.out" 2>"$tmp/x.err"; then
    fail_msg "the cross-unit fixture did not build:"; sed 's/^/  /' "$tmp/x.err" >&2
elif ! "$cc" -Wall -Wextra -std=c99 -I "$tmp/out" "$tmp/out"/*.c \
        -o "$tmp/x.bin" 2>"$tmp/x.cc"; then
    fail_msg "the cross-unit products did not build:"; sed 's/^/  /' "$tmp/x.cc" >&2
elif ! "$tmp/x.bin" >"$tmp/x.txt" 2>&1; then
    fail_msg "the cross-unit product exited non-zero"
elif ! cmp -s "$root/test/ast/244_cross_unit_drop/prog.expected.out" "$tmp/x.txt"; then
    fail_msg "cross-unit Drop output drifted: $(cat "$tmp/x.txt")"
elif ! grep -Fq 'void lib_Res_Drop_drop(void *);' "$tmp/out/res.h"; then
    fail_msg "the owner header does not publish the Drop prototype"
elif ! grep -Fq 'void lib_Res_Drop_drop(void *self);' "$tmp/out/res.c"; then
    fail_msg "the owner .c does not declare the exported Drop body"
elif grep -Fq 'static void __attribute__((unused)) lib_Res_Drop_drop' "$tmp/out/res.c"; then
    fail_msg "the owner Drop body is still static"
elif ! grep -Fq 'void lib_Res_Drop_drop(void *self) {' "$tmp/out/res.c"; then
    fail_msg "the owner Drop body is not a non-static definition"
elif ! grep -Fq 'extern void lib_Res_Drop_drop(void *self);' "$tmp/out/prog.c"; then
    fail_msg "the consumer does not declare the body extern"
else
    ok_msg "E48-2 cross-unit Drop body (header prototype, extern consumer)"
fi

# --- E48-5: impl outside the struct's header is L48-2 ----------------------
mkdir -p "$tmp/negout"
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" build --emit-c \
        test/ast/p48_errors/main.ct -o "$tmp/negout" ) \
        >"$tmp/neg.out" 2>"$tmp/neg.err"; then
    fail_msg "L48-2: the invisible impl compiled"
elif ! grep -Fq "Drop body for 'struct Res' is not visible through its header" "$tmp/neg.err"; then
    fail_msg "L48-2: $(cat "$tmp/neg.err")"
elif ! grep -Fq "test/ast/p48_errors/lib/res.h.ct:5:1: error:" "$tmp/neg.err"; then
    fail_msg "L48-2: the diagnostic is not positioned at the struct: $(cat "$tmp/neg.err")"
elif [ -n "$(find "$tmp/negout" -name '*.c' -print -quit)" ]; then
    fail_msg "L48-2: a rejected build still wrote a .c"
else
    ok_msg "E48-5 L48-2 (rc=1, positioned message, no .c)"
fi

echo "p48/drop: $fail failure(s)"
[ "$fail" -eq 0 ]
