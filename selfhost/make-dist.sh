#!/bin/sh
# PH-83 / S83d: build the Linux x64 distribution artefact.
#
#   bash selfhost/make-dist.sh [--out <dir>] [--cross <zig>] [--no-smoke]
#
# Pipeline (same bootstrap as check-ast.sh):
#   L0 (cc) -> L1.c -> L1 -> L2.c -> L2 -> astsrc/*.c -> target ct
# The target compiler is either the host's cc on Linux, or a cross compiler
# (zig cc -target x86_64-linux-musl -static) so a macOS host can still produce
# a real Linux ELF. The artefact is:
#
#   <out>/ct-linux-x64.tar.gz     contains `ct` and the `ctc` -> ct symlink
#   <out>/ct-linux-x64.tar.gz.sha256
#
# Environment:
#   CC          host bootstrap compiler (default cc)
#   ZIG         zig executable; enables the static musl cross build
#   CT_LINUX_ASSETS  dir with vmlinuz + busybox for the QEMU smoke (see docs/dist.md)
#
# Exit: 0 artefact written (smoke may print UNVERIFIED); 2 usage; 1 build/smoke
# failed. The version is whatever CTC_VERSION says; the closeout commits it.
set -u
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/.." && pwd)
out="$root/dist"
cross=${ZIG:-}
smoke=1
while [ $# -gt 0 ]; do
    case "$1" in
        --out) [ $# -ge 2 ] || { echo "make-dist: --out needs a dir" >&2; exit 2; }
               out=$2; shift 2 ;;
        --cross) [ $# -ge 2 ] || { echo "make-dist: --cross needs a zig path" >&2; exit 2; }
                 cross=$2; shift 2 ;;
        --no-smoke) smoke=0; shift ;;
        -h | --help) sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "make-dist: unknown argument '$1'" >&2; exit 2 ;;
    esac
done
cd "$root" || exit 1

work=$(mktemp -d "${TMPDIR:-/tmp}/make-dist.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

echo "== bootstrap (host $CC) =="
$CC -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$work/ctc" || exit 1
"$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" || exit 1
$CC -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" || exit 1
mkdir -p "$work/l2src"
"$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.log" 2>&1 || {
    echo "make-dist: L1 could not build L2:" >&2; sed 's/^/  /' "$work/l2.log" >&2; exit 1; }
$CC -Wall -Wextra -std=c99 "$work"/l2src/*.c -o "$work/l2" || exit 1
mkdir -p "$work/astsrc"
"$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.log" 2>&1 || {
    echo "make-dist: L2 could not build ct-ast:" >&2; sed 's/^/  /' "$work/ast.log" >&2; exit 1; }

echo "== target (Linux x86_64) =="
if [ -n "$cross" ]; then
    [ -x "$cross" ] || { echo "make-dist: not executable: $cross" >&2; exit 2; }
    mkdir -p "$work/zigcache"
    echo "cross: $cross cc -target x86_64-linux-musl -static"
    ZIG_GLOBAL_CACHE_DIR="$work/zigcache" ZIG_LOCAL_CACHE_DIR="$work/zigcache" \
        "$cross" cc -target x86_64-linux-musl -static -O2 -std=c99 \
        "$work"/astsrc/*.c -o "$work/ct" || {
        echo "make-dist: zig cross build failed" >&2; exit 1; }
    linkage="static musl"
elif [ "$(uname -s)" = "Linux" ]; then
    # A native Linux build is the authority; prefer a static link so the
    # glibc baseline does not leak into the artefact, but fall back with a
    # warning when static libc is absent.
    if $CC -O2 -std=c99 -static "$work"/astsrc/*.c -o "$work/ct" 2>"$work/link.log"; then
        linkage="static"
    else
        echo "make-dist: warning: static link unavailable; using the host glibc" >&2
        $CC -O2 -std=c99 "$work"/astsrc/*.c -o "$work/ct" || exit 1
        linkage="dynamic (host glibc $(getconf GNU_LIBC_VERSION 2>/dev/null || echo '?'))"
    fi
else
    echo "make-dist: not Linux and no --cross/ZIG given" >&2
    echo "  use --cross <zig> (cross build) or run on a Linux host" >&2
    exit 2
fi
if command -v file >/dev/null 2>&1; then
    desc=$(file -b "$work/ct")
    echo "file: $desc"
    case "$desc" in
        *"ELF 64-bit"*x86-64*) ;;
        *) echo "make-dist: target is not an ELF 64-bit x86-64 binary" >&2; exit 1 ;;
    esac
fi

# Package the entry command and the compatibility symlink.
pkg="$work/pkg"
mkdir -p "$pkg"
cp "$work/ct" "$pkg/ct"
chmod +x "$pkg/ct"
ln -s ct "$pkg/ctc"
mkdir -p "$out"
tarfile="$out/ct-linux-x64.tar.gz"
rm -f "$tarfile" "$tarfile.sha256"
( cd "$pkg" && COPYFILE_DISABLE=1 tar -czf "$tarfile" ct ctc ) || exit 1
( cd "$out" && { command -v sha256sum >/dev/null 2>&1 && sha256sum ct-linux-x64.tar.gz \
    || shasum -a 256 ct-linux-x64.tar.gz; } >ct-linux-x64.tar.gz.sha256 ) || exit 1
echo "artefact: $tarfile"
echo "linkage:  $linkage"
echo "sha256:   $(awk '{print $1}' "$tarfile.sha256")"

if [ "$smoke" -eq 1 ]; then
    if sh selfhost/run-linux-binary.sh "$pkg/ct" -v >"$work/smoke.out" 2>"$work/smoke.err"; then
        echo "smoke:    $(cat "$work/smoke.out")"
    else
        rc=$?
        if [ "$rc" -eq 77 ]; then
            echo "smoke:    UNVERIFIED ($(tail -1 "$work/smoke.err"))"
        else
            echo "make-dist: smoke failed (exit $rc):" >&2
            sed 's/^/  /' "$work/smoke.err" >&2
            exit 1
        fi
    fi
fi
exit 0
