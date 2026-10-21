#!/usr/bin/env bash
#
# check-all.sh - run every hard gate in one command.
#
# `./test/run.sh` only drives L0 (selfhost/l0/ctc.c); the CT line (selfhost/l1/ctc.ct plus
# selfhost/l2/**) has its own scripts. The 2026-10-17 review found no single
# entry point that runs them all (issues/ci/no-aggregate-gate-entry.md), so this
# wrapper is that entry point.
#
# Hard gates (any failure fails the run):
#   1. ./test/run.sh                             L0 suite (eight layers)
#   2. selfhost/check-goldens.sh                 L1 vs goldens, L1' loop, L1/L2 fixpoint
#   3. selfhost/check-archive.sh                 L2 against the archived oracle (ratchet)
#   4. selfhost/check-m2a.sh                     L1 output byte-identical with L0
#   5. selfhost/ct-tour.sh                       end-to-end tour
#   6. editors/vscode/test/check-grammar.py      editor grammar (21 assertions)
#   7. test/pkg/run.sh                           package manager (Phase 8.1 + 8.2 + 8.3)
#   8. selfhost/check-ast.sh                     AST compiler (Phase 9.1–9.7 + 10.x + 11.x + 12.1:
#                                                probes, corpus equivalence, fixpoint, negatives)
#
# test/acceptance/run.sh reports separately and never blocks: its PENDING entries
# are expected (AGENTS.md section 6), and run.sh's green must keep meaning
# "the compiler is correct", not "the compiler is complete".
#
# Usage:  bash selfhost/check-all.sh
#         CC=clang bash selfhost/check-all.sh

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

# Under -Wall -Wextra, GCC >= 8 also enables -Wformat-truncation and fires on a
# batch of snprintf calls in the frozen L0/L1/L2 sources; Apple clang, the
# baseline compiler for "zero warnings", does not. Wrap GCC so the gates mean the
# same thing on both, without editing the frozen layers (AGENTS.md section 6).
tmpcc="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmpcc"' EXIT HUP INT TERM
if "${CC:-cc}" --version 2>/dev/null | grep -q 'Free Software Foundation'; then
    ccbin="$(command -v "${CC:-cc}")" || ccbin="${CC:-cc}"
    printf '#!/bin/sh\nexec "%s" -Wno-format-truncation "$@"\n' "$ccbin" > "$tmpcc/cc-gcc"
    chmod +x "$tmpcc/cc-gcc"
    CC="$tmpcc/cc-gcc"
    export CC
    printf 'CC is GCC: wrapping it with -Wno-format-truncation (AGENTS.md section 6)\n'
fi

fail=0
nrun=0

banner() {
    printf '\n=============================================================\n%s\n=============================================================\n' "$1"
}

run_gate() {
    label="$1"
    shift
    banner "$label"
    "$@"
    st=$?
    nrun=$((nrun + 1))
    if [ "$st" -ne 0 ]; then
        printf 'FAIL: %s (exit %d)\n' "$label" "$st"
        fail=1
    fi
}

run_gate "1) L0 suite (test/run.sh)" ./test/run.sh
run_gate "2) CT: check-goldens" bash selfhost/check-goldens.sh
run_gate "3) CT: check-archive" bash selfhost/check-archive.sh
run_gate "4) CT: check-m2a" bash selfhost/check-m2a.sh
run_gate "5) CT: ct-tour" bash selfhost/ct-tour.sh
run_gate "6) editor grammar" python3 editors/vscode/test/check-grammar.py
run_gate "7) package manager (Phase 8.1 + 8.2 + 8.3)" bash test/pkg/run.sh
run_gate "8) AST compiler (Phase 9.1–9.7 + 10.x + 11.x + 12.1)" bash selfhost/check-ast.sh

banner "acceptance probes (reported only, never blocking)"
if [ -f test/acceptance/run.sh ]; then
    bash test/acceptance/run.sh || true
else
    printf 'SKIP: test/acceptance/run.sh not present\n'
fi

banner "VERDICT"
if [ "$fail" -eq 0 ]; then
    printf 'check-all: OK (%d hard gates green)\n' "$nrun"
else
    printf 'check-all: FAIL (at least one hard gate failed)\n'
fi
exit "$fail"
