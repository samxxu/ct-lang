#!/bin/sh
# PH-67-R2: a second vendor. The same CT program must boot on Renode's
# nRF52840 model (flash at 0x0, UART0 at 0x40002000) and print a marker.
#
# Usage: sh test/ast/p67_nrf52.sh <ct-ast>
# 0 = pass, 77 = skipped (no Linux Renode / cross toolchain), 1 = fail.
set -u
ctast=${1:?usage: p67_nrf52.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
d="$root/test/baremetal-renode/nrf52"
fail=0

for f in link.ld startup.c board.c prog.ct prog.expected.out run.sh; do
    [ -f "$d/$f" ] || { echo "FAIL p67/nrf52: missing $f" >&2; fail=1; }
done
[ -f "$d/prog.expected.out" ] && grep -q '^mcu=nrf52$' "$d/prog.expected.out" || {
    echo "FAIL p67/nrf52: expected output does not pin mcu=nrf52" >&2
    fail=1
}
[ "$fail" -eq 0 ] || exit 1

sh "$d/run.sh" "$ctast"
