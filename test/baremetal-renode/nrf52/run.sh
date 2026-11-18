#!/bin/sh
# nRF52840 smoke on Renode (PH-67-R2). Linux-only: the portable Linux Renode
# lives in .temp/renode-linux (downloaded by CI); macOS skips (host Renode
# cannot run inside the agent sandbox).
set -u
ctast=${1:?usage: run.sh <ct-ast>}
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../../.." && pwd)
armcc=${ARMCC:-arm-none-eabi-gcc}
nm=${ARMNM:-arm-none-eabi-nm}
work="$root/.temp/renode-nrf52"
renode="$root/.temp/renode-linux/renode"

[ "$(uname -s)" = Linux ] || { echo "skip: nRF52 probe needs Linux Renode (CI)" >&2; exit 77; }
command -v "$armcc" >/dev/null 2>&1 || { echo "skip: arm-none-eabi-gcc not found" >&2; exit 77; }
[ -x "$renode" ] || { echo "skip: .temp/renode-linux/renode missing" >&2; exit 77; }

rm -rf "$work"; mkdir -p "$work/c" "$work/out"
( cd "$root" && "$ctast" build --freestanding --emit-c test/baremetal-renode/nrf52/prog.ct -o "$work/c" ) >"$work/ct.log" 2>&1 || {
    echo "FAIL: ct build failed" >&2; sed 's/^/  /' "$work/ct.log" >&2; exit 1
}
"$armcc" -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard \
    -ffreestanding -nostdlib -O1 -Wall -Wextra \
    -I "$here" -T "$here/link.ld" \
    "$here/startup.c" "$here/board.c" "$work/c/prog.c" \
    -o "$work/fw.elf" 2>"$work/cc.log" || {
    echo "FAIL: the cross build failed" >&2; sed 's/^/  /' "$work/cc.log" >&2; exit 1
}
[ -s "$work/cc.log" ] && { echo "FAIL: cross build not warning-free" >&2; sed 's/^/  /' "$work/cc.log" >&2; exit 1; }
undef=$("$nm" -u "$work/fw.elf" 2>/dev/null)
[ -n "$undef" ] && { echo "FAIL: unresolved symbols:" >&2; printf '%s\n' "$undef" >&2; exit 1; }

HOME="$work/out" timeout 240 "$renode" --disable-gui --plain -P -1 \
    -e "mach create \"nrf52\"" \
    -e "machine LoadPlatformDescription @platforms/cpus/nrf52840.repl" \
    -e "sysbus LoadELF @$work/fw.elf" \
    -e "sysbus.uart0 CreateFileBackend @$work/out/uart.txt" \
    -e "start" -e "sleep 2" -e "sysbus.cpu" -e "sleep 6" -e "quit" >"$work/renode.log" 2>&1
diff -u "$here/prog.expected.out" "$work/out/uart.txt" >"$work/diff" || {
    echo "FAIL: nRF52840 UART output differs" >&2
    head -10 "$work/diff" >&2
    echo "--- renode log ---" >&2
    sed 's/^/  /' "$work/renode.log" | tail -20 >&2
    od -c "$work/out/uart.txt" 2>/dev/null | head -5 >&2
    exit 1
}
echo "OK p67/nrf52"
