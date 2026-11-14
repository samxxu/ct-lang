#!/bin/sh
set -u
ctast=${1:?usage: p44_try_errors.sh <ct-ast>}
pass=0
fail=0
check() {
    d=$1; want=$2
    "$ctast" compile "test/ast/errors/$d/prog.ct" -o "/tmp/p44-$d.c" >/tmp/p44.out 2>/tmp/p44.err
    if [ $? -eq 0 ]; then echo "FAIL $d: rc=0"; fail=$((fail + 1)); return; fi
    if ! grep -Fq "$want" /tmp/p44.err; then
        echo "FAIL $d: missing '$want'"; sed 's/^/  /' /tmp/p44.err; fail=$((fail + 1)); return
    fi
    pass=$((pass + 1))
}
check p44_outer "postfix '?' needs a function returning Result"
check p44_error_type "expected error type 'int', got 'char*'"
check p44_operand "'?' needs a Result operand"
echo "p44/errors: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
