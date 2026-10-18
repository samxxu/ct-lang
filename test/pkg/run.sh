#!/bin/sh
#
# test/pkg/run.sh - Phase 8.1 + 8.2: the local and git halves of ct-pkg.
#
# Builds the whole bootstrap chain (L0 -> L1 -> L2) and exercises `ct get` on a
# throwaway project: manifest parsing, a version range, a recursive local `dep`,
# vendoring into `vendor/<name>` and the resolution order recorded in `ct.lock`.
# Phase 8.2 adds a git source: a local git repository stands in for the registry
# (so the test needs no network), and the `git` absent case must fail hard. The
# cache and the registry are redirected through HOME / CT_REGISTRY.
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
echo "== git sources (a local git repo stands in for the registry) =="
if ! command -v git >/dev/null 2>&1; then
    echo "  skip  git is not installed"
else
    GIT_AUTHOR_EMAIL=pkg@test GIT_AUTHOR_NAME=pkg
    GIT_COMMITTER_EMAIL=pkg@test GIT_COMMITTER_NAME=pkg
    export GIT_AUTHOR_EMAIL GIT_AUTHOR_NAME GIT_COMMITTER_EMAIL GIT_COMMITTER_NAME
    reg="$work/reg"
    mkdir -p "$reg/gutil"
    ( cd "$reg/gutil" \
        && git init -q \
        && printf 'name = gutil\nversion = 0.1.0\n' >ct.pkg \
        && printf 'int gutil_value(void) { return 3; }\n' >gutil.c \
        && git add -A && git commit -qm one && git tag 0.1.0 \
        && printf 'name = gutil\nversion = 0.2.0\n' >ct.pkg \
        && git add -A && git commit -qm two && git tag v0.2.0 )
    mkdir -p "$work/home"
    if ( cd "$work/proj" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/l2" get "gutil@^0.1.0" >"$work/g.out" 2>"$work/g.err" ); then
        ok "ct get <git> exits 0"
    else
        bad "ct get <git>" "non-zero exit: $(cat "$work/g.err")"
    fi
    if [ -f "$work/proj/vendor/gutil/ct.pkg" ] && [ -f "$work/proj/vendor/gutil/gutil.c" ]; then
        ok "vendors the git package"
    else
        bad "ct get <git>" "vendor/gutil is incomplete"
    fi
    if grep -Eq "^gutil 0\.1\.0 git [0-9a-f]{40}$" "$work/proj/ct.lock"; then
        ok "MVS picks the lowest satisfying tag and pins its commit"
    else
        bad "ct.lock <git>" "expected 'gutil 0.1.0 git <commit>', got: $(grep gutil "$work/proj/ct.lock")"
    fi

    echo
    echo "== a git repo with no tags falls back to the default branch =="
    mkdir -p "$reg/notags"
    ( cd "$reg/notags" \
        && git init -q \
        && printf 'name = notags\nversion = 0.0.1\n' >ct.pkg \
        && printf 'int notags_value(void) { return 9; }\n' >notags.c \
        && git add -A && git commit -qm one )
    if ( cd "$work/proj" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/l2" get "notags@*" >"$work/h.out" 2>"$work/h.err" ); then
        if grep -Eq "^notags 0\.0\.1 git [0-9a-f]{40}$" "$work/proj/ct.lock"; then
            ok "locks the default branch tip when there is no tag"
        else
            bad "ct.lock <HEAD>" "expected 'notags 0.0.1 git <commit>', got: $(grep notags "$work/proj/ct.lock")"
        fi
    else
        bad "ct get <HEAD>" "non-zero exit: $(cat "$work/h.err")"
    fi

    echo
    echo "== without git on PATH, a git source fails hard =="
    mkdir -p "$work/nobin"
    if ( cd "$work/proj" && PATH="$work/nobin" HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/l2" get "gutil@^0.1.0" >"$work/ng.out" 2>"$work/ng.err" ); then
        bad "no-git" "expected a non-zero exit"
    elif grep -Fq "install git" "$work/ng.err"; then
        ok "fails hard with an install hint"
    else
        bad "no-git" "wrong diagnostic: $(cat "$work/ng.err")"
    fi
fi

echo
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
