#!/bin/sh
# v1-PH-2 S1a-0 C2n-0 spike: the string-interning pool and the TypeAlias move.
#
# The spike adds `runtime::text::Intern` and migrates `TypeAlias.name` /
# `.target` from `char[160]` to `const char *` owned by that pool. This probe is
# the slice's own gate:
#
#   S1/S2  build a tiny Ct program that imports `runtime::text::Intern`, then
#          link the generated `Intern.c` with a C harness and assert: dedup by
#          content, a real per-entry malloc copy, pointer stability across every
#          table grow (4096 rows), length semantics (embedded NUL, prefix, zero),
#          NULL / negative-length refusal, 65536 bytes accepted, 65537 refused
#          without truncation, `ct_internf`'s measuring pass (a 200-byte text
#          kept whole, 65536 accepted, 65537 refused), and a reset that leaves
#          the pool usable.
#   S3     2000 distinct `pub type` aliases compile in one `.h.ct` unit; the
#          last aliases resolve to the right width and the generated C builds
#          and runs.
#   S4     a three-deep alias chain still expands, the pinned alias-cycle
#          diagnostic is byte-identical, and an imported `pub type` still
#          resolves through the module layer (the add-visible path).
#   S5     a 223-byte C name (namespace prefix + source name) is kept whole in
#          every place it is emitted -- declaration prototype, function
#          definition and call site -- which C2n-2 makes a `Node.text` row.
#          C2n-1 only kept the prototype (the definition and the call were cut
#          at 160 bytes and the old test's `grep` could not see it).
#   S6     string literals of 200 and 1000 bytes (adjacent literal
#          concatenation, the lexer's per-token cap) still round-trip through
#          the literal pool and print byte-for-byte.
#
# Usage: bash test/ast/intern_pool.sh <ct-ast> [cc]
# Exit code 0 means every assertion passed.
set -u
ct=${1:?usage: intern_pool.sh <ct-ast> [cc]}
cc=${2:-${CC:-cc}}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/internpool.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM

cflags="-Wall -Wextra -std=c99"
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL intern_pool: $1" >&2; }

# --- S1/S2: the pool unit ---------------------------------------------------
mkdir -p "$w/gen"
cat >"$w/user.ct" <<'CT'
import runtime::text::Intern;

int main(void)
{
    const char *p = runtime::text::ct_intern("probe");
    return p && runtime::text::ct_intern_len("probe", 5) == p ? 0 : 1;
}
CT
if ! "$ct" build --emit-c -I selfhost/ct-ast "$w/user.ct" -o "$w/gen" \
        >"$w/gen.out" 2>"$w/gen.err"; then
    bad "ct-ast could not build the Intern probe: $(head -3 "$w/gen.err" | tr '\n' ' ')"
elif [ ! -f "$w/gen/Intern.c" ] || [ ! -f "$w/gen/Intern.h" ]; then
    bad "the build did not emit Intern.c + Intern.h"
elif ! grep -q 'runtime_text_ct_intern' "$w/gen/Intern.h"; then
    bad "the generated Intern.h carries no ct_intern prototype"
else
    ok
fi

cat >"$w/harness.c" <<'C'
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "Intern.h"

#define LIMIT 65536
#define MANY 4096

static int failed;

static void check(int cond, const char *what, int line)
{
    if (cond) return;
    fprintf(stderr, "FAIL line %d: %s\n", line, what);
    failed++;
}

#define CHECK(cond) check((cond), #cond, __LINE__)

int main(void)
{
    const char *a, *b, *c, *p, *q;
    char buf[64];
    char *big;
    char **ptrs;
    int i;

    /* S1: dedup, distinctness, and a real copy (not an alias of the caller). */
    a = runtime_text_ct_intern("alpha");
    b = runtime_text_ct_intern("alpha");
    c = runtime_text_ct_intern("beta");
    CHECK(a != NULL && b != NULL && c != NULL);
    CHECK(a == b);
    CHECK(a != c);
    CHECK(strcmp(a, "alpha") == 0 && strcmp(c, "beta") == 0);
    strcpy(buf, "copied");
    p = runtime_text_ct_intern(buf);
    buf[0] = 'X';
    CHECK(p != NULL && strcmp(p, "copied") == 0);
    CHECK(runtime_text_ct_intern(NULL) == NULL);

    /* S2: length semantics -- prefix of a C string, embedded NUL, zero, invalid. */
    CHECK(runtime_text_ct_intern_len("alpha", 5) == a);
    CHECK(runtime_text_ct_intern_len("alphabet", 5) == a);
    p = runtime_text_ct_intern_len("abc\0def", 7);
    q = runtime_text_ct_intern_len("abc\0def", 7);
    CHECK(p != NULL && p == q);
    CHECK(strcmp(p, "abc") == 0);
    CHECK(runtime_text_ct_intern_len("abc\0eef", 7) != p);
    CHECK(runtime_text_ct_intern_len("abc", -1) == NULL);
    CHECK(runtime_text_ct_intern_len(NULL, 3) == NULL);
    p = runtime_text_ct_intern_len("ignored", 0);
    q = runtime_text_ct_intern("");
    CHECK(p != NULL && p == q && p[0] == 0);

    /* S1: pointer stability across every grow the table needs (4096 rows force
       the slot cap 64 -> 8192 at the 0.7 load factor). */
    ptrs = (char **)calloc(MANY, sizeof(*ptrs));
    CHECK(ptrs != NULL);
    if (ptrs) {
        for (i = 0; i < MANY; i++) {
            snprintf(buf, sizeof buf, "name-%d", i);
            ptrs[i] = (char *)runtime_text_ct_intern(buf);
            CHECK(ptrs[i] != NULL);
        }
        CHECK(ptrs[0] != NULL && strcmp(ptrs[0], "name-0") == 0);
        CHECK(ptrs[MANY - 1] != NULL && strcmp(ptrs[MANY - 1], "name-4095") == 0);
        for (i = MANY - 1; i >= 0; i--) {
            snprintf(buf, sizeof buf, "name-%d", i);
            p = runtime_text_ct_intern(buf);
            CHECK(p == ptrs[i]);
            if (p != ptrs[i]) break;
        }
        free(ptrs);
    }

    /* S2: the formal text bound. 65537 bytes is refused, not cut; 65536 is
       kept whole and dedups exactly. The 'b' variant proves the stored bytes
       are the caller's whole text, not a truncated prefix. */
    big = (char *)malloc(LIMIT + 3);
    CHECK(big != NULL);
    if (big) {
        memset(big, 'a', (size_t)LIMIT + 1);
        big[LIMIT + 1] = 0;
        CHECK(runtime_text_ct_intern(big) == NULL);
        CHECK(runtime_text_ct_intern_len(big, LIMIT + 1) == NULL);
        big[LIMIT] = 0;
        p = runtime_text_ct_intern(big);
        CHECK(p != NULL && strlen(p) == (size_t)LIMIT);
        CHECK(runtime_text_ct_intern_len(big, LIMIT) == p);
        big[LIMIT - 1] = 'b';
        q = runtime_text_ct_intern(big);
        CHECK(q != NULL && q != p);
        CHECK(q != NULL && q[LIMIT - 1] == 'b');
        free(big);
    }

    /* S2: `ct_internf` measures first, so a 200-byte text is kept whole (the
       old `Node.text` row held 159) and dedups by content. */
    {
        char m[201];
        memset(m, 'm', 200);
        m[200] = 0;
        p = runtime_text_ct_internf("%s", m);
        CHECK(p != NULL && strlen(p) == 200);
        CHECK(p == runtime_text_ct_intern(m));
        p = runtime_text_ct_internf("%s/%d", "alpha", 3);
        CHECK(p != NULL && strcmp(p, "alpha/3") == 0);
        CHECK(p == runtime_text_ct_intern("alpha/3"));
    }
    /* S2: exactly TEXT_LIMIT is kept; one byte more is refused, not cut. The
       width form avoids a second 64 KiB source buffer. */
    p = runtime_text_ct_internf("%065536d", 1);
    CHECK(p != NULL && strlen(p) == (size_t)LIMIT);
    CHECK(runtime_text_ct_internf("%065537d", 1) == NULL);
    CHECK(runtime_text_ct_internf(0) == NULL);

    /* The pool can be reset and used again; a second reset is a no-op. */
    runtime_text_ct_intern_reset();
    a = runtime_text_ct_intern("alpha");
    b = runtime_text_ct_intern("alpha");
    CHECK(a != NULL && a == b && strcmp(a, "alpha") == 0);
    runtime_text_ct_intern_reset();
    runtime_text_ct_intern_reset();

    printf("intern: %d failed\n", failed);
    return failed ? 1 : 0;
}
C

if [ -f "$w/gen/Intern.c" ] && [ -f "$w/gen/Intern.h" ]; then
    if ! $cc $cflags -I "$w/gen" "$w/gen/Intern.c" "$w/gen/Result.c" "$w/harness.c" -o "$w/harness" \
            >"$w/harness.build" 2>&1; then
        bad "the Intern harness did not build: $(head -3 "$w/harness.build" | tr '\n' ' ')"
    elif ! "$w/harness" >"$w/harness.out" 2>"$w/harness.err"; then
        bad "pool assertions failed: $(tail -3 "$w/harness.err" | tr '\n' ' ')"
    elif ! grep -q '0 failed$' "$w/harness.out"; then
        bad "the harness did not report 0 failed: $(tail -2 "$w/harness.out" | tr '\n' ' ')"
    else
        ok
        printf '  intern pool: %s\n' "$(tail -1 "$w/harness.out")"
    fi
fi

# --- S3: 2000 aliases in one unit ------------------------------------------
# Even aliases are `int`, odd ones `long`, so the last two prove the names were
# stored and looked up individually (a collision would not paint both widths).
{
    i=0
    while [ "$i" -lt 2000 ]; do
        if [ $((i % 2)) -eq 0 ]; then
            printf 'pub type A%d = int;\n' "$i"
        else
            printf 'pub type A%d = long;\n' "$i"
        fi
        i=$((i + 1))
    done
    cat <<'CT'

int main(void)
{
    A1998 x = 7;
    A1999 y = 9;
    return (int)(x + y) - 16;
}
CT
} >"$w/aliases.h.ct"

if ! "$ct" "$w/aliases.h.ct" -o "$w/aliases.c" >"$w/aliases.out" 2>"$w/aliases.err"; then
    bad "2000 type aliases did not compile: $(head -3 "$w/aliases.err" | tr '\n' ' ')"
elif ! grep -q 'int x' "$w/aliases.c" || ! grep -q 'long y' "$w/aliases.c"; then
    bad "the 2000 aliases did not resolve to their own targets"
elif ! $cc $cflags "$w/aliases.c" -o "$w/aliases" >"$w/aliases.cc" 2>&1; then
    bad "the 2000-alias C did not build: $(head -3 "$w/aliases.cc" | tr '\n' ' ')"
elif ! "$w/aliases"; then
    bad "the 2000-alias program exited non-zero"
else
    ok
    printf '  2000 aliases: compiled, built and ran\n'
fi

# --- S4: chains, the cycle diagnostic, the imported alias path ---------------
cat >"$w/chain.h.ct" <<'CT'
pub type A = int;
pub type B = A;
pub type C = B;

int main(void)
{
    C x = 3;
    return x - 3;
}
CT
if ! "$ct" "$w/chain.h.ct" -o "$w/chain.c" >"$w/chain.out" 2>"$w/chain.err"; then
    bad "the alias chain did not compile: $(head -3 "$w/chain.err" | tr '\n' ' ')"
elif ! $cc $cflags "$w/chain.c" -o "$w/chain" >"$w/chain.cc" 2>&1 || ! "$w/chain"; then
    bad "the alias chain did not build and run"
else
    ok
fi

"$ct" test/ast/errors/type_alias_cycle.h.ct -o "$w/cycle.c" \
    >"$w/cycle.out" 2>"$w/cycle.err"
if [ $? -eq 0 ]; then
    bad "the alias-cycle negative compiled"
elif grep -qF "type alias cycle: 'B' -> 'A' -> 'B'" "$w/cycle.err"; then
    ok
else
    bad "the alias-cycle diagnostic drifted: $(head -2 "$w/cycle.err" | tr '\n' ' ')"
fi

mkdir -p "$w/x" "$w/x/gen"
cat >"$w/x/lib.h.ct" <<'CT'
pub type MyInt = int;

pub int bump(MyInt x) { return x + 1; }
CT
cat >"$w/x/main.ct" <<'CT'
import lib;

int main(void)
{
    MyInt x = 5;
    return bump(x) - 6;
}
CT
if ! "$ct" build --emit-c -I "$w/x" "$w/x/main.ct" -o "$w/x/gen" \
        >"$w/x/build.out" 2>"$w/x/build.err"; then
    bad "the imported alias build failed: $(head -3 "$w/x/build.err" | tr '\n' ' ')"
elif ! grep -q 'int bump(int)' "$w/x/gen/lib.h"; then
    bad "the imported alias did not normalise in the header"
elif ! $cc $cflags -I "$w/x/gen" "$w/x/gen/main.c" "$w/x/gen/lib.c" -o "$w/x/run" \
        >"$w/x/cc.out" 2>&1 || ! "$w/x/run"; then
    bad "the imported alias program did not build and run"
else
    ok
    printf '  imported pub type: resolved across units\n'
fi


# --- S5: a >160-byte C name (namespace prefix + source name), C2n-1 ----------
# The row fields are pool pointers now, so `ns + name` is built by
# `ct_intern_join` instead of a 160-byte scratch buffer. 25 short namespace
# segments (123 bytes, so the namespace itself stays inside its own cap) plus a
# 100-byte function/global name gives a 223-byte C name: b380eb57 rejects it
# with `name is too long`, the migrated table keeps it whole.
longroot="$w/longns"
longrel="n00/n01/n02/n03/n04/n05/n06/n07/n08/n09/n10/n11/n12/n13/n14/n15/n16/n17/n18/n19/n20/n21/n22/n23/n24"
longns="n00::n01::n02::n03::n04::n05::n06::n07::n08::n09::n10::n11::n12::n13::n14::n15::n16::n17::n18::n19::n20::n21::n22::n23::n24"
longfn="f$(printf 'x%.0s' $(seq 1 99))"
longgv="g$(printf 'y%.0s' $(seq 1 99))"
mkdir -p "$longroot/$longrel" "$w/longgen"
cat >"$longroot/$longrel/long.ct" <<CT
namespace $longns;

pub int $longfn(void) { return 7; }
pub int $longgv = 5;

int main(void)
{
    /* C2n-2: the call's C name is a Node.text2 row now. Before the slice the
       row was 160 bytes, so the definition and the call were cut while the
       prototype stayed whole -- the emitted C still linked (definition and call
       shared the cut name) but no longer named the declared symbol. The count
       check below pins the full name in all three positions. */
    return ($longfn() == 7) ? 0 : 1;
}
CT
if ! "$ct" build --emit-c --ns-root "$longroot" -I "$root/selfhost/ct-ast" \
        "$longroot/$longrel/long.ct" -o "$w/longgen" \
        >"$w/long.out" 2>"$w/long.err"; then
    bad "the 223-byte namespaced name did not compile: $(head -3 "$w/long.err" | tr '\n' ' ')"
elif [ "$(grep -o "$longfn" "$w/longgen/long.c" | wc -l | tr -d ' ')" -lt 3 ] \
     || [ "$(grep -o "$longgv" "$w/longgen/long.c" | wc -l | tr -d ' ')" -lt 1 ]; then
    bad "the emitted C did not carry the full >160-byte names in every position (prototype/definition/call): $(grep -c "$longfn" "$w/longgen/long.c") of the function name, $(grep -c "$longgv" "$w/longgen/long.c") of the global"
elif ! $cc $cflags -I "$w/longgen" "$w/longgen/long.c" -o "$w/longgen/long" \
        >"$w/long.cc" 2>&1 || ! "$w/longgen/long"; then
    bad "the >160-byte-name program did not build and run"
else
    ok
    printf '  >160-byte names: 223-byte C name kept whole and ran\n'
fi

# --- S6: 200- and 1000-byte string literals (C2n-2) --------------------------
# A lexer token stops at MAX_TEXT-1, so a long literal is written as adjacent
# literals; they concatenate in the arena literal pool (`N_STR.num` is an
# offset, never a `Node.text` row). Both lengths must survive byte for byte.
# The fixture returns a status (no stdio) so the probe runs with the strict C
# boundary on: 1 = wrong length, 2 = wrong edge byte.
mkruns() {
    awk -v c="$1" -v n="$2" 'BEGIN { for (i = 0; i < n; i++) printf "%s", c }'
}
{
    printf 'int main(void)\n{\n'
    printf '    const char *a200 = '
    i=0
    while [ "$i" -lt 2 ]; do printf '"%s"' "$(mkruns a 100)"; i=$((i + 1)); done
    printf ';\n'
    printf '    const char *a1000 = '
    i=0
    while [ "$i" -lt 10 ]; do printf '"%s"' "$(mkruns b 100)"; i=$((i + 1)); done
    printf ';\n'
    cat <<'CT'
    int n = 0, m = 0;
    while (a200[n]) n++;
    while (a1000[m]) m++;
    if (n != 200 || m != 1000) return 1;
    if (a200[199] != 'a' || a1000[999] != 'b') return 2;
    return 0;
}
CT
} >"$w/longlit.ct"
if ! "$ct" "$w/longlit.ct" -o "$w/longlit.c" >"$w/longlit.out" 2>"$w/longlit.err"; then
    bad "the 200/1000-byte literals did not compile: $(head -3 "$w/longlit.err" | tr '\n' ' ')"
elif ! $cc $cflags "$w/longlit.c" -o "$w/longlit" >"$w/longlit.cc" 2>&1; then
    bad "the long-literal C did not build: $(head -3 "$w/longlit.cc" | tr '\n' ' ')"
elif ! "$w/longlit"; then
    bad "the long literals did not round-trip (status $?)"
else
    ok
    printf '  long literals: 200 and 1000 bytes round-trip\n'
fi

# --- S7: C2n-3 emitter text buffers -----------------------------------------
# The emitter's `char[160]` locals held generated C names, member paths, type
# spellings and initialiser items. A source identifier stops at 159 bytes, so a
# single name fits; an *emitter-built* text does not: `recv + "." + field` for a
# nested vptr, a `String` initialiser item longer than the old row, or a
# diagnostic that names a long trait and struct. These fixtures are red on the
# 160-byte rows and must stay whole after the builder migration.

# S7a: a nested array field's vptr statement. `sub` was `recv + "." + field`
# in a 160-byte row: a 90-byte local and a 90-byte field cut the member name,
# and `cc` rejected the emitted C (`no member named 'fff…'`). The members are
# spelled in full here, so the fix is visible in the product, not just the run.
s7_inner="I$(mkruns i 90)"
s7_field="f$(mkruns f 90)"
s7_outer="O$(mkruns o 90)"
s7_var="v$(mkruns v 90)"
s7_trait="T$(mkruns t 40)"
s7_meth="m$(mkruns m 20)"
cat >"$w/nested.ct" <<CT
trait $s7_trait {
    int $s7_meth();
}

struct $s7_inner {
    int x;
} use $s7_trait;

impl $s7_trait for $s7_inner {
    int $s7_meth() { return self->x; }
}

struct $s7_outer {
    $s7_inner $s7_field[2];
}

int main(void)
{
    $s7_outer $s7_var;
    $s7_var.$s7_field[0].x = 3;
    $s7_var.$s7_field[1].x = 4;
    return $s7_var.$s7_field[0].x + $s7_var.$s7_field[1].x - 7;
}
CT
if ! "$ct" "$w/nested.ct" -o "$w/nested.c" >"$w/nested.out" 2>"$w/nested.err"; then
    bad "the nested long-member fixture did not compile: $(head -3 "$w/nested.err" | tr '\n' ' ')"
elif ! $cc $cflags "$w/nested.c" -o "$w/nested" >"$w/nested.cc" 2>&1; then
    bad "the nested vptr path was cut at 160 bytes (cc: $(head -1 "$w/nested.cc"))"
elif ! "$w/nested"; then
    bad "the nested long-member program exited non-zero"
elif ! grep -q "$s7_var.$s7_field\[0\]" "$w/nested.c"; then
    bad "the emitted C does not spell the full nested member path"
else
    ok
    printf '  nested member path: 90-byte local + 90-byte field kept whole\n'
fi

# S7b: a `String` field initialised from a 200- and a 1000-byte literal. The
# rewrite to an owning `str_dup_len` copy was guarded by `e0 - fs < MAX_TEXT`,
# so a longer item stayed a bare literal and `release` freed static storage.
{
    printf 'struct Bag {\n    String s;\n}\n\nint main(void)\n{\n'
    printf '    Bag a = { .s = '
    i=0
    while [ "$i" -lt 2 ]; do printf '"%s"' "$(mkruns a 100)"; i=$((i + 1)); done
    printf ' };\n'
    printf '    Bag b = { .s = '
    i=0
    while [ "$i" -lt 10 ]; do printf '"%s"' "$(mkruns b 100)"; i=$((i + 1)); done
    printf ' };\n'
    cat <<'CT'
    int n = a.s.len();
    int m = b.s.len();
    int ok = (n == 200 && m == 1000);
    a.s.release();
    b.s.release();
    return ok ? 0 : 1;
}
CT
} >"$w/longfield.ct"
if ! "$ct" "$w/longfield.ct" -o "$w/longfield.c" >"$w/longfield.out" 2>"$w/longfield.err"; then
    bad "the long String-field initialiser did not compile: $(head -3 "$w/longfield.err" | tr '\n' ' ')"
elif [ "$(grep -c '\.s = str_dup_len(' "$w/longfield.c")" -ne 2 ]; then
    bad "a 200/1000-byte String initialiser item was not rewritten to an owning copy"
elif ! grep -q "$(mkruns b 100)" "$w/longfield.c"; then
    bad "the 1000-byte initialiser item lost its last 100-byte literal segment"
elif ! $cc $cflags "$w/longfield.c" -o "$w/longfield" >"$w/longfield.cc" 2>&1; then
    bad "the long String-field C did not build: $(head -1 "$w/longfield.cc")"
elif ! "$w/longfield"; then
    bad "the long String-field initialiser lost its bytes or double-freed (status $?)"
else
    ok
    printf '  long initialiser items: 200/1000 bytes become owning copies\n'
fi

# S7d: a 150-byte label and its `goto` (the label rows are interned since
# C2n-2; this keeps the emitter from re-introducing a row).
s7_label="L$(mkruns l 150)"
cat >"$w/longlabel.ct" <<CT
int main(void)
{
    int n = 0;
$s7_label:
    n = 1;
    if (n == 0) goto $s7_label;
    return n - 1;
}
CT
if ! "$ct" "$w/longlabel.ct" -o "$w/longlabel.c" >"$w/longlabel.out" 2>"$w/longlabel.err"; then
    bad "the 150-byte label did not compile: $(head -3 "$w/longlabel.err" | tr '\n' ' ')"
elif ! grep -q "$s7_label" "$w/longlabel.c"; then
    bad "the emitted C lost the 150-byte label"
elif ! $cc $cflags "$w/longlabel.c" -o "$w/longlabel" >"$w/longlabel.cc" 2>&1 || ! "$w/longlabel"; then
    bad "the 150-byte label program did not build and run"
else
    ok
    printf '  long label: 150-byte label emitted whole\n'
fi

echo "intern_pool: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
