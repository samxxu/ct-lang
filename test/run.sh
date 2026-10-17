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
#   limits    known limitations characterised: unrewritten one-liners     (no fixture dir)
#   cli       argument handling: help/version/errors and `ct compile`    (no fixture dir)
#
# test/archive/ holds the Phases 2–5 (CT-side) fixtures -- namespaces, multi-file
# `ct build`, imports, Drop, `#line` and warning diagnostics -- that Phase 0.3
# moved out of ctc.c. They are kept, not run here, as the diff baseline for the
# Phases 2–5 CT reimplementation.

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

# A method body now goes through the very same rewriting pipeline as top-level
# code (Phase 1.9c): a local variable receiver inside an impl body is dispatched
# and the emitted method compiles.
cat >"$TMP/bodyrecv.ct" <<'EOF'
#include <stdio.h>
trait G { void greet(); void run(); }
struct P { char *name; } use G;
impl G for P {
    void greet() { printf("hi %s\n", self->name); }
    void run() {
        struct P q = { .name = "Q" };
        q.greet();
    }
}
int main(void) {
    struct P p = { .name = "Z" };
    p.run();
    return 0;
}
EOF
if ! "$TMP/ctc" "$TMP/bodyrecv.ct" -o "$TMP/bodyrecv.c" 2>"$TMP/bodyrecv.err"; then
    bad "limits/body-local-receiver" "expected exit 0, got non-zero: $(cat "$TMP/bodyrecv.err")"
else
    if grep -Fq 'q.__g_vptr->greet(&q);' "$TMP/bodyrecv.c"; then
        ok "limits/a local receiver inside a method body is dispatched"
    else
        bad "limits/body-local-receiver" "expected the dispatched call 'q.__g_vptr->greet(&q);'"
    fi
    if $CC $CFLAGS -c "$TMP/bodyrecv.c" -o "$TMP/bodyrecv.o" 2>/dev/null; then
        ok "limits/body-local receiver output compiles"
    else
        bad "limits/body-local-receiver-cc" "expected the rewritten output to compile"
    fi
fi

# Same line-based rule, for the two forms the oneline case above does not cover:
# interface boxing and an rvalue receiver sharing their line with the construct.
cat >"$TMP/oneline_box.ct" <<'EOF'
#include <stdio.h>
trait G { void greet(); }
struct P { char *name; } use G;
impl G for P { void greet() { printf("hi %s\n", self->name); } }
void announce(G g);
int main(void){ struct P p = { .name = "B" }; announce(p); return 0; }
EOF
if "$TMP/ctc" "$TMP/oneline_box.ct" -o "$TMP/oneline_box.c" 2>"$TMP/oneline_box.err" \
        && grep -Fq 'announce(p)' "$TMP/oneline_box.c" \
        && ! grep -Fq 'G_iface)' "$TMP/oneline_box.c"; then
    ok "limits/a one-line interface argument is passed through unboxed (known limitation)"
else
    bad "limits/oneline-box" "expected 'announce(p)' verbatim and no boxing"
fi

cat >"$TMP/oneline_rval.ct" <<'EOF'
#include <stdio.h>
trait G { void greet(); }
struct P { char *name; } use G;
struct P mk(void) { struct P p = { .name = "A" }; return p; }
impl G for P { void greet() { printf("hi %s\n", self->name); } }
int main(void){ mk().greet(); return 0; }
EOF
if "$TMP/ctc" "$TMP/oneline_rval.ct" -o "$TMP/oneline_rval.c" 2>"$TMP/oneline_rval.err" \
        && grep -Fq 'mk().greet();' "$TMP/oneline_rval.c"; then
    ok "limits/a one-line rvalue receiver is passed through unrewritten (known limitation)"
else
    bad "limits/oneline-rval" "expected 'mk().greet();' verbatim; rewriting may now be implemented"
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

# capabilities that moved to the CT layer in Phase 0.3 must fail loudly instead
# of falling through: the module system (namespace / import / pub / `ct build`)
# and the diagnostics flags
cli_expect build-removed nonzero "'build' (multi-file) is not supported" build a.ct -o "$TMP/x"
cli_expect diagnostics-removed nonzero "unknown option" --diagnostics=json test/cases/01_trait_basic.ct
cli_expect line-removed nonzero "unknown option" --line test/cases/01_trait_basic.ct

# the output write is a failure site: the .c cannot be created
cli_expect compile-cannot-write nonzero "cannot write" compile test/cases/21_empty_init_iface.ct -o /nonexistent-dir/x.c
cli_expect short-read nonzero "short read" "$TMP"

# two more reachable driver failure sites (2026-10-17 audit): a non-seekable
# input — a pipe — makes read_file's fseek/ftell fail (`cannot read`), and an
# unusable $TMPDIR makes tmpfile() fail (`cannot create a temporary file`).
# Both messages are pinned verbatim against the real binary.
if printf 'int x;\n' | "$TMP/ctc" /dev/stdin -o "$TMP/stdin.c" >"$TMP/cli.out" 2>"$TMP/cli.err"; then
    bad "cli/cannot-read" "expected a non-zero exit"
elif grep -Fq "cannot read" "$TMP/cli.err"; then
    ok "cli/cannot-read"
else
    bad "cli/cannot-read" "wrong message: $(cat "$TMP/cli.err")"
fi

if TMPDIR=/nonexistent/zzz "$TMP/ctc" test/cases/21_empty_init_iface.ct -o "$TMP/tmpdir.c" >"$TMP/cli.out" 2>"$TMP/cli.err"; then
    bad "cli/tmpfile-cannot-create" "expected a non-zero exit"
elif grep -Fq "cannot create a temporary file" "$TMP/cli.err"; then
    ok "cli/tmpfile-cannot-create"
else
    bad "cli/tmpfile-cannot-create" "wrong message: $(cat "$TMP/cli.err")"
fi

# the header write is a separate failure site from the .c write above: make the
# same-named .h path a directory so the header open fails
mkdir -p "$TMP/hdr/x.h"
printf 'int main(void){ return 0; }\n' >"$TMP/hdr/x.ct"
if "$TMP/ctc" "$TMP/hdr/x.ct" -o "$TMP/hdr/x.c" >"$TMP/cli.out" 2>"$TMP/cli.err"; then
    bad "cli/cannot-write-header" "expected a non-zero exit"
elif grep -Fq "cannot write" "$TMP/cli.err"; then
    ok "cli/cannot-write-header"
else
    bad "cli/cannot-write-header" "wrong message: $(cat "$TMP/cli.err")"
fi

# default_output()'s other branch: a `.ct` suffix is stripped, but an input
# without one keeps its whole name, so the output lands as <input>.c with the
# header beside it. Pinned because the audit found the branch untested.
cp test/cases/21_empty_init_iface.ct "$TMP/noext"
if "$TMP/ctc" "$TMP/noext" >"$TMP/cli.out" 2>"$TMP/cli.err" &&
    [ -s "$TMP/noext.c" ] && [ -s "$TMP/noext.h" ]; then
    ok "cli/default-output-non-ct"
else
    bad "cli/default-output-non-ct" "expected <input>.c + <input>.h for a non-.ct input: $(cat "$TMP/cli.err")"
fi

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
