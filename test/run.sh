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
#   build     ctc itself must compile under -Wall -Wextra -std=c99 with no warnings
#   unit      white-box tests of ctc's pure helpers              (test/unit)
#   cases     golden tests: generate, diff, compile, run        (test/cases)
#   errors    diagnostics: must fail with the expected message  (test/errors)
#   examples  end-to-end demos: generate, build, run, compare   (examples)
#   multifile `ct build` multi-file demo: build, compare goldens, run   (test/multifile)
#   import    `ct build` with `import`: resolve, compare goldens, run    (test/import)
#   cli       argument handling: help/version/errors and `ct compile`    (no fixture dir)

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

# ------------------------------------------------------------------ multifile
echo
echo "== multi-file (ct build) =="
mkdir -p "$TMP/mf"
if ! "$TMP/ctc" build test/multifile/calc.ct test/multifile/app.ct -o "$TMP/mf" >"$TMP/mf.out" 2>"$TMP/mf.err"; then
    bad "multifile/build" "ctc build exited non-zero: $(cat "$TMP/mf.err")"
else
    # the generated .c/.h are pinned byte for byte, like the single-file cases
    for pair in calc.c:calc.expected.c calc.h:calc.expected.h \
                app.c:app.expected.c app.h:app.expected.h; do
        gen=${pair%%:*}; exp=${pair##*:}
        if ! diff -u "test/multifile/$exp" "$TMP/mf/$gen" >"$TMP/mf.$gen.diff"; then
            bad "multifile/golden" "$gen differs from $exp"
            sed -n '1,40p' "$TMP/mf.$gen.diff" | sed 's/^/    /'
        else
            ok "multifile/golden $gen"
        fi
    done
    if ! $CC $CFLAGS "$TMP/mf/calc.c" "$TMP/mf/app.c" -o "$TMP/mf/app" 2>"$TMP/mf.log"; then
        bad "multifile/cc" "generated C does not build"
        sed 's/^/    /' "$TMP/mf.log"
    else
        "$TMP/mf/app" >"$TMP/mf.stdout" 2>&1
        if ! diff -u test/multifile/expected.out "$TMP/mf.stdout" >"$TMP/mf.diff"; then
            bad "multifile/run" "program output differs from expected.out"
            sed -n '1,40p' "$TMP/mf.diff" | sed 's/^/    /'
        else
            ok "multifile/build+run"
        fi
    fi
fi

# ------------------------------------------------------------------ import
echo
echo "== import (ct build with a single root) =="
mkdir -p "$TMP/imp"
if ! "$TMP/ctc" build test/import/app.ct -o "$TMP/imp" >"$TMP/imp.out" 2>"$TMP/imp.err"; then
    bad "import/build" "ctc build exited non-zero: $(cat "$TMP/imp.err")"
else
    if [ ! -f "$TMP/imp/shapes.c" ]; then
        bad "import/build" "the imported unit was not compiled"
    fi
    # the generated .c/.h are pinned byte for byte, like the single-file cases
    for pair in shapes.c:shapes.expected.c shapes.h:shapes.expected.h \
                app.c:app.expected.c app.h:app.expected.h; do
        gen=${pair%%:*}; exp=${pair##*:}
        if ! diff -u "test/import/$exp" "$TMP/imp/$gen" >"$TMP/imp.$gen.diff"; then
            bad "import/golden" "$gen differs from $exp"
            sed -n '1,40p' "$TMP/imp.$gen.diff" | sed 's/^/    /'
        else
            ok "import/golden $gen"
        fi
    done
    if ! $CC $CFLAGS "$TMP/imp/shapes.c" "$TMP/imp/app.c" -o "$TMP/imp/app" 2>"$TMP/imp.log"; then
        bad "import/cc" "generated C does not build"
        sed 's/^/    /' "$TMP/imp.log"
    else
        "$TMP/imp/app" >"$TMP/imp.stdout" 2>&1
        if ! diff -u test/import/expected.out "$TMP/imp.stdout" >"$TMP/imp.diff"; then
            bad "import/run" "program output differs from expected.out"
            sed -n '1,40p' "$TMP/imp.diff" | sed 's/^/    /'
        else
            ok "import/build+run"
        fi
    fi
fi

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

# ------------------------------------------------------------------ cli
echo
echo "== cli =="

# cli_expect <label> <zero|nonzero> <required-output-or-empty> <ctc args...>
cli_expect() {
    cli_label=$1; cli_want=$2; cli_substr=$3; shift 3
    if "$TMP/ctc" "$@" >"$TMP/cli.out" 2>"$TMP/cli.err"; then cli_st=0; else cli_st=$?; fi
    if [ "$cli_want" = zero ]; then
        if [ "$cli_st" -ne 0 ]; then bad "cli/$cli_label" "expected exit 0, got $cli_st"; return; fi
    else
        if [ "$cli_st" -eq 0 ]; then bad "cli/$cli_label" "expected a non-zero exit"; return; fi
    fi
    if [ -n "$cli_substr" ] && ! grep -Fq -- "$cli_substr" "$TMP/cli.out" "$TMP/cli.err"; then
        bad "cli/$cli_label" "output missing: $cli_substr"
        return
    fi
    ok "cli/$cli_label"
}

cli_expect help zero "usage:" --help
cli_expect version zero "ctc v" --version
cli_expect unknown-option nonzero "unknown option" -Z
cli_expect o-needs-arg nonzero "-o needs an argument" test/cases/21_empty_init_iface.ct -o
cli_expect no-input nonzero "usage:"
cli_expect cannot-open nonzero "cannot open" /nonexistent/nope.ct

# `ct build` driver errors
printf 'import nothing;\n' >"$TMP/cli_imp.ct"
cli_expect build-import-missing nonzero "cannot resolve import" build "$TMP/cli_imp.ct" -o "$TMP"
cli_expect build-o-needs-arg nonzero "-o needs an argument" build test/cases/21_empty_init_iface.ct -o
cli_expect build-unknown-option nonzero "unknown option" build -Q test/cases/21_empty_init_iface.ct
cli_expect build-cannot-write nonzero "cannot write" build test/cases/21_empty_init_iface.ct -o /nonexistent-dir

# `compile` is an explicit alias for the default subcommand; its output must be
# byte-identical to the default-mode golden
if "$TMP/ctc" compile test/cases/21_empty_init_iface.ct -o "$TMP/cli.c" 2>"$TMP/cli.err"; then
    if diff -u test/cases/21_empty_init_iface.expected.c "$TMP/cli.c" >"$TMP/cli.diff"; then
        ok "cli/compile-subcommand"
    else
        bad "cli/compile-subcommand" "output differs from the default-mode golden"
        sed -n '1,40p' "$TMP/cli.diff" | sed 's/^/    /'
    fi
else
    bad "cli/compile-subcommand" "ctc compile exited non-zero: $(cat "$TMP/cli.err")"
fi

# ------------------------------------------------------------------ summary
echo
echo "== summary: $pass passed, $fail failed =="
if [ "$fail" -ne 0 ]; then
    printf 'failures:%b\n' "$failed_names"
    exit 1
fi
exit 0
