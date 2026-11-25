#!/bin/sh
# PH-72-R1 (LANG-3) / S1a-0 C1: the call table is large enough for real
# packages (>= 4096 calls in one build) and now grows past 8192.
#
# Usage: sh test/ast/p72_maxcalls.sh <ct-ast>
set -u
ctast=${1:?usage: p72_maxcalls.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p72mc.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

gen() { # gen <n> <file>
    python3 - "$1" "$2" <<'PY'
import sys
n = int(sys.argv[1])
out = ["int f(int x);", "int main(void) {"]
out += ["    f(%d);" % i for i in range(n)]
out += ["    return 0;", "}"]
open(sys.argv[2], "w").write("\n".join(out) + "\n")
PY
}

gen 3000 "$work/n3000.ct"
mkdir -p "$work/ok"
if ! ( cd "$root" && "$ctast" build --emit-c -o "$work/ok" "$work/n3000.ct" ) >"$work/ok.log" 2>&1; then
    echo "FAIL p72/maxcalls: 3000 calls rejected" >&2
    sed 's/^/  /' "$work/ok.log" | head -4 >&2
    fail=1
fi

# S1a-0 C1: MAX_CALLS is a starting capacity, so 9000 calls (past the old
# 8192 limit) must grow the table instead of reporting an overflow.
gen 9000 "$work/n9000.ct"
mkdir -p "$work/big"
if ! ( cd "$root" && "$ctast" build --emit-c -o "$work/big" "$work/n9000.ct" ) >"$work/big.log" 2>&1; then
    echo "FAIL p72/maxcalls: 9000 calls rejected after MAX_CALLS became growable" >&2
    sed 's/^/  /' "$work/big.log" | head -4 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/maxcalls (4096+ calls, grows past 8192)"
