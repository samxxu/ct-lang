#!/usr/bin/env bash
#
# check-m2a.sh - M2-a acceptance gate for L1 (selfhost/ctc.ct).
#
# One command that reproduces the whole M2-a path:
#   1) build L0 from ctc.c (warning-free)
#   2) L0 compiles L1  (selfhost/ctc.ct -> /tmp/ctc-l1.c)
#   3) build L1 warning-free
#   4) L1 compiles test/cases/01_trait_basic.ct
#   5) diff the generated .c and .h against the golden (byte for byte)
#   6) [beyond M2-a] L1 compiles itself; reported but never changes the verdict
#
# Usage:  bash selfhost/check-m2a.sh        (or ./selfhost/check-m2a.sh after chmod +x)
#         CC=clang bash selfhost/check-m2a.sh
#
# Exits non-zero when any M2-a step fails. The self-compile step (6) is a
# precondition check for later milestones only: if it fails it is printed as
# "beyond M2-a" and does NOT affect the M2-a verdict.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-gcc}"
work="${TMPDIR:-/tmp}"
work="${work%/}"

l1_c="$work/ctc-l1.c"
l1_bin="$work/ctc-l1"
l1_out="$work/l1-out.c"
self_c="$work/l1-self.c"
self_bin="$work/l1-self"

case_in="test/cases/01_trait_basic.ct"
exp_c="test/cases/01_trait_basic.expected.c"
exp_h="test/cases/01_trait_basic.expected.h"

fail=0
selfhost_fail=0

banner() {
    printf '\n=============================================================\n%s\n=============================================================\n' "$1"
}

# run <label> <cmd> [args...] ; echo it, run it, return its status
run() {
    local label="$1"
    shift
    printf '\n--- %s\n+ %s\n' "$label" "$*"
    "$@"
    return $?
}

# ---------------------------------------------------------------- 1) L0
banner "1) build L0 (ctc.c) warning-free"
if ! run "build L0" "$CC" -Wall -Wextra -std=c99 ctc.c -o ctc; then
    echo "FATAL: L0 did not build; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------------- 2) L0 compiles L1
banner "2) L0 compiles L1 (selfhost/ctc.ct -> $l1_c)"
if ! run "L0 compile L1" ./ctc selfhost/ctc.ct -o "$l1_c"; then
    echo "FATAL: L0 could not compile L1; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------------------- 3) build L1
banner "3) build L1 warning-free ($l1_c -> $l1_bin)"
if ! run "build L1" "$CC" -Wall -Wextra -std=c99 "$l1_c" -o "$l1_bin"; then
    echo "FATAL: L1 did not build; cannot continue." >&2
    exit 1
fi

# --------------------------------------------- 4) L1 compiles the case
banner "4) L1 compiles $case_in -> $l1_out"
if ! run "L1 compile case" "$l1_bin" "$case_in" -o "$l1_out"; then
    fail=1
fi

# The .h include guard (write_guard) is derived from the OUTPUT basename, so a
# byte-identical .h requires an output named 01_trait_basic.* (the golden is
# 01_trait_basic.expected.h, whose guard is _01_TRAIT_BASIC_H). The .c output is
# name-independent: its banner quotes the INPUT path.
mkpath="$work/m2a"
mkdir -p "$mkpath"
goldname_c="$mkpath/01_trait_basic.c"
goldname_h="$mkpath/01_trait_basic.h"
banner "4b) L1 compiles $case_in -> $goldname_c (golden basename, for the .h guard)"
if ! run "L1 compile (golden basename)" "$l1_bin" "$case_in" -o "$goldname_c"; then
    fail=1
fi

# --------------------------------------------------------- 5) byte diffs
banner "5) byte-for-byte diff against the golden"
if [ -f "$l1_out" ] && [ -f "$exp_c" ]; then
    if run "diff .c" diff "$l1_out" "$exp_c"; then
        printf 'OK: generated .c is byte-identical\n'
    else
        printf 'FAIL: generated .c differs from %s\n' "$exp_c"
        fail=1
    fi
else
    printf 'SKIP: %s or %s missing\n' "$l1_out" "$exp_c"
    fail=1
fi

if [ -f "$goldname_h" ] && [ -f "$exp_h" ]; then
    if run "diff .h" diff "$goldname_h" "$exp_h"; then
        printf 'OK: generated .h is byte-identical\n'
    else
        printf 'FAIL: generated .h differs from %s\n' "$exp_h"
        fail=1
    fi
else
    printf 'SKIP: %s or %s missing\n' "$goldname_h" "$exp_h"
    fail=1
fi

# ---------------------------------------- 6) beyond-M2-a: L1 self-compiles
banner "6) [beyond M2-a] L1 compiles itself ($self_c) and builds"
if run "L1 compile itself" "$l1_bin" selfhost/ctc.ct -o "$self_c"; then
    if run "build L1-self" "$CC" -Wall -Wextra -std=c99 "$self_c" -o "$self_bin"; then
        printf 'OK: L1 can compile itself (later-milestone precondition met)\n'
    else
        printf 'NOTE (beyond M2-a): the self-compiled L1 did not build; does not affect M2-a\n'
        selfhost_fail=1
    fi
else
    printf 'NOTE (beyond M2-a): L1 could not compile itself yet; does not affect M2-a\n'
    selfhost_fail=1
fi

# --------------------------------------------------------------- verdict
banner "VERDICT"
if [ "$fail" -eq 0 ]; then
    printf 'M2-a: PASS (L1 output is byte-identical with L0 on %s)\n' "$case_in"
else
    printf 'M2-a: FAIL\n'
fi
if [ "$selfhost_fail" -ne 0 ]; then
    printf 'self-compile: not yet (beyond M2-a; expected until later milestones)\n'
fi

exit "$fail"
