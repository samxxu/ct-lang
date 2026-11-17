#!/usr/bin/env bash
# PH-64-T5 probe: under `--freestanding` a file-scope trait array without an
# initialiser cannot be filled -- the per-unit constructor is never emitted, so
# the vptrs would stay NULL. The compiler must reject it with a position instead
# of shipping a program that faults at run time.
#
# Usage: bash test/ast/p64_no_init_array.sh <ct-ast>
set -u
CT=${1:?usage: p64_no_init_array.sh <ct-ast>}
CC=${CC:-cc}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p64nia.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/prog.ct" <<'CT'
trait Greeter {
    char *who();
}

struct Person {
    char *name;
} use Greeter;

impl Greeter for Person {
    char *who() {
        return self->name;
    }
}

Person ps[2];

int main(void)
{
    return 0;
}
CT

fail=0
# 1) without --freestanding the same source keeps the constructor path
if ! "$CT" "$tmp/prog.ct" -o "$tmp/prog.c" >"$tmp/out.log" 2>"$tmp/err.log"; then
    echo "FAIL p64nia: the default compile failed: $(head -2 "$tmp/err.log")" >&2
    fail=1
elif ! grep -q '__attribute__((constructor))' "$tmp/prog.c"; then
    echo "FAIL p64nia: the default compile lost its constructor" >&2
    fail=1
fi

# 2) --freestanding rejects it, with a position and the reason
if "$CT" --freestanding "$tmp/prog.ct" -o "$tmp/fs.c" >"$tmp/fs.out" 2>"$tmp/fs.err"; then
    echo "FAIL p64nia: --freestanding accepted a constructor-only array" >&2
    fail=1
elif grep -qE "^$tmp/prog\.ct:15:[0-9]+: error: .*--freestanding" "$tmp/fs.err"; then
    :
else
    echo "FAIL p64nia: wrong diagnostic: $(head -2 "$tmp/fs.err")" >&2
    fail=1
fi

# 3) with an initialiser the same shape is accepted (the SH-86 path)
cat >"$tmp/ok.ct" <<'CT'
#include <stdio.h>

trait Greeter {
    char *who();
}

struct Person {
    char *name;
} use Greeter;

impl Greeter for Person {
    char *who() {
        return self->name;
    }
}

Person ps[2] = { { .name = "a" }, { .name = "b" } };

int main(void)
{
    /* PH-66: a freestanding product may not call printf; the array semantics
       are what this probe checks, so observe them without libc. */
    return ps[0].who()[0] == 'a' ? 0 : 1;
}
CT
if ! "$CT" --freestanding "$tmp/ok.ct" -o "$tmp/ok.c" >"$tmp/ok.log" 2>"$tmp/ok.err"; then
    echo "FAIL p64nia: --freestanding rejected an initialised array: $(head -2 "$tmp/ok.err")" >&2
    fail=1
elif grep -q '__attribute__((constructor))' "$tmp/ok.c"; then
    echo "FAIL p64nia: --freestanding emitted a constructor" >&2
    fail=1
elif ! "$CC" -Wall -Wextra -std=c99 "$tmp/ok.c" -o "$tmp/ok" 2>"$tmp/ok.cc"; then
    echo "FAIL p64nia: the initialised product did not build: $(head -2 "$tmp/ok.cc")" >&2
    fail=1
elif ! "$tmp/ok" >/dev/null 2>&1; then
    echo "FAIL p64nia: the initialised product exited non-zero" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p64nia"
exit "$fail"
