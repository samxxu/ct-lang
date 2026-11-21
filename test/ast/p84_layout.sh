#!/usr/bin/env bash
# PH-84 S84c probe: the ADT layout, the emitted construction / match, and the
# public-header ABI.
#
# The frozen layout is `struct T { int tag; union { ... } u; }`: the tag comes
# first, the payload union follows it, and C's own rules give both the largest
# member alignment. The tag is written numerically by the constructor and read
# by the match, so no helper function, no allocation and no vtable is involved.
# A `pub` ADT in a `.h.ct` unit publishes that layout plus its `_Static_assert`s.
#
# Usage: bash test/ast/p84_layout.sh <ct-ast>
#   E84-4 (bindings are by value; no fallthrough; break keeps the loop's meaning)
#   E84-5 (tag+union layout is deterministic; the pub ABI header carries it)
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: p84_layout.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p84lay.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p84layout: $1" >&2; }
dump() { sed 's/^/    /' "$tmp/o" >&2; }
has() { grep -qF -- "$2" "$1"; }
no()  { ! grep -qF -- "$2" "$1"; }

# ---- one program with every construct the phase emits ----------------------
cat >"$tmp/adt.ct" <<'CT'
#include <stdio.h>

enum Shape {
    Circle(int r),
    Rect(int w, int h),
    Empty(),
}

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { r = r + 100; return r; }
        Shape.Rect(w, h) => { return w * h; }
        Shape.Empty() => { return -1; }
    }
}

int peek(Shape *p)
{
    match (p) {
        Shape.Circle(r) => { return r; }
        _ => { return 0; }
    }
}

int falls(Shape s)
{
    int n = 0;
    match (s) {
        Shape.Circle(r) => { n = n + r; }
        Shape.Rect(w, h) => { n = n + w; }
        Shape.Empty() => { n = n + 9; }
    }
    return n;
}

int loopbreak(void)
{
    int total = 0;
    int i;
    for (i = 0; i < 5; i++) {
        Shape s = Shape.Circle(i);
        match (s) {
            Shape.Circle(r) => { if (r == 3) { break; } total = total + r; }
            _ => { total = total + 100; }
        }
    }
    return total;
}

int main(void)
{
    Shape c = Shape.Circle(2);
    Shape r = Shape.Rect(3, 4);
    Shape e = Shape.Empty();
    printf("%d %d %d\n", area(c), area(r), area(e));
    printf("%d %d\n", peek(&c), area(c));
    printf("%d %d\n", falls(c), loopbreak());
    return 0;
}
CT

if ! "$CT" "$tmp/adt.ct" -o "$tmp/adt.c" >"$tmp/o" 2>&1; then
    bad "the ADT program did not compile"
    dump
else
    ok
fi

if [ -f "$tmp/adt.c" ]; then
    c="$tmp/adt.c"
    # tag first, payload union second
    if has "$c" "struct Shape {" && has "$c" "int tag;" \
       && has "$c" "union {" && has "$c" "} u;"; then
        ok
    else
        bad "the ADT layout is not tag + union"
        sed -n '1,30p' "$c" | sed 's/^/    /' >&2
    fi
    tagline=$(grep -n 'int tag;' "$c" | head -1 | cut -d: -f1)
    uline=$(grep -n '^    union {' "$c" | head -1 | cut -d: -f1)
    endline=$(grep -n '^    } u;' "$c" | head -1 | cut -d: -f1)
    if [ -n "$tagline" ] && [ -n "$uline" ] && [ -n "$endline" ] \
       && [ "$tagline" -lt "$uline" ] && [ "$uline" -lt "$endline" ]; then
        ok
    else
        bad "the tag is not strictly before the payload union"
    fi
    # one tag field, one union member per payload variant
    if [ "$(grep -c '^    int tag;' "$c")" -eq 1 ] \
       && has "$c" "} Circle;" && has "$c" "} Rect;"; then
        ok
    else
        bad "the layout does not carry one tag and one member per payload variant"
    fi
    # ABI assertions: tag at offset 0 plus the union relationship
    if has "$c" '_Static_assert(offsetof(struct Shape, tag) == 0' \
       && [ "$(grep -c '^_Static_assert(' "$c")" -eq 4 ]; then
        ok
    else
        bad "the layout does not publish its four _Static_asserts"
        grep '_Static_assert' "$c" | sed 's/^/    /' >&2
    fi
    # construction is a compound literal: no helper function, no vtable
    if has "$c" '((struct Shape){ .tag = 0, .u = { .Circle = { .r = ('; then
        ok
    else
        bad "the constructor is not the frozen compound literal"
    fi
    if has "$c" '((struct Shape){ .tag = 2 })'; then
        ok
    else
        bad "a zero-field variant is not a tag-only literal"
    fi
    if no "$c" "vtable" && no "$c" "vptr"; then
        ok
    else
        bad "an ADT product mentions a vtable / vptr"
    fi
    # no fallthrough: the arms are an if / else-if / else chain
    if has "$c" "__ct_match0" && has "$c" "__ct_match0.tag == 0" \
       && has "$c" "else " && no "$c" "switch ("; then
        ok
    else
        bad "the match is not emitted as an if / else chain"
    fi
    # a pointer subject reads through `->`, a value subject through `.`
    if has "$c" "->tag == 0" && has "$c" "->u.Circle.r"; then
        ok
    else
        bad "a pointer subject is not read through '->'"
    fi
    # the generated product stays warning-free
    if "$CC" -Wall -Wextra -std=c99 -c "$c" -o "$tmp/adt.o" >"$tmp/o" 2>&1; then
        ok
    else
        bad "the generated C warns or fails under -Wall -Wextra"
        dump
    fi
    if "$CC" -Wall -Wextra -std=c99 "$c" -o "$tmp/adt.bin" >"$tmp/o" 2>&1; then
        ok
    else
        bad "the generated C did not link"
        dump
    fi
    # E84-4: copy bindings, no fallthrough, break keeps the loop's meaning
    printf '102 12 -1\n2 102\n2 3\n' >"$tmp/adt.expected"
    if "$tmp/adt.bin" >"$tmp/adt.out" 2>&1 \
       && cmp -s "$tmp/adt.out" "$tmp/adt.expected"; then
        ok
    else
        bad "the ADT program output differs: $(cat "$tmp/adt.out" 2>/dev/null)"
    fi
fi

# ---- a typedef'd ADT keeps the alias in its C form --------------------------
cat >"$tmp/td.ct" <<'CT'
#include <stdio.h>

typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int area(Alias a)
{
    switch (a.tag) {
    case 0:
        return a.u.Circle.r;
    default:
        return a.u.Rect.w * a.u.Rect.h;
    }
}

int main(void)
{
    Alias c = Shape.Circle(2);
    Alias r = Shape.Rect(3, 4);
    printf("%d %d\n", area(c), area(r));
    return 0;
}
CT
if ! "$CT" "$tmp/td.ct" -o "$tmp/td.c" >"$tmp/o" 2>&1; then
    bad "the typedef'd ADT did not compile"
    dump
elif ! grep -qE '^typedef struct Shape \{' "$tmp/td.c"; then
    bad "the typedef'd ADT is not emitted as 'typedef struct'"
elif ! "$CC" -Wall -Wextra -std=c99 "$tmp/td.c" -o "$tmp/td.bin" >"$tmp/o" 2>&1 \
     || ! "$tmp/td.bin" >"$tmp/td.out" 2>&1 \
     || [ "$(cat "$tmp/td.out")" != "2 12" ]; then
    bad "the typedef'd ADT product does not build and run: $(cat "$tmp/td.out" 2>/dev/null)"
    dump
else
    ok
fi

# ---- a `pub` ADT publishes the layout through its header (E84-5) -----------
mkdir -p "$tmp/x/lib" "$tmp/x/out"
cat >"$tmp/x/lib/lib.h.ct" <<'CT'
namespace lib;

pub enum Shape {
    Circle(int r),
    Rect(int w, int h),
}
CT
cat >"$tmp/x/prog.ct" <<'CT'
#include <stdio.h>

import lib::lib;

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}

int main(void)
{
    printf("%d %d\n", area(Shape.Circle(2)), area(Shape.Rect(3, 4)));
    return 0;
}
CT
if ! ( cd "$tmp/x" && "$CT" build --emit-c prog.ct -o out ) >"$tmp/o" 2>&1; then
    bad "the cross-unit ADT build failed"
    dump
elif [ ! -f "$tmp/x/out/lib.h" ] || [ ! -f "$tmp/x/out/prog.c" ]; then
    bad "the cross-unit ADT build did not publish both products"
else
    ok
    h="$tmp/x/out/lib.h"
    if has "$h" "struct lib_Shape {" && has "$h" "_Static_assert(offsetof(struct lib_Shape, tag) == 0" \
       && has "$h" "} u;" && no "$h" "vtable" \
       && no "$tmp/x/out/lib.c" "struct lib_Shape {"; then
        ok
    else
        bad "the pub ADT layout is not in the header (and only there)"
    fi
    t=$(grep -n 'int tag;' "$h" | head -1 | cut -d: -f1)
    u=$(grep -n '^    union {' "$h" | head -1 | cut -d: -f1)
    if [ -n "$t" ] && [ -n "$u" ] && [ "$t" -lt "$u" ]; then
        ok
    else
        bad "the header layout does not put the tag first"
    fi
    if ( cd "$tmp/x" && "$CC" -Wall -Wextra -std=c99 out/*.c -o out.bin ) >"$tmp/o" 2>&1 \
       && "$tmp/x/out.bin" >"$tmp/x/out.txt" 2>&1 \
       && [ "$(cat "$tmp/x/out.txt")" = "12 12" ]; then
        ok
    else
        bad "the cross-unit ADT product did not build and run: $(cat "$tmp/o" 2>/dev/null)"
    fi
    if has "$tmp/x/out/prog.c" "__ct_match0.tag == 0"; then
        ok
    else
        bad "the consumer did not emit the match chain"
    fi
fi

# ---- F1: the typedef alias also matches and runs ---------------------------
cat >"$tmp/alias.ct" <<'CT'
#include <stdio.h>

typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int area(Alias a)
{
    match (a) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}

int main(void)
{
    Alias c = Shape.Circle(2);
    Alias r = Shape.Rect(3, 4);
    printf("%d %d\n", area(c), area(r));
    return 0;
}
CT
if ! "$CT" "$tmp/alias.ct" -o "$tmp/alias.c" >"$tmp/o" 2>&1; then
    bad "the typedef-alias match did not compile"
    dump
elif ! "$CC" -Wall -Wextra -std=c99 "$tmp/alias.c" -o "$tmp/alias.bin" >"$tmp/o" 2>&1 \
     || ! "$tmp/alias.bin" >"$tmp/alias.out" 2>&1 \
     || [ "$(cat "$tmp/alias.out")" != "12 12" ]; then
    bad "the typedef-alias match did not run: $(cat "$tmp/alias.out" 2>/dev/null)"
    dump
else
    ok
fi

# ---- F2: `pub typedef` across units, tag and alias both usable ------------
mkdir -p "$tmp/xt/lib" "$tmp/xt/out"
cat >"$tmp/xt/lib/lib.h.ct" <<'CT'
namespace lib;

pub typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;
CT
cat >"$tmp/xt/prog.ct" <<'CT'
#include <stdio.h>

import lib::lib;

int by_tag(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}

int by_alias(Alias a)
{
    match (a) {
        Shape.Circle(r) => { return r; }
        Shape.Rect(w, h) => { return w + h; }
    }
}

int main(void)
{
    Shape c = Shape.Circle(2);
    Alias r = Shape.Rect(3, 4);
    printf("%d %d %d\n", by_tag(c), by_alias(c), by_alias(r));
    return 0;
}
CT
if ! ( cd "$tmp/xt" && "$CT" build --emit-c prog.ct -o out ) >"$tmp/o" 2>&1; then
    bad "the pub-typedef cross-unit build failed"
    dump
elif [ ! -f "$tmp/xt/out/lib.h" ] || [ ! -f "$tmp/xt/out/prog.c" ]; then
    bad "the pub-typedef build did not publish both products"
else
    ok
    if has "$tmp/xt/out/lib.h" "typedef struct lib_Shape {" \
       && has "$tmp/xt/out/lib.h" "} lib_Alias;" \
       && has "$tmp/xt/out/prog.c" "struct lib_Shape"; then
        ok
    else
        bad "the pub-typedef header/consumer spelling is wrong"
    fi
    if no "$tmp/xt/out/prog.c" "Shape"; then
        ok
    elif grep -qE '(^|[^_A-Za-z0-9])Shape([^_A-Za-z0-9]|$)' "$tmp/xt/out/prog.c"; then
        bad "the consumer product still spells the undeclared tag 'Shape'"
        grep -nE '(^|[^_A-Za-z0-9])Shape([^_A-Za-z0-9]|$)' "$tmp/xt/out/prog.c" | head -3 | sed 's/^/    /' >&2
    else
        ok
    fi
    if ( cd "$tmp/xt" && "$CC" -Wall -Wextra -std=c99 out/*.c -o out.bin ) >"$tmp/o" 2>&1 \
       && "$tmp/xt/out.bin" >"$tmp/xt/out.txt" 2>&1 \
       && [ "$(cat "$tmp/xt/out.txt")" = "12 2 7" ]; then
        ok
    else
        bad "the pub-typedef product did not build and run: $(cat "$tmp/o" 2>/dev/null)"
        head -4 "$tmp/xt/out.txt" 2>/dev/null | sed 's/^/    /' >&2
    fi
fi

# ---- the C enum / switch products do not move ------------------------------
if ! "$CT" "$root/test/ast/30_enum/prog.ct" -o "$tmp/enum.c" >"$tmp/o" 2>&1; then
    bad "the existing enum fixture no longer compiles"
    dump
elif has "$tmp/enum.c" "enum Color {" && no "$tmp/enum.c" "vtable"; then
    ok
else
    bad "a plain enum is no longer emitted as a C enum"
fi

if ! "$CT" "$root/examples/c-superset/s01_switch/dispatch.ct" -o "$tmp/switch.c" >"$tmp/o" 2>&1; then
    bad "the existing switch example no longer compiles"
    dump
elif has "$tmp/switch.c" "switch (verb)" && has "$tmp/switch.c" "case VERB_ADD:" \
     && has "$tmp/switch.c" "default:"; then
    ok
else
    bad "the switch product changed shape"
fi

echo "p84layout: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK p84layout"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
