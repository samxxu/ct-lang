#!/bin/sh
# Negative fixtures for G1/G5 (8.3: a gate change ships with a failing
# fixture). The good card passes both; a card missing frozen fields fails g1;
# an E-ID defined once and never referenced fails g5.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
exe="$root/tools/gates/phase_card.py"
work=$(mktemp -d "${TMPDIR:-/tmp}/g15card.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

run() { # name dir want pattern
    name=$1; dir=$2; want=$3; pattern=$4
    if python3 "$exe" "$root" "$name" --dir "$dir" >"$work/out" 2>"$work/err"; then got=0; else got=1; fi
    if [ "$got" -ne "$want" ]; then
        echo "FAIL gate=$name dir=$dir exit=$got want=$want" >&2
        cat "$work/out" "$work/err" >&2
        fail=1
        return
    fi
    if [ "$want" -ne 0 ] && ! grep -qF "$pattern" "$work/err"; then
        echo "FAIL gate=$name dir=$dir missing diagnostic '$pattern'" >&2
        cat "$work/err" >&2
        fail=1
    fi
}

run g1 "$here/phase_card/good" 0 ""
run g5 "$here/phase_card/good" 0 ""
run g1 "$here/phase_card/bad_missing" 1 "missing/empty"
run g5 "$here/phase_card/bad_eid" 1 "defined but never referenced"

[ "$fail" -eq 0 ] && echo "OK g1/g5 (good + 2 negative cases)"
exit "$fail"
