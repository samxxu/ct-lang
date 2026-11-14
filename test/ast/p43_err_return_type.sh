#!/bin/sh
# Phase 43 E43-1: err: payload mismatch is a hard error in check/compile.
set -u
ctast=$1
pass=0
fail=0
for d in p43_err_return_int p43_err_return_ptr p43_err_return_struct p43_err_return_result; do
    src="test/ast/errors/$d/prog.ct"
    "$ctast" check "$src" >/tmp/p43.out 2>/tmp/p43.err
    if [ $? -eq 0 ]; then echo "FAIL $d: check rc=0"; fail=$((fail + 1)); continue; fi
    if ! grep -q "return: expected '" /tmp/p43.err; then
        echo "FAIL $d: missing L43-1"; sed 's/^/  /' /tmp/p43.err; fail=$((fail + 1)); continue
    fi
    out=/tmp/p43-$d.c
    rm -f "$out"
    "$ctast" compile "$src" -o "$out" >/tmp/p43.o2 2>/tmp/p43.e2
    if [ $? -eq 0 ] || [ -f "$out" ]; then
        echo "FAIL $d: compile wrote output or rc=0"; fail=$((fail + 1)); continue
    fi
    pass=$((pass + 1))
done
echo "p43/errors: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
