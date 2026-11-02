#!/bin/sh
#
# test/pkg/run.sh - Phase 8.1 + 8.2 + 8.3: the local, git and install halves of ct-pkg.
#
# Builds the whole bootstrap chain (L0 -> L1 -> L2 -> ct-ast, the compiler that
# now ships `get`/`install`) and exercises `ct get` on a throwaway project:
# manifest parsing, a version range, a recursive local `dep`, vendoring into
# `vendor/<name>` and the resolution order recorded in `ct.lock`.
# Phase 8.2 adds a git source: a local git repository stands in for the registry
# (so the test needs no network), and the `git` absent case must fail hard. The
# cache and the registry are redirected through HOME / CT_REGISTRY.
# Phase 8.3 adds `ct install`, which checks the vendored tree against the lock's
# content digests and the manifest's dependencies, then prints a `ct build`
# command; a tampered tree, a missing package or an uncovered dependency fails.
# The error branches of both subcommands are covered too: no or empty `ct.lock`,
# a missing or incomplete `ct.pkg`, a malformed `dep` and bad `ct get` arguments.
# Phase 17.5 adds the comparator ranges, `ct update` / `ct verify`, the explicit
# plain-text index (`CT_INDEX` / `--index`) and the build metadata that `ct
# install` folds into its single printed command.
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
if ! "$CC" -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$work/ctc" 2>"$work/l0.log"; then
    echo "  compiler build failed:"; sed 's/^/    /' "$work/l0.log"; exit 1
fi
if ! "$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" 2>"$work/l1.log"; then
    echo "  L0 could not compile L1:"; sed 's/^/    /' "$work/l1.log"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "  L1 did not build:"; sed 's/^/    /' "$work/l1b.log"; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "  L1 could not build the split tree:"; sed 's/^/    /' "$work/l2.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "  L2 did not build:"; sed 's/^/    /' "$work/l2b.log"; exit 1
fi
# Phase 10.6: the package subcommands now ship with the AST compiler (ct-ast),
# which L2 builds from selfhost/ct-ast/main.ct. This gate drives that entry.
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.out" 2>&1; then
    echo "  L2 could not build the AST compiler:"; sed 's/^/    /' "$work/ast.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
    echo "  the AST compiler did not build:"; sed 's/^/    /' "$work/astb.log"; exit 1
fi
ok "the chain builds (L0 -> L1 -> L2 -> ct-ast)"

echo
echo "== a project and two local packages =="
mkdir -p "$work/proj" "$work/pkgs/util" "$work/pkgs/extra"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/util@^0.2.0\n' >"$work/proj/ct.pkg"
printf 'import util;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(21)); return 0; }\n' >"$work/proj/main.ct"
printf 'name = util\nversion = 0.2.0\nlicense = MIT\ndep = ../extra@^0.1.0\n' >"$work/pkgs/util/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$work/pkgs/util/util.h.ct"
printf 'name = extra\nversion = 0.1.0\n' >"$work/pkgs/extra/ct.pkg"
printf 'int extra_value(void) { return 7; }\n' >"$work/pkgs/extra/extra.c"
ok "fixtures created"

echo
echo "== ct get: recursive local dependency =="
if ( cd "$work/proj" && "$work/ct-ast" get ../pkgs/util >"$work/get.out" 2>"$work/get.err" ); then
    ok "exits 0"
else
    bad "ct get" "non-zero exit: $(cat "$work/get.err")"
fi
if [ -f "$work/proj/vendor/util/ct.pkg" ] && [ -f "$work/proj/vendor/util/util.h.ct" ]; then
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
# D24: `get` writes the manifest too, and a re-run must not duplicate the line
# that already named this package (the fixture spells it with a range).
if [ "$(grep -c '^dep = ' "$work/proj/ct.pkg")" = "1" ]; then
    ok "get leaves an existing dep line alone"
else
    bad "ct.pkg" "unexpected dep lines: $(cat "$work/proj/ct.pkg")"
fi

echo
echo "== ct install: verifies the lock and prints a build command =="
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/i.out" 2>"$work/i.err" ); then
    ok "ct install exits 0"
else
    bad "ct install" "non-zero exit: $(cat "$work/i.err")"
fi
if grep -Fq -- "-I vendor/util" "$work/i.out" && grep -Fq -- "-I vendor/extra" "$work/i.out" \
   && grep -Fq "build" "$work/i.out"; then
    ok "suggests -I roots for every vendored package"
else
    bad "ct install" "no suggested build command: $(cat "$work/i.out")"
fi

echo
echo "== ct install rejects a tampered vendor tree =="
printf 'pub int twice(int x);\nint twice(int x) { return 99; }\n' >"$work/proj/vendor/util/util.h.ct"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/it.out" 2>"$work/it.err" ); then
    bad "install tamper" "expected a non-zero exit"
elif grep -Fq "does not match ct.lock" "$work/it.err"; then
    ok "rejects a digest mismatch"
else
    bad "install tamper" "wrong diagnostic: $(cat "$work/it.err")"
fi
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$work/proj/vendor/util/util.h.ct"

echo
echo "== ct install rejects a same-size tamper =="
# SH-44: a change that keeps the file's length must still be caught.
printf 'pub int twice(int x);\nint twice(int x) { return 3 * x; }\n' >"$work/proj/vendor/util/util.h.ct"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/is.out" 2>"$work/is.err" ); then
    bad "install same-size tamper" "expected a non-zero exit"
elif grep -Fq "does not match ct.lock" "$work/is.err"; then
    ok "rejects a same-size digest mismatch"
else
    bad "install same-size tamper" "wrong diagnostic: $(cat "$work/is.err")"
fi
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$work/proj/vendor/util/util.h.ct"

echo
echo "== ct install rejects a legacy FNV digest =="
# SH-44: the algorithm is part of the lock format. A 16-hex FNV value must be
# reported, not silently compared against a SHA-256.
cp "$work/proj/ct.lock" "$work/proj/ct.lock.good"
sed -E 's/sha256:[0-9a-f]{64}/0123456789abcdef/' "$work/proj/ct.lock.good" >"$work/proj/ct.lock"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/il.out" 2>"$work/il.err" ); then
    bad "install legacy digest" "expected a non-zero exit"
elif grep -Fq "unsupported digest" "$work/il.err"; then
    ok "rejects a legacy FNV digest"
else
    bad "install legacy digest" "wrong diagnostic: $(cat "$work/il.err")"
fi
mv "$work/proj/ct.lock.good" "$work/proj/ct.lock"

echo
echo "== ct install rejects a missing vendored package =="
mv "$work/proj/vendor/extra" "$work/proj/vendor/extra.bak"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/im.out" 2>"$work/im.err" ); then
    bad "install missing" "expected a non-zero exit"
elif grep -Fq "not vendored" "$work/im.err"; then
    ok "rejects a missing vendored package"
else
    bad "install missing" "wrong diagnostic: $(cat "$work/im.err")"
fi
mv "$work/proj/vendor/extra.bak" "$work/proj/vendor/extra"

echo
echo "== ct install rejects an uncovered manifest dependency =="
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/util@^0.2.0\ndep = ghost@^1.0.0\n' >"$work/proj/ct.pkg"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/ic.out" 2>"$work/ic.err" ); then
    bad "install coverage" "expected a non-zero exit"
elif grep -Fq "is not satisfied by ct.lock" "$work/ic.err"; then
    ok "rejects a dependency missing from the lock"
else
    bad "install coverage" "wrong diagnostic: $(cat "$work/ic.err")"
fi
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/util@^0.2.0\n' >"$work/proj/ct.pkg"

echo
echo "== ct install rejects a malformed dep =="
printf 'name = demo\nversion = 0.1.0\ndep = @^0.1.0\n' >"$work/proj/ct.pkg"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/id.out" 2>"$work/id.err" ); then
    bad "install bad dep" "expected a non-zero exit"
elif grep -Fq "bad dependency" "$work/id.err"; then
    ok "rejects a dep with no path"
else
    bad "install bad dep" "wrong diagnostic: $(cat "$work/id.err")"
fi
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/util@^0.2.0\n' >"$work/proj/ct.pkg"

echo
echo "== ct build compiles against vendor/ =="
mkdir -p "$work/proj/out"
if ( cd "$work/proj" && "$work/ct-ast" build --emit-c -I vendor/util main.ct -o out >"$work/b.out" 2>"$work/b.err" ); then
    if "$CC" "$work/proj/out"/*.c -o "$work/app" 2>"$work/bc.err" \
       && [ "$("$work/app")" = "42" ]; then
        ok "imports a vendored package and runs"
    else
        bad "build vendor" "compile/run failed: $(cat "$work/bc.err")"
    fi
else
    bad "build vendor" "ct build failed: $(cat "$work/b.err")"
fi

echo
echo "== a range that cannot match =="
if ( cd "$work/proj" && "$work/ct-ast" get ../pkgs/util@^1.0.0 >"$work/mm.out" 2>"$work/mm.err" ); then
    bad "mismatch" "expected a non-zero exit"
elif grep -Fq "does not satisfy" "$work/mm.err"; then
    ok "rejects a version outside the range"
else
    bad "mismatch" "wrong diagnostic: $(cat "$work/mm.err")"
fi

echo
echo "== a directory without ct.pkg =="
mkdir -p "$work/pkgs/empty"
if ( cd "$work/proj" && "$work/ct-ast" get ../pkgs/empty >"$work/e.out" 2>"$work/e.err" ); then
    bad "no-manifest" "expected a non-zero exit"
elif grep -Eq "cannot (open|read)" "$work/e.err"; then
    ok "reports a missing manifest"
else
    bad "no-manifest" "wrong diagnostic: $(cat "$work/e.err")"
fi

echo
echo "== ct install: missing or empty ct.lock =="
mkdir -p "$work/nolock"
printf 'name = demo\nversion = 0.1.0\n' >"$work/nolock/ct.pkg"
if ( cd "$work/nolock" && "$work/ct-ast" install >"$work/nl.out" 2>"$work/nl.err" ); then
    bad "install no-lock" "expected a non-zero exit"
elif grep -Fq "no './ct.lock'" "$work/nl.err"; then
    ok "asks for ct.lock when it is missing"
else
    bad "install no-lock" "wrong diagnostic: $(cat "$work/nl.err")"
fi
: >"$work/nolock/ct.lock"
if ( cd "$work/nolock" && "$work/ct-ast" install >"$work/el.out" 2>"$work/el.err" ); then
    bad "install empty-lock" "expected a non-zero exit"
elif grep -Fq "ct.lock is empty" "$work/el.err"; then
    ok "rejects an empty ct.lock"
else
    bad "install empty-lock" "wrong diagnostic: $(cat "$work/el.err")"
fi

echo
echo "== ct install without ct.pkg =="
mkdir -p "$work/nomanifest"
if ( cd "$work/nomanifest" && "$work/ct-ast" install >"$work/nm.out" 2>"$work/nm.err" ); then
    bad "install no-manifest" "expected a non-zero exit"
elif grep -Fq "cannot open './ct.pkg'" "$work/nm.err"; then
    ok "reports a missing manifest"
else
    bad "install no-manifest" "wrong diagnostic: $(cat "$work/nm.err")"
fi

echo
echo "== ct install with an incomplete manifest =="
printf 'name = demo\n' >"$work/nomanifest/ct.pkg"
if ( cd "$work/nomanifest" && "$work/ct-ast" install >"$work/ni.out" 2>"$work/ni.err" ); then
    bad "install incomplete-manifest" "expected a non-zero exit"
elif grep -Fq "cannot read './ct.pkg'" "$work/ni.err"; then
    ok "rejects a manifest without a version"
else
    bad "install incomplete-manifest" "wrong diagnostic: $(cat "$work/ni.err")"
fi

echo
echo "== ct get: argument errors =="
if ( cd "$work/proj" && "$work/ct-ast" get --bogus >"$work/ga.out" 2>"$work/ga.err" ); then
    bad "get unknown-option" "expected a non-zero exit"
elif grep -Fq "unknown option '--bogus'" "$work/ga.err"; then
    ok "rejects an unknown option"
else
    bad "get unknown-option" "wrong diagnostic: $(cat "$work/ga.err")"
fi
if ( cd "$work/proj" && "$work/ct-ast" get >"$work/gn.out" 2>"$work/gn.err" ); then
    bad "get no-spec" "expected a non-zero exit"
elif grep -Fq "usage:" "$work/gn.err"; then
    ok "prints usage without a spec"
else
    bad "get no-spec" "wrong diagnostic: $(cat "$work/gn.err")"
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
            "$work/ct-ast" get "gutil@^0.1.0" >"$work/g.out" 2>"$work/g.err" ); then
        ok "ct get <git> exits 0"
    else
        bad "ct get <git>" "non-zero exit: $(cat "$work/g.err")"
    fi
    if [ -f "$work/proj/vendor/gutil/ct.pkg" ] && [ -f "$work/proj/vendor/gutil/gutil.c" ]; then
        ok "vendors the git package"
    else
        bad "ct get <git>" "vendor/gutil is incomplete"
    fi
    # D24: the manifest records what `get` brought in, so `install` can be run
    # later without re-typing the spec.
    if grep -Fq 'dep = gutil@^0.1.0' "$work/proj/ct.pkg"; then
        ok "get records the git package in ct.pkg"
    else
        bad "ct.pkg <git>" "missing the gutil dep: $(cat "$work/proj/ct.pkg")"
    fi
    if grep -Eq "^gutil 0\.1\.0 git [0-9a-f]{40} sha256:[0-9a-f]{64}$" "$work/proj/ct.lock"; then
        ok "MVS picks the lowest satisfying tag and pins its commit"
    else
        bad "ct.lock <git>" "expected 'gutil 0.1.0 git <commit> sha256:<digest>', got: $(grep gutil "$work/proj/ct.lock")"
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
            "$work/ct-ast" get "notags@*" >"$work/h.out" 2>"$work/h.err" ); then
        if grep -Eq "^notags 0\.0\.1 git [0-9a-f]{40} sha256:[0-9a-f]{64}$" "$work/proj/ct.lock"; then
            ok "locks the default branch tip when there is no tag"
        else
            bad "ct.lock <HEAD>" "expected 'notags 0.0.1 git <commit> sha256:<digest>', got: $(grep notags "$work/proj/ct.lock")"
        fi
    else
        bad "ct get <HEAD>" "non-zero exit: $(cat "$work/h.err")"
    fi

    echo
    echo "== without git on PATH, a git source fails hard =="
    mkdir -p "$work/nobin"
    if ( cd "$work/proj" && PATH="$work/nobin" HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil@^0.1.0" >"$work/ng.out" 2>"$work/ng.err" ); then
        bad "no-git" "expected a non-zero exit"
    elif grep -Fq "install git" "$work/ng.err"; then
        ok "fails hard with an install hint"
    else
        bad "no-git" "wrong diagnostic: $(cat "$work/ng.err")"
    fi

    echo
    echo "== a fetched manifest whose name differs from the source =="
    mkdir -p "$reg/mismatch"
    ( cd "$reg/mismatch" \
        && git init -q \
        && printf 'name = other\nversion = 0.1.0\n' >ct.pkg \
        && printf 'int other_value(void) { return 1; }\n' >other.c \
        && git add -A && git commit -qm one && git tag 0.1.0 )
    if ( cd "$work/proj" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "mismatch@*" >"$work/mis.out" 2>"$work/mis.err" ); then
        bad "name mismatch" "expected a non-zero exit"
    elif grep -Fq "names 'other'" "$work/mis.err"; then
        ok "rejects a manifest name that disagrees with the source"
    else
        bad "name mismatch" "wrong diagnostic: $(cat "$work/mis.err")"
    fi

    echo
    echo "== an explicit index resolves a bare package name =="
    # A throwaway project pins gutil 0.1.0 and its digest; the digest is the
    # index entry's fifth field, so the index can vouch for the vendored tree.
    mkdir -p "$work/idxseed" "$work/home2"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/idxseed/ct.pkg"
    if ( cd "$work/idxseed" && HOME="$work/home2" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil@^0.1.0" >"$work/is.out" 2>"$work/is.err" ); then
        dig="$(awk '$1 == "gutil" { print $NF }' "$work/idxseed/ct.lock")"
        printf 'gutil 0.1.0 file://%s/gutil 0.1.0 %s\n' "$reg" "$dig" >"$work/index"
        ok "a seeded lock supplies the index digest"
    else
        bad "index seed" "non-zero exit: $(cat "$work/is.err")"
    fi
    mkdir -p "$work/idxuse"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/idxuse/ct.pkg"
    if ( cd "$work/idxuse" && HOME="$work/home2" \
            "$work/ct-ast" get --index "$work/index" gutil >"$work/ix.out" 2>"$work/ix.err" ); then
        ok "resolves a bare name through --index"
    else
        bad "index lookup" "non-zero exit: $(cat "$work/ix.err")"
    fi
    if [ -f "$work/idxuse/vendor/gutil/ct.pkg" ]; then
        ok "the index entry's git source is vendored"
    else
        bad "index vendor" "vendor/gutil is missing"
    fi
    if grep -Eq "^gutil 0\.1\.0 git [0-9a-f]{40} sha256:[0-9a-f]{64}$" "$work/idxuse/ct.lock"; then
        ok "the indexed version and digest reach ct.lock"
    else
        bad "index lock" "unexpected lock line: $(grep gutil "$work/idxuse/ct.lock")"
    fi
    mkdir -p "$work/idxenv"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/idxenv/ct.pkg"
    if ( cd "$work/idxenv" && HOME="$work/home2" CT_INDEX="$work/index" \
            "$work/ct-ast" get gutil >"$work/ie.out" 2>"$work/ie.err" ); then
        ok "CT_INDEX names the same index as --index"
    else
        bad "CT_INDEX" "non-zero exit: $(cat "$work/ie.err")"
    fi
    if ( cd "$work/idxuse" && HOME="$work/home2" \
            "$work/ct-ast" get --index "$work/index" absent >"$work/ia.out" 2>"$work/ia.err" ); then
        bad "index missing-name" "expected a non-zero exit"
    elif grep -Fq "package 'absent' is not in the index" "$work/ia.err"; then
        ok "a name the index does not list is rejected"
    else
        bad "index missing-name" "wrong diagnostic: $(cat "$work/ia.err")"
    fi
    if ( cd "$work/idxuse" && HOME="$work/home2" \
            "$work/ct-ast" get --index "$work/no-such-index" gutil >"$work/ir.out" 2>"$work/ir.err" ); then
        bad "index unreadable" "expected a non-zero exit"
    elif grep -Fq "cannot read the package index" "$work/ir.err"; then
        ok "an unreadable index fails with its path"
    else
        bad "index unreadable" "wrong diagnostic: $(cat "$work/ir.err")"
    fi
    badsha="sha256:0000000000000000000000000000000000000000000000000000000000000000"
    printf 'gutil 0.1.0 file://%s/gutil 0.1.0 %s\n' "$reg" "$badsha" >"$work/index-bad"
    if ( cd "$work/idxuse" && HOME="$work/home2" \
            "$work/ct-ast" get --index "$work/index-bad" gutil >"$work/ib.out" 2>"$work/ib.err" ); then
        bad "index digest" "expected a non-zero exit"
    elif grep -Fq "does not match the index" "$work/ib.err"; then
        ok "the index digest is checked against the fetched source"
    else
        bad "index digest" "wrong diagnostic: $(cat "$work/ib.err")"
    fi
fi

echo
echo "== ct install: help and argument errors =="
if ( cd "$work/proj" && "$work/ct-ast" install --help >"$work/ih.out" 2>"$work/ih.err" ) \
   && grep -Fq "usage: " "$work/ih.out"; then
    ok "install --help prints usage"
else
    bad "install --help" "no usage on stdout: $(cat "$work/ih.out" "$work/ih.err")"
fi
if ( cd "$work/proj" && "$work/ct-ast" install --bogus >"$work/iu.out" 2>"$work/iu.err" ); then
    bad "install unknown-option" "expected a non-zero exit"
elif grep -Fq "unknown option '--bogus'" "$work/iu.err"; then
    ok "install rejects an unknown option"
else
    bad "install unknown-option" "wrong diagnostic: $(cat "$work/iu.err")"
fi
if ( cd "$work/proj" && "$work/ct-ast" install stray >"$work/ix.out" 2>"$work/ix.err" ); then
    bad "install extra-arg" "expected a non-zero exit"
elif grep -Fq "unexpected argument 'stray'" "$work/ix.err"; then
    ok "install rejects a stray argument"
else
    bad "install extra-arg" "wrong diagnostic: $(cat "$work/ix.err")"
fi

echo
echo "== a local package whose directory differs from its manifest name =="
# `get` vendors under the manifest name; `install` must resolve the same name
# from the dep spec instead of trusting the directory segment.
mkdir -p "$work/pkgs/dirname"
printf 'name = realname\nversion = 0.1.0\n' >"$work/pkgs/dirname/ct.pkg"
printf 'int realname_value(void) { return 1; }\n' >"$work/pkgs/dirname/a.c"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/dirname@^0.1.0\n' >"$work/proj/ct.pkg"
if ( cd "$work/proj" && "$work/ct-ast" get ../pkgs/dirname >"$work/rn.out" 2>"$work/rn.err" ); then
    if [ -d "$work/proj/vendor/realname" ]; then
        ok "get vendors under the manifest name"
    else
        bad "get dirname" "vendor/realname is missing"
    fi
    if ( cd "$work/proj" && "$work/ct-ast" install >"$work/rni.out" 2>"$work/rni.err" ); then
        ok "install resolves the same manifest name"
    else
        bad "install dirname" "non-zero exit: $(cat "$work/rni.err")"
    fi
else
    bad "get dirname" "non-zero exit: $(cat "$work/rn.err")"
fi

echo
echo "== version ranges: comparators and space-separated AND =="
mkdir -p "$work/pkgs/rutil" "$work/rproj"
printf 'name = rutil\nversion = 1.2.0\n' >"$work/pkgs/rutil/ct.pkg"
printf 'int rutil_value(void) { return 1; }\n' >"$work/pkgs/rutil/r.c"
printf 'name = demo\nversion = 0.1.0\n' >"$work/rproj/ct.pkg"
if ( cd "$work/rproj" && "$work/ct-ast" get '../pkgs/rutil@>=1.0.0 <2.0.0' >"$work/rg1.out" 2>"$work/rg1.err" ); then
    ok "space-separated comparators accept a version inside the range"
else
    bad "range AND" "non-zero exit: $(cat "$work/rg1.err")"
fi
if ( cd "$work/rproj" && "$work/ct-ast" get '../pkgs/rutil@>=2.0.0' >"$work/rg2.out" 2>"$work/rg2.err" ); then
    bad "range reject" "expected a non-zero exit"
elif grep -Fq "does not satisfy '>=2.0.0'" "$work/rg2.err"; then
    ok "a comparator range rejects a version outside it"
else
    bad "range reject" "wrong diagnostic: $(cat "$work/rg2.err")"
fi

echo
echo "== build metadata: cflags / ldflags / requires =="
mkdir -p "$work/pkgs/meta" "$work/pkgs/mbad" "$work/mproj"
printf 'name = meta\nversion = 0.1.0\ncflags = -DMETA=1\nldflags = -lm\nrequires = ct >= 0.1.0\n' >"$work/pkgs/meta/ct.pkg"
printf 'int meta_value(void) { return 1; }\n' >"$work/pkgs/meta/m.c"
printf 'name = mbad\nversion = 0.1.0\nrequires = ct >= 9.0.0\n' >"$work/pkgs/mbad/ct.pkg"
printf 'int mbad_value(void) { return 2; }\n' >"$work/pkgs/mbad/b.c"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/meta@^0.1.0\ndep = ../pkgs/mbad@^0.1.0\n' >"$work/mproj/ct.pkg"
if ( cd "$work/mproj" && "$work/ct-ast" get ../pkgs/meta >"$work/mg.out" 2>"$work/mg.err" ); then
    ok "get vendors the first metadata package"
else
    bad "metadata get" "non-zero exit: $(cat "$work/mg.err")"
fi

echo
echo "== ct update: resolve ct.pkg offline, keep the lock honest =="
if ( cd "$work/mproj" && "$work/ct-ast" update >"$work/u.out" 2>"$work/u.err" ); then
    if grep -Fq "updated 2 package(s)" "$work/u.out"; then
        ok "update re-resolves every ct.pkg dependency and rewrites ct.lock"
    else
        bad "update" "wrong output: $(cat "$work/u.out")"
    fi
else
    bad "update" "non-zero exit: $(cat "$work/u.err")"
fi
if [ -f "$work/mproj/vendor/mbad/ct.pkg" ] && [ -f "$work/mproj/vendor/meta/ct.pkg" ]; then
    ok "update vendors the dependencies ct.pkg names"
else
    bad "update" "vendor/ is incomplete"
fi
if ( cd "$work/mproj" && "$work/ct-ast" update --bogus >"$work/uo.out" 2>"$work/uo.err" ); then
    bad "update unknown-option" "expected a non-zero exit"
elif grep -Fq "unknown option '--bogus'" "$work/uo.err"; then
    ok "update rejects an unknown option"
else
    bad "update unknown-option" "wrong diagnostic: $(cat "$work/uo.err")"
fi
if ( cd "$work/mproj" && "$work/ct-ast" update stray >"$work/us.out" 2>"$work/us.err" ); then
    bad "update extra-arg" "expected a non-zero exit"
elif grep -Fq "unexpected argument 'stray'" "$work/us.err"; then
    ok "update rejects a stray argument"
else
    bad "update extra-arg" "wrong diagnostic: $(cat "$work/us.err")"
fi

echo
echo "== ct install: one command carrying each package's flags =="
if ( cd "$work/mproj" && "$work/ct-ast" install >"$work/mi.out" 2>"$work/mi.err" ); then
    ok "install accepts a lock that update wrote"
else
    bad "install after update" "non-zero exit: $(cat "$work/mi.err")"
fi
if grep -Fq -- "--cflags '-DMETA=1'" "$work/mi.out"; then
    ok "install folds a package's cflags into the printed command"
else
    bad "cflags" "no --cflags in: $(cat "$work/mi.out")"
fi
if grep -Fq -- "--ldflags '-lm'" "$work/mi.out"; then
    ok "install folds a package's ldflags into the printed command"
else
    bad "ldflags" "no --ldflags in: $(cat "$work/mi.out")"
fi
if grep -Fq "requires 'ct >= 9.0.0'" "$work/mi.err"; then
    ok "an unsatisfied requires is a warning, not a refusal"
else
    bad "requires" "no warning on stderr: $(cat "$work/mi.err")"
fi

echo
echo "== ct verify: the lock against the vendored tree =="
if ( cd "$work/mproj" && "$work/ct-ast" verify >"$work/v.out" 2>"$work/v.err" ); then
    if grep -Fq "verified 2 package(s)" "$work/v.out"; then
        ok "verify accepts an untampered vendor tree"
    else
        bad "verify" "wrong output: $(cat "$work/v.out")"
    fi
else
    bad "verify" "non-zero exit: $(cat "$work/v.err")"
fi
printf 'int meta_value(void) { return 3; }\n' >"$work/mproj/vendor/meta/m.c"
if ( cd "$work/mproj" && "$work/ct-ast" verify >"$work/vt.out" 2>"$work/vt.err" ); then
    bad "verify tampered" "expected a non-zero exit"
elif grep -Fq "does not match ct.lock" "$work/vt.err"; then
    ok "verify rejects a tampered vendored file"
else
    bad "verify tampered" "wrong diagnostic: $(cat "$work/vt.err")"
fi

echo
echo "== package conventions: the agreed manifest keys (Phase 18.1) =="
# `licence` and other agreed-but-unparsed keys must not disturb resolution, and
# must not leak into the command `install` prints.
mkdir -p "$work/pkgs/lic" "$work/cproj"
printf '# the agreed keys, plus keys the tool ignores\nname = lic\nversion = 1.0.0\nlicence = MIT\nwebsite = https://example.invalid\n' >"$work/pkgs/lic/ct.pkg"
printf 'int lic_value(void) { return 0; }\n' >"$work/pkgs/lic/l.c"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/lic@^1.0.0\n' >"$work/cproj/ct.pkg"
if ( cd "$work/cproj" && "$work/ct-ast" get ../pkgs/lic >"$work/cg.out" 2>"$work/cg.err" ); then
    if [ -f "$work/cproj/vendor/lic/ct.pkg" ]; then
        ok "get ignores licence and an unknown manifest key"
    else
        bad "conventions get" "vendor/lic is missing"
    fi
else
    bad "conventions get" "non-zero exit: $(cat "$work/cg.err")"
fi
if ( cd "$work/cproj" && "$work/ct-ast" install >"$work/ci.out" 2>"$work/ci.err" ); then
    if grep -Fq "licence" "$work/ci.out"; then
        bad "conventions install" "licence leaked into the printed command"
    else
        ok "licence stays a convention out of the build command"
    fi
else
    bad "conventions install" "non-zero exit: $(cat "$work/ci.err")"
fi
# Phase 18.3: a package that carries no `requires` is not a warning case.
if [ -s "$work/ci.err" ]; then
    bad "conventions install" "unexpected stderr for a package without requires: $(cat "$work/ci.err")"
else
    ok "a package without requires installs silently"
fi
# `name` and `version` are the only required keys, and an empty one counts as missing.
mkdir -p "$work/pkgs/nover" "$work/pkgs/noname"
printf 'name = nover\n' >"$work/pkgs/nover/ct.pkg"
printf 'name =\nversion = 0.1.0\n' >"$work/pkgs/noname/ct.pkg"
if ( cd "$work/cproj" && "$work/ct-ast" get ../pkgs/nover >"$work/nv.out" 2>"$work/nv.err" ); then
    bad "manifest version" "expected a non-zero exit"
elif grep -Fq "ct.pkg" "$work/nv.err"; then
    ok "a manifest without version is refused"
else
    bad "manifest version" "wrong diagnostic: $(cat "$work/nv.err")"
fi
if ( cd "$work/cproj" && "$work/ct-ast" get ../pkgs/noname >"$work/nn.out" 2>"$work/nn.err" ); then
    bad "manifest name" "expected a non-zero exit"
elif grep -Fq "ct.pkg" "$work/nn.err"; then
    ok "a manifest with an empty name is refused"
else
    bad "manifest name" "wrong diagnostic: $(cat "$work/nn.err")"
fi

echo
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
