#!/bin/sh
#
# check-sanitizers.sh - the ASAN/UBSAN gate (Phase 17.1).
#
# Builds ct-ast from the frozen seed (bootstrap/ct-ast, D-022) with
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
if [ "${CT_ASAN_STACK:-0}" = "1" ]; then
    ASAN_OPTIONS="$ASAN_OPTIONS:detect_stack_use_after_return=1"
fi
UBSAN_OPTIONS="halt_on_error=1:print_stacktrace=1"
export ASAN_OPTIONS UBSAN_OPTIONS

work="$(mktemp -d "${CT_SHORT_TMP:-/tmp}/ctsan.XXXXXX")" || exit 1
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
echo "== build the AST compiler from the frozen seed (sanitized) =="
# v1-PH-0 S2b: instrument the shipped compiler. L2 cannot build ct-ast after
# `match`; L1/L2 stay the regression oracle of gates 2/3/4/5, not this input.
if ! CC="$SANCC" CFLAGS="-Wall -Wextra -std=c99" \
        sh "$root/selfhost/seed-ct.sh" build "$work/ct-ast" >"$work/ast.out" 2>&1; then
    echo "  ct-ast did not build from the frozen seed:"
    sed 's/^/    /' "$work/ast.out"; exit 1
fi
ok "ct-ast builds from the frozen seed (sanitized)"
# v1-PH-2 S9 M4: strict by default; only registered C-interop fixtures get the
# explicit CLI allow (test/c-boundary-allow.tsv).
sh "$root/test/make-ct-ast-wrapper.sh" "$work/ct-ast" "$root" || {
    echo "  could not install the C-boundary allow wrapper"; exit 1
}

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
    # The same three fixtures check-ast.sh leaves to their dedicated probes: a
    # null-vtable dispatch (p37), a cancelled thread and a refcount race (p41).
    case "$name" in 219_runtime_guard|p41_cancel_flag|p41_refcount) continue;; esac
    src="$d/prog.ct"
    [ -f "$src" ] || continue
    c="$work/$name.c"
    exe="$work/$name.bin"

    # A fixture with a mapping unit or a header unit is multi-file: `import` is
    # a build-mode feature, so it goes through `build --emit-c` and every unit
    # is compiled here (the same split check-ast.sh uses).
    if [ -n "$(find "$d" \( -name '*.m.ct' -o -name '*.h.ct' \) -print -quit)" ]; then
        md="$work/$name.mod"
        incs=""
        rm -rf "$md"
        mkdir -p "$md"
        for h in $(find "$d" -name '*.shim.h'); do incs="$incs -I $(dirname "$h")"; done
        if ! "$work/ct-ast" build --emit-c $incs "$src" -o "$md" \
                >"$work/$name.out" 2>"$work/$name.err"; then
            bad "$name" "ct-ast build failed: $(cat "$work/$name.err")"
            continue
        fi
        if sanitizer_report "$work/$name.out" "$work/$name.err"; then
            bad "$name" "ct-ast emitted a sanitizer report"
            continue
        fi
        if ! "$SANCC" -Wall -Wextra -std=c99 -pthread $incs -I "$md" "$md"/*.c \
                $(find "$d" -name '*.shim.c') -o "$exe" 2>"$work/$name.cc"; then
            bad "$name" "generated C did not build: $(cat "$work/$name.cc")"
            continue
        fi
    else
        if ! "$work/ct-ast" "$src" -o "$c" >"$work/$name.out" 2>"$work/$name.err"; then
            bad "$name" "ct-ast failed: $(cat "$work/$name.err")"
            continue
        fi
        if sanitizer_report "$work/$name.out" "$work/$name.err"; then
            bad "$name" "ct-ast emitted a sanitizer report"
            continue
        fi
        if ! "$SANCC" -Wall -Wextra -std=c99 -pthread "$c" -o "$exe" 2>"$work/$name.cc"; then
            bad "$name" "generated C did not build: $(cat "$work/$name.cc")"
            continue
        fi
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

    # SH-75: the default ASAN options cannot see a stack dangling (REQ-CI-2),
    # so the fixture that used to return a local struct as an interface value
    # is also built with clang's compile-time use-after-return instrumentation
    # and must stay clean.
    if [ "$name" = "239_local_iface_return" ] \
       && "$CC" --version 2>/dev/null | grep -qi clang; then
        if ! "$CC" -std=c99 -O0 -fsanitize-address-use-after-return=always \
                "$c" -o "$work/$name.uar" 2>"$work/$name.uarc"; then
            bad "$name" "the UAR build failed: $(cat "$work/$name.uarc")"
        elif ASAN_OPTIONS="detect_leaks=0:detect_stack_use_after_return=1" \
                "$work/$name.uar" >"$work/$name.uar.out" 2>"$work/$name.uar.err" \
             && ! sanitizer_report "$work/$name.uar.err"; then
            ok "$name (use-after-return instrumented)"
        else
            bad "$name" "a stack-use-after-return is still reachable"
        fi
    fi
done

echo
echo "== negative fixtures (test/ast/errors/*.ct) =="
for src in test/ast/errors/*.ct; do
    [ -f "$src" ] || continue
    name="$(basename "$src" .ct)"
    # Phase 37: these exit 0 in compile mode by design (warning); their
    # build/check severity is asserted by test/ast/p37_probe.sh in check-ast.
    case "$name" in p37_sig_*) continue;; esac
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
