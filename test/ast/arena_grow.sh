#!/bin/sh
# v1-PH-2 S1a-0 C1: node arena grows past its initial capacity instead of
# failing at MAX_NODES. CT_ARENA_INIT is a test-only initial capacity; a small
# source with more nodes than the init still compiles and produces C.
set -u
ct=${1:?usage: arena_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/arena.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cat >"$w/prog.ct" <<'CT'
int f(int x) { int a = x + 1; int b = a * 2; if (b > 3) { b = b - 1; } return b; }
int main(void) { return f(2); }
CT
if CT_ARENA_INIT=8 "$ct" compile "$w/prog.ct" -o "$w/prog.c" >"$w/log" 2>&1 \
   && cc -std=c99 -c "$w/prog.c" -o "$w/prog.o" >"$w/cc" 2>&1; then
    echo "ok   arena grows from CT_ARENA_INIT=8"
else
    echo "FAIL arena growth: $(head -3 "$w/log" "$w/cc" 2>/dev/null | tr '\n' ' ')"
    exit 1
fi
