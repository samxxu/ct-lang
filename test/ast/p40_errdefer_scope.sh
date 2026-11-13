#!/usr/bin/env bash
# R2 probe: errdefer scope/control/own/goto diagnostics (L40-5..8).
set -u
CT=${1:?usage: p40_errdefer_scope.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fail=0
n=0
neg() {
    n=$((n + 1))
    f="$root/test/ast/errors/$1"
    msg=$2
    "$CT" check "$f" >"$root/.p40r2.$n.out" 2>"$root/.p40r2.$n.err"
    rc=$?
    rm -f "$root/.p40r2.$n.out"
    if [ "$rc" -eq 0 ]; then
        echo "FAIL p40/r2 $1: expected non-zero" >&2
        fail=1
    elif ! grep -Fq -- "$msg" "$root/.p40r2.$n.err"; then
        echo "FAIL p40/r2 $1: missing '$msg'" >&2
        sed 's/^/  /' "$root/.p40r2.$n.err" >&2
        fail=1
    fi
    rm -f "$root/.p40r2.$n.err"
}
neg p40_errdefer_switch/prog.ct 'errdefer is not allowed here'
neg p40_errdefer_header/prog.h.ct 'errdefer is not allowed here'
neg p40_errdefer_file/prog.ct 'errdefer is not allowed here'
neg p40_errdefer_control/prog.ct 'an errdefer block cannot transfer control'
neg p40_errdefer_own/prog.ct 'an own object cannot be rolled back by errdefer'
neg p40_errdefer_goto/prog.ct 'a goto cannot cross a block with errdefer'
if [ "$fail" -eq 0 ]; then echo "p40_r2: OK"; fi
exit "$fail"
