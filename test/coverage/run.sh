#!/bin/sh
# TEST-25: offline line-coverage report for ct-ast (gcov, report only).
#
# Builds the bootstrap chain, instruments the generated C tree with
# `--coverage`, runs the compiler over its behavioural corpus (compile mode
# where it can, build mode for the multi-unit fixtures), and turns the gcov
# counters into one line-coverage summary plus a per-file table.
#
# Why gcov: it ships with GCC, needs no third-party tool and no network. The
# generated C carries `#line` anchors back to the `.ct` sources, so the report
# names the sources that were actually not executed.
#
# Report only: there is no threshold and a low percentage never fails the run.
# A build or instrumentation failure does fail (the report must not be silently
# missing). Where gcov or `--coverage` is unavailable the script SKIPs locally;
# with CI set it fails instead, so a coverage job cannot go green while blind.
#
# Usage:  bash test/coverage/run.sh
#         CC=gcc GCOV=gcov bash test/coverage/run.sh
#         COVERAGE_OUT=.temp/coverage bash test/coverage/run.sh
#
# Output: $COVERAGE_OUT/summary.txt   (totals + per-file lines)
#         $COVERAGE_OUT/summary.tsv   (source, executed, executable, percent)
#         $COVERAGE_OUT/gcov/         (raw gcov intermediate files)
set -u

root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
CC=${CC:-cc}
GCOV=${GCOV:-gcov}
out=${COVERAGE_OUT:-$root/.temp/coverage}
work=${TMPDIR:-/tmp}/ct-coverage.$$
cflags="-Wall -Wextra -std=c99"

rm -rf "$work"
mkdir -p "$work" "$out/gcov" || exit 1
trap 'rm -rf "$work"' EXIT INT TERM

skip_or_fail() {
    echo "coverage: SKIP ($1)" >&2
    if [ -n "${CI:-}" ]; then
        echo "coverage: gcov/--coverage is required in CI; failing instead of using a blind report" >&2
        exit 1
    fi
    echo "coverage: local run skipped; reproduce with: CC=gcc bash test/coverage/run.sh" >&2
    exit 0
}

command -v "$GCOV" >/dev/null 2>&1 || skip_or_fail "$GCOV is not installed"
# Probe the whole instrument-and-link path once; a compiler may accept
# --coverage but lack its runtime library (a common minimal-image case).
printf 'int main(void) { return 0; }\n' >"$work/probe.c"
if ! $CC $cflags --coverage "$work/probe.c" -o "$work/probe" >"$work/probe.log" 2>&1; then
    skip_or_fail "$CC cannot link with --coverage (see $work/probe.log)"
fi

echo "== build the bootstrap chain and the instrumentation =="
if ! $CC $cflags selfhost/l0/ctc.c -o "$work/ctc" 2>"$work/l0.log"; then
    echo "coverage: the L0 build failed:" >&2; sed 's/^/  /' "$work/l0.log" >&2; exit 1
fi
if ! "$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" 2>"$work/l1.log"; then
    echo "coverage: L0 could not compile L1:" >&2; sed 's/^/  /' "$work/l1.log" >&2; exit 1
fi
if ! $CC $cflags "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "coverage: L1 did not build:" >&2; sed 's/^/  /' "$work/l1b.log" >&2; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "coverage: L1 could not build L2:" >&2; sed 's/^/  /' "$work/l2.out" >&2; exit 1
fi
if ! $CC $cflags "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "coverage: L2 did not build:" >&2; sed 's/^/  /' "$work/l2b.log" >&2; exit 1
fi
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" \
        >"$work/ast.out" 2>&1; then
    echo "coverage: L2 could not build the AST compiler:" >&2; sed 's/^/  /' "$work/ast.out" >&2; exit 1
fi

# Instrument all units in one directory so every gcno/gcda pair lands in
# $work. The replay below runs the binary from the repo root, where the
# relative `#line` anchors resolve.
if ! ( cd "$work" && $CC $cflags --coverage -I "$work/astsrc" "$work"/astsrc/*.c -o ct-ast ) \
        >"$work/instrument.log" 2>&1; then
    echo "coverage: the instrumented ct-ast did not build:" >&2
    sed 's/^/  /' "$work/instrument.log" >&2
    exit 1
fi

echo "== exercise the compiler corpus =="
fixtures=0
compile_fail=0
run_fixture() {
    f=$1
    d=$(dirname "$f")
    fixtures=$((fixtures + 1))
    if [ -d "$d/ct-dialects" ]; then
        return 0
    fi
    if [ -n "$(find "$d" -maxdepth 2 \( -name '*.m.ct' -o -name '*.h.ct' \) -print -quit 2>/dev/null)" ]; then
        rm -rf "$work/prod"
        mkdir -p "$work/prod"
        if ! "$work/ct-ast" build --emit-c "$f" -o "$work/prod" \
                >"$work/fx.out" 2>"$work/fx.err"; then
            compile_fail=$((compile_fail + 1))
        fi
    else
        if ! "$work/ct-ast" "$f" -o "$work/fx.c" >"$work/fx.out" 2>"$work/fx.err"; then
            compile_fail=$((compile_fail + 1))
        fi
    fi
    return 0
}

for f in test/ast/*/prog.ct test/cases/*.ct examples/*/*.ct; do
    [ -f "$f" ] || continue
    run_fixture "$f"
done
# Negative fixtures are expected to fail; they still exercise the diagnostics.
for f in $(find test/ast/errors -name '*.ct' | sort); do
    run_fixture "$f"
done
# The src-layout demos only exist in build mode.
for f in examples/*/src/main.ct; do
    [ -f "$f" ] || continue
    run_fixture "$f"
done

# A few driver surfaces the corpus does not reach: the model JSON, the typed
# checker and the built-in layer's version banner.
"$work/ct-ast" test/ast/01_hello/prog.ct --emit-model - >"$work/model.json" 2>/dev/null
"$work/ct-ast" check test/ast/01_hello/prog.ct --types >/dev/null 2>&1
"$work/ct-ast" --version >/dev/null 2>&1

echo "  fixtures: $fixtures run ($compile_fail rejected, expected for negatives)"

echo "== collect gcov =="
# The intermediate format carries one `lcount:<line>,<count>` per executable
# line; summing those is exact, unlike adding up rounded percentages.
if ! ( cd "$work" && "$GCOV" -i ct-ast-*.gcno >"$work/gcov.log" 2>&1 ); then
    echo "coverage: gcov failed:" >&2; sed 's/^/  /' "$work/gcov.log" >&2; exit 1
fi
n_gcov=$(ls "$work"/*.gcov 2>/dev/null | wc -l | tr -d ' ')
if [ "$n_gcov" = 0 ]; then
    echo "coverage: gcov produced no .gcov files" >&2
    exit 1
fi

rm -f "$out/summary.txt" "$out/summary.tsv"
: >"$out/summary.tsv"
awk -v work="$work/" -v out="$out/summary.tsv" '
    /^file:/ {
        if (file != "") printf "%s\t%d\t%d\t%.2f\n", file, exec, total, (total ? 100 * exec / total : 0) >> out
        file = substr($0, 6)
        sub(work, "", file)
        exec = 0; total = 0
        next
    }
    /^lcount:/ {
        split($0, a, ",")
        total++
        if (a[2] + 0 > 0) exec++
    }
    END {
        if (file != "") printf "%s\t%d\t%d\t%.2f\n", file, exec, total, (total ? 100 * exec / total : 0) >> out
    }
' "$work"/*.gcov
# drop empty rows (a unit that emitted no executable lines)
awk -F'\t' '$3 + 0 > 0' "$out/summary.tsv" >"$out/summary.tsv.tmp" && mv "$out/summary.tsv.tmp" "$out/summary.tsv"

cp "$work"/*.gcov "$out/gcov/" 2>/dev/null || true
total=$(awk -F'\t' '{ s += $3 } END { print s + 0 }' "$out/summary.tsv")
executed=$(awk -F'\t' '{ s += $2 } END { print s + 0 }' "$out/summary.tsv")
files=$(wc -l <"$out/summary.tsv" | tr -d ' ')
if [ "$total" -eq 0 ]; then
    echo "coverage: no executable lines were found" >&2
    exit 1
fi
pct=$(awk -v e="$executed" -v t="$total" 'BEGIN { printf "%.2f", 100 * e / t }')

{
    echo "ct-ast line coverage (gcov, report only)"
    echo "generated: $(date -u '+%Y-%m-%dT%H:%M:%SZ')"
    echo "cc: $CC"
    echo "sources: $files"
    echo "executable lines: $total"
    echo "executed lines: $executed"
    echo "line coverage: ${pct}%"
    echo "fixtures: $fixtures run ($compile_fail rejected)"
    echo
    echo "per-source (executed/executable, percent):"
    sort -t'	' -k2,2nr "$out/summary.tsv" | while IFS='	' read -r src e t p; do
        printf '  %6.2f%%  %5d/%-5d  %s\n' "$p" "$e" "$t" "$src"
    done
} >"$out/summary.txt"

cat "$out/summary.txt"
echo
echo "coverage: report written to $out/summary.txt (report only; no threshold)"
exit 0
