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

# Fixed collation, so `find | sort` picks the same seed order on every host.
LC_ALL=C
export LC_ALL

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
root_seed=20261102

work="$(mktemp -d)" || exit 1
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
echo "== build the bootstrap chain and the AST compiler =="
if ! "$CC" $flags selfhost/l0/ctc.c -o "$work/ctc" 2>"$work/l0.log"; then
    echo "  compiler build failed:"; sed 's/^/    /' "$work/l0.log"; exit 1
fi
if ! "$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" 2>"$work/l1.log"; then
    echo "  L0 could not compile L1:"; sed 's/^/    /' "$work/l1.log"; exit 1
fi
if ! "$CC" $flags "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "  L1 did not build:"; sed 's/^/    /' "$work/l1b.log"; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "  L1 could not build the split tree:"; sed 's/^/    /' "$work/l2.out"; exit 1
fi
if ! "$CC" $flags "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "  L2 did not build:"; sed 's/^/    /' "$work/l2b.log"; exit 1
fi
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.out" 2>&1; then
    echo "  L2 could not build the AST compiler:"; sed 's/^/    /' "$work/ast.out"; exit 1
fi
if ! "$CC" $flags "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
    echo "  the AST compiler did not build:"; sed 's/^/    /' "$work/astb.log"; exit 1
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
