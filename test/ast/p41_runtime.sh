#!/bin/sh
# Phase 41 p41/runtime: pthread fixtures are excluded from the generic
# behavioural loop, so this probe owns their -pthread link and run.
set -u
ctast=$1
cc=${2:-cc}
work=$3
pass=0
fail=0
for d in p41_cancel_flag p41_refcount; do
    src="test/ast/$d/prog.ct"
    c="$work/$d.c"
    exe="$work/$d.bin"
    if ! "$ctast" "$src" -o "$c" 2>"$work/$d.err"; then
        echo "FAIL $d: ct-ast: $(cat "$work/$d.err")"; fail=$((fail + 1)); continue
    fi
    if ! "$cc" -std=c11 -Wall -Wextra -pthread "$c" -o "$exe" 2>"$work/$d.cc"; then
        echo "FAIL $d: cc: $(cat "$work/$d.cc")"; fail=$((fail + 1)); continue
    fi
    if ! "$exe" >"$work/$d.out" 2>&1; then
        echo "FAIL $d: run failed"; fail=$((fail + 1)); continue
    fi
    if ! diff -u "test/ast/$d/prog.expected.out" "$work/$d.out" >"$work/$d.diff"; then
        echo "FAIL $d: output differs"; sed 's/^/  /' "$work/$d.diff"; fail=$((fail + 1)); continue
    fi
    pass=$((pass + 1))
done
echo "p41/runtime: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
