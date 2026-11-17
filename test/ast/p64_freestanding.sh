#!/usr/bin/env bash
# PH-64-T4 probe: the `--freestanding` symbol-surface contract. Every generated
# unit must link under `-ffreestanding -nostdlib -c`, and its undefined symbols
# (`nm -u`) must be a subset of the allowed set: the compiler's own builtins,
# the `--alloc` mapping, and nothing else. libc must not leak in.
#
# Usage: bash test/ast/p64_freestanding.sh <ct-ast>
set -u
CT=${1:?usage: p64_freestanding.sh <ct-ast>}
CC=${CC:-cc}
NM=${NM:-nm}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p64free.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/min" "$tmp/trait" "$tmp/heap"

cat >"$tmp/min/m.ct" <<'CT'
int main(void)
{
    return 0;
}
CT

cat >"$tmp/trait/t.ct" <<'CT'
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

Person one = { .name = "a" };

int main(void)
{
    return one.who() != 0;
}
CT

cat >"$tmp/heap/h.ct" <<'CT'
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
    int r = p->who() != 0;
    delete p;
    return r;
}
CT

fail=0
# `nm -u` prints one line per undefined symbol; the allowed set is passed as a
# space-separated list of names (empty by default).
check_units() {
    dir=$1
    allowed=$2
    shift 2
    for f in "$dir"/*.c; do
        [ -e "$f" ] || continue
        obj="$f.o"
        if ! "$CC" -ffreestanding -nostdlib -c "$f" -o "$obj" 2>"$obj.log"; then
            echo "FAIL p64free: $(basename "$f") did not compile freestanding: $(head -3 "$obj.log")" >&2
            fail=1
            continue
        fi
        for sym in $("$NM" -u "$obj" 2>/dev/null | awk '{print $NF}'); do
            # Mach-O prefixes C symbols with an underscore; the contract is
            # about the C name.
            sym=${sym#_}
            case " $allowed " in
                *" $sym "*) ;;
                *)
                    echo "FAIL p64free: $(basename "$f") needs '$sym' (not in the allowed set)" >&2
                    fail=1
                    ;;
            esac
        done
    done
}

( cd "$root" && "$CT" build --freestanding --emit-c "$tmp/min/m.ct" -o "$tmp/min" ) >"$tmp/min.log" 2>"$tmp/min.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64free: the bare program did not build: $(head -2 "$tmp/min.err")" >&2
    fail=1
else
    check_units "$tmp/min" ""
fi

( cd "$root" && "$CT" build --freestanding --emit-c "$tmp/trait/t.ct" -o "$tmp/trait" ) >"$tmp/trait.log" 2>"$tmp/trait.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64free: the trait program did not build: $(head -2 "$tmp/trait.err")" >&2
    fail=1
else
    check_units "$tmp/trait" ""
fi

( cd "$root" && "$CT" build --freestanding --alloc pvPortMalloc,vPortFree --emit-c "$tmp/heap/h.ct" -o "$tmp/heap" ) >"$tmp/heap.log" 2>"$tmp/heap.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64free: the mapped heap program did not build: $(head -2 "$tmp/heap.err")" >&2
    fail=1
else
    check_units "$tmp/heap" "pvPortMalloc vPortFree"
fi

# SH-90: `--freestanding` must also drop the implicit container layer in single-
# file (compile) mode. The layer used to be spliced unconditionally, so a
# freestanding product still carried `<stdio.h>`/`<stdlib.h>` and the `Str`
# unit's `malloc` calls -- fatal under `-nostdlib`.
mkdir -p "$tmp/cmode" "$tmp/cmode/out"
cat >"$tmp/cmode/c.ct" <<'CT'
int main(void)
{
    return 0;
}
CT
( cd "$root" && CT_STD_DIR="$root/lib/std" "$CT" --freestanding "$tmp/cmode/c.ct" -o "$tmp/cmode/c.c" ) >"$tmp/cmode.log" 2>"$tmp/cmode.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64free: the compile-mode freestanding program failed: $(head -2 "$tmp/cmode.err")" >&2
    fail=1
else
    if grep -q '#include *<' "$tmp/cmode/c.c"; then
        echo "FAIL p64free: compile-mode --freestanding kept system headers:" >&2
        grep -n '#include *<' "$tmp/cmode/c.c" | head -3 >&2
        fail=1
    fi
    if grep -q 'malloc(' "$tmp/cmode/c.c"; then
        echo "FAIL p64free: compile-mode --freestanding kept the builtin layer (malloc)" >&2
        grep -n 'malloc(' "$tmp/cmode/c.c" | head -3 >&2
        fail=1
    fi
fi

[ "$fail" -eq 0 ] && echo "OK p64free"
exit "$fail"
