#!/bin/sh
# PH-69-E69-2: legal import-bearing units must check cleanly through the unit
# graph. Error tours and the L28-3 fixture (`p28_bound_static`) are excluded:
# the former expect a diagnostic, the latter is a deliberate hard error.
#
# Usage: sh test/ast/p69_fp.sh <ct-ast>
set -u
ctast=${1:?usage: p69_fp.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p69fp.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

n=0
fp=0
for f in $(cd "$root" && find test/ast -name '*.ct' | sort); do
    grep -q '^import ' "$root/$f" 2>/dev/null || continue
    case "$f" in
        */errors/*|*/check_errors/*|*/p48_errors/*|*/p40_return_err/*) continue ;;
        */p52_private/consumer.ct) continue ;;
    esac
    n=$((n+1))
    out=$work/out
    ( cd "$root" && "$ctast" check --types "$f" ) >"$out" 2>&1
    if [ $? -ne 0 ] || [ -s "$out" ]; then
        fp=$((fp+1))
        echo "FAIL p69/fp: $f" >&2
        sed 's/^/  /' "$out" | head -3 >&2
    fi
done

[ "$fp" -eq 0 ] || { echo "FAIL p69/fp: $fp/$n import units not clean" >&2; exit 1; }
echo "OK p69/fp (0 issues in $n import-bearing units)"
