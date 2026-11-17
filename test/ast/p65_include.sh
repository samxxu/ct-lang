#!/usr/bin/env bash
# PH-65 R2 probe: strict `.ct` / `.h.ct` reject a direct `#include`; the only
# include a strict unit may write is its own `<base>.shim.h`. The CT tree and
# `--c-boundary=allow` keep the old behaviour.
# Usage: bash test/ast/p65_include.sh <ct-ast>
set -u
CT=${1:?usage: p65_include.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65inc.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

mkdir -p "$tmp/strict" "$tmp/own" "$tmp/other" "$tmp/hdr" "$tmp/allow" "$tmp/out"

cat >"$tmp/strict/bad.ct" <<'CT'
#include <stdio.h>

int main(void) { return 0; }
CT
cat >"$tmp/own/good.ct" <<'CT'
#include "good.shim.h"

int main(void) { return 0; }
CT
cat >"$tmp/other/o.ct" <<'CT'
#include "notmine.shim.h"

int main(void) { return 0; }
CT
cat >"$tmp/hdr/h.h.ct" <<'CT'
#include <stdint.h>
CT
cat >"$tmp/allow/a.ct" <<'CT'
#include <stdio.h>

int main(void) { return 0; }
CT

expect_err() {   # expect_err <label> <want-line> <file> [extra args...]
    local label=$1 want=$2 file=$3 out rc
    shift 3
    ( cd "$root" && "$CT" "$@" "$file" -o "$tmp/out/x.c" ) >"$tmp/out/o.log" 2>"$tmp/out/e.log"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        echo "FAIL p65/include: $label: rc=$rc (want 1)" >&2
        fail=1
        return
    fi
    if ! grep -q "a strict C boundary forbids '#include'; use .m.ct or <base>.shim.h" "$tmp/out/e.log"; then
        echo "FAIL p65/include: $label: no boundary message" >&2
        sed 's/^/  /' "$tmp/out/e.log" | head -3 >&2
        fail=1
        return
    fi
    if ! grep -q ":$want:1: error:" "$tmp/out/e.log"; then
        echo "FAIL p65/include: $label: message is not at line $want" >&2
        head -2 "$tmp/out/e.log" >&2
        fail=1
    fi
}

expect_ok() {    # expect_ok <label> <file> [extra args...]
    local label=$1 file=$2
    shift 2
    if ! ( cd "$root" && "$CT" "$@" "$file" -o "$tmp/out/x.c" ) >"$tmp/out/o.log" 2>"$tmp/out/e.log"; then
        echo "FAIL p65/include: $label: expected success" >&2
        sed 's/^/  /' "$tmp/out/e.log" | head -3 >&2
        fail=1
    fi
}

expect_err "strict .ct system include" 1 "$tmp/strict/bad.ct"
expect_err "strict .h.ct system include" 1 "$tmp/hdr/h.h.ct"
expect_err "foreign shim name" 1 "$tmp/other/o.ct"
expect_ok  "own shim allowed" "$tmp/own/good.ct"
expect_ok  "allow keeps old behaviour" "$tmp/allow/a.ct" --c-boundary=allow
expect_ok  "CT tree keeps old behaviour" test/ast/p65_include/inside.ct

[ "$fail" -eq 0 ] && echo "OK p65/include"
exit "$fail"
