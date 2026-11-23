#!/bin/sh
#
# seed-ct.sh - the one build path for ct-ast after the v1-PH-0 seed cutover.
#
# D-022 / S2b. `bootstrap/ct-ast` is the C that the shipped ct-ast emits for
# itself. The L1/L2 chain predates ADT/`match`, so it can no longer compile
# `selfhost/ct-ast/**`; every harness that needs the current compiler must
# compile the seed instead. L1/L2 stay only as the regression oracle of gates
# 2/3/4/5 (they still build themselves), never as ct-ast's build path.
#
# Usage:
#   sh selfhost/seed-ct.sh build  <out-binary>   compile the seed warning-free
#   sh selfhost/seed-ct.sh astsrc <out-dir>      materialise the seed C tree
#   sh selfhost/seed-ct.sh exists                exit 0 when the seed is present
#
# Environment:
#   CC            C compiler (default cc)
#   CFLAGS        compiler flags (default -Wall -Wextra -std=c99)
#   SEED_CT_ROOT  tree to read bootstrap/ct-ast from (default: this repo)
#
# `astsrc` copies the seed rather than re-emitting it: gate 13 proves the seed
# is a fixpoint of `build --emit-c`, so the bytes are the same and a second
# compiler build buys nothing. Only .c/.h files are copied; `.ctcache/` is a
# rebuild accelerator and not seed content.
set -u

root="${SEED_CT_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
seed="$root/bootstrap/ct-ast"
CC="${CC:-cc}"
CFLAGS="${CFLAGS:--Wall -Wextra -std=c99}"

die() { printf 'seed-ct: error: %s\n' "$*" >&2; exit 1; }

[ -d "$seed" ] || die "the frozen seed is missing: $seed (run: bash selfhost/gen-seed.sh)"

cmd=${1:-}
case "$cmd" in
    build)
        out=${2:-}
        [ -n "$out" ] || die "usage: seed-ct.sh build <out-binary>"
        # shellcheck disable=SC2086
        "$CC" $CFLAGS -I "$seed" "$seed"/*.c -o "$out" || die "the seed did not build"
        ;;
    astsrc)
        out=${2:-}
        [ -n "$out" ] || die "usage: seed-ct.sh astsrc <out-dir>"
        case "$out" in /|"") die "refusing to replace '$out'" ;; esac
        rm -rf "$out"
        mkdir -p "$out" || die "cannot create $out"
        for f in "$seed"/*.c "$seed"/*.h; do
            [ -f "$f" ] || continue
            cp "$f" "$out/" || die "cannot copy $f"
        done
        ;;
    exists)
        exit 0
        ;;
    *)
        printf 'usage: %s {build <out-binary>|astsrc <out-dir>|exists}\n' "$0" >&2
        exit 2
        ;;
esac
