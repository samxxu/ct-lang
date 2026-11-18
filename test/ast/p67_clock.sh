#!/bin/sh
# PH-67-R1: the STM32F4 firmware must configure the PLL (168 MHz) and derive
# the USART BRR from that clock instead of assuming the 16 MHz HSI.
#
# Static part (runs anywhere): the generated C calls clock_init_168() and emits
# a `clk=` line; the board asks for the BRR instead of hard-coding it.
# Runtime part (CI, Renode) is covered by prog.expected.out, which now contains
# `clk=168` and is compared by test/baremetal-renode/run.sh.
#
# Usage: sh test/ast/p67_clock.sh <ct-ast>
set -u
ctast=${1:?usage: p67_clock.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p67clock.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0

( cd "$root" && "$ctast" build --freestanding --emit-c \
    test/baremetal-renode/prog.ct -o "$tmp" ) >"$tmp/build.log" 2>&1 || {
    echo "FAIL p67/clock: ct build failed" >&2
    sed 's/^/  /' "$tmp/build.log" >&2
    exit 1
}

prod=$tmp/prog.c
grep -q 'clock_init_168' "$prod" || {
    echo "FAIL p67/clock: firmware never calls clock_init_168()" >&2
    fail=1
}
grep -q '"clk=' "$prod" || {
    echo "FAIL p67/clock: firmware does not report the clock" >&2
    fail=1
}
grep -q 'uart_brr' "$root/test/baremetal-renode/board.c" || {
    echo "FAIL p67/clock: board.c still hard-codes the BRR" >&2
    fail=1
}
grep -q '^clk=168$' "$root/test/baremetal-renode/prog.expected.out" || {
    echo "FAIL p67/clock: expected output does not pin clk=168" >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p67/clock (168MHz, BRR derived from PCLK)"
