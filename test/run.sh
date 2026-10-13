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
#   line      `#line` error mapping in multi-file mode                   (no fixture dir)
#   warnings  leak warnings + --diagnostics=json, exit stays 0           (no fixture dir)
#   limits    known limitations characterised: unrewritten one-liners     (no fixture dir)
#   warn      leak warnings and --diagnostics=text|json                  (no fixture dir)
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

# ------------------------------------------------------------------ #line
echo
echo "== #line (multi-file error mapping, D4 = A) =="
mkdir -p "$TMP/line"
# line 4 is a deliberate error: with #line the compiler must blame the .ct, not the .c
cat >"$TMP/line/err.ct" <<'EOF'
int helper(void) { return 0; }

int main(void) {
    int x = undefined_symbol;
    return x;
}
EOF
if ! "$TMP/ctc" build "$TMP/line/err.ct" -o "$TMP/line" >"$TMP/line.out" 2>"$TMP/line.err"; then
    bad "#line/build" "ctc build exited non-zero: $(cat "$TMP/line.err")"
else
    $CC $CFLAGS -c "$TMP/line/err.c" -o "$TMP/line/err.o" 2>"$TMP/line.cc" || true
    if grep -q 'err\.ct:4:' "$TMP/line.cc"; then
        ok "#line maps the C error back to the .ct line"
    else
        bad "#line" "expected 'err.ct:4:' in the C compiler diagnostic"
        sed -n '1,10p' "$TMP/line.cc" | sed 's/^/    /'
    fi
    "$TMP/ctc" build --no-line "$TMP/line/err.ct" -o "$TMP/line" >/dev/null 2>&1
    if grep -q '#line' "$TMP/line/err.c"; then
        bad "#line/--no-line" "directives were not suppressed"
    else
        ok "#line --no-line suppresses the directives"
    fi
fi

# ------------------------------------------------------------------ warnings
echo
echo "== leak warnings (Phase 1.7) =="
mkdir -p "$TMP/warn"
cat >"$TMP/warn/leak.ct" <<'EOF'
#include <stdlib.h>

struct Thing {
    int n;
};

struct Box {
    Thing *owner;
};

int leaky(void) {
    Thing *p = malloc(sizeof(struct Thing));
    return 0;
}

int clean(void) {
    Thing *q = malloc(sizeof(struct Thing));
    delete q;
    return 0;
}

int escaped(Box *b) {
    Thing *e = malloc(sizeof(struct Thing));
    b->owner = e;
    return 0;
}

int main(void) {
    Box b;
    return leaky() + clean() + escaped(&b);
}
EOF
if "$TMP/ctc" "$TMP/warn/leak.ct" -o "$TMP/warn/leak.c" >"$TMP/warn.out" 2>"$TMP/warn.err"; then
    n=$(grep -c 'warning: potential leak' "$TMP/warn.err")
    if [ "$n" = 1 ] && grep -Fq "'p' (Thing*)" "$TMP/warn.err"; then
        ok "warnings/exactly one leak (delete and escape stay quiet), exit 0"
    else
        bad "warnings/leak" "expected 1 warning naming 'p', got $n"
        sed 's/^/    /' "$TMP/warn.err"
    fi
else
    bad "warnings/leak" "ctc exited non-zero: $(cat "$TMP/warn.err")"
fi
if "$TMP/ctc" --diagnostics=json "$TMP/warn/leak.ct" -o "$TMP/warn/leak.c" 2>/dev/null \
   | python3 -c "import sys,json; w=json.load(sys.stdin)['warnings']; sys.exit(0 if len(w)==1 and w[0]['variable']=='p' and w[0]['type']=='potential_leak' else 1)"; then
    ok "warnings/--diagnostics=json parses (1 warning)"
else
    bad "warnings/json" "json output did not parse as expected"
fi
if "$TMP/ctc" --diagnostics=xml "$TMP/warn/leak.ct" -o "$TMP/warn/leak.c" >/dev/null 2>"$TMP/warn.err"; then
    bad "warnings/diag-unknown" "expected a non-zero exit for an unknown diagnostics format"
elif grep -Fq 'unknown diagnostics format' "$TMP/warn.err"; then
    ok "warnings/unknown diagnostics format rejected"
else
    bad "warnings/diag-unknown" "missing the expected message"
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

# ------------------------------------------------------------------ limits
echo
echo "== known limitations =="
# Characterisation test for a documented limitation (docs/language-spec.md §6.2):
# rewriting is line based, so a statement written on the same line as its
# construct is left alone. This pins the current behaviour so that a fix (or a
# regression) is visible here rather than silently.
cat >"$TMP/oneline.ct" <<'EOF'
#include <stdio.h>
trait T { void f(); }
struct S { int x; } use T;
impl T for S { void f() { printf("f %d\n", self->x); } }
int main(void){ S s; s.x = 1; s.f(); return 0; }
EOF
if ! "$TMP/ctc" "$TMP/oneline.ct" -o "$TMP/oneline.c" 2>"$TMP/oneline.err"; then
    bad "limits/one-line-accepted" "expected exit 0 (limitation), got non-zero: $(cat "$TMP/oneline.err")"
else
    if grep -Fq 'int main(void){ S s; s.x = 1; s.f(); return 0; }' "$TMP/oneline.c"; then
        ok "limits/one-line body is passed through unrewritten (known limitation)"
    else
        bad "limits/one-line" "expected the line verbatim; rewriting may now be implemented"
    fi
    if $CC $CFLAGS -c "$TMP/oneline.c" -o "$TMP/oneline.o" 2>/dev/null; then
        bad "limits/one-line-cc" "expected the un-rewritten output NOT to compile"
    else
        ok "limits/one-line output does not compile (consequence of the limitation)"
    fi
fi

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
cli_expect help-short zero "usage:" -h
cli_expect version zero "ctc v" --version
cli_expect version-short zero "ctc v" -v
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
cli_expect build-no-input nonzero "usage:" build
cli_expect build-version zero "ctc v" build --version

# #line: off by default in single-file mode, forceable with --line
"$TMP/ctc" test/cases/21_empty_init_iface.ct -o "$TMP/ln_default.c" 2>/dev/null
if grep -q '#line' "$TMP/ln_default.c"; then
    bad "cli/line-single-default" "single-file mode emitted #line by default"
else
    ok "cli/line-single-default (off by default)"
fi
if "$TMP/ctc" --line test/cases/21_empty_init_iface.ct -o "$TMP/ln_forced.c" 2>/dev/null \
        && grep -q '#line' "$TMP/ln_forced.c"; then
    ok "cli/line-single-forced (--line forces directives)"
else
    bad "cli/line-single-forced" "--line did not emit #line directives"
fi
cli_expect help-line-flag zero "--line" --help

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
