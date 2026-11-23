#!/bin/sh
# SH-116: `ct build` must emit the Box built-in unit (`lib/core/Box.h.ct`)
# whenever a program uses `Box<T>` / the deprecated `box<T>` alias / `new T {}`,
# exactly like the Vec / Option / Result / Str units are emitted on demand.
#
# Before the fix the unit was *loaded* by `build_main` but `builtin_live_for`
# had no `Box` branch, so `emit_unit` / `write_unit_header` pruned it: the
# product kept only `struct ct_Box_hdr;`, `cc` rejected the incomplete type and
# `.ctbuild` carried no `Box.c` / `Box.h`.
#
# Groups:
#   1. Box<T>     build  -> Box.c + Box.h emitted, product builds and runs;
#   2. Box<T>     compile -> one translation unit keeps the header definition;
#   3. box<T>     build  -> the deprecated alias still loads the same unit and
#                            warns exactly once per alias token;
#   4. box<T>     compile -> same warning, one TU;
#   5. user `struct Box` build -> the built-in layer stays out (LANG-24), the
#                            product still runs, and no `ct_Box_hdr` leaks in;
#   6. user `struct Box` compile -> same, byte-shape unchanged.
#
# Usage: sh test/ast/sh116_build_box.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: sh116_build_box.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/sh116.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
cc=${CC:-cc}
fail=0
pass=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); echo "FAIL sh116: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; }
cd "$root" || exit 1

# Each fixture lives in its own directory so `.ctbuild/` is per-case.
new_case() { # name
    mkdir -p "$work/$1"
}

build_case() { # name, expected stdout
    name=$1
    want=$2
    dir=$work/$name
    if ! ( cd "$dir" && "$ctast" build -o prog main.ct ) >"$dir/build.log" 2>&1; then
        bad "$name: build failed" "$(sed -n '1,8p' "$dir/build.log")"
        return 1
    fi
    if ! ( cd "$dir" && ./prog ) >"$dir/run.out" 2>"$dir/run.err"; then
        bad "$name: product failed" "$(sed -n '1,8p' "$dir/run.err")"
        return 1
    fi
    if [ -s "$dir/run.err" ]; then
        bad "$name: product wrote stderr" "$(head -2 "$dir/run.err")"
        return 1
    fi
    if ! printf '%s\n' "$want" | cmp -s - "$dir/run.out"; then
        bad "$name: stdout differs" "$(sed -n '1,4p' "$dir/run.out")"
        return 1
    fi
    ok "$name: build + run ($want)"
}
compile_case() { # name, expected stdout
    name=$1
    want=$2
    dir=$work/$name
    if ! "$ctast" "$dir/main.ct" -o "$dir/main.c" >"$dir/compile.log" 2>&1; then
        bad "$name: compile failed" "$(sed -n '1,8p' "$dir/compile.log")"
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$dir/main.c" -o "$dir/prog" 2>"$dir/cc.err"; then
        bad "$name: cc failed" "$(sed -n '1,8p' "$dir/cc.err")"
        return 1
    fi
    if [ -s "$dir/cc.err" ]; then
        bad "$name: cc was not warning-free" "$(head -2 "$dir/cc.err")"
        return 1
    fi
    if ! "$dir/prog" >"$dir/run.out" 2>"$dir/run.err"; then
        bad "$name: product failed" "$(sed -n '1,8p' "$dir/run.err")"
        return 1
    fi
    if ! printf '%s\n' "$want" | cmp -s - "$dir/run.out"; then
        bad "$name: stdout differs" "$(sed -n '1,4p' "$dir/run.out")"
        return 1
    fi
    ok "$name: compile + run ($want)"
}

# ---- 1/2. Box<T> in build and compile mode --------------------------------
new_case box_build
cat >"$work/box_build/main.ct" <<'CT'
#include <stdio.h>

struct P { int x; }

int main(void)
{
    Box<P> b = new P { 7 };
    int y = b.at()->x;
    b.release();
    printf("%d\n", y);
    return 0;
}
CT
if build_case box_build 7; then
    dir=$work/box_build
    if [ ! -f "$dir/.ctbuild/Box.c" ] || [ ! -f "$dir/.ctbuild/Box.h" ]; then
        bad "box_build: .ctbuild is missing the Box unit" \
            "$(ls "$dir/.ctbuild" 2>/dev/null | tr '\n' ' ')"
    elif ! grep -Fq 'struct ct_Box_hdr {' "$dir/.ctbuild/Box.h"; then
        bad "box_build: Box.h keeps only a forward declaration" \
            "$(grep -n 'ct_Box_hdr' "$dir/.ctbuild/Box.h" | head -3)"
    elif ! grep -Fq 'Box_P__new' "$dir/.ctbuild/main.c"; then
        bad "box_build: the consuming unit has no Box_P__new" \
            "$(grep -c 'Box_P' "$dir/.ctbuild/main.c")"
    elif ! grep -Fq '#include "Box.h"' "$dir/.ctbuild/main.c"; then
        bad "box_build: the user unit does not include Box.h" \
            "$(grep -n '^#include' "$dir/.ctbuild/main.c" | head -5)"
    else
        ok "box_build: Box.c/Box.h emitted, user unit includes Box.h"
    fi
fi

new_case box_compile
cat >"$work/box_compile/main.ct" <<'CT'
#include <stdio.h>

struct P { int x; }

int main(void)
{
    Box<P> b = new P { 7 };
    int y = b.at()->x;
    b.release();
    printf("%d\n", y);
    return 0;
}
CT
if compile_case box_compile 7; then
    if ! grep -Fq 'struct ct_Box_hdr {' "$work/box_compile/main.c"; then
        bad "box_compile: the one TU lost the header definition"
    elif ! grep -Fq 'Box_P__new' "$work/box_compile/main.c"; then
        bad "box_compile: the one TU lost Box_P__new"
    else
        ok "box_compile: the header definition stays inlined"
    fi
fi

# ---- 3/4. deprecated box<T> alias ----------------------------------------
new_case alias_build
cat >"$work/alias_build/main.ct" <<'CT'
#include <stdio.h>

struct P { int x; }

int main(void)
{
    box<P> b = new P { 6 };
    int y = b.at()->x;
    b.release();
    printf("%d\n", y);
    return 0;
}
CT
if build_case alias_build 6; then
    dir=$work/alias_build
    nwarn=$(grep -cF "'box<T>' is deprecated; write 'Box<T>'" "$dir/build.log")
    if [ "$nwarn" -ne 1 ]; then
        bad "alias_build: deprecated warning count $nwarn, expected 1" \
            "$(head -3 "$dir/build.log")"
    elif [ ! -f "$dir/.ctbuild/Box.c" ] || [ ! -f "$dir/.ctbuild/Box.h" ]; then
        bad "alias_build: the alias did not emit the Box unit" \
            "$(ls "$dir/.ctbuild" 2>/dev/null | tr '\n' ' ')"
    else
        ok "alias_build: box<T> emits Box.c/Box.h and warns once"
    fi
fi

new_case alias_compile
cat >"$work/alias_compile/main.ct" <<'CT'
#include <stdio.h>

struct P { int x; }

int main(void)
{
    box<P> b = new P { 6 };
    int y = b.at()->x;
    b.release();
    printf("%d\n", y);
    return 0;
}
CT
if compile_case alias_compile 6; then
    nwarn=$(grep -cF "'box<T>' is deprecated; write 'Box<T>'" "$work/alias_compile/compile.log")
    if [ "$nwarn" -ne 1 ]; then
        bad "alias_compile: deprecated warning count $nwarn, expected 1"
    elif ! grep -Fq 'struct ct_Box_hdr {' "$work/alias_compile/main.c"; then
        bad "alias_compile: the one TU lost the header definition"
    else
        ok "alias_compile: box<T> stays a parse-level alias"
    fi
fi

# ---- 5/6. a user-owned struct Box keeps the built-in layer out (LANG-24) --
new_case user_box_build
cat >"$work/user_box_build/main.ct" <<'CT'
#include <stdio.h>

struct Box { int x; }

int main(void)
{
    Box b = { 5 };
    printf("%d\n", b.x);
    return 0;
}
CT
if build_case user_box_build 5; then
    dir=$work/user_box_build
    if [ -e "$dir/.ctbuild/Box.c" ] || [ -e "$dir/.ctbuild/Box.h" ]; then
        bad "user_box_build: the built-in Box unit was emitted anyway"
    elif grep -Fq 'ct_Box_hdr' "$dir/.ctbuild/main.c"; then
        bad "user_box_build: the built-in header leaked into the product"
    else
        ok "user_box_build: the built-in layer stays out"
    fi
fi

new_case user_box_compile
cat >"$work/user_box_compile/main.ct" <<'CT'
#include <stdio.h>

struct Box { int x; }

int main(void)
{
    Box b = { 5 };
    printf("%d\n", b.x);
    return 0;
}
CT
if compile_case user_box_compile 5; then
    if grep -Fq 'ct_Box_hdr' "$work/user_box_compile/main.c"; then
        bad "user_box_compile: the built-in header leaked into the one TU"
    else
        ok "user_box_compile: the built-in layer stays out"
    fi
fi

printf 'sh116_build_box: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
