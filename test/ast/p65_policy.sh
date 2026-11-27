#!/usr/bin/env bash
# PH-65 R1 probe, flipped by v1-PH-2 S9: the C boundary policy resolves to the
# right side.
#   every input          -> strict by default (the CT-tree exemption is gone)
#   the working dir      -> not an input (SH-93: an external unit stays strict
#                           even when ct runs from the repo root)
#   a package manifest   -> its `c-boundary` key; no key is strict too
#   the command line     -> wins over all of the above
# Usage: bash test/ast/p65_policy.sh <ct-ast>
set -u
CT=${1:?usage: p65_policy.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65pol.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

mkdir -p "$tmp/ext" "$tmp/allow" "$tmp/strict" "$tmp/old"
printf 'int main(void) { return 0; }\n' >"$tmp/ext/x.ct"
printf 'int main(void) { return 0; }\n' >"$tmp/allow/u.ct"
printf 'int main(void) { return 0; }\n' >"$tmp/strict/v.ct"
printf 'int main(void) { return 0; }\n' >"$tmp/old/w.ct"
printf 'name = demo\nc-boundary = allow\n'  >"$tmp/allow/ct.pkg"
printf 'name = demo\nc-boundary = strict\n' >"$tmp/strict/ct.pkg"
printf 'name = demo\n'                      >"$tmp/old/ct.pkg"

check() {   # check <label> <want> <cmd...>
    local label=$1 want=$2 got
    shift 2
    got=$( cd "$root" && "$@" 2>"$tmp/err" )
    if [ "$got" != "$want" ]; then
        echo "FAIL p65/policy: $label: want '$want', got '$got' ($(head -1 "$tmp/err"))" >&2
        fail=1
    fi
}

check_in() {   # check <label> <want> <dir> <cmd...>
    local label=$1 want=$2 dir=$3 got
    shift 3
    got=$( cd "$dir" && "$@" 2>"$tmp/err" )
    if [ "$got" != "$want" ]; then
        echo "FAIL p65/policy: $label: want '$want', got '$got' ($(head -1 "$tmp/err"))" >&2
        fail=1
    fi
}
check_in "external default" strict "$tmp" "$CT" --show-c-boundary "$tmp/ext/x.ct"
# SH-93 negative: running from the CT repo root must not relax an external
# unit; only the input path decides. S9 removed the directory exemption, so the
# CT tree is strict as well.
check "external from repo root" strict "$CT" --show-c-boundary "$tmp/ext/x.ct"
check_in "CLI allow"        allow  "$tmp" "$CT" --c-boundary=allow --show-c-boundary "$tmp/ext/x.ct"
check "CT tree default"  strict "$CT" --show-c-boundary test/ast/p65_policy/inside.ct
check "selfhost default" strict "$CT" --show-c-boundary selfhost/ct-ast/main.ct
check "lib/core default"  strict "$CT" --show-c-boundary lib/core/Vec.h.ct
check "CLI strict wins"  strict "$CT" --c-boundary=strict --show-c-boundary test/ast/p65_policy/inside.ct
check "package allow"    allow  "$CT" build -I "$tmp/allow" --show-c-boundary "$tmp/allow/u.ct"
check "package strict"   strict "$CT" build -I "$tmp/strict" --show-c-boundary "$tmp/strict/v.ct"
check "old package (no key)" strict "$CT" build -I "$tmp/old" --show-c-boundary "$tmp/old/w.ct"
check "CLI over package" allow "$CT" build -I "$tmp/strict" --c-boundary=allow --show-c-boundary "$tmp/strict/v.ct"

( cd "$root" && "$CT" --c-boundary=nope --show-c-boundary "$tmp/ext/x.ct" >"$tmp/bad.out" 2>"$tmp/bad.err" )
rc=$?
if [ "$rc" -eq 0 ] || ! grep -q "takes strict or allow" "$tmp/bad.err"; then
    echo "FAIL p65/policy: a bad --c-boundary value was not rejected (rc=$rc)" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p65/policy"
exit "$fail"
