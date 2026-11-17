#!/bin/sh
#
# test/pkg/run.sh - Phase 8.1 + 8.2 + 8.3: the local, git and install halves of ct-pkg.
#
# Builds the whole bootstrap chain (L0 -> L1 -> L2 -> ct-ast, the compiler that
# now ships `get`/`install`) and exercises `ct get` on a throwaway project:
# manifest parsing, a version range, a recursive local `dep`, the shared store
# ($CT_HOME/pkg/<publisher>/<name>/<version>) and the v2 `ct.lock` rows.
# Phase 8.2 adds a git source: a local git repository stands in for the registry
# (so the test needs no network), and the `git` absent case must fail hard. The
# cache and the registry are redirected through HOME / CT_REGISTRY.
# Phase 8.3 adds `ct install`, which checks the store against the lock's content
# digests and the manifest's dependencies, then prints a `ct build` command; a
# tampered tree, a missing package or an uncovered dependency fails.
# The error branches of both subcommands are covered too: no or empty `ct.lock`,
# a missing or incomplete `ct.pkg`, a malformed `dep` and bad `ct get` arguments.
# Phase 17.5 adds the comparator ranges, `ct update` / `ct verify`, the explicit
# plain-text index (`CT_INDEX` / `--index`) and the build metadata that `ct
# install` folds into its single printed command.
# Phase 20 (P20-04) makes an unsatisfied `requires` a hard failure in both `get`
# and `install`; `--force` downgrades it to a warning, and a refused `get` must
# leave an existing `ct.lock` byte-identical (the check precedes the write).
# PH-54 S7 removes vendor/ from the read and write paths: `get` only writes the
# shared store and a v2 lock, `install`/`verify`/`update` only read the store,
# and a v1 lock is a hard error that points at the one-time `ct migrate` bridge
# (which still reads an existing vendor/ tree and rewrites it as v2).
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

# Every `ct get` installs into the shared store; keep it inside the throwaway
# root so the real $HOME is never touched. Suites that need isolation override
# CT_HOME inline.
CT_HOME="$work/cthome"
export CT_HOME
mkdir -p "$CT_HOME" || exit 1

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
printf 'name = util\npublisher = ct\nversion = 0.2.0\nns-root = .\nlicense = MIT\ndep = ../extra@^0.1.0\n' >"$work/pkgs/util/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$work/pkgs/util/util.h.ct"
printf 'name = extra\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$work/pkgs/extra/ct.pkg"
printf 'int extra_value(void) { return 7; }\n' >"$work/pkgs/extra/extra.c"
ok "fixtures created"

echo
echo "== ct get: recursive local dependency =="
if ( cd "$work/proj" && "$work/ct-ast" get ../pkgs/util >"$work/get.out" 2>"$work/get.err" ); then
    ok "exits 0"
else
    bad "ct get" "non-zero exit: $(cat "$work/get.err")"
fi
if [ -f "$CT_HOME/pkg/ct/util/0.2.0/ct.pkg" ] \
   && [ -f "$CT_HOME/pkg/ct/util/0.2.0/util.h.ct" ]; then
    ok "stores the requested package"
else
    bad "ct get" "the store copy of util is incomplete"
fi
if [ -f "$CT_HOME/pkg/ct/extra/0.1.0/ct.pkg" ] \
   && [ -f "$CT_HOME/pkg/ct/extra/0.1.0/extra.c" ]; then
    ok "stores the transitive dependency"
else
    bad "ct get" "the store copy of extra is incomplete"
fi
if [ ! -e "$work/proj/vendor" ]; then
    ok "ct get writes no vendor/ tree"
else
    bad "ct get" "vendor/ was created"
fi
if [ -f "$work/proj/ct.lock" ]; then
    first="$(sed -n 1p "$work/proj/ct.lock")"
    row1="$(sed -n 2p "$work/proj/ct.lock")"
    row2="$(sed -n 3p "$work/proj/ct.lock")"
    if [ "$first" = "# ct-lock 2" ]; then
        ok "the lock starts with the v2 header"
    else
        bad "ct.lock" "expected the v2 header, got '$first'"
    fi
    case "$row1" in
        ct/extra\ 0.1.0\ dir\ *) ok "the lock lists the dependency first" ;;
        *) bad "ct.lock" "expected ct/extra first, got '$row1'" ;;
    esac
    case "$row2" in
        ct/util\ 0.2.0\ dir\ *) ok "the lock lists the requested package second" ;;
        *) bad "ct.lock" "expected ct/util second, got '$row2'" ;;
    esac
    if [ "$(awk 'NR>1{print NF}' "$work/proj/ct.lock" | sort -u)" = "7" ]; then
        ok "every lock row has seven v2 fields"
    else
        bad "ct.lock" "unexpected row width: $(awk 'NR>1{print NF}' "$work/proj/ct.lock" | sort -u)"
    fi
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
echo "== ct install: verifies the store and prints a build command =="
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/i.out" 2>"$work/i.err" ); then
    ok "ct install exits 0"
else
    bad "ct install" "non-zero exit: $(cat "$work/i.err")"
fi
if grep -Fq "build" "$work/i.out" && grep -Fq "# lock-format: v2" "$work/i.out"; then
    ok "prints a store-backed build command"
else
    bad "ct install" "no suggested build command: $(cat "$work/i.out")"
fi
if ! grep -Fq -- "-I " "$work/i.out"; then
    ok "the v2 build command needs no explicit -I (build reads the lock)"
else
    bad "ct install" "unexpected -I in: $(cat "$work/i.out")"
fi

echo
echo "== ct install rejects an import the lock roots cannot resolve =="
# PKG-6: install's success means the printed `ct build` line can resolve the
# project's imports. A missing unit must fail here, not at build time.
mkdir -p "$work/p6pkg" "$work/p6proj"
printf 'name = p6pkg\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$work/p6pkg/ct.pkg"
printf 'name = demo6\nversion = 0.1.0\n' >"$work/p6proj/ct.pkg"
printf 'import missing::Absent;\nint main(void) { return 0; }\n' >"$work/p6proj/main.ct"
if ( cd "$work/p6proj" && "$work/ct-ast" get ../p6pkg >/dev/null 2>&1 ); then
    if ( cd "$work/p6proj" && "$work/ct-ast" install >"$work/p6i.out" 2>"$work/p6i.err" ); then
        bad "PKG-6 install" "expected a non-zero exit"
    elif grep -Fq "cannot resolve import 'missing/Absent'" "$work/p6i.err"; then
        ok "install rejects an unresolved import"
    else
        bad "PKG-6 install" "wrong diagnostic: $(cat "$work/p6i.err")"
    fi
else
    bad "PKG-6 fixture" "ct get failed: $(cat "$work/p6g.err" 2>/dev/null)"
fi

echo
echo "== ct pkg warns about unknown manifest keys =="
mkdir -p "$work/p3pkg" "$work/p3proj"
printf 'name = p3pkg\npublisher = ct\nversion = 0.1.0\nns-root = .\nfrobnicate = yes\n' >"$work/p3pkg/ct.pkg"
printf 'name = demo3\nversion = 0.1.0\ndep = ../p3pkg@^0.1.0\n' >"$work/p3proj/ct.pkg"
printf 'int main(void) { return 0; }\n' >"$work/p3proj/main.ct"
if ( cd "$work/p3proj" && "$work/ct-ast" get ../p3pkg >"$work/p3.out" 2>"$work/p3.err" ); then
    if grep -Fq "has unknown key 'frobnicate'" "$work/p3.err"; then
        ok "unknown keys produce a warning"
    else
        bad "PKG-3 warning" "missing warning: $(cat "$work/p3.err")"
    fi
else
    bad "PKG-3 get" "non-zero exit: $(cat "$work/p3.err")"
fi

echo
echo "== ct get refuses a package that requires a newer compiler =="
# P20-04: `requires` is a hard failure in `get` too, and the check runs before
# ct.lock is merged or written, so a refused package leaves the lock untouched.
mkdir -p "$work/hi" "$work/proj2"
printf 'name = hi\npublisher = ct\nversion = 0.1.0\nns-root = .\nrequires = ct >= 99.0.0\n' >"$work/hi/ct.pkg"
printf 'pub int hi(void);\nint hi(void) { return 1; }\n' >"$work/hi/hi.h.ct"
printf 'name = demo2\nversion = 0.1.0\ndep = ../hi@^0.1.0\n' >"$work/proj2/ct.pkg"
printf 'int main(void) { return 0; }\n' >"$work/proj2/main.ct"
if ( cd "$work/proj2" && "$work/ct-ast" get ../hi >"$work/hig.out" 2>"$work/hig.err" ); then
    bad "requires hard fail" "ct get should refuse the package"
elif grep -Fq "requires 'ct >= 99.0.0', but this is v" "$work/hig.err" \
     && grep -Fq -- "--force" "$work/hig.err"; then
    ok "ct get exits non-zero, names both versions and points at --force"
else
    bad "requires hard fail" "wrong diagnostic: $(cat "$work/hig.err")"
fi
if [ -e "$work/proj2/ct.lock" ]; then
    bad "requires failure" "ct.lock was written by the failed get"
else
    ok "a failed get does not create ct.lock"
fi
# An existing lock must survive the failure byte-for-byte, not be half-merged.
printf '# ct-lock 2\nct/old 0.0.0 dir ./old - . sha256:%064d\n' 0 >"$work/proj2/ct.lock"
cp "$work/proj2/ct.lock" "$work/proj2/ct.lock.before"
if ( cd "$work/proj2" && "$work/ct-ast" get ../hi >/dev/null 2>&1 ); then
    bad "requires failure" "ct get should still refuse the package"
elif cmp -s "$work/proj2/ct.lock.before" "$work/proj2/ct.lock"; then
    ok "a failed get leaves an existing ct.lock untouched"
else
    bad "requires failure" "ct.lock changed on the failure path"
fi
rm -f "$work/proj2/ct.lock" "$work/proj2/ct.lock.before"
if ( cd "$work/proj2" && "$work/ct-ast" get --force ../hi >"$work/hifg.out" 2>"$work/hifg.err" ); then
    if grep -Fq "continuing despite the requires mismatch (--force)" "$work/hifg.err" \
       && [ -f "$work/proj2/ct.lock" ]; then
        ok "ct get --force warns, continues and writes ct.lock"
    else
        bad "requires --force" "no warning or ct.lock"
    fi
else
    bad "requires --force" "expected a zero exit: $(cat "$work/hifg.err")"
fi
if ( cd "$work/proj2" && "$work/ct-ast" install >"$work/hi.out" 2>"$work/hi.err" ); then
    bad "requires hard fail" "expected a non-zero exit"
elif grep -Fq "requires 'ct >= 99.0.0', but this is v" "$work/hi.err"; then
    ok "ct install exits non-zero and names both versions"
else
    bad "requires hard fail" "wrong diagnostic: $(cat "$work/hi.err")"
fi
if ( cd "$work/proj2" && "$work/ct-ast" install --force >"$work/hif.out" 2>"$work/hif.err" ); then
    if grep -Fq "continuing despite the requires mismatch (--force)" "$work/hif.err" \
       && grep -Fq "build" "$work/hif.out"; then
        ok "ct install --force warns and continues"
    else
        bad "requires --force" "no warning or build command"
    fi
else
    bad "requires --force" "expected a zero exit: $(cat "$work/hif.err")"
fi
echo
echo "== ct get accepts a package whose requires is satisfied =="
mkdir -p "$work/lo" "$work/proj3"
printf 'name = lo\npublisher = ct\nversion = 0.1.0\nns-root = .\nrequires = ct >= 0.1.0\n' >"$work/lo/ct.pkg"
printf 'pub int lo(void);\nint lo(void) { return 1; }\n' >"$work/lo/lo.h.ct"
if ( cd "$work/proj3" && "$work/ct-ast" get ../lo >"$work/log.out" 2>"$work/log.err" ); then
    if grep -Fq "requires" "$work/log.err"; then
        bad "requires satisfied" "unexpected diagnostic: $(cat "$work/log.err")"
    else
        ok "ct get accepts a satisfied requires"
    fi
else
    bad "requires satisfied" "ct get failed: $(cat "$work/log.err")"
fi

echo
echo "== requires accepts a comparator glued to 'ct' =="
# M3: `ct>=99.0.0` is a version range, not an unsupported clause -- the operator
# after the name must not depend on a separating space.
mkdir -p "$work/hi2" "$work/proj4"
printf 'name = hi2\npublisher = ct\nversion = 0.1.0\nns-root = .\nrequires = ct>=99.0.0\n' >"$work/hi2/ct.pkg"
printf 'pub int hi2(void);\nint hi2(void) { return 1; }\n' >"$work/hi2/hi2.h.ct"
printf 'name = demo4\nversion = 0.1.0\n' >"$work/proj4/ct.pkg"
if ( cd "$work/proj4" && "$work/ct-ast" get ../hi2 >"$work/hig2.out" 2>"$work/hig2.err" ); then
    bad "glued requires" "ct get should refuse 'ct>=99.0.0'"
elif grep -Fq "requires 'ct>=99.0.0', but this is v" "$work/hig2.err"; then
    ok "a comparator glued to 'ct' is read as a version range"
else
    bad "glued requires" "wrong diagnostic: $(cat "$work/hig2.err")"
fi

echo
echo "== ct get refuses an upgrade without touching the store or the lock =="
# M2: the requires check runs before the tree is committed, so a refused upgrade
# leaves the previously stored copy byte-identical, not only ct.lock.
mkdir -p "$work/up/proj" "$work/up/v1" "$work/up/v2"
printf 'name = mix\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$work/up/v1/ct.pkg"
printf 'pub int mix(void);\nint mix(void) { return 1; }\n' >"$work/up/v1/mix.h.ct"
printf 'name = mix\npublisher = ct\nversion = 0.2.0\nns-root = .\nrequires = ct >= 99.0.0\n' >"$work/up/v2/ct.pkg"
printf 'pub int mix(void);\nint mix(void) { return 2; }\n' >"$work/up/v2/mix.h.ct"
printf 'name = up\nversion = 0.1.0\n' >"$work/up/proj/ct.pkg"
if ( cd "$work/up/proj" && "$work/ct-ast" get ../v1 >/dev/null 2>&1 ); then
    ok "the baseline get stores mix 0.1.0"
else
    bad "requires upgrade" "the baseline get failed"
fi
cp -R "$CT_HOME/pkg/ct/mix/0.1.0" "$work/up/before"
cp "$work/up/proj/ct.lock" "$work/up/lock.before"
if ( cd "$work/up/proj" && "$work/ct-ast" get ../v2 >/dev/null 2>&1 ); then
    bad "requires upgrade" "ct get should refuse the upgrade"
elif diff -r "$work/up/before" "$CT_HOME/pkg/ct/mix/0.1.0" >/dev/null 2>&1 \
     && cmp -s "$work/up/lock.before" "$work/up/proj/ct.lock"; then
    ok "a refused upgrade leaves the store and ct.lock byte-identical"
else
    bad "requires upgrade" "the store or ct.lock changed on the failure path"
fi

echo
echo "== ct install rejects a tampered store tree =="
printf 'pub int twice(int x);\nint twice(int x) { return 99; }\n' >"$CT_HOME/pkg/ct/util/0.2.0/util.h.ct"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/it.out" 2>"$work/it.err" ); then
    bad "install tamper" "expected a non-zero exit"
elif grep -Fq "does not match ct.lock" "$work/it.err"; then
    ok "rejects a digest mismatch"
else
    bad "install tamper" "wrong diagnostic: $(cat "$work/it.err")"
fi
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$CT_HOME/pkg/ct/util/0.2.0/util.h.ct"

echo
echo "== ct install rejects a same-size tamper =="
# SH-44: a change that keeps the file's length must still be caught.
printf 'pub int twice(int x);\nint twice(int x) { return 3 * x; }\n' >"$CT_HOME/pkg/ct/util/0.2.0/util.h.ct"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/is.out" 2>"$work/is.err" ); then
    bad "install same-size tamper" "expected a non-zero exit"
elif grep -Fq "does not match ct.lock" "$work/is.err"; then
    ok "rejects a same-size digest mismatch"
else
    bad "install same-size tamper" "wrong diagnostic: $(cat "$work/is.err")"
fi
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$CT_HOME/pkg/ct/util/0.2.0/util.h.ct"

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
echo "== ct install rejects a missing store package =="
mv "$CT_HOME/pkg/ct/extra/0.1.0" "$CT_HOME/pkg/ct/extra/0.1.0.bak"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/im.out" 2>"$work/im.err" ); then
    bad "install missing" "expected a non-zero exit"
elif grep -Fq "is not installed" "$work/im.err"; then
    ok "rejects a missing store package"
else
    bad "install missing" "wrong diagnostic: $(cat "$work/im.err")"
fi
mv "$CT_HOME/pkg/ct/extra/0.1.0.bak" "$CT_HOME/pkg/ct/extra/0.1.0"

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
echo "== ct build rejects a v1 lock =="
mkdir -p "$work/proj/out"
cp "$work/proj/ct.lock" "$work/proj/ct.lock.v2"
printf 'util 0.2.0 dir ./untouched sha256:%064d\n' 0 >"$work/proj/ct.lock"
if ( cd "$work/proj" && "$work/ct-ast" build --emit-c main.ct -o out >"$work/b.out" 2>"$work/b.err" ); then
    bad "build v1" "a v1 lock passed"
elif grep -Fq "ct.lock is v1" "$work/b.err" \
     && grep -Fq "run 'ct migrate'" "$work/b.err"; then
    ok "build rejects a v1 lock and points at ct migrate"
else
    bad "build v1" "wrong diagnostic: $(cat "$work/b.err")"
fi
mv "$work/proj/ct.lock.v2" "$work/proj/ct.lock"

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
        && printf 'name = gutil\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >ct.pkg \
        && printf 'int gutil_value(void) { return 3; }\n' >gutil.c \
        && git add -A && git commit -qm one && git tag 0.1.0 \
        && printf 'name = gutil\npublisher = ct\nversion = 0.2.0\nns-root = .\n' >ct.pkg \
        && git add -A && git commit -qm two && git tag v0.2.0 )
    mkdir -p "$work/home"
    if ( cd "$work/proj" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil@^0.1.0" >"$work/g.out" 2>"$work/g.err" ); then
        ok "ct get <git> exits 0"
    else
        bad "ct get <git>" "non-zero exit: $(cat "$work/g.err")"
    fi
    if [ -f "$CT_HOME/pkg/ct/gutil/0.1.0/ct.pkg" ] \
       && [ -f "$CT_HOME/pkg/ct/gutil/0.1.0/gutil.c" ]; then
        ok "stores the git package"
    else
        bad "ct get <git>" "the store copy of gutil is incomplete"
    fi
    # D24: the manifest records what `get` brought in, so `install` can be run
    # later without re-typing the spec.
    if grep -Fq 'dep = gutil@^0.1.0' "$work/proj/ct.pkg"; then
        ok "get records the git package in ct.pkg"
    else
        bad "ct.pkg <git>" "missing the gutil dep: $(cat "$work/proj/ct.pkg")"
    fi
    if grep -Eq "^ct/gutil 0\.1\.0 git file://.* [0-9a-f]{40} \. sha256:[0-9a-f]{64}$" "$work/proj/ct.lock"; then
        ok "MVS picks the lowest satisfying tag and pins its commit"
    else
        bad "ct.lock <git>" "expected a seven-field v2 gutil row, got: $(grep gutil "$work/proj/ct.lock")"
    fi

    echo
    echo "== no range / * picks the newest tag =="
    mkdir -p "$work/latest"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/latest/ct.pkg"
    if ( cd "$work/latest" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil" >"$work/latest.out" 2>"$work/latest.err" ); then
        if grep -Eq "^ct/gutil 0\.2\.0 git file://.* [0-9a-f]{40} \. sha256:[0-9a-f]{64}$" "$work/latest/ct.lock"; then
            ok "ct get <git> with no range picks the newest tag"
        else
            bad "ct.lock <git> latest" "expected gutil 0.2.0, got: $(grep gutil "$work/latest/ct.lock")"
        fi
    else
        bad "ct get <git> latest" "non-zero exit: $(cat "$work/latest.err")"
    fi
    rm -f "$work/latest/ct.lock" "$work/latest/ct.pkg"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/latest/ct.pkg"
    if ( cd "$work/latest" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil@*" >"$work/star.out" 2>"$work/star.err" ); then
        if grep -Eq "^ct/gutil 0\.2\.0 git file://.* [0-9a-f]{40} \. sha256:[0-9a-f]{64}$" "$work/latest/ct.lock"; then
            ok "ct get <git>@* picks the newest tag"
        else
            bad "ct.lock <git> *" "expected gutil 0.2.0, got: $(grep gutil "$work/latest/ct.lock")"
        fi
    else
        bad "ct get <git> *" "non-zero exit: $(cat "$work/star.err")"
    fi

    echo
    echo "== a git repo with no tags falls back to the default branch =="
    mkdir -p "$reg/notags"
    ( cd "$reg/notags" \
        && git init -q \
        && printf 'name = notags\npublisher = ct\nversion = 0.0.1\nns-root = .\n' >ct.pkg \
        && printf 'int notags_value(void) { return 9; }\n' >notags.c \
        && git add -A && git commit -qm one )
    if ( cd "$work/proj" && HOME="$work/home" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "notags@*" >"$work/h.out" 2>"$work/h.err" ); then
        if grep -Eq "^ct/notags 0\.0\.1 git file://.* [0-9a-f]{40} \. sha256:[0-9a-f]{64}$" "$work/proj/ct.lock"; then
            ok "locks the default branch tip when there is no tag"
        else
            bad "ct.lock <HEAD>" "expected a seven-field v2 notags row, got: $(grep notags "$work/proj/ct.lock")"
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
        && printf 'name = other\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >ct.pkg \
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
    # index entry's fifth field, so the index can vouch for the stored tree.
    mkdir -p "$work/idxseed" "$work/home2"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/idxseed/ct.pkg"
    if ( cd "$work/idxseed" && HOME="$work/home2" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil@^0.1.0" >"$work/is.out" 2>"$work/is.err" ); then
        dig="$(awk '$1 == "ct/gutil" { print $NF }' "$work/idxseed/ct.lock")"
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
    if [ -f "$CT_HOME/pkg/ct/gutil/0.1.0/ct.pkg" ]; then
        ok "the index entry's git source is stored"
    else
        bad "index store" "the store copy of gutil is missing"
    fi
    if grep -Eq "^ct/gutil 0\.1\.0 git file://.* [0-9a-f]{40} \. sha256:[0-9a-f]{64}$" "$work/idxuse/ct.lock"; then
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
    if ( cd "$work" && unset CT_INDEX && HOME="$work/home2" \
            "$work/ct-ast" get ct/http >"$work/noindex.out" 2>"$work/noindex.err" ); then
        bad "no-index guidance" "expected a non-zero exit"
    elif grep -Fq "no index resolver for 'ct/http'" "$work/noindex.err" \
         && grep -Fq "publisher-qualified package name" "$work/noindex.err" \
         && grep -Fq "1) built-in / official library" "$work/noindex.err" \
         && grep -Fq "ct get http" "$work/noindex.err" \
         && grep -Fq "2) publisher-qualified package" "$work/noindex.err" \
         && grep -Fq "ct get --index <file> ct/http" "$work/noindex.err" \
         && grep -Fq "name version publisher git-url tag sha256" "$work/noindex.err" \
         && grep -Fq "CT_REGISTRY only applies to bare names" "$work/noindex.err"; then
        ok "a qualified name without an index explains the resolver"
    else
        bad "no-index guidance" "wrong diagnostic: $(cat "$work/noindex.err")"
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

    echo
    echo "== two publishers may ship the same package name =="
    # PKG-5: the cache key must carry the publisher. Both sources are local
    # git repos; the index maps `a/util` and `b/util` to them. Fetching b after
    # a must not reuse a's cache (the old bare-name key did, silently).
    mkdir -p "$work/pub/a/util" "$work/pub/b/util" "$work/p5seed" "$work/p5a" "$work/p5b" "$work/p5home"
    for pub in a b; do
        ( cd "$work/pub/$pub/util" \
            && git init -q \
            && printf 'name = util\npublisher = %s\nns-root = .\nversion = 0.1.0\n' "$pub" >ct.pkg \
            && printf 'int util_value(void) { return %s; }\n' "$([ "$pub" = a ] && echo 1 || echo 2)" >util.c \
            && git add -A && git commit -qm "$pub" && git tag 0.1.0 )
    done
    printf 'name = demo\nversion = 0.1.0\n' >"$work/p5seed/ct.pkg"
    ( cd "$work/p5seed" && HOME="$work/p5home" "$work/ct-ast" get "$work/pub/a/util" >/dev/null 2>&1 ) \
        && adig="$(awk '$1 == "a/util" { print $NF }' "$work/p5seed/ct.lock")"
    ( cd "$work/p5seed" && HOME="$work/p5home" "$work/ct-ast" get "$work/pub/b/util" >/dev/null 2>&1 ) \
        && bdig="$(awk '$1 == "b/util" { print $NF }' "$work/p5seed/ct.lock")"
    printf 'util 0.1.0 a file://%s/pub/a/util 0.1.0 %s\n' "$work" "$adig" >"$work/p5.index"
    printf 'util 0.1.0 b file://%s/pub/b/util 0.1.0 %s\n' "$work" "$bdig" >>"$work/p5.index"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/p5a/ct.pkg"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/p5b/ct.pkg"
    if ( cd "$work/p5a" && HOME="$work/p5home" "$work/ct-ast" get --index "$work/p5.index" a/util >/dev/null 2>"$work/p5a.err" ) \
       && ( cd "$work/p5b" && HOME="$work/p5home" "$work/ct-ast" get --index "$work/p5.index" b/util >/dev/null 2>"$work/p5b.err" ); then
        if [ -d "$work/p5home/.cache/ct-pkg/a/util/.git" ] && [ -d "$work/p5home/.cache/ct-pkg/b/util/.git" ]; then
            ok "the cache key separates publishers"
        else
            bad "PKG-5 cache" "expected a/util and b/util caches"
        fi
        if [ -f "$CT_HOME/pkg/b/util/0.1.0/util.c" ] \
           && grep -Fq 'return 2' "$CT_HOME/pkg/b/util/0.1.0/util.c"; then
            ok "b/util gets b's source, not a's cached copy"
        else
            bad "PKG-5 store" "b/util took the wrong source: $(cat "$CT_HOME/pkg/b/util/0.1.0/util.c" 2>/dev/null)"
        fi
    else
        bad "PKG-5 get" "$(cat "$work/p5a.err" "$work/p5b.err")"
    fi
    # A cache whose origin no longer matches the index must not be reused.
    printf 'util 0.1.0 a file://%s/pub/b/util 0.1.0 %s\n' "$work" "$adig" >"$work/p5.bad"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/p5a/ct.pkg"
    if ( cd "$work/p5a" && HOME="$work/p5home" "$work/ct-ast" get --index "$work/p5.bad" a/util >/dev/null 2>"$work/p5c.err" ); then
        bad "PKG-5 origin" "expected a non-zero exit"
    elif grep -Fq "different origin" "$work/p5c.err"; then
        ok "a cached origin that disagrees with the index is rejected"
    else
        bad "PKG-5 origin" "wrong diagnostic: $(cat "$work/p5c.err")"
    fi

    echo
    echo "== a second ct get keeps the rows the first one pinned =="
    # PKG-2: one invocation resolves one spec; rewriting ct.lock from that run's
    # rows alone would drop every package fetched earlier, so an index tag such
    # as v0.2.0 silently disappears from the pins.
    mkdir -p "$work/pkgs/one" "$work/pinseed" "$work/pinhome" "$work/pinproj"
    printf 'name = one\npublisher = ct\nversion = 1.0.0\nns-root = .\n' >"$work/pkgs/one/ct.pkg"
    printf 'int one_value(void) { return 1; }\n' >"$work/pkgs/one/one.c"
    printf 'name = demo\nversion = 0.1.0\n' >"$work/pinseed/ct.pkg"
    if ( cd "$work/pinseed" && HOME="$work/pinhome" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" get "gutil@>=0.2.0" >"$work/ps.out" 2>"$work/ps.err" ); then
        pdig="$(awk '$1 == "ct/gutil" { print $NF }' "$work/pinseed/ct.lock")"
        printf 'gutil 0.2.0 file://%s/gutil v0.2.0 %s\n' "$reg" "$pdig" >"$work/index2"
        ok "a seed lock supplies the 0.2.0 digest"
    else
        bad "pin seed" "non-zero exit: $(cat "$work/ps.err")"
    fi
    printf 'name = demo\nversion = 0.1.0\n' >"$work/pinproj/ct.pkg"
    if ( cd "$work/pinproj" && HOME="$work/pinhome" \
            "$work/ct-ast" get --index "$work/index2" gutil >"$work/p1.out" 2>"$work/p1.err" ); then
        ok "the index pins gutil at its tag"
    else
        bad "pin get" "non-zero exit: $(cat "$work/p1.err")"
    fi
    if ( cd "$work/pinproj" && HOME="$work/pinhome" \
            "$work/ct-ast" get ../pkgs/one >"$work/p2.out" 2>"$work/p2.err" ); then
        ok "a second get resolves its own spec"
    else
        bad "second get" "non-zero exit: $(cat "$work/p2.err")"
    fi
    if grep -Fq 'ct/gutil 0.2.0 ' "$work/pinproj/ct.lock"; then
        ok "the second get leaves the first package pinned"
    else
        bad "lock merge" "the gutil row was dropped: $(cat "$work/pinproj/ct.lock")"
    fi
    if [ "$(grep -c '^ct/one 1\.0\.0 ' "$work/pinproj/ct.lock")" = "1" ]; then
        ok "the second get writes its own row once"
    else
        bad "lock merge" "unexpected one rows: $(cat "$work/pinproj/ct.lock")"
    fi
    if ( cd "$work/pinproj" && HOME="$work/pinhome" CT_REGISTRY="file://$reg" \
            "$work/ct-ast" update >"$work/pu.out" 2>"$work/pu.err" ); then
        if grep -Fq 'ct/gutil 0.2.0 ' "$work/pinproj/ct.lock"; then
            ok "update keeps the pinned 0.2.0 row"
        else
            bad "update pin" "gutil moved: $(grep gutil "$work/pinproj/ct.lock")"
        fi
    else
        bad "update pin" "non-zero exit: $(cat "$work/pu.err")"
    fi
    if ( cd "$work/pinproj" && "$work/ct-ast" verify >"$work/pv.out" 2>"$work/pv.err" ) \
       && grep -Fq "verified 2 package(s)" "$work/pv.out"; then
        ok "verify covers both merged packages"
    else
        bad "verify merge" "$(cat "$work/pv.out" "$work/pv.err")"
    fi
    if ( cd "$work/pinproj" && HOME="$work/pinhome" \
            "$work/ct-ast" get --index "$work/index2" gutil >"$work/p3.out" 2>"$work/p3.err" ); then
        if [ "$(grep -c '^ct/gutil ' "$work/pinproj/ct.lock")" = "1" ] \
           && [ "$(grep -c '^ct/one ' "$work/pinproj/ct.lock")" = "1" ]; then
            ok "re-getting a package replaces its row instead of duplicating it"
        else
            bad "lock replace" "unexpected rows: $(cat "$work/pinproj/ct.lock")"
        fi
    else
        bad "re-get" "non-zero exit: $(cat "$work/p3.err")"
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
# `get` stores under the manifest name; `install` must resolve the same name
# from the dep spec instead of trusting the directory segment.
mkdir -p "$work/pkgs/dirname"
printf 'name = realname\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$work/pkgs/dirname/ct.pkg"
printf 'int realname_value(void) { return 1; }\n' >"$work/pkgs/dirname/a.c"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/dirname@^0.1.0\n' >"$work/proj/ct.pkg"
if ( cd "$work/proj" && "$work/ct-ast" get ../pkgs/dirname >"$work/rn.out" 2>"$work/rn.err" ); then
    if [ -d "$CT_HOME/pkg/ct/realname/0.1.0" ]; then
        ok "get stores under the manifest name"
    else
        bad "get dirname" "the store copy of realname is missing"
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
printf 'name = rutil\npublisher = ct\nversion = 1.2.0\nns-root = .\n' >"$work/pkgs/rutil/ct.pkg"
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
printf 'name = meta\npublisher = ct\nversion = 0.1.0\nns-root = .\ncflags = -DMETA=1\nldflags = -lm\nrequires = ct >= 0.1.0\n' >"$work/pkgs/meta/ct.pkg"
printf 'int meta_value(void) { return 1; }\n' >"$work/pkgs/meta/m.c"
printf 'name = mbad\npublisher = ct\nversion = 0.1.0\nns-root = .\nrequires = ct >= 9.0.0\n' >"$work/pkgs/mbad/ct.pkg"
printf 'int mbad_value(void) { return 2; }\n' >"$work/pkgs/mbad/b.c"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/meta@^0.1.0\ndep = ../pkgs/mbad@^0.1.0\n' >"$work/mproj/ct.pkg"
if ( cd "$work/mproj" && "$work/ct-ast" get ../pkgs/meta >"$work/mg.out" 2>"$work/mg.err" ); then
    ok "get stores the first metadata package"
else
    bad "metadata get" "non-zero exit: $(cat "$work/mg.err")"
fi
# `get --force` is the only way a package with an unsatisfied `requires` enters
# the store; update then audits both pins instead of re-resolving ct.pkg.
if ( cd "$work/mproj" && "$work/ct-ast" get --force ../pkgs/mbad >"$work/mbg.out" 2>"$work/mbg.err" ); then
    ok "get --force stores the unsatisfied metadata package"
else
    bad "metadata get" "non-zero exit: $(cat "$work/mbg.err")"
fi

echo
echo "== ct update: audit the store and every ct.pkg dependency, keep the lock honest =="
if ( cd "$work/mproj" && "$work/ct-ast" update >"$work/u.out" 2>"$work/u.err" ); then
    if grep -Fq "updated 2 package(s)" "$work/u.out"; then
        ok "update verifies every ct.pkg dependency and rewrites ct.lock"
    else
        bad "update" "wrong output: $(cat "$work/u.out")"
    fi
else
    bad "update" "non-zero exit: $(cat "$work/u.err")"
fi
if [ -f "$CT_HOME/pkg/ct/mbad/0.1.0/ct.pkg" ] \
   && [ -f "$CT_HOME/pkg/ct/meta/0.1.0/ct.pkg" ]; then
    ok "update keeps the dependencies ct.pkg names in the store"
else
    bad "update" "the store is incomplete"
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
echo "== ct install --force: one command carrying each package's flags =="
if ( cd "$work/mproj" && "$work/ct-ast" install --force >"$work/mi.out" 2>"$work/mi.err" ); then
    ok "install --force accepts the audited lock"
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
if grep -Fq "requires 'ct >= 9.0.0'" "$work/mi.err" \
   && grep -Fq "continuing despite the requires mismatch (--force)" "$work/mi.err"; then
    ok "--force keeps an unsatisfied requires as a warning"
else
    bad "requires" "no warning on stderr: $(cat "$work/mi.err")"
fi

echo
echo "== P20-08: an unsupported requires points at dep =="
# `requires` only understands a compiler-version range. A package dependency
# written there is not that, so the message must name the key that does it.
mkdir -p "$work/pkgs/lng" "$work/lngproj"
printf 'name = lng\npublisher = ct\nversion = 0.1.0\nns-root = .\nrequires = utils >= 1.0\n' >"$work/pkgs/lng/ct.pkg"
printf 'pub int lng(void);\nint lng(void) { return 1; }\n' >"$work/pkgs/lng/lng.h.ct"
printf 'name = lngproj\nversion = 0.1.0\ndep = ../pkgs/lng@^0.1.0\n' >"$work/lngproj/ct.pkg"
printf 'int main(void) { return 0; }\n' >"$work/lngproj/main.ct"
( cd "$work/lngproj" && "$work/ct-ast" get ../pkgs/lng >"$work/lngg.out" 2>"$work/lngg.err" )
if ( cd "$work/lngproj" && "$work/ct-ast" install >"$work/lngi.out" 2>"$work/lngi.err" ); then
    if grep -Fq "unsupported requires" "$work/lngi.err" \
       && grep -Fq "use dep = pkg@range for package dependencies" "$work/lngi.err"; then
        ok "an unsupported requires names dep"
    else
        bad "unsupported requires" "no dep hint: $(cat "$work/lngi.err")"
    fi
else
    bad "unsupported requires" "expected a zero exit: $(cat "$work/lngi.err")"
fi

echo
echo "== ct verify: the lock against the store =="
if ( cd "$work/mproj" && "$work/ct-ast" verify >"$work/v.out" 2>"$work/v.err" ); then
    if grep -Fq "verified 2 package(s)" "$work/v.out"; then
        ok "verify accepts an untampered store"
    else
        bad "verify" "wrong output: $(cat "$work/v.out")"
    fi
else
    bad "verify" "non-zero exit: $(cat "$work/v.err")"
fi
printf 'int meta_value(void) { return 3; }\n' >"$CT_HOME/pkg/ct/meta/0.1.0/m.c"
if ( cd "$work/mproj" && "$work/ct-ast" verify >"$work/vt.out" 2>"$work/vt.err" ); then
    bad "verify tampered" "expected a non-zero exit"
elif grep -Fq "does not match ct.lock" "$work/vt.err"; then
    ok "verify rejects a tampered stored file"
else
    bad "verify tampered" "wrong diagnostic: $(cat "$work/vt.err")"
fi

echo
echo "== package conventions: the agreed manifest keys (Phase 18.1) =="
# `licence` and other agreed-but-unparsed keys must not disturb resolution, and
# must not leak into the command `install` prints.
mkdir -p "$work/pkgs/lic" "$work/cproj"
printf '# the agreed keys, plus keys the tool ignores\nname = lic\npublisher = ct\nversion = 1.0.0\nns-root = .\nlicence = MIT\nwebsite = https://example.invalid\n' >"$work/pkgs/lic/ct.pkg"
printf 'int lic_value(void) { return 0; }\n' >"$work/pkgs/lic/l.c"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/lic@^1.0.0\n' >"$work/cproj/ct.pkg"
if ( cd "$work/cproj" && "$work/ct-ast" get ../pkgs/lic >"$work/cg.out" 2>"$work/cg.err" ); then
    if [ -f "$CT_HOME/pkg/ct/lic/1.0.0/ct.pkg" ]; then
        ok "get ignores licence and an unknown manifest key"
    else
        bad "conventions get" "the store copy of lic is missing"
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
# Phase 18.3: a package that carries no `requires` is not a warning case, and
# S7 leaves no v1 lock note behind.
if [ -z "$(cat "$work/ci.err")" ]; then
    ok "a package without requires installs silently"
else
    bad "conventions install" "unexpected stderr for a package without requires: $(cat "$work/ci.err")"
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
echo "== S0: lock format and ct pkg check =="
# S7: a v1 lock (no header) is a hard error and points at the one-time bridge.
cp "$work/proj/ct.lock" "$work/proj/ct.lock.v2"
awk 'NR>1 { print $1 ~ /\// ? substr($1,index($1,"/")+1) : $1, $2, $3, $4, $NF }' \
    "$work/proj/ct.lock.v2" >"$work/proj/ct.lock"
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/s0i.out" 2>"$work/s0i.err" ); then
    bad "install v1" "a v1 lock passed install"
elif grep -Fq "ct.lock is v1" "$work/s0i.err" \
     && grep -Fq "run 'ct migrate'" "$work/s0i.err"; then
    ok "install rejects a v1 lock and points at ct migrate"
else
    bad "install v1" "wrong diagnostic: $(cat "$work/s0i.err")"
fi
if ( cd "$work/proj" && "$work/ct-ast" verify >"$work/s0v.out" 2>"$work/s0v.err" ); then
    bad "verify v1" "a v1 lock passed verify"
elif grep -Fq "ct.lock is v1" "$work/s0v.err" \
     && grep -Fq "run 'ct migrate'" "$work/s0v.err"; then
    ok "verify rejects a v1 lock and points at ct migrate"
else
    bad "verify v1" "wrong diagnostic: $(cat "$work/s0v.err")"
fi
if ( cd "$work/proj" && "$work/ct-ast" update >"$work/s0u.out" 2>"$work/s0u.err" ); then
    bad "update v1" "a v1 lock passed update"
elif grep -Fq "ct.lock is v1" "$work/s0u.err" \
     && grep -Fq "run 'ct migrate'" "$work/s0u.err"; then
    ok "update rejects a v1 lock and points at ct migrate"
else
    bad "update v1" "wrong diagnostic: $(cat "$work/s0u.err")"
fi
mv "$work/proj/ct.lock.v2" "$work/proj/ct.lock"
# The v2 lock installs and reports its format.
if ( cd "$work/proj" && "$work/ct-ast" install >"$work/s0v2.out" 2>"$work/s0v2.err" ); then
    if grep -Fq "# lock-format: v2" "$work/s0v2.out" && ! grep -Fq "ct.lock is v1" "$work/s0v2.err"; then
        ok "install recognises a v2 header"
    else
        bad "lock format v2" "unexpected: $(cat "$work/s0v2.out" "$work/s0v2.err")"
    fi
else
    bad "lock format v2" "install failed: $(cat "$work/s0v2.err")"
fi
# S0/D2: `ct pkg check` is read-only and judges PK-1/2/5/8.
mkdir -p "$work/s0/good/src/demo" "$work/s0/nopub" "$work/s0/nons" \
         "$work/s0/absns" "$work/s0/nodir" "$work/s0/absi"
printf 'name = demo\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$work/s0/good/ct.pkg"
printf 'namespace demo;\n' >"$work/s0/good/src/demo/Demo.h.ct"
printf 'name = demo\nversion = 0.1.0\nns-root = src\n' >"$work/s0/nopub/ct.pkg"
printf 'name = demo\npublisher = ct\nversion = 0.1.0\n' >"$work/s0/nons/ct.pkg"
printf 'name = demo\npublisher = ct\nversion = 0.1.0\nns-root = /abs\n' >"$work/s0/absns/ct.pkg"
printf 'name = demo\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$work/s0/nodir/ct.pkg"
printf 'name = demo\npublisher = ct\nversion = 0.1.0\nns-root = .\ncflags = -I /opt/x\n' >"$work/s0/absi/ct.pkg"
before=$(cd "$work/s0/good" && find . -type f | sort | xargs shasum -a 256)
if "$work/ct-ast" pkg check "$work/s0/good" >"$work/s0g.out" 2>"$work/s0g.err"; then
    if grep -Fq "ok: 4 criteria" "$work/s0g.out"; then
        ok "pkg check passes a fully declared package"
    else
        bad "pkg check good" "missing ok line: $(cat "$work/s0g.out")"
    fi
else
    bad "pkg check good" "non-zero exit: $(cat "$work/s0g.err")"
fi
after=$(cd "$work/s0/good" && find . -type f | sort | xargs shasum -a 256)
if [ "$before" = "$after" ]; then
    ok "pkg check is read-only"
else
    bad "pkg check read-only" "the package tree changed"
fi
if "$work/ct-ast" pkg check "$work/s0/nopub" >"$work/s0n.out" 2>"$work/s0n.err"; then
    bad "pkg check publisher" "expected a non-zero exit"
elif grep -Fq "is missing 'publisher'" "$work/s0n.err"; then
    ok "pkg check requires publisher"
else
    bad "pkg check publisher" "wrong diagnostic: $(cat "$work/s0n.err")"
fi
if "$work/ct-ast" pkg check "$work/s0/nons" >"$work/s0ns.out" 2>"$work/s0ns.err"; then
    bad "pkg check ns-root" "expected a non-zero exit"
elif grep -Fq "is missing 'ns-root'" "$work/s0ns.err"; then
    ok "pkg check requires ns-root"
else
    bad "pkg check ns-root" "wrong diagnostic: $(cat "$work/s0ns.err")"
fi
if "$work/ct-ast" pkg check "$work/s0/absns" >"$work/s0a.out" 2>"$work/s0a.err"; then
    bad "pkg check absolute ns-root" "expected a non-zero exit"
elif grep -Fq "must be a relative path" "$work/s0a.err"; then
    ok "pkg check rejects an absolute ns-root"
else
    bad "pkg check absolute ns-root" "wrong diagnostic: $(cat "$work/s0a.err")"
fi
if "$work/ct-ast" pkg check "$work/s0/nodir" >"$work/s0d.out" 2>"$work/s0d.err"; then
    bad "pkg check missing ns-root dir" "expected a non-zero exit"
elif grep -Fq "is not a directory" "$work/s0d.err"; then
    ok "pkg check rejects a missing ns-root directory"
else
    bad "pkg check missing ns-root dir" "wrong diagnostic: $(cat "$work/s0d.err")"
fi
if "$work/ct-ast" pkg check "$work/s0/absi" >"$work/s0ai.out" 2>"$work/s0ai.err"; then
    bad "pkg check absolute -I" "expected a non-zero exit"
elif grep -Fq "contains an absolute -I" "$work/s0ai.err"; then
    ok "pkg check rejects an absolute -I"
else
    bad "pkg check absolute -I" "wrong diagnostic: $(cat "$work/s0ai.err")"
fi

echo
echo "== S1: shared store =="
S1="$work/s1"
mkdir -p "$S1/home" "$S1/cthome" "$S1/proj" "$S1/pkgs/std/src"
printf 'name = std\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$S1/pkgs/std/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S1/pkgs/std/src/std.h.ct"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/std@^0.1.0\n' >"$S1/proj/ct.pkg"
STORE="$S1/cthome/pkg/ct/std/0.1.0"
if ( cd "$S1/proj" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/std >"$S1/g.out" 2>"$S1/g.err" ); then
    ok "S1 get exits 0"
else
    bad "S1 get" "non-zero exit: $(cat "$S1/g.err")"
fi
if [ -f "$STORE/ct.pkg" ] && [ -f "$STORE/src/std.h.ct" ]; then
    ok "S1 writes \$CT_HOME/pkg/<pub>/<name>/<ver>"
else
    bad "S1 store" "store tree is incomplete"
fi
if [ ! -e "$S1/proj/vendor" ]; then
    ok "S1 get writes no vendor/ tree"
else
    bad "S1 vendor" "vendor/ was created"
fi
if [ "$(head -1 "$S1/proj/ct.lock")" = "# ct-lock 2" ] \
   && [ "$(awk 'NR>1{print NF}' "$S1/proj/ct.lock" | sort -u)" = "7" ]; then
    ok "S1 lock is v2 with seven fields per row"
else
    bad "S1 lock" "unexpected lock: $(cat "$S1/proj/ct.lock")"
fi
if ( cd "$S1/proj" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" install >"$S1/i.out" 2>"$S1/i.err" ) \
   && ! grep -Fq -- "-I " "$S1/i.out" \
   && grep -Fq "# lock-format: v2" "$S1/i.out"; then
    ok "S1 install omits -I for a v2 lock (build adds it)"
else
    bad "S1 install" "$(cat "$S1/i.out" "$S1/i.err")"
fi
before="$(find "$STORE" -type f -exec shasum -a 256 {} + | sort | shasum -a 256 | awk '{print $1}')"
if ( cd "$S1/proj" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/std >"$S1/g2.out" 2>"$S1/g2.err" ); then
    after="$(find "$STORE" -type f -exec shasum -a 256 {} + | sort | shasum -a 256 | awk '{print $1}')"
    if [ "$before" = "$after" ]; then
        ok "S1 same-version reinstall is a no-op"
    else
        bad "S1 reinstall" "store content changed"
    fi
else
    bad "S1 reinstall" "non-zero exit: $(cat "$S1/g2.err")"
fi
printf '// changed\n' >>"$S1/pkgs/std/src/std.h.ct"
if ( cd "$S1/proj" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/std >"$S1/g3.out" 2>"$S1/g3.err" ); then
    bad "S1 digest mismatch" "a changed same-version package was overwritten"
elif grep -Fq "different digest" "$S1/g3.err"; then
    ok "S1 same version with a different digest is a hard error"
else
    bad "S1 digest mismatch" "wrong diagnostic: $(cat "$S1/g3.err")"
fi
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S1/pkgs/std/src/std.h.ct"
mkdir -p "$S1/pkgs/std2/src" "$S1/proj2"
printf 'name = std\npublisher = ct\nversion = 0.2.0\nns-root = src\n' >"$S1/pkgs/std2/ct.pkg"
printf 'pub int twice(int x);\n' >"$S1/pkgs/std2/src/std.h.ct"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/std2@^0.2.0\n' >"$S1/proj2/ct.pkg"
if ( cd "$S1/proj2" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/std2 >"$S1/g4.out" 2>"$S1/g4.err" ) \
   && [ -d "$S1/cthome/pkg/ct/std/0.1.0" ] \
   && [ -d "$S1/cthome/pkg/ct/std/0.2.0" ]; then
    ok "S1 lets two versions coexist"
else
    bad "S1 versions" "$(cat "$S1/g4.err")"
fi
mkdir -p "$S1/pkgs/nsbad" "$S1/proj3"
printf 'name = nsbad\npublisher = ct\nversion = 0.1.0\n' >"$S1/pkgs/nsbad/ct.pkg"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/nsbad@^0.1.0\n' >"$S1/proj3/ct.pkg"
if ( cd "$S1/proj3" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/nsbad >"$S1/ns.out" 2>"$S1/ns.err" ); then
    bad "S1 missing ns-root" "expected a non-zero exit"
elif grep -Fq "is missing 'ns-root'" "$S1/ns.err"; then
    ok "S1 requires ns-root"
else
    bad "S1 missing ns-root" "wrong diagnostic: $(cat "$S1/ns.err")"
fi
mkdir -p "$S1/pkgs/nsabs/src" "$S1/proj4"
printf 'name = nsabs\npublisher = ct\nversion = 0.1.0\nns-root = /tmp\n' >"$S1/pkgs/nsabs/ct.pkg"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/nsabs@^0.1.0\n' >"$S1/proj4/ct.pkg"
if ( cd "$S1/proj4" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/nsabs >"$S1/na.out" 2>"$S1/na.err" ); then
    bad "S1 absolute ns-root" "expected a non-zero exit"
elif grep -Fq "must be a relative path" "$S1/na.err"; then
    ok "S1 rejects an absolute ns-root"
else
    bad "S1 absolute ns-root" "wrong diagnostic: $(cat "$S1/na.err")"
fi
mkdir -p "$S1/pkgs/nopub/src" "$S1/proj5"
printf 'name = nopub\nversion = 0.1.0\nns-root = src\n' >"$S1/pkgs/nopub/ct.pkg"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/nopub@^0.1.0\n' >"$S1/proj5/ct.pkg"
if ( cd "$S1/proj5" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/nopub >"$S1/np.out" 2>"$S1/np.err" ); then
    bad "S1 missing publisher" "expected a non-zero exit"
elif grep -Fq "is missing 'publisher'" "$S1/np.err"; then
    ok "S1 requires publisher when ns-root is present"
else
    bad "S1 missing publisher" "wrong diagnostic: $(cat "$S1/np.err")"
fi
mkdir -p "$S1/pkgs/plocal/src" "$S1/proj6"
printf 'name = plocal\npublisher = local\nversion = 0.1.0\nns-root = src\n' >"$S1/pkgs/plocal/ct.pkg"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkgs/plocal@^0.1.0\n' >"$S1/proj6/ct.pkg"
if ( cd "$S1/proj6" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get ../pkgs/plocal >"$S1/pl.out" 2>"$S1/pl.err" ); then
    bad "S1 local publisher" "expected a non-zero exit"
elif grep -Fq "is missing 'publisher'" "$S1/pl.err"; then
    ok "S1 rejects publisher 'local'"
else
    bad "S1 local publisher" "wrong diagnostic: $(cat "$S1/pl.err")"
fi
printf x >>"$STORE/src/std.h.ct"
if ( cd "$S1/proj" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" install >"$S1/t.out" 2>"$S1/t.err" ); then
    bad "S1 tampered store" "a changed store passed install"
elif grep -Fq "does not match ct.lock" "$S1/t.err"; then
    ok "S1 install rejects a tampered store"
else
    bad "S1 tampered store" "wrong diagnostic: $(cat "$S1/t.err")"
fi
printf 'dup 0.1.0 pubA file:///tmp/a 0.1.0 sha256:%064d\ndup 0.1.0 pubB file:///tmp/b 0.1.0 sha256:%064d\n' 0 0 >"$S1/index"
if ( cd "$S1/proj" && HOME="$S1/home" CT_HOME="$S1/cthome" \
        "$work/ct-ast" get --index ../index dup >"$S1/amb.out" 2>"$S1/amb.err" ); then
    bad "S1 ambiguous index" "expected a non-zero exit"
elif grep -Fq "is ambiguous" "$S1/amb.err"; then
    ok "S1 bare index name with two publishers is ambiguous"
else
    bad "S1 ambiguous index" "wrong diagnostic: $(cat "$S1/amb.err")"
fi

echo
echo "== S2: build reads ct.lock =="
S2="$work/s2"
mkdir -p "$S2/home" "$S2/cthome" "$S2/pkg/src" "$S2/proj"
printf 'name = p\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$S2/pkg/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S2/pkg/src/p.h.ct"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkg@^0.1.0\n' >"$S2/proj/ct.pkg"
printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(21)); return 0; }\n' >"$S2/proj/main.ct"
if ( cd "$S2/proj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" get ../pkg >"$S2/g.out" 2>"$S2/g.err" ); then
    ok "S2 fixture get exits 0"
else
    bad "S2 fixture get" "$(cat "$S2/g.err")"
fi
# Turn the dir row into a store-backed git row: build never reads the URL, only
# the package/version/ns-root/digest fields.
awk 'NR>1 && $1=="ct/p" { print "ct/p 0.1.0 git file:///nonexistent deadbeef " $6 " " $7; next } { print }' \
    "$S2/proj/ct.lock" >"$S2/proj/ct.lock.tmp" && mv "$S2/proj/ct.lock.tmp" "$S2/proj/ct.lock"
if ( cd "$S2/proj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/app" >"$S2/b.out" 2>"$S2/b.err" ) \
   && [ "$("$S2/app")" = "42" ]; then
    ok "S2 build auto-adds the store ns-root -I"
else
    bad "S2 build store" "$(cat "$S2/b.out" "$S2/b.err")"
fi
if ( cd "$S2/proj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/app2" --locked >"$S2/l.out" 2>"$S2/l.err" ); then
    ok "S2 --locked accepts a matching store"
else
    bad "S2 --locked" "$(cat "$S2/l.out" "$S2/l.err")"
fi
printf x >>"$S2/cthome/pkg/ct/p/0.1.0/src/p.h.ct"
if ( cd "$S2/proj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/app3" --locked >"$S2/t.out" 2>"$S2/t.err" ); then
    bad "S2 --locked tamper" "a tampered store passed --locked"
elif grep -Fq "does not match ct.lock" "$S2/t.err"; then
    ok "S2 --locked rejects a store digest mismatch"
else
    bad "S2 --locked tamper" "wrong diagnostic: $(cat "$S2/t.err")"
fi
rm -rf "$S2/cthome/pkg/ct/p"
if ( cd "$S2/proj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/app4" --locked >"$S2/m.out" 2>"$S2/m.err" ); then
    bad "S2 --locked missing" "a missing store passed --locked"
elif grep -Fq "is not installed" "$S2/m.err"; then
    ok "S2 --locked rejects a missing store"
else
    bad "S2 --locked missing" "wrong diagnostic: $(cat "$S2/m.err")"
fi
# dev override: a dir row produces the note and uses the local tree.
mkdir -p "$S2/devpkg/src" "$S2/devproj"
printf 'name = p\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$S2/devpkg/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S2/devpkg/src/p.h.ct"
printf 'name = demo\nversion = 0.1.0\ndep = ../devpkg@^0.1.0\n' >"$S2/devproj/ct.pkg"
printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(6)); return 0; }\n' >"$S2/devproj/main.ct"
( cd "$S2/devproj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
    "$work/ct-ast" get ../devpkg >/dev/null 2>&1 )
if ( cd "$S2/devproj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/devapp" >"$S2/d.out" 2>"$S2/d.err" ) \
   && grep -Fq "resolves to the local directory (dev override)" "$S2/d.err" \
   && [ "$("$S2/devapp")" = "12" ]; then
    ok "S2 dir row is a dev override with a note"
else
    bad "S2 dev override" "$(cat "$S2/d.out" "$S2/d.err")"
fi
# no lock: vendor/ is no longer a build input; imports must be explicit.
mkdir -p "$S2/vproj/vendor/p"
printf 'name = demo\nversion = 0.1.0\n' >"$S2/vproj/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S2/vproj/vendor/p/p.h.ct"
printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(5)); return 0; }\n' >"$S2/vproj/main.ct"
if ( cd "$S2/vproj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/vapp" >"$S2/v.out" 2>"$S2/v.err" ); then
    bad "S2 vendor fallback" "vendor/ was still read"
elif grep -Fq "cannot resolve import 'p'" "$S2/v.err"; then
    ok "S2 no lock does not read vendor/"
else
    bad "S2 vendor fallback" "wrong diagnostic: $(cat "$S2/v.out" "$S2/v.err")"
fi
# no lock and no vendor: still builds, and prints no fallback warning.
mkdir -p "$S2/nproj"
printf 'name = demo\nversion = 0.1.0\n' >"$S2/nproj/ct.pkg"
printf 'int main(void){return 0;}\n' >"$S2/nproj/main.ct"
if ( cd "$S2/nproj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/napp" >"$S2/n.out" 2>"$S2/n.err" ) \
   && [ ! -s "$S2/n.err" ]; then
    ok "S2 no lock and no vendor stays quiet"
else
    bad "S2 no vendor" "$(cat "$S2/n.out" "$S2/n.err")"
fi
# duplicate rows: same bare name under two publishers.
mkdir -p "$S2/dproj"
printf 'int main(void){return 0;}\n' >"$S2/dproj/main.ct"
printf '# ct-lock 2\na/p 0.1.0 git u c src sha256:%064d\nb/p 0.1.0 git u c src sha256:%064d\n' 0 0 >"$S2/dproj/ct.lock"
if ( cd "$S2/dproj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -o "$S2/dapp" >"$S2/dd.out" 2>"$S2/dd.err" ); then
    bad "S2 duplicate lock" "two rows for one package passed"
elif grep -Fq "is required twice" "$S2/dd.err"; then
    ok "S2 duplicate lock rows are a hard error"
else
    bad "S2 duplicate lock" "wrong diagnostic: $(cat "$S2/dd.err")"
fi
# explicit -I still works with no lock and no vendor.
mkdir -p "$S2/iproj"
printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(7)); return 0; }\n' >"$S2/iproj/main.ct"
if ( cd "$S2/iproj" && HOME="$S2/home" CT_HOME="$S2/cthome" \
        "$work/ct-ast" build main.ct -I ../devpkg/src -o "$S2/iapp" >"$S2/i.out" 2>"$S2/i.err" ) \
   && [ "$("$S2/iapp")" = "14" ]; then
    ok "S2 explicit -I still works"
else
    bad "S2 explicit -I" "$(cat "$S2/i.out" "$S2/i.err")"
fi
if "$work/ct-ast" build --help 2>&1 | grep -Fq -- "--locked"; then
    ok "S2 build --help documents --locked"
else
    bad "S2 help" "--locked is not documented"
fi

echo
echo "== S3: verify, migrate, update =="
S3="$work/s3"
mkdir -p "$S3/home" "$S3/cthome" "$S3/pkg/src" "$S3/proj"
printf 'name = p\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$S3/pkg/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S3/pkg/src/p.h.ct"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkg@^0.1.0\n' >"$S3/proj/ct.pkg"
printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(9)); return 0; }\n' >"$S3/proj/main.ct"
( cd "$S3/proj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
    "$work/ct-ast" get ../pkg >/dev/null 2>&1 )
printf x >>"$S3/cthome/pkg/ct/p/0.1.0/src/p.h.ct"
if ( cd "$S3/proj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" verify >"$S3/v1.out" 2>"$S3/v1.err" ); then
    bad "S3 verify tamper" "a tampered store passed verify"
elif grep -Fq "does not match ct.lock" "$S3/v1.err"; then
    ok "S3 verify rejects a store digest mismatch"
else
    bad "S3 verify tamper" "wrong diagnostic: $(cat "$S3/v1.err")"
fi
rm -rf "$S3/cthome/pkg/ct/p"
if ( cd "$S3/proj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" verify >"$S3/v2.out" 2>"$S3/v2.err" ); then
    bad "S3 verify missing" "a missing store passed verify"
elif grep -Fq "is not installed" "$S3/v2.err"; then
    ok "S3 verify rejects a missing store"
else
    bad "S3 verify missing" "wrong diagnostic: $(cat "$S3/v2.err")"
fi
( cd "$S3/proj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
    "$work/ct-ast" get ../pkg >/dev/null 2>&1 )
# dir row: strict rejects it, plain verify accepts it.
mkdir -p "$S3/dev/src" "$S3/devproj"
printf 'name = p\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$S3/dev/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S3/dev/src/p.h.ct"
printf 'name = demo\nversion = 0.1.0\ndep = ../dev@^0.1.0\n' >"$S3/devproj/ct.pkg"
printf 'import p;\nint main(void) { return twice(1); }\n' >"$S3/devproj/main.ct"
( cd "$S3/devproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
    "$work/ct-ast" get ../dev >/dev/null 2>&1 )
if ( cd "$S3/devproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" verify >"$S3/vd.out" 2>"$S3/vd.err" ); then
    ok "S3 verify accepts a dir row without --strict"
else
    bad "S3 verify dir" "$(cat "$S3/vd.err")"
fi
if ( cd "$S3/devproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" verify --strict >"$S3/vs.out" 2>"$S3/vs.err" ); then
    bad "S3 strict dir" "a dir row passed --strict"
elif grep -Fq "dev override (dir row)" "$S3/vs.err"; then
    ok "S3 --strict rejects a dir row"
else
    bad "S3 strict dir" "wrong diagnostic: $(cat "$S3/vs.err")"
fi
# v1 lock: --strict rejects it before any store read, pointing at the bridge.
awk 'NR>1 { print $1 ~ /\// ? substr($1,index($1,"/")+1) : $1, $2, $3, $4, $NF }' \
    "$S3/devproj/ct.lock" >"$S3/devproj/ct.lock.v1" && mv "$S3/devproj/ct.lock.v1" "$S3/devproj/ct.lock"
if ( cd "$S3/devproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" verify --strict >"$S3/vv.out" 2>"$S3/vv.err" ); then
    bad "S3 strict v1" "a v1 lock passed --strict"
elif grep -Fq "ct.lock is v1" "$S3/vv.err" \
     && grep -Fq "run 'ct migrate'" "$S3/vv.err"; then
    ok "S3 --strict rejects a v1 lock and points at ct migrate"
else
    bad "S3 strict v1" "wrong diagnostic: $(cat "$S3/vv.err")"
fi
# S7 keeps exactly one bridge: a hand-built v1 project (five-field lock plus a
# vendor/ tree) still migrates into the store. The vendored tree is a copy of
# the store's p 0.1.0, and the lock digest is that tree's digest.
mkdir -p "$S3/mproj/vendor/p"
cp -R "$S3/cthome/pkg/ct/p/0.1.0/." "$S3/mproj/vendor/p/"
mdig="$(awk '$1 == "ct/p" { print $NF }' "$S3/proj/ct.lock")"
printf 'p 0.1.0 dir ./vendor/p %s\n' "$mdig" >"$S3/mproj/ct.lock"
printf 'name = demo\nversion = 0.1.0\ndep = ../pkg@^0.1.0\n' >"$S3/mproj/ct.pkg"
printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(9)); return 0; }\n' >"$S3/mproj/main.ct"
if ( cd "$S3/mproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" migrate >"$S3/m.out" 2>"$S3/m.err" ); then
    if [ "$(head -1 "$S3/mproj/ct.lock")" = "# ct-lock 2" ] \
       && [ "$(awk 'NR>1{print NF}' "$S3/mproj/ct.lock" | sort -u)" = "7" ] \
       && [ -d "$S3/cthome/pkg/ct/p/0.1.0" ]; then
        ok "S3 migrate writes a v2 store-backed lock"
    else
        bad "S3 migrate lock" "$(cat "$S3/mproj/ct.lock")"
    fi
else
    bad "S3 migrate" "$(cat "$S3/m.err")"
fi
mv "$S3/mproj/vendor" "$S3/mproj/vendor.moved"
if ( cd "$S3/mproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" build main.ct -o "$S3/mapp" >"$S3/mb.out" 2>"$S3/mb.err" ) \
   && [ "$("$S3/mapp")" = "18" ]; then
    ok "S3 build works after vendor/ is moved away"
else
    bad "S3 migrate build" "$(cat "$S3/mb.out" "$S3/mb.err")"
fi
if ( cd "$S3/mproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" verify --strict >"$S3/ms.out" 2>"$S3/ms.err" ); then
    ok "S3 migrated lock passes --strict"
else
    bad "S3 migrated strict" "$(cat "$S3/ms.err")"
fi
cp "$S3/mproj/ct.lock" "$S3/mproj/ct.lock.before"
if ( cd "$S3/mproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" update >"$S3/u.out" 2>"$S3/u.err" ) \
   && cmp -s "$S3/mproj/ct.lock.before" "$S3/mproj/ct.lock"; then
    ok "S3 update preserves v2 pins"
else
    bad "S3 update v2" "$(cat "$S3/u.out" "$S3/u.err")"
fi
printf 'dep = ct/ghost@^1.0.0\n' >>"$S3/mproj/ct.pkg"
if ( cd "$S3/mproj" && HOME="$S3/home" CT_HOME="$S3/cthome" \
        "$work/ct-ast" update >"$S3/ug.out" 2>"$S3/ug.err" ); then
    bad "S3 update missing" "an unsatisfied dependency passed update"
elif grep -Fq "is not satisfied by ct.lock" "$S3/ug.err"; then
    ok "S3 update reports an unsatisfied dependency"
else
    bad "S3 update missing" "wrong diagnostic: $(cat "$S3/ug.err")"
fi

echo
echo "== S5: dual-HOME reproducibility =="
S5="$work/s5"
mkdir -p "$S5/repo/p/src" "$S5/proj1" "$S5/proj2"
printf 'name = p\npublisher = ct\nversion = 0.1.0\nns-root = src\n' >"$S5/repo/p/ct.pkg"
printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >"$S5/repo/p/src/p.h.ct"
( cd "$S5/repo/p" && git init -q && git add -A \
    && git -c user.email=a@b -c user.name=a commit -qm one && git tag 0.1.0 )
for n in 1 2; do
    mkdir -p "$S5/home$n" "$S5/cthome$n" "$S5/c$n"
    printf 'name = demo\nversion = 0.1.0\ndep = ct/p@^0.1.0\n' >"$S5/proj$n/ct.pkg"
    printf 'import p;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", twice(21)); return 0; }\n' >"$S5/proj$n/main.ct"
    ( cd "$S5/proj$n" && HOME="$S5/home$n" CT_HOME="$S5/cthome$n" \
        CT_REGISTRY=file://"$S5/repo" "$work/ct-ast" get p@^0.1.0 >/dev/null 2>&1 \
      && HOME="$S5/home$n" CT_HOME="$S5/cthome$n" \
        "$work/ct-ast" build main.ct -o "$S5/app$n" >"$S5/b$n.out" 2>"$S5/b$n.err" \
      && HOME="$S5/home$n" CT_HOME="$S5/cthome$n" \
        "$work/ct-ast" build main.ct --emit-c -o "$S5/c$n" >/dev/null 2>&1 )
    # The store root and project root are the only differences the compiler may
    # see; normalize them and compare the emitted C tree.
    ( cd "$S5/c$n" && find . -type f ! -path './.ctcache/*' | sort | while read -r f; do
        printf '== %s ==\n' "$f"
        sed -e "s|$S5/cthome$n|@STORE@|g" -e "s|$S5/proj$n|@PROJ@|g" "$f"
      done ) >"$S5/norm$n"
done
if cmp -s "$S5/proj1/ct.lock" "$S5/proj2/ct.lock"; then
    ok "S5 the same v2 lock is written under both HOMEs"
else
    bad "S5 locks" "$(diff "$S5/proj1/ct.lock" "$S5/proj2/ct.lock" | head -5)"
fi
if [ -x "$S5/app1" ] && [ -x "$S5/app2" ] \
   && [ "$("$S5/app1")" = "42" ] && [ "$("$S5/app2")" = "42" ] \
   && [ -s "$S5/norm1" ] && cmp -s "$S5/norm1" "$S5/norm2"; then
    ok "S5 builds produce identical normalized C and output under two HOMEs"
else
    bad "S5 build" "$(cat "$S5/b1.err" "$S5/b2.err")"
fi
if ( cd "$S5/proj1" && HOME="$S5/home1" CT_HOME="$S5/cthome1" \
        "$work/ct-ast" verify --strict >/dev/null 2>&1 ) \
   && ( cd "$S5/proj2" && HOME="$S5/home2" CT_HOME="$S5/cthome2" \
        "$work/ct-ast" verify --strict >/dev/null 2>&1 ); then
    ok "S5 both stores pass --strict independently"
else
    bad "S5 verify" "one of the isolated stores failed --strict"
fi

echo
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
