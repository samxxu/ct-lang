#!/bin/sh
# PH-83 / S83d: verify the Linux x64 distribution artefact (E83-6).
#
#   sh test/ast/p83_dist.sh [<ct-ast>] [--require]
#
# Checks, in order:
#   1. dist/ct-linux-x64.tar.gz and its .sha256 exist;
#   2. the recorded sha256 matches the tarball (and `sha256sum -c` accepts it);
#   3. the tarball contains exactly `ct` and the `ctc` -> ct symlink;
#   4. unpacked `ct` is an ELF 64-bit x86-64 executable (when `file` exists);
#   5. `ct -v` runs on Linux (native, or the QEMU boot helper) and reports the
#      version in selfhost/ct-ast/main.ct (and, when <ct-ast> is given, the
#      same version as the host compiler).
#
# Without --require a missing artefact (or no way to run a Linux binary) is a
# `skip` (77): CI may not have dist/ or a cross toolchain. With --require it is
# a failure, which is what a release/closeout record uses.
#
# Usage: sh selfhost/make-dist.sh --cross <zig>   # produce dist/
set -u
ctast=
require=${CT_DIST_REQUIRE:-0}
for a in "$@"; do
    case "$a" in
        --require) require=1 ;;
        -h | --help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        -*) echo "p83_dist: unknown option '$a'" >&2; exit 2 ;;
        *) ctast=$a ;;
    esac
done
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p83/dist: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
miss() {
    if [ "$require" -eq 1 ]; then
        bad "$1"
        exit 1
    fi
    echo "skip p83/dist: $1" >&2
    exit 77
}

tarfile=${CT_DIST:-dist/ct-linux-x64.tar.gz}
shafile="$tarfile.sha256"
[ -f "$tarfile" ] || miss "no artefact at $tarfile (run selfhost/make-dist.sh)"
[ -f "$shafile" ] || bad "no sha256 file at $shafile"

expect=$(grep -m1 '#define CTC_VERSION' selfhost/ct-ast/main.ct | sed 's/.*"\(.*\)".*/\1/')
[ -n "$expect" ] || bad "cannot read CTC_VERSION from selfhost/ct-ast/main.ct"

# 2. checksum
if command -v sha256sum >/dev/null 2>&1; then
    got=$(sha256sum "$tarfile" | awk '{print $1}')
    ( cd "$(dirname "$tarfile")" && sha256sum -c "$(basename "$shafile")" ) >/dev/null 2>&1 \
        && ok "sha256sum -c accepts the artefact" || bad "sha256sum -c rejects the artefact"
elif command -v shasum >/dev/null 2>&1; then
    got=$(shasum -a 256 "$tarfile" | awk '{print $1}')
else
    miss "no sha256sum/shasum"
fi
want=$(awk '{print $1}' "$shafile")
if [ "$got" = "$want" ]; then ok "sha256 matches $want"; else bad "sha256 mismatch" "want $want, got $got"; fi

# 3. contents
listing=$(tar -tzf "$tarfile" 2>/dev/null | sed 's|^\./||')
if [ "$listing" = "ct
ctc" ]; then
    ok "the tarball contains ct and ctc only"
else
    bad "unexpected tarball contents" "$listing"
fi

work=$(mktemp -d "${TMPDIR:-/tmp}/p83dist.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/unpack"
tar -xzf "$tarfile" -C "$work/unpack" || bad "cannot unpack the artefact"
[ -x "$work/unpack/ct" ] && ok "unpacked ct is executable" || bad "unpacked ct is not executable"
if [ -L "$work/unpack/ctc" ] && [ "$(readlink "$work/unpack/ctc")" = "ct" ]; then
    ok "unpacked ctc is the ct symlink"
else
    bad "unpacked ctc is not the ct symlink"
fi

# 4. ELF shape
if command -v file >/dev/null 2>&1; then
    desc=$(file -b "$work/unpack/ct")
    case "$desc" in
        *"ELF 64-bit"*x86-64*) ok "ELF 64-bit x86-64 ($desc)" ;;
        *) bad "not an ELF 64-bit x86-64 binary" "$desc" ;;
    esac
fi

# 5. run it
if sh selfhost/run-linux-binary.sh "$work/unpack/ct" -v >"$work/v.out" 2>"$work/v.err"; then
    v=$(cat "$work/v.out")
    if [ "$v" = "ct v$expect" ]; then
        ok "unpacked ct -v prints '$v'"
    else
        bad "ct -v mismatch" "expected 'ct v$expect', got '$v'"
    fi
else
    rc=$?
    if [ "$rc" -eq 77 ] && [ "$require" -eq 0 ]; then
        echo "skip p83/dist: artefact exists but cannot run a Linux x86-64 binary here ($(tail -1 "$work/v.err"))" >&2
        exit 77
    fi
    bad "ct -v failed on Linux" "$(tail -3 "$work/v.err")"
fi

# Version coherence with the host compiler, when one was named.
if [ -n "$ctast" ] && [ -x "$ctast" ]; then
    hv=$("$ctast" -v 2>/dev/null)
    case "$hv" in
        *" v$expect") ok "host compiler agrees on v$expect" ;;
        *) bad "host compiler version" "expected v$expect, got '$hv'" ;;
    esac
fi

[ "$fail" -eq 0 ] && echo "p83_dist: OK"
exit "$fail"
