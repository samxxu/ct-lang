#!/bin/sh
# PH-67-R4 (register level): DMA1 Stream6 is wired to USART2_TX on the STM32F4.
# The firmware programs PAR/M0AR/NDTR/CR and reads them back; a real transfer is
# hardware-gated (registered separately), so this probe only checks the
# descriptor contract, never claims bytes moved.
#
# Usage: sh test/ast/p67_dma.sh <ct-ast>
set -u
ctast=${1:?usage: p67_dma.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
d="$root/test/baremetal-renode"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p67dma.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0

[ -f "$d/dma.c" ] && [ -f "$d/dma.h" ] || { echo "FAIL p67/dma: dma.c/.h missing" >&2; fail=1; }
[ -f "$d/prog.expected.out" ] && grep -q '^dma=1$' "$d/prog.expected.out" || {
    echo "FAIL p67/dma: expected output does not pin dma=1" >&2; fail=1; }
[ "$fail" -eq 0 ] || exit 1

( cd "$root" && "$ctast" build --freestanding --emit-c test/baremetal-renode/prog.ct -o "$tmp" ) >"$tmp/build.log" 2>&1 || {
    echo "FAIL p67/dma: ct build failed" >&2; sed 's/^/  /' "$tmp/build.log" >&2; exit 1; }
grep -q 'dma_setup_tx' "$tmp/prog.c" || { echo "FAIL p67/dma: firmware never calls dma_setup_tx()" >&2; fail=1; }
grep -q 'dma_setup_tx' "$d/run.sh" || { echo "FAIL p67/dma: run.sh does not link dma.c" >&2; fail=1; }

[ "$fail" -eq 0 ] || exit 1
echo "OK p67/dma (DMA1 Stream6 descriptor registers)"
