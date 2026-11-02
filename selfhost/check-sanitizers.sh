#!/bin/sh
#
# check-sanitizers.sh - the ASAN/UBSAN gate (Phase 17.1).
#
# Builds the whole chain (L0 -> L1 -> L2 -> ct-ast) with
# `-fsanitize=address,undefined -fno-omit-frame-pointer`, then runs:
#
#   1. ./test/run.sh          (the L0 suite, with every generated binary and
#                             helper built through the same sanitizer wrapper)
#   2. test/ast/*/prog.ct     (compile -> build -> run -> compare, sanitized)
#   3. test/ast/errors/*.ct   (must fail, and must fail cleanly)
#
# Any sanitizer report fails the run. Leak detection is off: the compiler keeps
# its arenas alive for the whole process, so leak semantics are the compile-time
# analysis in check-warnings.sh, not LeakSanitizer.
#
# This gate is deliberately not part of selfhost/check-all.sh (D17-6): it is
# much slower than the nine local gates. CI runs it nightly; locally, run it by
# hand when touching memory-sensitive code.
#
# Usage:  bash selfhost/check-sanitizers.sh
#         CC=clang bash selfhost/check-sanitizers.sh
#
# Exit code 0 means no sanitizer report anywhere.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
san="-fsanitize=address,undefined -fno-omit-frame-pointer"

ASAN_OPTIONS="detect_leaks=0"
UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
export ASAN_OPTIONS UBSAN_OPTIONS

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

# One wrapper for every compile below. GCC >= 8 also enables
# -Wformat-truncation / -Wimplicit-fallthrough, so the wrapper carries the same
# two -Wno flags as check-all.sh: the frozen layers must stay warning-free on
# both compilers (AGENTS.md section 6).
extra="$san"
if "$CC" --version 2>/dev/null | grep -q 'Free Software Foundation'; then
    extra="$san -Wno-format-truncation -Wno-implicit-fallthrough"
fi
ccbin="$(command -v "$CC")" || ccbin="$CC"
printf '#!/bin/sh\nexec "%s" %s "$@"\n' "$ccbin" "$extra" > "$work/cc-san"
chmod +x "$work/cc-san"
SANCC="$work/cc-san"
CC="$SANCC"
export CC

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

sanitizer_report() {
    grep -Eq 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' "$@"
}

echo "cc: $CC ($san)"
echo
echo "== build the bootstrap chain and the AST compiler (sanitized) =="
if ! "$SANCC" -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$work/ctc" 2>"$work/l0.log"; then
    echo "  compiler build failed:"; sed 's/^/    /' "$work/l0.log"; exit 1
fi
if ! "$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" 2>"$work/l1.log"; then
    echo "  L0 could not compile L1:"; sed 's/^/    /' "$work/l1.log"; exit 1
fi
if ! "$SANCC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "  L1 did not build:"; sed 's/^/    /' "$work/l1b.log"; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "  L1 could not build the split tree:"; sed 's/^/    /' "$work/l2.out"; exit 1
fi
if ! "$SANCC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "  L2 did not build:"; sed 's/^/    /' "$work/l2b.log"; exit 1
fi
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.out" 2>&1; then
    echo "  L2 could not build the AST compiler:"; sed 's/^/    /' "$work/ast.out"; exit 1
fi
if ! "$SANCC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
    echo "  the AST compiler did not build:"; sed 's/^/    /' "$work/astb.log"; exit 1
fi
ok "the chain builds (L0 -> L1 -> L2 -> ct-ast)"

echo
echo "== L0 suite (test/run.sh, sanitized) =="
if ./test/run.sh >"$work/run.log" 2>&1; then
    if sanitizer_report "$work/run.log"; then
        bad "test/run.sh" "a sanitizer report is present"
        grep -E 'AddressSanitizer|LeakSanitizer|UndefinedBehaviorSanitizer|runtime error:' \
            "$work/run.log" | sed 's/^/    /' | head -20
    else
        ok "test/run.sh (no sanitizer report)"
    fi
else
    bad "test/run.sh" "the suite failed (exit $?)"
fi
tail -n 5 "$work/run.log" | sed 's/^/    /'

echo
echo "== behavioural fixtures (test/ast/*/prog.ct) =="
for d in test/ast/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    name="$(basename "$d")"
    src="$d/prog.ct"
    [ -f "$src" ] || continue
    c="$work/$name.c"
    exe="$work/$name.bin"

    if ! "$work/ct-ast" "$src" -o "$c" >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name" "ct-ast failed: $(cat "$work/$name.err")"
        continue
    fi
    if sanitizer_report "$work/$name.out" "$work/$name.err"; then
        bad "$name" "ct-ast emitted a sanitizer report"
        continue
    fi
    if ! "$SANCC" -Wall -Wextra -std=c99 "$c" -o "$exe" 2>"$work/$name.cc"; then
        bad "$name" "generated C did not build: $(cat "$work/$name.cc")"
        continue
    fi
    if ! "$exe" >"$work/$name.stdout" 2>"$work/$name.stderr"; then
        bad "$name" "the program exited non-zero"
        continue
    fi
    if sanitizer_report "$work/$name.stderr"; then
        bad "$name" "the program emitted a sanitizer report"
        continue
    fi
    if ! cmp -s "$work/$name.stdout" "$d/prog.expected.out"; then
        bad "$name" "program output differs"
        continue
    fi
    ok "$name"
done

echo
echo "== negative fixtures (test/ast/errors/*.ct) =="
for src in test/ast/errors/*.ct; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .ct)"
    "$work/ct-ast" "$src" -o "$work/neg.c" >"$work/neg.out" 2>"$work/neg.err"
    st=$?
    if [ "$st" -ge 128 ]; then
        bad "$name" "ct-ast crashed (exit $st)"
        continue
    fi
    if sanitizer_report "$work/neg.out" "$work/neg.err"; then
        bad "$name" "ct-ast emitted a sanitizer report"
        continue
    fi
    if [ "$st" -eq 0 ]; then
        bad "$name" "the negative fixture compiled"
        continue
    fi
    ok "$name"
done

echo
if [ "$fail" -eq 0 ]; then
    printf 'check-sanitizers: OK (%d checks, no sanitizer report)\n' "$pass"
else
    printf 'check-sanitizers: FAIL (%d failed, %d passed)\n' "$fail" "$pass"
fi
[ "$fail" -eq 0 ]
