#!/usr/bin/env bash
# PH-64-T1 probe: the vtable and every vptr that points at it must be `const`,
# so the table lands in .rodata on a bare-metal target. `sizeof` must not move
# (the field is a pointer either way), and the program must still dispatch.
#
# Usage: bash test/ast/p64_const_vtable.sh <ct-ast>
set -u
# PH-65: the fixtures write free `#include`s; this probe is not about the C
# boundary. SH-93 removed the cwd shortcut, so opt into allow explicitly.
export CT_C_BOUNDARY=allow
CT=${1:?usage: p64_const_vtable.sh <ct-ast>}
CC=${CC:-cc}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p64cv.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/prog.ct" <<'CT'
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

Person one = { .name = "a" };

int main(void)
{
    Greeter g = one;
    printf("%s %d\n", g.who(), (int)sizeof(Person));
    return 0;
}
CT

fail=0
if ! "$CT" "$tmp/prog.ct" -o "$tmp/prog.c" >"$tmp/out" 2>"$tmp/err"; then
    echo "FAIL p64cv: compile failed" >&2
    sed 's/^/  /' "$tmp/err" >&2
    exit 1
fi

# 1) the table definition is const
if grep -q '^static const struct Greeter_vtbl Person_Greeter_vtable __attribute__((unused)) = {$' "$tmp/prog.c"; then
    :
else
    echo "FAIL p64cv: the vtable definition is not const" >&2
    grep -n 'Person_Greeter_vtable' "$tmp/prog.c" | head -3 >&2
    fail=1
fi

# 2) the struct's vptr field is a pointer to const
if grep -q '^    const struct Greeter_vtbl \*__greeter_vptr;$' "$tmp/prog.c"; then
    :
else
    echo "FAIL p64cv: __greeter_vptr is not a pointer to const" >&2
    grep -n '__greeter_vptr' "$tmp/prog.c" | head -3 >&2
    fail=1
fi

# 3) the interface's vt slot is a pointer to const
if grep -q '^    const struct Greeter_vtbl \*vt;$' "$tmp/prog.c"; then
    :
else
    echo "FAIL p64cv: _iface.vt is not a pointer to const" >&2
    grep -n 'vt;' "$tmp/prog.c" | head -3 >&2
    fail=1
fi

# 4) the product still builds warning-free, runs, and keeps its size
if ! "$CC" -Wall -Wextra -std=c99 "$tmp/prog.c" -o "$tmp/prog" 2>"$tmp/cc.log"; then
    echo "FAIL p64cv: the product did not build" >&2
    sed 's/^/  /' "$tmp/cc.log" >&2
    fail=1
elif ! "$tmp/prog" >"$tmp/run.out" 2>&1; then
    echo "FAIL p64cv: the program exited non-zero" >&2
    fail=1
elif [ "$(cat "$tmp/run.out")" != "a 16" ]; then
    echo "FAIL p64cv: expected 'a 16', got '$(cat "$tmp/run.out")'" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p64cv"
exit "$fail"
