#!/usr/bin/env bash
# Phase 38 probe: L38-1/2/3 diagnostics and the first positive defer program.
# Usage: bash test/ast/p38_probe.sh <ct-ast-binary>
set -u
CT=${1:?usage: p38_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p38-probe.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

check_neg() {
    name=$1
    msg=$2
    "$CT" check "$root/test/ast/errors/$name.ct" >"$tmp/$name.out" 2>"$tmp/$name.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "FAIL $name: expected non-zero, got 0" >&2
        fail=1
    elif ! grep -Fq "$msg" "$tmp/$name.err"; then
        echo "FAIL $name: missing '$msg'" >&2
        sed 's/^/  /' "$tmp/$name.err" >&2
        fail=1
    fi
}

check_neg p38_goto_cross "a goto cannot cross a block with defer"
check_neg p38_defer_control "a defer block cannot transfer control"
check_neg p38_defer_scope "defer is only allowed inside a function"

"$CT" compile "$root/test/ast/220_defer_order/prog.ct" -o "$tmp/220.c" >"$tmp/220.out" 2>"$tmp/220.err"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL 220_defer_order: compile failed" >&2
    sed 's/^/  /' "$tmp/220.err" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "p38_probe: OK"
fi
exit "$fail"
