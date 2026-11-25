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
#          without truncation, and a reset that leaves the pool usable.
#   S3     2000 distinct `pub type` aliases compile in one `.h.ct` unit; the
#          last aliases resolve to the right width and the generated C builds
#          and runs.
#   S4     a three-deep alias chain still expands, the pinned alias-cycle
#          diagnostic is byte-identical, and an imported `pub type` still
#          resolves through the module layer (the add-visible path).
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
    if ! $cc $cflags -I "$w/gen" "$w/gen/Intern.c" "$w/harness.c" -o "$w/harness" \
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

echo "intern_pool: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
