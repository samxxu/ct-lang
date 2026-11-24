#!/bin/sh
# Gate 1 after SH-119 S3: the seed-built ct is the compiler under test.
#
# The L0 C suite (L0 internals, dialect plugins, ctc-specific CLI) retired with
# selfhost/l0; its corpus coverage is retained by gate 12 (static goldens) and
# gate 8 (check-ast). This gate keeps the shipping build honest: the frozen seed
# must build, report its version, compile every test/cases fixture and produce C
# that cc accepts, then run one end-to-end example.
set -u
cd "$(dirname "$0")/.." || exit 1
CC=${CC:-cc}
TMP=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/ctrun.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "== build the seed ct =="
if $CC -Wall -Wextra -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o "$TMP/ct" 2>"$TMP/build.log"; then
    [ -s "$TMP/build.log" ] && { cat "$TMP/build.log" >&2; bad build "warnings"; } || ok "build (warning-free)"
else
    cat "$TMP/build.log" >&2; bad build "the seed did not build"; echo "test/run: FAIL"; exit 1
fi

ver=$("$TMP/ct" -v | awk '{print $NF}')
case "$ver" in v[0-9]*.[0-9]*.[0-9]*) ok "version ($ver)" ;; *) bad version "$ver" ;; esac

echo "== compile test/cases =="
n=0
for f in test/cases/*.ct; do
    b=$(basename "$f" .ct)
    if ! "$TMP/ct" compile "$f" -o "$TMP/$b.c" >"$TMP/$b.log" 2>&1; then
        bad "$b" "$(head -1 "$TMP/$b.log")"; continue
    fi
    if ! $CC -std=c99 -c "$TMP/$b.c" -o "$TMP/$b.o" >"$TMP/$b.cc" 2>&1; then
        bad "$b" "generated C does not compile: $(head -1 "$TMP/$b.cc")"; continue
    fi
    n=$((n+1))
done
[ "$n" -eq 25 ] && ok "all 25 test/cases compile and pass cc" || bad "test/cases" "$n/25"

echo "== end-to-end example =="
if "$TMP/ct" build examples/01_greeter/greeter.ct -o "$TMP/greet" >"$TMP/greet.log" 2>&1 \
   && "$TMP/greet" >"$TMP/greet.out" 2>&1; then
    ok "examples/01_greeter runs"
else
    bad greeter "$(head -2 "$TMP/greet.log" "$TMP/greet.out" 2>/dev/null | tr '\n' ' ')"
fi

echo "test/run: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
