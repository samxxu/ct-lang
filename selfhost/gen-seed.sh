#!/usr/bin/env bash
#
# gen-seed.sh - regenerate `bootstrap/ct-ast/` and `bootstrap/MANIFEST.sha256`.
#
# D-022 / v1-PH-0 S0. The seed is the C that the current ct-ast emits for its
# own source; it is what install.sh, check-ast.sh and ct-tour.sh build the
# shipped compiler from. Regenerate it only when cutting a release tag
# (R-V1-1) and commit the whole directory with this script's manifest.
#
# One-step bootstrap: the seed comes from the ct-ast of the previous release.
# When `bootstrap/ct-ast` already exists (the normal case) that frozen seed is
# compiled and used as the emitter -- it is the previous release's compiler and
# understands the current source. `CT_BOOTSTRAP_CT` overrides it when a newer
# compiler is at hand (two-stage bootstrap). Only when no seed exists yet does
# this fall back to the old L0 -> L1 -> L2 -> ct-ast walk: that is the
# seed-missing bootstrap exception, kept for the very first seed and for a
# historical checkout, not a build path for any harness.
#
# Usage:
#   bash selfhost/gen-seed.sh
#   CT_BOOTSTRAP_CT=/path/to/ct bash selfhost/gen-seed.sh
#   CC=clang bash selfhost/gen-seed.sh
#
# The output is deterministic: two runs must be byte-identical (gate 13).
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
out="$root/bootstrap/ct-ast"
manifest="$root/bootstrap/MANIFEST.sha256"

say() { printf '==> %s\n' "$*"; }
die() { printf 'gen-seed: error: %s\n' "$*" >&2; exit 1; }

work="$(mktemp -d "${CT_SHORT_TMP:-/tmp}/ctseed.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

# --- 1. obtain a ct-ast binary ------------------------------------------------
if [ -n "${CT_BOOTSTRAP_CT:-}" ]; then
    ct="$CT_BOOTSTRAP_CT"
    [ -x "$ct" ] || die "CT_BOOTSTRAP_CT is not executable: $ct"
    say "using CT_BOOTSTRAP_CT=$ct"
elif sh "$root/selfhost/seed-ct.sh" exists; then
    say "using the frozen seed bootstrap/ct-ast as the emitter"
    CC="$CC" CFLAGS="-Wall -Wextra -std=c99" \
        sh "$root/selfhost/seed-ct.sh" build "$work/ct" ||
        die "the frozen seed cannot build itself; set CT_BOOTSTRAP_CT to a newer ct (two-stage bootstrap)"
    ct="$work/ct"
else
    die "no frozen seed: bootstrap/ct-ast is required (L0/L1/L2 retired); set CT_BOOTSTRAP_CT for a one-step rebuild"

fi

say "emitter: $("$ct" -v)"

# --- 2. emit the seed ---------------------------------------------------------
# Keep the relative source path spelling: the emitted banner and `#line`
# directives record it, and gate 13 rebuilds with the same spelling.
rm -rf "$out"
mkdir -p "$out"
"$ct" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$out" ||
    die "ct-ast could not emit its own C"
# .ctcache/ is a rebuild accelerator, not seed content.
rm -rf "$out/.ctcache"

nc=$(find "$out" -maxdepth 1 -type f -name '*.c' | wc -l | tr -d ' ')
nh=$(find "$out" -maxdepth 1 -type f -name '*.h' | wc -l | tr -d ' ')
[ "$nc" -gt 0 ] || die "the emitter wrote no .c"
[ "$nh" -gt 0 ] || die "the emitter wrote no .h"

# --- 3. freeze the digests ----------------------------------------------------
# Paths are repo-relative, one `<sha256>  <path>` line per file, sorted by path
# so a regeneration produces an identical manifest.
say "writing bootstrap/MANIFEST.sha256"
if command -v shasum >/dev/null 2>&1; then
    sha256_of() { shasum -a 256 "$1" | awk '{print $1}'; }
else
    sha256_of() { sha256sum "$1" | awk '{print $1}'; }
fi
: >"$manifest"
find bootstrap/ct-ast -maxdepth 1 -type f \( -name '*.c' -o -name '*.h' \) |
    LC_ALL=C sort |
    while IFS= read -r f; do
        printf '%s  %s\n' "$(sha256_of "$root/$f")" "$f"
    done >"$manifest"

lines=$(cat "$out"/*.c "$out"/*.h | wc -l | tr -d ' ')
bytes=$(du -sk "$out" | awk '{print $1}')
say "seed: $nc .c + $nh .h, $lines lines, ${bytes} KB"
say "next: bash selfhost/check-seed.sh   (gate 13 must be green before committing)"
