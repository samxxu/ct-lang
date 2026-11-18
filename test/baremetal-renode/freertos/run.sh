#!/bin/sh
# FreeRTOS smoke on the STM32F4 Renode model (PH-67-R3). Linux-only.
set -u
ctast=${1:?usage: run.sh <ct-ast>}
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../../.." && pwd)
armcc=${ARMCC:-arm-none-eabi-gcc}
work="$root/.temp/renode-freertos"
kernel="$root/.temp/FreeRTOS-Kernel"
renode="$root/.temp/renode-linux/renode"

[ "$(uname -s)" = Linux ] || { echo "skip: FreeRTOS probe needs Linux Renode (CI)" >&2; exit 77; }
command -v "$armcc" >/dev/null 2>&1 || { echo "skip: arm-none-eabi-gcc not found" >&2; exit 77; }
[ -x "$renode" ] || { echo "skip: .temp/renode-linux/renode missing" >&2; exit 77; }
[ -d "$kernel" ] || { echo "skip: .temp/FreeRTOS-Kernel missing (CI downloads it)" >&2; exit 77; }

rm -rf "$work"; mkdir -p "$work/c" "$work/out"
( cd "$root" && "$ctast" build --freestanding --emit-c test/baremetal-renode/freertos/prog.ct -o "$work/c" ) >"$work/ct.log" 2>&1 || {
    echo "FAIL: ct build failed" >&2; sed 's/^/  /' "$work/ct.log" >&2; exit 1
}

# Kernel sources are third-party: build them without -Wall/-Wextra. The app
# (startup/board/rtos/prog) stays warning-free.
"$armcc" -mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffreestanding -O1 -w \
    -I "$here" -I "$kernel/include" -I "$kernel/portable/GCC/ARM_CM3" \
    -c "$kernel/tasks.c" -o "$work/tasks.o" || exit 1
"$armcc" -mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffreestanding -O1 -w \
    -I "$here" -I "$kernel/include" -I "$kernel/portable/GCC/ARM_CM3" \
    -c "$kernel/queue.c" -o "$work/queue.o" || exit 1
"$armcc" -mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffreestanding -O1 -w \
    -I "$here" -I "$kernel/include" -I "$kernel/portable/GCC/ARM_CM3" \
    -c "$kernel/list.c" -o "$work/list.o" || exit 1
"$armcc" -mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffreestanding -O1 -w \
    -I "$here" -I "$kernel/include" -I "$kernel/portable/GCC/ARM_CM3" \
    -c "$kernel/portable/GCC/ARM_CM3/port.c" -o "$work/port.o" || exit 1
"$armcc" -mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffreestanding -O1 -w \
    -I "$here" -I "$kernel/include" -I "$kernel/portable/GCC/ARM_CM3" \
    -c "$kernel/portable/MemMang/heap_4.c" -o "$work/heap.o" || exit 1

"$armcc" -mcpu=cortex-m4 -mthumb -mfloat-abi=soft -ffreestanding -nostdlib -O1 \
    -Wall -Wextra -I "$here" -I "$kernel/include" -I "$kernel/portable/GCC/ARM_CM3" \
    -T "$here/link.ld" \
    "$here/startup.c" "$here/board.c" "$here/rtos.c" "$here/libc_min.c" "$work/c/prog.c" \
    "$work/tasks.o" "$work/queue.o" "$work/list.o" "$work/port.o" "$work/heap.o" \
    -o "$work/fw.elf" 2>"$work/cc.log" || {
    echo "FAIL: the cross build failed" >&2; sed 's/^/  /' "$work/cc.log" >&2; exit 1
}
[ -s "$work/cc.log" ] && { echo "FAIL: cross build not warning-free" >&2; sed 's/^/  /' "$work/cc.log" >&2; exit 1; }

HOME="$work/out" timeout 240 "$renode" --disable-gui --plain -P -1 \
    -e "mach create \"stm32f4\"" \
    -e "machine LoadPlatformDescription @platforms/boards/stm32f4_discovery-kit.repl" \
    -e "sysbus LoadELF @$work/fw.elf" \
    -e "sysbus.usart2 CreateFileBackend @$work/out/uart.txt" \
    -e "start" -e "sleep 8" -e "quit" >"$work/renode.log" 2>&1
diff -u "$here/prog.expected.out" "$work/out/uart.txt" >"$work/diff" || {
    echo "FAIL: FreeRTOS UART output differs" >&2
    head -10 "$work/diff" >&2
    od -c "$work/out/uart.txt" 2>/dev/null | head -5 >&2
    tail -10 "$work/renode.log" >&2
    exit 1
}
echo "OK p67/freertos (2 tasks, queue)"
