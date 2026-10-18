#!/bin/sh
#
# test/pkg/run.sh - Phase 8.1: the local half of ct-pkg.
#
# Builds the whole bootstrap chain (L0 -> L1 -> L2) and exercises `ct get` on a
# throwaway project: manifest parsing, a version range, a recursive local `dep`,
# vendoring into `vendor/<name>` and the resolution order recorded in `ct.lock`.
# No git and no network are involved -- 8.2 adds those.
#
# Usage:  bash test/pkg/run.sh
#         CC=gcc bash test/pkg/run.sh
#
# Exit code 0 means every assertion passed.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-pkg-test.$$"

rm -rf "$work"
mkdir -p "$work" || exit 1

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "cc: $CC"
echo
echo "== build the bootstrap chain =="
if ! "$CC" -Wall -Wextra -std=c99 ctc.c -o "$work/ctc" 2>"$work/l0.log"; then
    echo "  compiler build failed:"; sed 's/^/    /' "$work/l0.log"; exit 1
fi
if ! "$work/ctc" selfhost/ctc.ct -o "$work/l1.c" 2>"$work/l1.log"; then
    echo "  L0 could not compile L1:"; sed 's/^/    /' "$work/l1.log"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "  L1 did not build:"; sed 's/^/    /' "$work/l1b.log"; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build selfhost/src/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "  L1 could not build the split tree:"; sed 's/^/    /' "$work/l2.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "  L2 did not build:"; sed 's/^/    /' "$work/l2b.log"; exit 1
fi
ok "the chain builds (L0 -> L1 -> L2)"

echo
echo "== a project and two local packages =="
mkdir -p "$work/proj" "$work/pkgs/util" "$work/pkgs/extra"
printf 'name = demo\nversion = 0.1.0\n' >"$work/proj/ct.pkg"
printf 'name = util\nversion = 0.2.0\nlicense = MIT\ndep = ../extra@^0.1.0\n' >"$work/pkgs/util/ct.pkg"
printf 'int util_value(void) { return 42; }\n' >"$work/pkgs/util/util.c"
printf 'name = extra\nversion = 0.1.0\n' >"$work/pkgs/extra/ct.pkg"
printf 'int extra_value(void) { return 7; }\n' >"$work/pkgs/extra/extra.c"
ok "fixtures created"

echo
echo "== ct get: recursive local dependency =="
if ( cd "$work/proj" && "$work/l2" get ../pkgs/util >"$work/get.out" 2>"$work/get.err" ); then
    ok "exits 0"
else
    bad "ct get" "non-zero exit: $(cat "$work/get.err")"
fi
if [ -f "$work/proj/vendor/util/ct.pkg" ] && [ -f "$work/proj/vendor/util/util.c" ]; then
    ok "vendors the requested package"
else
    bad "ct get" "vendor/util is incomplete"
fi
if [ -f "$work/proj/vendor/extra/ct.pkg" ] && [ -f "$work/proj/vendor/extra/extra.c" ]; then
    ok "vendors the transitive dependency"
else
    bad "ct get" "vendor/extra is incomplete"
fi
if [ -f "$work/proj/ct.lock" ]; then
    first="$(sed -n 1p "$work/proj/ct.lock")"
    second="$(sed -n 2p "$work/proj/ct.lock")"
    case "$first" in
        extra\ 0.1.0*) ok "the lock lists the dependency first" ;;
        *) bad "ct.lock" "expected extra first, got '$first'" ;;
    esac
    case "$second" in
        util\ 0.2.0*) ok "the lock lists the requested package second" ;;
        *) bad "ct.lock" "expected util second, got '$second'" ;;
    esac
else
    bad "ct.lock" "was not written"
fi

echo
echo "== a range that cannot match =="
if ( cd "$work/proj" && "$work/l2" get ../pkgs/util@^1.0.0 >"$work/mm.out" 2>"$work/mm.err" ); then
    bad "mismatch" "expected a non-zero exit"
elif grep -Fq "does not satisfy" "$work/mm.err"; then
    ok "rejects a version outside the range"
else
    bad "mismatch" "wrong diagnostic: $(cat "$work/mm.err")"
fi

echo
echo "== a directory without ct.pkg =="
mkdir -p "$work/pkgs/empty"
if ( cd "$work/proj" && "$work/l2" get ../pkgs/empty >"$work/e.out" 2>"$work/e.err" ); then
    bad "no-manifest" "expected a non-zero exit"
elif grep -Eq "cannot (open|read)" "$work/e.err"; then
    ok "reports a missing manifest"
else
    bad "no-manifest" "wrong diagnostic: $(cat "$work/e.err")"
fi

echo
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
