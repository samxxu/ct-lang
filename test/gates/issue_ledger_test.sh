#!/bin/sh
# Negative fixture for G6 issue_ledger (8.3: a gate change ships with a
# failing fixture). Each bad ledger must turn g6 red with the matching
# diagnostic; the good-only ledger must stay green.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/g6ledger.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
gate="$root/tools/gates/issue_ledger.py"
fail=0

run_case() { # name expected-rc pattern
    name=$1; want=$2; pattern=$3
    mkdir -p "$work/issues"
    rm -f "$work/issues"/*.md
    cp "$here/issue_ledger/$name.md" "$work/issues/$name.md"
    if python3 "$gate" "$work" >"$work/out" 2>"$work/err"; then got=0; else got=1; fi
    if [ "$got" -ne "$want" ]; then
        echo "FAIL g6 negative: $name exit=$got want=$want" >&2
        cat "$work/err" >&2
        fail=1
        return
    fi
    if ! grep -qF "$pattern" "$work/err" "$work/out"; then
        echo "FAIL g6 negative: $name missing diagnostic '$pattern'" >&2
        cat "$work/err" >&2
        fail=1
    fi
}

run_case good 0 "g6: OK"
run_case bad_nonclosed 1 "illegal status"
run_case bad_fixed 1 "must not be a status"
run_case bad_missing 1 "missing status"
run_case bad_mismatch 1 "!= table status"
run_case bad_verified_no_evidence 1 "without evidence"

[ "$fail" -eq 0 ] && echo "OK g6/ledger (5 negative cases + 1 positive)"
exit "$fail"
