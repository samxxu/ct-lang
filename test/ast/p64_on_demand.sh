#!/usr/bin/env bash
# PH-64-T2 probe: `ct build --emit-c` emits only the built-in layer units the
# program can reach. A bare program gets no container unit; `Option<int>` gets
# `Option` and nothing else. The layer is discovered from the repo root, so the
# probe runs `ct` from there.
#
# Usage: bash test/ast/p64_on_demand.sh <ct-ast>
set -u
# PH-65: the fixtures write free `#include`s; this probe is not about the C
# boundary. SH-93 removed the cwd shortcut, so opt into allow explicitly.
export CT_C_BOUNDARY=allow
CT=${1:?usage: p64_on_demand.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p64ond.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/min" "$tmp/opt"

cat >"$tmp/min/m.ct" <<'CT'
int main(void)
{
    return 0;
}
CT

cat >"$tmp/opt/o.ct" <<'CT'
#include <stdio.h>

int main(void)
{
    Option<int> a = { 1, 3 };
    printf("%d\n", a.has);
    return 0;
}
CT

fail=0
( cd "$root" && "$CT" build --emit-c "$tmp/min/m.ct" -o "$tmp/min" ) >"$tmp/min.log" 2>"$tmp/min.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the bare program did not build: $(head -2 "$tmp/min.err")" >&2
    fail=1
else
    for u in Vec Option Result Str; do
        if [ -e "$tmp/min/$u.c" ] || [ -e "$tmp/min/$u.h" ]; then
            echo "FAIL p64ond: the bare program still emits $u" >&2
            fail=1
        fi
    done
    [ -e "$tmp/min/m.c" ] || { echo "FAIL p64ond: m.c is missing" >&2; fail=1; }
fi

( cd "$root" && "$CT" build --emit-c "$tmp/opt/o.ct" -o "$tmp/opt" ) >"$tmp/opt.log" 2>"$tmp/opt.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the Option program did not build: $(head -2 "$tmp/opt.err")" >&2
    fail=1
else
    [ -e "$tmp/opt/Option.c" ] || { echo "FAIL p64ond: Option.c is missing" >&2; fail=1; }
    for u in Vec Result Str; do
        if [ -e "$tmp/opt/$u.c" ]; then
            echo "FAIL p64ond: Option<int> also pulled $u" >&2
            fail=1
        fi
    done
    if ! "$CC" -Wall -Wextra -std=c99 "$tmp/opt"/*.c -o "$tmp/opt.bin" 2>"$tmp/opt.cc"; then
        echo "FAIL p64ond: the Option product did not link: $(head -3 "$tmp/opt.cc")" >&2
        fail=1
    elif [ "$("$tmp/opt.bin" 2>&1)" != "1" ]; then
        echo "FAIL p64ond: the Option program printed '$( "$tmp/opt.bin" 2>&1 )'" >&2
        fail=1
    fi
fi

# SH-87 (battle hw-2): `Str` is not a template, so its liveness has three
# traps the first implementation fell into -- a layer helper contains no `Str`
# (false negative), `struct Struct` contains it (false positive), and a single
# `fread` dropped the tail of a large source (false negative). One case each.
mkdir -p "$tmp/strfn" "$tmp/structname" "$tmp/bigs"

cat >"$tmp/strfn/s.ct" <<'CT'
#include <stdio.h>

int main(void)
{
    String s = "hi";
    printf("%d\n", s.len());
    return 0;
}
CT
( cd "$root" && "$CT" build --emit-c "$tmp/strfn/s.ct" -o "$tmp/strfn" ) >"$tmp/strfn.log" 2>"$tmp/strfn.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the layer-helper program did not build: $(head -2 "$tmp/strfn.err")" >&2
    fail=1
elif [ ! -e "$tmp/strfn/String.c" ]; then
    echo "FAIL p64ond: a String use did not pull String.c" >&2
    fail=1
elif ! "$CC" -Wall -Wextra -std=c99 "$tmp/strfn"/*.c -o "$tmp/strfn.bin" 2>"$tmp/strfn.cc"; then
    echo "FAIL p64ond: the layer-helper product did not link: $(head -3 "$tmp/strfn.cc")" >&2
    fail=1
elif [ "$("$tmp/strfn.bin" 2>&1)" != "2" ]; then
    echo "FAIL p64ond: the layer-helper program printed '$( "$tmp/strfn.bin" 2>&1 )'" >&2
    fail=1
fi

cat >"$tmp/structname/s.ct" <<'CT'
#include <stdio.h>

struct Struct {
    int x;
};

int main(void)
{
    struct Struct v;
    v.x = 1;
    printf("%d\n", v.x);
    return 0;
}
CT
( cd "$root" && "$CT" build --emit-c "$tmp/structname/s.ct" -o "$tmp/structname" ) >"$tmp/structname.log" 2>"$tmp/structname.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the struct-Struct program did not build: $(head -2 "$tmp/structname.err")" >&2
    fail=1
elif [ -e "$tmp/structname/String.c" ]; then
    echo "FAIL p64ond: a user struct named Struct pulled String.c" >&2
    fail=1
fi

{
    echo '#include <stdio.h>'
    i=0
    while [ "$i" -lt 6500 ]; do
        echo '/* filler line to grow the source past 262143 bytes */'
        i=$((i + 1))
    done
    echo 'String s = "x";'
    echo 'int main(void) { printf("%d\n", s.len()); return 0; }'
} >"$tmp/bigs/b.ct"
( cd "$root" && "$CT" build --emit-c "$tmp/bigs/b.ct" -o "$tmp/bigs" ) >"$tmp/bigs.log" 2>"$tmp/bigs.err"
if [ $? -ne 0 ]; then
    echo "FAIL p64ond: the large-source program did not build: $(head -2 "$tmp/bigs.err")" >&2
    fail=1
elif [ ! -e "$tmp/bigs/String.c" ]; then
    echo "FAIL p64ond: a String mention past 262143 bytes was missed" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p64ond"
exit "$fail"
