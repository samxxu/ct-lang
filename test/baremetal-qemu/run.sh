#!/bin/sh
# Bare-metal smoke on QEMU's Cortex-M3 model (TEST-20).
#
# `ct build --freestanding --emit-c` produces the C, arm-none-eabi-gcc links it
# against startup.c/board.c with a flash/RAM linker script, and qemu-system-arm
# boots the ELF. The expected output proves three things at once:
#   boot ok  -> reset path (.data/.bss) and UART reached main
#   tick=3   -> the SysTick vector really fires, with an ISR written in C next
#               to CT-generated code
#   exit 0   -> SYS_EXIT_EXTENDED ran, so nothing hung and no `cc -nostdlib`
#               symbol was missing
#
# Usage: sh test/baremetal-qemu/run.sh <ct-ast>
# Exit: 0 ok, 1 failed, 77 skipped (toolchain or QEMU absent).
set -u
ctast=${1:?usage: run.sh <ct-ast>}
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
armcc=${ARMCC:-arm-none-eabi-gcc}
qemu=${QEMU:-qemu-system-arm}
nm=${ARMNM:-arm-none-eabi-nm}

for t in "$armcc" "$qemu" "$nm"; do
    if ! command -v "$t" >/dev/null 2>&1; then
        echo "skip: '$t' not found (install arm-none-eabi-gcc and qemu)" >&2
        exit 77
    fi
done

work=$(mktemp -d "${TMPDIR:-/tmp}/bmqemu.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/c"
if ! ( cd "$root" && "$ctast" build --freestanding --emit-c \
        test/baremetal-qemu/prog.ct -o "$work/c" ) >"$work/ct.log" 2>&1; then
    echo "FAIL: ct build failed" >&2
    sed 's/^/  /' "$work/ct.log" >&2
    exit 1
fi
if [ ! -f "$work/c/prog.c" ]; then
    echo "FAIL: no prog.c in the product" >&2
    exit 1
fi
# The freestanding promise: no implicit libc header reaches the product.
if grep -q '#include *<' "$work/c/prog.c"; then
    echo "FAIL: --freestanding product still includes a system header:" >&2
    grep -n '#include *<' "$work/c/prog.c" | head -3 >&2
    exit 1
fi

if ! "$armcc" -mcpu=cortex-m3 -mthumb -ffreestanding -nostdlib -O1 \
        -Wall -Wextra -I "$here" -T "$here/link.ld" \
        "$here/startup.c" "$here/board.c" "$work/c/prog.c" \
        -o "$work/fw.elf" 2>"$work/cc.log"; then
    echo "FAIL: the cross build failed" >&2
    sed 's/^/  /' "$work/cc.log" >&2
    exit 1
fi
if [ -s "$work/cc.log" ]; then
    echo "FAIL: the cross build was not warning-free" >&2
    sed 's/^/  /' "$work/cc.log" >&2
    exit 1
fi

undef=$("$nm" -u "$work/fw.elf" 2>/dev/null)
if [ -n "$undef" ]; then
    echo "FAIL: the image needs symbols the target cannot provide:" >&2
    printf '%s\n' "$undef" | head -5 >&2
    exit 1
fi

timeout 10 "$qemu" -M lm3s6965evb -display none -monitor none -serial stdio \
    -semihosting-config enable=on,target=native -kernel "$work/fw.elf" \
    >"$work/out.txt" 2>"$work/qemu.err"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL: qemu exited $rc (124 = timeout: the image hung)" >&2
    sed 's/^/  /' "$work/qemu.err" | head -3 >&2
    exit 1
fi
if ! diff -u "$here/prog.expected.out" "$work/out.txt" >"$work/diff"; then
    echo "FAIL: the guest output differs" >&2
    head -20 "$work/diff" >&2
    exit 1
fi
echo "OK baremetal-qemu"
exit 0
