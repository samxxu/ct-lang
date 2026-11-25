#!/bin/sh
# S1a-0 C2g: --cflags / --ldflags grow past the old 1024-byte MAX_FLAGS.
#
# One pass-through value carries `-DBIG=1` plus a >1024-byte macro name, so a
# compiler that still caps the accumulator rejects the whole value with
# `ctc: --cflags value is too long`. The fixture depends on -DBIG (a raw block
# with #error), so a green build also proves the long value reached cc, not
# just that the parser accepted it.
#
#   * `ct build ... --cflags <long>` (Module's build path)
#   * `ct <file> --cflags <long> -o out.c` (the Driver's compile path)
#
# Usage: sh test/ast/cap_flags.sh <ct-ast>
set -u
ct=${1:?usage: cap_flags.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
CT_C_BOUNDARY=allow
export CT_C_BOUNDARY
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/capflags.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}

longflags=$(awk 'BEGIN { printf "-DBIG=1 -D"; for (i = 0; i < 1100; i++) printf "A"; printf "=1" }')

cat >"$w/prog.ct" <<'SRC'
#ct-raw
#ifndef BIG
#error BIG is missing
#endif
#ct-endraw
int main(void)
{
    return 0;
}
SRC

fail=0

# --- 1) build path: Module appends the flag, cc must see -DBIG --------------
if ! "$ct" build "$w/prog.ct" --cflags "$longflags" -o "$w/prog" \
        >"$w/build.out" 2>"$w/build.err"; then
    echo "FAIL flags_build: ct-ast rejected a ${#longflags}-byte --cflags value:"
    sed 's/^/    /' "$w/build.err" | tail -3
    fail=1
elif [ ! -x "$w/prog" ]; then
    echo "FAIL flags_build: no binary produced"
    fail=1
else
    "$w/prog" || { echo "FAIL flags_build: linked program failed"; fail=1; }
    [ "$fail" -eq 0 ] && echo "ok   flags_build (${#longflags}-byte --cflags passed through)"
fi

# --- 2) compile path: the Driver parses --cflags and emits C ---------------
if ! "$ct" "$w/prog.ct" --cflags "$longflags" -o "$w/prog2.c" \
        >"$w/comp.out" 2>"$w/comp.err"; then
    echo "FAIL flags_compile: ct-ast rejected a ${#longflags}-byte --cflags value:"
    sed 's/^/    /' "$w/comp.err" | tail -3
    fail=1
else
    "$cc" -Wall -Wextra -std=c99 -DBIG=1 "$w/prog2.c" -o "$w/prog2" \
        >"$w/cc.out" 2>&1 || { echo "FAIL flags_compile: emitted C did not build"; fail=1; }
    [ "$fail" -eq 0 ] && echo "ok   flags_compile (${#longflags}-byte --cflags accepted)"
fi

if [ "$fail" -eq 0 ]; then
    echo "cap_flags: OK (--cflags accumulator)"
    exit 0
fi
echo "cap_flags: FAIL"
exit 1
