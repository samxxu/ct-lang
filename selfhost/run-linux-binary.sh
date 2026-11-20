#!/bin/sh
# PH-83 / S83d: run an x86-64 Linux binary on this host.
#
#   sh selfhost/run-linux-binary.sh <binary> [args...]
#
# On a Linux host it runs the binary directly. On macOS (or any non-Linux
# host) it boots the cached Alpine kernel + static busybox under
# qemu-system-x86_64, adds the binary to a one-shot initramfs and runs it with
# the given arguments; stdout is forwarded and the exit status is the binary's.
#
# Assets (not in git; see docs/dist.md for the download commands):
#   $CT_LINUX_ASSETS/vmlinuz     (default .temp/ph83/linux/vmlinuz)
#   $CT_LINUX_ASSETS/busybox     (default .temp/ph83/linux/busybox)
#
# Exit: the binary's status; 77 when no Linux host and no cached kernel/busybox
# (or no qemu-system-x86_64/cpio/gzip), so callers can report `skip`, never a
# silent green.
set -u
bin=${1:?usage: run-linux-binary.sh <binary> [args...]}
[ $# -gt 0 ] && shift
case "$bin" in
    /*) ;;
    *) bin=$(cd -- "$(dirname -- "$bin")" && pwd)/$(basename -- "$bin") ;;
esac
[ -x "$bin" ] || { echo "run-linux-binary: not executable: $bin" >&2; exit 2; }

if [ "$(uname -s)" = "Linux" ]; then
    exec "$bin" "$@"
fi

root=$(cd -- "$(dirname -- "$0")/.." && pwd)
assets=${CT_LINUX_ASSETS:-$root/.temp/ph83/linux}
kernel="$assets/vmlinuz"
busybox="$assets/busybox"
qemu=${QEMU:-qemu-system-x86_64}
for f in "$kernel" "$busybox"; do
    [ -f "$f" ] || {
        echo "run-linux-binary: no Linux kernel/busybox at $assets" >&2
        echo "  see docs/dist.md for the two curl commands (or run on Linux)" >&2
        exit 77
    }
done
for t in "$qemu" cpio gzip; do
    command -v "$t" >/dev/null 2>&1 || {
        echo "run-linux-binary: missing $t (needed for the QEMU boot smoke)" >&2
        exit 77
    }
done

tmp=$(mktemp -d "${TMPDIR:-/tmp}/linuxrun.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
r="$tmp/root"
mkdir -p "$r/bin" "$r/dev" "$r/proc" "$r/sys"
cp "$busybox" "$r/bin/busybox"
chmod +x "$r/bin/busybox"
for a in sh mount poweroff; do ln -sf busybox "$r/bin/$a"; done
# Keep the binary's own basename: `ct` vs `ctc` selects the entry identity and
# therefore the `-v` banner, which is exactly what the artefact smoke checks.
name=$(basename -- "$bin")
case "$name" in
    '' | *[!A-Za-z0-9._-]*) name=target ;;
esac
cp "$bin" "$r/bin/$name"
chmod +x "$r/bin/$name"
# Quote the arguments for the initramfs shell; the only caller passes `-v`.
qargs=
for a in "$@"; do
    esc=$(printf '%s' "$a" | sed "s/'/'\\\\''/g")
    qargs="$qargs '$esc'"
done
cat >"$r/init" <<EOF
#!/bin/sh
/bin/mount -t devtmpfs dev /dev
/bin/mount -t proc proc /proc
echo PH83-BOOT
/bin/$name$qargs
echo PH83-RC=\$?
/bin/poweroff -f
EOF
chmod +x "$r/init"
( cd "$r" && find . -print | cpio -o -H newc 2>/dev/null | gzip -9 ) >"$tmp/initrd.gz" || exit 1

timeout 180 "$qemu" -m 256 -kernel "$kernel" -initrd "$tmp/initrd.gz" \
    -append "console=ttyS0 rdinit=/init panic=-1" -nographic -no-reboot \
    >"$tmp/boot.log" 2>&1
qrc=$?
if [ "$qrc" -ne 0 ]; then
    echo "run-linux-binary: qemu exited $qrc" >&2
    tail -20 "$tmp/boot.log" >&2
    exit 1
fi
# Keep only the binary's own stdout on the caller's stdout.
# The serial console may add CR; normalise once before parsing.
tr -d '\r' <"$tmp/boot.log" >"$tmp/boot.clean"
rc=$(awk -F= '/^PH83-RC=/{print $2;exit}' "$tmp/boot.clean")
[ -n "$rc" ] || { echo "run-linux-binary: no PH83-RC marker in the boot log" >&2; exit 1; }
awk '/^PH83-BOOT$/{f=1;next} /^PH83-RC=/{f=0} f' "$tmp/boot.clean"
exit "$rc"
