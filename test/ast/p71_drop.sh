#!/bin/sh
# PH-71-R2: Drop reachability and release order. An inner owned object is
# released before the outer one; an explicit `delete` releases once (the
# scope-end AutoDrop must not fire again). The probe builds and runs the
# emitted C, so it pins behaviour, not just diagnostics.
#
# Usage: sh test/ast/p71_drop.sh <ct-ast>
set -u
ctast=${1:?usage: p71_drop.sh <ct-ast>}
cc=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p71drop.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

run_case() {
    name=$1; expect=$2; file=$3
    out=$work/out.$name
    mkdir -p "$out"
    ( cd "$root" && "$ctast" build --emit-c -o "$out" "$file" ) >"$work/build.$name.log" 2>&1 || {
        echo "FAIL p71/drop: $name build failed" >&2
        sed 's/^/  /' "$work/build.$name.log" | head -4 >&2
        fail=1
        return
    }
    "$cc" -std=c99 "$out"/*.c -o "$work/prog.$name" >"$work/cc.$name.log" 2>&1 || {
        echo "FAIL p71/drop: $name cc failed" >&2
        sed 's/^/  /' "$work/cc.$name.log" | head -4 >&2
        fail=1
        return
    }
    got=$("$work/prog.$name")
    [ "$got" = "$expect" ] || {
        printf 'FAIL p71/drop: %s order [%s], want [%s]\n' "$name" "$got" "$expect" >&2
        fail=1
    }
}

cat > "$work/order.ct" <<'CT'
#include <stdio.h>
#include <stdlib.h>
struct A { int v; } use Drop;
impl Drop for A { void drop() { printf("A\n"); } }
struct B { int v; } use Drop;
impl Drop for B { void drop() { printf("B\n"); } }
int main(void)
{
    own struct A *a = malloc(sizeof(struct A));
    {
        own struct B *b = malloc(sizeof(struct B));
        b->v = 1;
    }
    a->v = 2;
    return 0;
}
CT
run_case order "B
A" "$work/order.ct"

cat > "$work/once.ct" <<'CT'
#include <stdio.h>
#include <stdlib.h>
struct A { int v; } use Drop;
impl Drop for A { void drop() { printf("A\n"); } }
int main(void)
{
    own struct A *a = malloc(sizeof(struct A));
    a->v = 1;
    delete a;
    return 0;
}
CT
run_case once "A" "$work/once.ct"

[ "$fail" -eq 0 ] || exit 1
echo "OK p71/drop (order + single release)"
