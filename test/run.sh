#!/bin/sh
#
# ctc test runner.
#
#   ./test/run.sh            run everything
#   CC=gcc ./test/run.sh     pick another C compiler (default: cc)
#
# Verification only — this script is never part of the compiler build.
# Exit code 0 means every check passed.
#
# Layers
#   build    ctc itself must compile under -Wall -Wextra -std=c99 with no warnings
#   unit     white-box tests of ctc's pure helpers              (test/unit)
#   cases    golden tests: generate, diff, compile, run        (test/cases)
#   errors   diagnostics: must fail with the expected message  (test/errors)
#   examples end-to-end demos: generate, build, run, compare   (examples)

set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CC=${CC:-cc}
CFLAGS="-Wall -Wextra -std=c99"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

# Run ctc with paths relative to the repo root: the generated header embeds the
# input path in a comment, so the goldens depend on it.
cd "$ROOT" || exit 1

pass=0
fail=0
failed_names=""

ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); failed_names="$failed_names\n  - $1: $2"; printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "cc: $CC"

# ------------------------------------------------------------------ build
echo
echo "== build ctc =="
if ! $CC $CFLAGS ctc.c -o "$TMP/ctc" 2>"$TMP/build.log"; then
    echo "  compiler build failed:"
    sed 's/^/    /' "$TMP/build.log"
    exit 1
fi
if [ -s "$TMP/build.log" ]; then
    echo "  compiler build emitted warnings:"
    sed 's/^/    /' "$TMP/build.log"
    bad "build" "ctc.c must be warning-free"
else
    ok "build (warning-free)"
fi

# ------------------------------------------------------------------ unit
echo
echo "== unit tests =="
if $CC $CFLAGS test/unit/test_helpers.c -o "$TMP/unit" 2>"$TMP/unit.log"; then
    if "$TMP/unit" >"$TMP/unit.out" 2>&1; then
        sed 's/^/  /' "$TMP/unit.out"
        ok "unit/test_helpers"
    else
        sed 's/^/  /' "$TMP/unit.out"
        bad "unit/test_helpers" "assertions failed"
    fi
else
    sed 's/^/    /' "$TMP/unit.log"
    bad "unit/test_helpers" "compile failed"
fi

# ------------------------------------------------------------------ cases
echo
echo "== golden cases =="
for ct in test/cases/*.ct; do
    name=$(basename "$ct" .ct)
    exp_c="test/cases/$name.expected.c"
    exp_h="test/cases/$name.expected.h"
    exp_out="test/cases/$name.expected.out"

    if ! "$TMP/ctc" "$ct" -o "$TMP/$name.c" 2>"$TMP/$name.err"; then
        bad "$name" "ctc exited non-zero: $(cat "$TMP/$name.err")"
        continue
    fi
    if ! diff -u "$exp_c" "$TMP/$name.c" >"$TMP/$name.diff"; then
        bad "$name" "generated .c differs from golden"
        sed -n '1,60p' "$TMP/$name.diff" | sed 's/^/    /'
        continue
    fi
    if [ -f "$exp_h" ] && ! diff -u "$exp_h" "$TMP/$name.h" >"$TMP/$name.hdiff"; then
        bad "$name" "generated .h differs from golden"
        sed -n '1,60p' "$TMP/$name.hdiff" | sed 's/^/    /'
        continue
    fi
    if ! $CC $CFLAGS -c "$TMP/$name.c" -o "$TMP/$name.o" 2>"$TMP/$name.cc.log"; then
        bad "$name" "generated C does not compile"
        sed 's/^/    /' "$TMP/$name.cc.log"
        continue
    fi
    if [ -f "$exp_out" ]; then
        if ! $CC $CFLAGS "$TMP/$name.c" -o "$TMP/$name.bin" 2>"$TMP/$name.link.log"; then
            bad "$name" "generated C does not link"
            sed 's/^/    /' "$TMP/$name.link.log"
            continue
        fi
        "$TMP/$name.bin" >"$TMP/$name.stdout" 2>&1
        if ! diff -u "$exp_out" "$TMP/$name.stdout" >"$TMP/$name.odiff"; then
            bad "$name" "program output differs from golden"
            sed -n '1,40p' "$TMP/$name.odiff" | sed 's/^/    /'
            continue
        fi
    fi
    ok "$name"
done

# ------------------------------------------------------------------ examples
echo
echo "== examples =="
for ct in examples/*/*.ct; do
    dir=$(dirname "$ct")
    name=$(basename "$ct" .ct)
    label="$dir/$name.ct"
    exp_out="$dir/$name.expected.out"

    if ! "$TMP/ctc" "$ct" -o "$TMP/ex-$name.c" 2>"$TMP/ex-$name.err"; then
        bad "$label" "ctc exited non-zero: $(cat "$TMP/ex-$name.err")"
        continue
    fi
    if ! $CC $CFLAGS "$TMP/ex-$name.c" -o "$TMP/ex-$name.bin" 2>"$TMP/ex-$name.log"; then
        bad "$label" "generated C does not build"
        sed 's/^/    /' "$TMP/ex-$name.log"
        continue
    fi
    "$TMP/ex-$name.bin" >"$TMP/ex-$name.stdout" 2>&1
    if ! diff -u "$exp_out" "$TMP/ex-$name.stdout" >"$TMP/ex-$name.diff"; then
        bad "$label" "program output differs from $exp_out"
        sed -n '1,40p' "$TMP/ex-$name.diff" | sed 's/^/    /'
        continue
    fi
    ok "$label"
done

# ------------------------------------------------------------------ errors
echo
echo "== error cases =="
for ct in test/errors/*.ct; do
    name=$(basename "$ct" .ct)
    expected="test/errors/$name.expected-err"

    if "$TMP/ctc" "$ct" -o "$TMP/err-$name.c" 2>"$TMP/err-$name.log"; then
        bad "$name" "expected a non-zero exit, got 0"
        continue
    fi

    # every diagnostic must carry a position: file:line:col: error: ...
    if ! grep -Eq ':[0-9]+:[0-9]+: error: ' "$TMP/err-$name.log"; then
        bad "$name" "diagnostic has no file:line:col prefix: $(cat "$TMP/err-$name.log")"
        continue
    fi

    st=1
    while IFS= read -r want; do
        case "$want" in '' | '#'*) continue ;; esac
        if ! grep -Fq -- "$want" "$TMP/err-$name.log"; then
            bad "$name" "diagnostic missing: $want"
            st=0
            break
        fi
    done <"$expected"
    if [ "$st" = 1 ]; then ok "$name"; fi
done

# ------------------------------------------------------------------ summary
echo
echo "== summary: $pass passed, $fail failed =="
if [ "$fail" -ne 0 ]; then
    printf 'failures:%b\n' "$failed_names"
    exit 1
fi
exit 0
