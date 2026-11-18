#!/bin/sh
# PH-68-R4: false-positive account. Every legal fixture in the corpus must run
# `ct check --types` without a *type* diagnostic. Non-type messages (import is
# multi-file, semantic contracts, intentional L22-5 loop-count warnings) are
# not counted here; the intentional ones are listed in SKIP below.
#
# Usage: sh test/ast/p68_fp.sh <ct-ast>
set -u
ctast=${1:?usage: p68_fp.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p68fp.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

# Fixtures whose `--types` diagnostic is intentional (L22-5: a static
# non-integer loop count is legal but reported; `ct check` escalates it).
SKIP="loop_count_type"

n=0
fp=0
for f in "$root"/test/ast/*/prog.ct "$root"/examples/*/prog.ct "$root"/examples/*/src/main.ct "$root"/test/modules/*/lib.ct; do
    [ -f "$f" ] || continue
    name=$(basename "$(dirname "$f")")
    case "$f" in
        *neg_*|*_bad*|*err_*) continue ;;
    esac
    case " $SKIP " in *" $name "*) continue ;; esac
    out=$tmp/out
    ( cd "$root" && "$ctast" check --types "$f" ) >"$out" 2>&1
    n=$((n+1))
    if grep -qE "initializer:|assignment:|return:|argument [0-9]+:|type mismatch" "$out"; then
        fp=$((fp+1))
        echo "FAIL p68/fp: $f" >&2
        grep -E "initializer:|assignment:|return:|argument [0-9]+:|type mismatch" "$out" | head -2 >&2
    fi
done

if [ "$fp" -ne 0 ]; then
    echo "FAIL p68/fp: $fp type false positive(s) of $n legal fixtures" >&2
    exit 1
fi
echo "OK p68/fp (FP=0/$n legal fixtures; 1 documented skip: $SKIP)"
