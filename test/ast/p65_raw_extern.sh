#!/usr/bin/env bash
# PH-65 R3 probe: strict also closes the three bypass channels -- `#ct-raw`,
# `extern` C declarations, and function-like `#define`. An object-like macro
# stays (it is a constant), `.m.ct` stays a mapping unit, and the CT tree plus
# `--c-boundary=allow` keep the old behaviour.
# Usage: bash test/ast/p65_raw_extern.sh <ct-ast>
set -u
CT=${1:?usage: p65_raw_extern.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65raw.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/out"

cat >"$tmp/raw.ct" <<'CT'
#ct-raw
int side = 1;
#ct-endraw
int main(void) { return 0; }
CT
cat >"$tmp/ext.ct" <<'CT'
extern int flag;
int main(void) { return flag; }
CT
cat >"$tmp/fn.ct" <<'CT'
#define F(x) ((x) + 1)
int main(void) { return F(1); }
CT
cat >"$tmp/obj.ct" <<'CT'
#define K 3
int main(void) { return K; }
CT
cat >"$tmp/map.m.ct" <<'CT'
#include <stdint.h>
#define K 3
CT

expect_err() {   # expect_err <label> <needle> <file> [args...]
    local label=$1 needle=$2 file=$3 rc
    shift 3
    ( cd "$tmp" && "$CT" "$@" "$file" -o "$tmp/out/x.c" ) >"$tmp/out/o.log" 2>"$tmp/out/e.log"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        echo "FAIL p65/raw-extern: $label: rc=$rc (want 1)" >&2
        fail=1
        return
    fi
    if ! grep -qF "$needle" "$tmp/out/e.log"; then
        echo "FAIL p65/raw-extern: $label: missing '$needle'" >&2
        sed 's/^/  /' "$tmp/out/e.log" | head -3 >&2
        fail=1
    fi
}

expect_ok() {    # expect_ok <label> <file> [args...]
    local label=$1 file=$2
    shift 2
    if ! ( cd "$tmp" && "$CT" "$@" "$file" -o "$tmp/out/x.c" ) >"$tmp/out/o.log" 2>"$tmp/out/e.log"; then
        echo "FAIL p65/raw-extern: $label: expected success" >&2
        sed 's/^/  /' "$tmp/out/e.log" | head -3 >&2
        fail=1
    fi
}

expect_err "strict #ct-raw" "a strict C boundary forbids #ct-raw" raw.ct
expect_err "strict extern" "a strict C boundary forbids direct C declarations" ext.ct
expect_err "strict function-like #define" "a strict C boundary forbids function-like '#define'" fn.ct
expect_ok  "object-like #define stays" obj.ct
expect_ok  "allow keeps the old behaviour" raw.ct --c-boundary=allow

# `.m.ct` is the mapping boundary: include + object-like macro are fine.
( cd "$tmp" && "$CT" check map.m.ct ) >"$tmp/out/o.log" 2>"$tmp/out/e.log" || {
    echo "FAIL p65/raw-extern: a .m.ct with include + object macro was rejected" >&2
    sed 's/^/  /' "$tmp/out/e.log" | head -3 >&2
    fail=1
}

# The CT tree keeps its behaviour.
( cd "$root" && "$CT" test/ast/p65_raw_extern/inside.ct -o "$tmp/out/core.c" ) \
    >"$tmp/out/o.log" 2>"$tmp/out/e.log" || {
    echo "FAIL p65/raw-extern: the CT tree lost #ct-raw/extern" >&2
    sed 's/^/  /' "$tmp/out/e.log" | head -3 >&2
    fail=1
}

[ "$fail" -eq 0 ] && echo "OK p65/raw-extern"
exit "$fail"
