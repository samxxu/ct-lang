#!/bin/sh
# PH-67-R3: FreeRTOS on the STM32F4 model. Two tasks exchange three items over
# a queue and the consumer prints them in order; this proves the CT-generated
# program can hand control to a real scheduler (SysTick/PendSV/SVC).
#
# Kernel source is NOT vendored: CI downloads FreeRTOS-Kernel into
# `.temp/FreeRTOS-Kernel`. Without it the probe skips (77).
#
# Usage: sh test/ast/p67_freertos.sh <ct-ast>
set -u
ctast=${1:?usage: p67_freertos.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
d="$root/test/baremetal-renode/freertos"
fail=0

for f in FreeRTOSConfig.h startup.c link.ld board.c board.h rtos.c rtos.h prog.ct prog.expected.out run.sh; do
    [ -f "$d/$f" ] || { echo "FAIL p67/freertos: missing $f" >&2; fail=1; }
done
[ -f "$d/prog.expected.out" ] && grep -q '^q=3$' "$d/prog.expected.out" || {
    echo "FAIL p67/freertos: expected output does not pin q=3" >&2
    fail=1
}
[ "$fail" -eq 0 ] || exit 1

sh "$d/run.sh" "$ctast"
