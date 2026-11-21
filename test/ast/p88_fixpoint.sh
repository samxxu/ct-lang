#!/usr/bin/env bash
# PH-88 S88b probe: the self-hosting fixpoint is parameterised by rounds.
#
# D-017 (A1) and D-88 make the round count the only parameter: a daily run
# uses two rounds, a tag candidate three. The comparison may not fork, so
# `check-ast.sh` keeps one `fixpoint_stage` function (one `diff -r`) and the
# round count just bounds its loop. This probe:
#   1) checks the single implementation and the 2/3-only default;
#   2) runs the real stage for 2 and for 3 rounds against the given compiler
#      and requires "byte-identical" both times;
#   3) rejects an out-of-range round count (the parameter is not a silent
#      no-op).
#
# Usage: bash test/ast/p88_fixpoint.sh <ct-ast>
set -u
CT=${1:?usage: p88_fixpoint.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p88fix.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p88fixpoint: $1" >&2; }

script=selfhost/check-ast.sh
if [ ! -f "$script" ]; then
    echo "FAIL p88fixpoint: $script is missing" >&2
    exit 1
fi

# 1) one implementation, two allowed counts, and the daily default
grep -q 'CT_FIXPOINT_ROUNDS:-2' "$script" \
    && ok || bad "the daily default is not 2 (CT_FIXPOINT_ROUNDS:-2)"
if [ "$(grep -c '^fixpoint_stage()' "$script")" -eq 1 ] \
   && [ "$(grep -c 'diff -r -q -x .ctcache' "$script")" -eq 1 ]; then
    ok; echo "  p88fixpoint: one fixpoint_stage, one diff -r"
else
    bad "the fixpoint comparison forked (fixpoint_stage or diff -r count)"
fi
if grep -q 'fixpoint_stage "\$work/ct-ast" "\$FIXPOINT_ROUNDS"' "$script"; then
    ok
else
    bad "the ordinary gate does not call the parameterised stage"
fi

# The probe must fail fast on a tree without the parameterised entry, not run
# the whole legacy gate in its default mode.
if ! grep -q -- '--fixpoint-only' "$script"; then
    echo "FAIL p88fixpoint: check-ast.sh has no --fixpoint-only entry" >&2
    exit 1
fi

# 2) the real stage, 2 and 3 rounds
run_rounds() {
    rounds="$1"
    if CT_FIXPOINT_ROUNDS="$rounds" bash "$script" --fixpoint-only "$CT" \
            >"$tmp/$rounds.out" 2>"$tmp/$rounds.err"; then
        if grep -q "fixpoint: $rounds rounds byte-identical" "$tmp/$rounds.out"; then
            ok; echo "  p88fixpoint: $rounds rounds byte-identical"
        else
            bad "$rounds rounds: unexpected output: $(head -2 "$tmp/$rounds.out" | tr '\n' ' ')"
        fi
    else
        bad "$rounds rounds failed: $(head -2 "$tmp/$rounds.err" | tr '\n' ' ')"
    fi
}
run_rounds 2
run_rounds 3

# 3) an out-of-range count is rejected, not silently clamped
if CT_FIXPOINT_ROUNDS=4 bash "$script" --fixpoint-only "$CT" \
        >"$tmp/bad.out" 2>"$tmp/bad.err"; then
    bad "4 rounds was accepted"
elif [ "$?" -eq 2 ] && grep -q 'must be 2 or 3' "$tmp/bad.err"; then
    ok; echo "  p88fixpoint: 4 rounds is rejected"
else
    bad "4 rounds failed for the wrong reason: $(head -2 "$tmp/bad.err" | tr '\n' ' ')"
fi

echo "p88fixpoint: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
