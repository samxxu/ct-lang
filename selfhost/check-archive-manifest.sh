#!/usr/bin/env bash
#
# check-archive-manifest.sh - verify test/archive/ against its sha256 manifest.
#
# SH-119 S1: the archive becomes the historical reference after L0/L1/L2
# retire.  MANIFEST.sha256 lists every file below test/archive/ with its
# digest, so a silent edit or a missing/extra fixture is red.
#
# Usage: bash selfhost/check-archive-manifest.sh [--selftest]
#        CHECK_ARCHIVE_DIR=<dir>   directory override (selftest/negative use)
# Exit: 0 clean, 1 mismatch/missing/extra/unreadable, 2 usage.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1
dir="${CHECK_ARCHIVE_DIR:-$root/test/archive}"
manifest="$dir/MANIFEST.sha256"
fail=0

sha256_of() {
    if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
    else shasum -a 256 "$1" | awk '{print $1}'; fi
}

check() {
    if [ ! -f "$manifest" ]; then
        echo "FAIL archive: manifest missing: ${manifest#"$root"/}"
        return 1
    fi
    # Manifest paths are relative to test/archive/.
    while IFS= read -r line; do
        case "$line" in ''|'#'*) continue ;; esac
        want=${line%%  *}
        rel=${line#*  }
        [ -n "$want" ] && [ -n "$rel" ] || {
            echo "FAIL archive: malformed manifest line: $line"; fail=1; continue; }
        f="$dir/$rel"
        if [ ! -f "$f" ]; then
            echo "FAIL archive: missing file: $rel"; fail=1; continue
        fi
        got=$(sha256_of "$f")
        [ "$got" = "$want" ] || {
            echo "FAIL archive: digest mismatch: $rel"; fail=1; }
    done <"$manifest"
    # Every non-manifest regular file must be listed exactly once.
    ulist=$(mktemp "${TMPDIR:-/tmp}/ct-archive-unlisted.XXXXXX") || return 1
    find "$dir" -type f ! -name MANIFEST.sha256 | LC_ALL=C sort |
        while IFS= read -r f; do
            rel=${f#"$dir"/}
            grep -q "  $rel\$" "$manifest" || echo "FAIL archive: unlisted file: $rel"
        done >"$ulist"
    if [ -s "$ulist" ]; then
        cat "$ulist"
        fail=1
    fi
    rm -f "$ulist"
    return "$fail"
}

selftest() {
    work=$(mktemp -d "${TMPDIR:-/tmp}/ct-archive.XXXXXX") || exit 1
    trap 'rm -rf "$work"' EXIT HUP INT TERM
    cp -R "$dir" "$work/archive" || exit 1
    self="$root/selfhost/check-archive-manifest.sh"
    if CHECK_ARCHIVE_DIR="$work/archive" bash "$self" >/dev/null 2>&1; then
        echo "ok   archive-selftest: clean copy accepted"
    else
        echo "FAIL archive-selftest: clean copy was rejected"
        fail=1
    fi
    # flip one byte in a listed fixture; the manifest must catch it
    f="$work/archive/cases/19_namespace.ct"
    [ -f "$f" ] || f=$(find "$work/archive" -type f ! -name MANIFEST.sha256 | head -1)
    printf '\n// tampered\n' >> "$f"
    if CHECK_ARCHIVE_DIR="$work/archive" bash "$self" >/dev/null 2>&1; then
        echo "FAIL archive-selftest: tampered copy was accepted"
        fail=1
    else
        echo "ok   archive-selftest: tampered copy rejected"
    fi
    # remove a listed fixture; the manifest must catch that too
    rm -f "$work/archive/cases/19_namespace.ct" 2>/dev/null || true
    if CHECK_ARCHIVE_DIR="$work/archive" bash "$self" >/dev/null 2>&1; then
        echo "FAIL archive-selftest: missing file was accepted"
        fail=1
    else
        echo "ok   archive-selftest: missing file rejected"
    fi
    [ "$fail" -eq 0 ] && echo "archive-manifest: OK (manifest + negative fixtures)" || \
        echo "archive-manifest: FAIL"
    return "$fail"
}

case "${1:-}" in
    --selftest) selftest ;;
    '') if check; then
            echo "archive-manifest: OK ($(find "$dir" -type f ! -name MANIFEST.sha256 | wc -l | tr -d ' ') files)"
        else
            echo "archive-manifest: FAIL"
            exit 1
        fi ;;
    *) echo "usage: check-archive-manifest.sh [--selftest]" >&2; exit 2 ;;
esac
