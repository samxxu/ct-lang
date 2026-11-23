#!/usr/bin/env bash
#
# run.sh - deterministic fuzz for the AST compiler (Phase 17.1).
#
# Seeds come from test/ast/**/*.ct. Every seed is mutated three ways with a
# fixed LCG (truncation, a dropped line, a token swap), compiled by ct-ast, and
# checked for the three properties a fuzz gate can assert cheaply:
#
#   * no crash        - exit status below 128 (no signal), no sanitizer / abort text
#   * bounded time    - a 5-second watchdog per run
#   * bounded output  - diagnostics <= 64 KiB, emitted C <= 1 MiB
#
# The refusal of a mutated input is expected: a non-zero exit with a diagnostic
# is a pass. Determinism is the point - the same seed number and the same input
# files always produce the same mutation sequence, so a failure can be replayed.
#
# Not part of selfhost/check-all.sh (D17-6). CI runs it nightly; locally, run it
# by hand.
#
# Usage:  bash test/fuzz/run.sh
#         CC=clang bash test/fuzz/run.sh
#
# Exit code 0 means no crash, no timeout and no unbounded output.

set -u

# The mutations are written to a temp directory and may keep a free `#include`,
# so the source-level C boundary policy is not what this gate exercises.
export CT_C_BOUNDARY=allow

# Fixed collation, so `find | sort` picks the same seed order on every host.
LC_ALL=C
export LC_ALL

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
root_seed=20261102

work="$(mktemp -d "${CT_SHORT_TMP:-/tmp}/ctfuzz.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

# GCC >= 8 needs the same two -Wno flags check-all.sh uses, so the frozen layers
# stay warning-free on both compilers (AGENTS.md section 6).
flags="-Wall -Wextra -std=c99"
if "$CC" --version 2>/dev/null | grep -q 'Free Software Foundation'; then
    flags="$flags -Wno-format-truncation -Wno-implicit-fallthrough"
fi

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "cc: $CC"
echo "seed: $root_seed"
echo
echo "== build the AST compiler (frozen seed) =="
# v1-PH-0 S2b: fuzz the shipped compiler; the L1/L2 chain can no longer build
# ct-ast after `match`. L1/L2 remain gates 2/3/4/5's oracle, not this input.
if ! CC="$CC" CFLAGS="$flags" sh "$root/selfhost/seed-ct.sh" build "$work/ct-ast" \
        >"$work/ast.out" 2>&1; then
    echo "  the AST compiler did not build from the frozen seed:"
    sed 's/^/    /' "$work/ast.out"; exit 1
fi

# LCG from Numerical Recipes: explicit modulo keeps it identical on every host
# (awk's rand() is not portable across mawk / gawk / BSD).
lcg_seed="$root_seed"
rnd() { lcg_seed=$(( (lcg_seed * 1103515245 + 12345) % 2147483648 )); RND=$lcg_seed; }

# Keep every token of a command in one word, so nothing is re-split by the
# shell, and start a watchdog around it.
run_limited() {
    secs="$1"
    shift
    "$@" &
    pid=$!
    ticks=0
    limit=$((secs * 5))
    while kill -0 "$pid" 2>/dev/null; do
        ticks=$((ticks + 1))
        if [ "$ticks" -gt "$limit" ]; then
            kill -9 "$pid" 2>/dev/null
            wait "$pid" 2>/dev/null
            return 124
        fi
        sleep 0.2
    done
    wait "$pid"
}

bounded_size() {  # file, limit in bytes
    [ -f "$1" ] || return 0
    [ "$(wc -c < "$1")" -le "$2" ]
}

echo
echo "== mutated seeds (test/ast/**/*.ct) =="
count=0
for src in $(find test/ast -name '*.ct' | sort); do
    case "$(basename "$src")" in
        prog.expected.out) continue ;;
    esac

    for round in 1 2 3; do
        rnd; a=$RND
        rnd; b=$RND
        rnd; c=$RND
        mut="$work/mut-$((count + 1)).ct"
        count=$((count + 1))

        size="$(wc -c < "$src")"
        lines="$(wc -l < "$src")"
        op=$(( (a / 7) % 3 ))

        case "$op" in
            0)
                if [ "$size" -gt 1 ]; then
                    cut=$(( (b % (size - 1)) + 1 ))
                    head -c "$cut" "$src" > "$mut"
                else
                    cp "$src" "$mut"
                fi
                ;;
            1)
                if [ "$lines" -gt 1 ]; then
                    drop=$(( (b % lines) + 1 ))
                    awk -v n="$drop" 'NR != n' "$src" > "$mut"
                else
                    head -c "$((size / 2))" "$src" > "$mut"
                fi
                ;;
            2)
                # Token shuffle: ignore the original line structure on purpose.
                toks=($(<"$src"))
                n=${#toks[@]}
                if [ "$n" -gt 1 ]; then
                    i=$((a % n))
                    j=$((b % n))
                    tmp="${toks[$i]}"
                    toks[$i]="${toks[$j]}"
                    toks[$j]="$tmp"
                    printf '%s\n' "${toks[@]}" > "$mut"
                else
                    printf '%s\nx\n' "$(<"$src")" > "$mut"
                fi
                ;;
        esac

        out="$work/out-$count.c"
        run_limited 5 "$work/ct-ast" "$mut" -o "$out" >"$work/o-$count.log" 2>"$work/e-$count.log"
        st=$?

        label="$(basename "$src")#$count op$op"
        if [ "$st" -eq 124 ]; then
            bad "$label" "timeout after 5s"
        elif [ "$st" -ge 128 ]; then
            bad "$label" "crash (exit $st)"
        elif ! bounded_size "$work/e-$count.log" 65536; then
            bad "$label" "diagnostics exceed 64 KiB"
        elif ! bounded_size "$out" 1048576; then
            bad "$label" "emitted C exceeds 1 MiB"
        elif grep -Eq 'AddressSanitizer|Segmentation fault|Aborted|assertion failed|runtime error:' \
                "$work/e-$count.log" "$work/o-$count.log"; then
            bad "$label" "crash text in the output"
        else
            ok
        fi
    done
done

echo
if [ "$fail" -eq 0 ]; then
    printf 'fuzz: OK (%d runs, seed %d, no crash / timeout / unbounded output)\n' "$count" "$root_seed"
else
    printf 'fuzz: FAIL (%d failed, %d passed, %d runs, seed %d)\n' "$fail" "$pass" "$count" "$root_seed"
fi
[ "$fail" -eq 0 ]
