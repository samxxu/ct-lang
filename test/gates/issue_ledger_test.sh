#!/bin/sh
# Negative fixture for G6 issue_ledger (8.3: a gate change ships with a
# failing fixture). Each bad ledger must turn g6 red with the matching
# diagnostic; the good-only ledger must stay green.
#
# CI-13 ratchet: the same fixtures also prove the baseline behaviours --
# new debt is red, a zombie baseline row is red, a matching row is known and
# green, and strict mode without a baseline stays green.
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

# Tracking fixture: a whitelist must hang on a live issue with exit conditions.
setup_ledger() { # fixture...
    rm -rf "$work/issues"
    mkdir -p "$work/issues"
    cp "$here/issue_ledger/ci-14-tracking.md" "$work/issues/ci-14-tracking.md"
    for name in "$@"; do
        cp "$here/issue_ledger/$name.md" "$work/issues/$name.md"
    done
}

write_baseline() { # extra meta lines (may be empty)
    rm -f "$work/issues/.g6-baseline.tsv"
    if [ -n "${1:-}" ]; then
        printf '%s\n' "$1" > "$work/issues/.g6-baseline.tsv"
    fi
}

run_ratchet() { # expect-rc pattern
    want=$1; pattern=$2
    if python3 "$gate" "$work" --ratchet >"$work/out" 2>"$work/err"; then got=0; else got=1; fi
    if [ "$got" -ne "$want" ]; then
        echo "FAIL g6 ratchet: exit=$got want=$want" >&2
        cat "$work/err" "$work/out" >&2
        fail=1
        return
    fi
    if ! grep -qF "$pattern" "$work/err" "$work/out"; then
        echo "FAIL g6 ratchet: missing diagnostic '$pattern'" >&2
        cat "$work/err" "$work/out" >&2
        fail=1
    fi
}

run_case good 0 "g6: OK"
run_case bad_nonclosed 1 "illegal status"
run_case bad_fixed 1 "must not be a status"
run_case bad_missing 1 "missing status"
run_case bad_mismatch 1 "!= table status"
run_case bad_verified_no_evidence 1 "without evidence"

# --- CI-13 ratchet -------------------------------------------------------
# 1) strict mode without a baseline is still green (the default is unchanged).
setup_ledger good
rm -f "$work/issues/.g6-baseline.tsv"
if ! python3 "$gate" "$work" >"$work/out" 2>"$work/err" ||
   ! grep -qF "g6: OK" "$work/out"; then
    echo "FAIL g6 strict: clean ledger without a baseline must stay green" >&2
    cat "$work/err" "$work/out" >&2
    fail=1
fi

# 2) new debt: a violation absent from an (empty) baseline must be red.
setup_ledger bad_nonclosed
write_baseline "# g6-baseline v1
# tracking: CI-14
path	现状	归一键	类别"
run_ratchet 1 "new debt not in the baseline"

# 3) known debt: a matching baseline row is reported and stays green.
setup_ledger bad_nonclosed
write_baseline "# g6-baseline v1
# tracking: CI-14
path	现状	归一键	类别
issues/bad_nonclosed.md	已修（2026-11-21）	verified	核销类"
run_ratchet 0 "known=1 new=0"

# 4) zombie: the file was normalized/deleted but the row stayed in the baseline.
setup_ledger good
write_baseline "# g6-baseline v1
# tracking: CI-14
path	现状	归一键	类别
issues/bad_nonclosed.md	已修（2026-11-21）	verified	核销类"
run_ratchet 1 "zombie baseline row"

# 5) reduction: --write-baseline drops the row, and the ratchet is green again.
setup_ledger bad_nonclosed
if ! python3 "$gate" "$work" --write-baseline --tracking CI-14 >"$work/out" 2>"$work/err"; then
    echo "FAIL g6 --write-baseline: refused a valid tracking issue" >&2
    cat "$work/err" >&2
    fail=1
elif ! grep -qF "issues/bad_nonclosed.md	已修（2026-11-21）	verified	核销类" "$work/issues/.g6-baseline.tsv"; then
    echo "FAIL g6 --write-baseline: did not record the current violation" >&2
    cat "$work/issues/.g6-baseline.tsv" >&2
    fail=1
else
    run_ratchet 0 "known=1 new=0"
    setup_ledger good
    if ! python3 "$gate" "$work" --write-baseline --tracking CI-14 >"$work/out" 2>"$work/err"; then
        echo "FAIL g6 --write-baseline: clean ledger rewrite failed" >&2
        cat "$work/err" >&2
        fail=1
    elif grep -q "issues/" "$work/issues/.g6-baseline.tsv"; then
        echo "FAIL g6 --write-baseline: clean ledger still has baseline rows" >&2
        cat "$work/issues/.g6-baseline.tsv" >&2
        fail=1
    fi
    run_ratchet 0 "known=0 new=0"
fi

# 6) a baseline without a tracking issue is unusable.
setup_ledger bad_nonclosed
write_baseline "# g6-baseline v1
path	现状	归一键	类别
issues/bad_nonclosed.md	已修（2026-11-21）	verified	核销类"
run_ratchet 1 "no \`# tracking:"

# 7) a tracking issue without 退出条件 is unusable.
setup_ledger good
cat > "$work/issues/ci-14-tracking.md" <<'EOF'
---
id: CI-14
status: open
---

# tracking without exit conditions

This file mentions the g6 gate but deliberately omits the exit-condition
section the ratchet requires, so the baseline must be rejected as unusable.
EOF
write_baseline "# g6-baseline v1
# tracking: CI-14
path	现状	归一键	类别
issues/bad_nonclosed.md	已修（2026-11-21）	verified	核销类"
run_ratchet 1 "no \`退出条件\` section"

[ "$fail" -eq 0 ] && echo "OK g6/ledger (5 negative cases + 1 positive; ratchet 7 cases)"
exit "$fail"
