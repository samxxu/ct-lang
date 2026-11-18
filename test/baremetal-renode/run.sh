#!/bin/sh
# STM32F4 Discovery smoke on Renode (TEST-21).
#
# `ct build --freestanding --emit-c` produces the C; arm-none-eabi-gcc links it
# against a self-contained startup (vector table, .data/.bss) and the STM32F407
# linker script; Renode boots the ELF on its Discovery-kit model and UART2 is
# written to a file the probe compares.
#
# Renode needs to write its user directory, which is outside this workspace.
# Two supported arrangements:
#   RENODE_MODE=podman (default when available): run the Linux portable Renode
#     from `.temp/renode-linux/` inside podman; every write stays in the
#     workspace, so no host permissions are needed.
#   RENODE_MODE=host: run the host `renode` (the caller must have prepared
#     `dotnet` + a writable ~/Library/Application Support/renode; the agent
#     sandbox cannot do that).
# Missing toolchain/Renode => exit 77 (skip), never a silent pass.
#
# Usage: sh test/baremetal-renode/run.sh <ct-ast>
set -u
ctast=${1:?usage: run.sh <ct-ast>}
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
armcc=${ARMCC:-arm-none-eabi-gcc}
nm=${ARMNM:-arm-none-eabi-nm}
mode=${RENODE_MODE:-auto}
work="$root/.temp/renode-run"

if ! command -v "$armcc" >/dev/null 2>&1 || ! command -v "$nm" >/dev/null 2>&1; then
    echo "skip: arm-none-eabi-gcc/arm-none-eabi-nm not found" >&2
    exit 77
fi

case "$mode" in
    auto)
        # Linux CI runs the portable Linux build directly; on macOS the same
        # tarball can only run inside a Linux container.
        if [ -x "$root/.temp/renode-linux/renode" ] && [ "$(uname -s)" = Linux ]; then
            mode=local
        elif [ "$(uname -s)" = Darwin ] && command -v podman >/dev/null 2>&1 \
             && [ -x "$root/.temp/renode-linux/renode" ]; then
            mode=podman
        else
            mode=host
        fi
        ;;
esac
if [ "$mode" = host ] && ! command -v renode >/dev/null 2>&1; then
    echo "skip: 'renode' not found (or set RENODE_MODE=podman with .temp/renode-linux)" >&2
    exit 77
fi
# Inside the podman VM of this macOS host Renode does not get past platform
# load (20+ minutes without a machine); keep local gates fast and explicit.
if [ "$mode" = podman ] && [ -z "${CI:-}" ] && [ "${RENODE_ALLOW_SLOW:-0}" != 1 ]; then
    echo "skip: container Renode is known-slow here; set RENODE_ALLOW_SLOW=1 to try" >&2
    exit 77
fi
if { [ "$mode" = podman ] || [ "$mode" = local ]; } && [ ! -x "$root/.temp/renode-linux/renode" ]; then
    echo "skip: .temp/renode-linux/renode missing (see test/baremetal-renode/README.md)" >&2
    exit 77
fi

rm -rf "$work"
mkdir -p "$work/c" "$work/home" "$work/out"

if ! ( cd "$root" && "$ctast" build --freestanding --emit-c \
        test/baremetal-renode/prog.ct -o "$work/c" ) >"$work/ct.log" 2>&1; then
    echo "FAIL: ct build failed" >&2
    sed 's/^/  /' "$work/ct.log" >&2
    exit 1
fi
[ -f "$work/c/prog.c" ] || { echo "FAIL: no prog.c in the product" >&2; exit 1; }
if grep -q '#include *<' "$work/c/prog.c"; then
    echo "FAIL: --freestanding product still includes a system header:" >&2
    grep -n '#include *<' "$work/c/prog.c" | head -3 >&2
    exit 1
fi

if ! "$armcc" -mcpu=cortex-m4 -mthumb -mfpu=fpv4-sp-d16 -mfloat-abi=hard \
        -ffreestanding -nostdlib -O1 -Wall -Wextra \
        -I "$here" -T "$here/link.ld" \
        "$here/startup.c" "$here/clock.c" "$here/board.c" "$work/c/prog.c" \
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

if [ "$mode" = local ]; then
    HOME="$work/home" timeout 300 "$root/.temp/renode-linux/renode" --disable-gui --plain -P -1 \
        -e "mach create \"stm32f4\"" \
        -e "machine LoadPlatformDescription @platforms/boards/stm32f4_discovery-kit.repl" \
        -e "sysbus LoadELF @$work/fw.elf" \
        -e "sysbus.usart2 CreateFileBackend @$work/out/uart.txt" \
        -e "start" -e "sleep 8" -e "quit" \
        >"$work/renode.log" 2>&1
    rc=$?
elif [ "$mode" = podman ]; then
    # The portable Renode is self-contained (bundled .NET); HOME is redirected
    # into the mounted workspace so nothing is written to the container's root.
    timeout 300 podman run --rm --platform linux/arm64 \
        -v "$root":/src:ro -v "$work/out":/w -v "$work/home":/h -e HOME=/h \
        docker.io/library/ubuntu:24.04 \
        /src/.temp/renode-linux/renode --disable-gui --plain -P -1 \
        -e "mach create \"stm32f4\"" \
        -e "machine LoadPlatformDescription @platforms/boards/stm32f4_discovery-kit.repl" \
        -e "sysbus LoadELF @/w/fw.elf" \
        -e "sysbus.usart2 CreateFileBackend @/w/uart.txt" \
        -e "start" -e "sleep 8" -e "quit" \
        >"$work/renode.log" 2>&1
    rc=$?
else
    cp "$work/fw.elf" "$work/out/fw.elf"
    timeout 300 renode --disable-gui --plain -P -1 \
        -e "mach create \"stm32f4\"" \
        -e "machine LoadPlatformDescription @platforms/boards/stm32f4_discovery-kit.repl" \
        -e "sysbus LoadELF @$work/fw.elf" \
        -e "sysbus.usart2 CreateFileBackend @$work/out/uart.txt" \
        -e "start" -e "sleep 8" -e "quit" \
        >"$work/renode.log" 2>&1
    rc=$?
fi
# Renode's quit may not terminate promptly on slow hosts; the UART file is the
# judged artefact, so only a run without output is a failure.
if [ "$rc" -eq 124 ] && [ ! -s "$work/out/uart.txt" ]; then
    echo "FAIL: Renode produced no output within the 8s window" >&2
    sed 's/^/  /' "$work/renode.log" | tail -6 >&2
    exit 1
fi
# A host that cannot write Renode's user directory or its JIT pages is an
# environment gap, not a firmware failure: report skip with the hint.
if [ ! -s "$work/out/uart.txt" ] && grep -qE "config\.lock|UnauthorizedAccess|Code Signature|denied" "$work/renode.log" 2>/dev/null; then
    echo "skip: host Renode cannot use its user directory/JIT (run it outside the agent sandbox)" >&2
    exit 77
fi
if ! diff -u "$here/prog.expected.out" "$work/out/uart.txt" >"$work/diff"; then
    echo "FAIL: the guest UART output differs ($mode mode)" >&2
    head -20 "$work/diff" >&2
    echo "--- uart bytes ---" >&2
    od -c "$work/out/uart.txt" 2>/dev/null | head -10 >&2
    exit 1
fi
echo "OK baremetal-renode ($mode)"
exit 0
