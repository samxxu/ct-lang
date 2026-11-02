#!/usr/bin/env bash
#
# test/std/run.sh - the std layer gate (Phase 17.2), hard gate 11.
#
# Builds the bootstrap chain (L0 -> L1 -> L2 -> ct-ast), then for every module
# under std/<mod>/<Mod>.h.ct checks that the unit declares the namespace its
# directory implies and a `pub struct` named after its file, and drives each
# fixture under test/std/<name>/:
#
#   main.ct -> ct-ast build --emit-c -I . -> cc -Wall -Wextra -> run
#
# The fixture asserts its own cases through std::test and exits non-zero on a
# failure, so nothing here compares a hand-written golden. `test/std/test` is
# the negative half: it must exit non-zero and name each failure on stderr.
# `test/std/fs` receives a directory with exactly two entries and a file path
# outside it, so its listing assertions are deterministic.
#
# Discovery is explicit: every fixture passes `-I .`; the compiler has no
# default include root (D17-2).
#
# Usage:  bash test/std/run.sh
#         CC=clang bash test/std/run.sh
#
# Exit code 0 means every assertion passed.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-std-test.$$"

rm -rf "$work"
mkdir -p "$work" || exit 1

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "cc: $CC"
echo
echo "== std units (namespace and type follow the directory) =="
unit_bad=""
for f in $(find std -name '*.h.ct' | sort); do
    mod="$(basename "$(dirname "$f")")"
    base="$(basename "$f" .h.ct)"
    if ! grep -qE "^namespace std::$mod;" "$f"; then
        unit_bad="$unit_bad $f(namespace)"
    fi
    if ! grep -qE "^(pub )?struct $base( |$)" "$f"; then
        unit_bad="$unit_bad $f(type)"
    fi
done
if [ -z "$unit_bad" ]; then
    ok "every std unit names its namespace and its type"
else
    bad "std units" "$unit_bad"
fi

echo
echo "== build the bootstrap chain and the AST compiler =="
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
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.out" 2>&1; then
    echo "  L2 could not build the AST compiler:"; sed 's/^/    /' "$work/ast.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
    echo "  the AST compiler did not build:"; sed 's/^/    /' "$work/astb.log"; exit 1
fi
ok "the chain builds (L0 -> L1 -> L2 -> ct-ast)"

mkdir -p "$work/fsdir"
: > "$work/fsdir/a.txt"
: > "$work/fsdir/b.txt"

echo
echo "== modules =="
for dir in test/std/*/; do
    name="$(basename "$dir")"
    out="$work/$name"
    mkdir -p "$out"
    if ! "$work/ct-ast" build --emit-c -I . "$dir/main.ct" -o "$out" \
            >"$out/build.log" 2>&1; then
        bad "$name" "$(sed 's/^/    /' "$out/build.log")"
        continue
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$out"/*.c -o "$work/$name.bin" 2>"$out/cc.log"; then
        bad "$name" "$(sed 's/^/    /' "$out/cc.log")"
        continue
    fi
    case "$name" in
        fs)
            if "$work/$name.bin" "$work/fsdir" "$work/out.txt" \
                    >"$out/stdout" 2>"$out/stderr" \
               && grep -q ' 0 failures' "$out/stdout"; then
                ok "$name"
            else
                bad "$name" "$(cat "$out/stderr" "$out/stdout")"
            fi
            ;;
        test)
            # The negative fixture: a non-zero exit and one FAIL line per failure.
            if "$work/$name.bin" >"$out/stdout" 2>"$out/stderr"; then
                bad "$name" "the failing fixture exited 0"
            elif [ "$(grep -c '^FAIL:' "$out/stderr")" = "3" ]; then
                ok "$name (three failures reported, non-zero exit)"
            else
                bad "$name" "$(cat "$out/stderr")"
            fi
            ;;
        *)
            if "$work/$name.bin" >"$out/stdout" 2>"$out/stderr" \
               && grep -q ' 0 failures' "$out/stdout"; then
                ok "$name"
            else
                bad "$name" "$(cat "$out/stderr" "$out/stdout")"
            fi
            ;;
    esac
done

echo
printf 'std: %d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -ne 0 ]; then
    exit 1
fi
