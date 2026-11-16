#!/usr/bin/env bash
# PH-64-T3 probe: `--alloc A,B` maps every compiler-emitted and source-level
# malloc/free onto the target's own symbols, so a bare-metal link needs no libc
# heap. Without the flag the product keeps libc names (byte-identical to before).
#
# Usage: bash test/ast/p64_alloc.sh <ct-ast>
set -u
CT=${1:?usage: p64_alloc.sh <ct-ast>}
CC=${CC:-cc}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p64alloc.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/prog.ct" <<'CT'
#include <stdio.h>

trait Greeter {
    char *who();
}

struct Person {
    char *name;
} use Greeter, Drop;

impl Greeter for Person {
    char *who() {
        return self->name;
    }
}

impl Drop for Person {
    void drop() {
    }
}

int main(void)
{
    Person *p = malloc(sizeof(struct Person));
    p->name = "x";
    printf("%s\n", p->who());
    delete p;
    return 0;
}
CT

cat >"$tmp/stub.c" <<'C'
/* the target's allocator, as a bare-metal port would provide it */
void *pvPortMalloc(unsigned long n);
void vPortFree(void *p);
void *pvPortMalloc(unsigned long n) { extern void *malloc(unsigned long); return malloc(n); }
void vPortFree(void *p) { extern void free(void *); free(p); }
C

fail=0
# 1) default: libc names stay
if ! "$CT" "$tmp/prog.ct" -o "$tmp/plain.c" >"$tmp/plain.log" 2>"$tmp/plain.err"; then
    echo "FAIL p64alloc: the default compile failed: $(head -2 "$tmp/plain.err")" >&2
    fail=1
elif ! grep -q 'malloc(sizeof(struct Person))' "$tmp/plain.c"; then
    echo "FAIL p64alloc: the default product lost its libc malloc call" >&2
    fail=1
fi

# 2) --alloc renames both directions
if ! "$CT" --alloc pvPortMalloc,vPortFree "$tmp/prog.ct" -o "$tmp/mapped.c" >"$tmp/m.log" 2>"$tmp/m.err"; then
    echo "FAIL p64alloc: --alloc compile failed: $(head -2 "$tmp/m.err")" >&2
    fail=1
else
    if grep -qE '\b(malloc|free)\(' "$tmp/mapped.c"; then
        echo "FAIL p64alloc: the product still calls libc: $(grep -nE '\b(malloc|free)\(' "$tmp/mapped.c" | head -2)" >&2
        fail=1
    fi
    if ! grep -q 'pvPortMalloc(sizeof(struct Person))' "$tmp/mapped.c"; then
        echo "FAIL p64alloc: malloc was not mapped" >&2
        fail=1
    fi
    if ! grep -q 'vPortFree(p)' "$tmp/mapped.c"; then
        echo "FAIL p64alloc: free was not mapped" >&2
        fail=1
    fi
fi

# 3) --freestanding without --alloc is a hard error, with a position
if "$CT" --freestanding "$tmp/prog.ct" -o "$tmp/fs.c" >"$tmp/fs.log" 2>"$tmp/fs.err"; then
    echo "FAIL p64alloc: --freestanding accepted an unmapped heap" >&2
    fail=1
elif ! grep -qE 'error: .*--alloc' "$tmp/fs.err"; then
    echo "FAIL p64alloc: wrong diagnostic: $(head -2 "$tmp/fs.err")" >&2
    fail=1
fi

# 4) mapped product builds against a stub allocator and runs
if [ "$fail" -eq 0 ]; then
    if ! "$CC" -Wall -Wextra -std=c99 "$tmp/mapped.c" "$tmp/stub.c" -o "$tmp/mapped" 2>"$tmp/cc.log"; then
        echo "FAIL p64alloc: the mapped product did not build: $(head -3 "$tmp/cc.log")" >&2
        fail=1
    elif [ "$("$tmp/mapped" 2>&1)" != "x" ]; then
        echo "FAIL p64alloc: the mapped program printed '$( "$tmp/mapped" 2>&1 )'" >&2
        fail=1
    fi
fi

[ "$fail" -eq 0 ] && echo "OK p64alloc"
exit "$fail"
