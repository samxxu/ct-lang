#!/bin/sh
# GDB smoke (PH-67-R5): boot the STM32F4 image under Renode with its GDB server
# enabled, attach an ARM GDB, break on main and continue. Linux-only: CI
# installs gdb-multiarch and the portable Renode.
set -u
ctast=${1:?usage: gdb.sh <ct-ast>}
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
armcc=${ARMCC:-arm-none-eabi-gcc}
work="$root/.temp/renode-gdb"
renode="$root/.temp/renode-linux/renode"
gdb=${GDB:-}
[ -n "$gdb" ] || { command -v gdb-multiarch >/dev/null 2>&1 && gdb=gdb-multiarch; }
[ -n "$gdb" ] || { command -v arm-none-eabi-gdb >/dev/null 2>&1 && gdb=arm-none-eabi-gdb; }

[ "$(uname -s)" = Linux ] || { echo "skip: GDB probe needs Linux Renode (CI)" >&2; exit 77; }
command -v "$armcc" >/dev/null 2>&1 || { echo "skip: arm-none-eabi-gcc not found" >&2; exit 77; }
[ -x "$renode" ] || { echo "skip: .temp/renode-linux/renode missing" >&2; exit 77; }
[ -n "$gdb" ] || { echo "skip: no ARM-capable gdb (install gdb-multiarch)" >&2; exit 77; }

rm -rf "$work"; mkdir -p "$work/c" "$work/out"
( cd "$root" && "$ctast" build --freestanding --emit-c test/baremetal-renode/prog.ct -o "$work/c" ) >"$work/ct.log" 2>&1 || {
    echo "FAIL: ct build failed" >&2; sed 's/^/  /' "$work/ct.log" >&2; exit 1
}
"$armcc" -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard \
    -ffreestanding -nostdlib -O1 -Wall -Wextra -I "$here" -T "$here/link.ld" \
    "$here/startup.c" "$here/clock.c" "$here/dma.c" "$here/board.c" "$work/c/prog.c" \
    -o "$work/fw.elf" 2>"$work/cc.log" || {
    echo "FAIL: cross build failed" >&2; sed 's/^/  /' "$work/cc.log" >&2; exit 1
}

# `monitor` commands are not needed: GDB connects to Renode's own server.
"$renode" --disable-gui --plain -P -1 \
    -e "mach create \"stm32f4\"" \
    -e "machine LoadPlatformDescription @platforms/boards/stm32f4_discovery-kit.repl" \
    -e "sysbus LoadELF @$work/fw.elf" \
    -e "machine StartGdbServer 3333" \
    -e "start" >"$work/renode.log" 2>&1 &
rpid=$!
trap 'kill $rpid 2>/dev/null' EXIT HUP INT TERM
i=0
while [ $i -lt 100 ]; do
    grep -q "GDB server" "$work/renode.log" 2>/dev/null && break
    sleep 0.2; i=$((i+1))
done

timeout 60 "$gdb" -q -batch \
    -ex "set confirm off" \
    -ex "target remote :3333" \
    -ex "break main" \
    -ex "continue" \
    -ex "info registers pc" >"$work/gdb.log" 2>&1
rc=$?
kill $rpid 2>/dev/null
if [ $rc -ne 0 ] || ! grep -q "Breakpoint 1" "$work/gdb.log" || ! grep -q "main" "$work/gdb.log"; then
    echo "FAIL: GDB did not stop on main" >&2
    sed 's/^/  /' "$work/gdb.log" | tail -20 >&2
    exit 1
fi
echo "OK p67/gdb (breakpoint main)"
