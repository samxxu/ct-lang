#!/bin/sh
# Phase 44: the postfix `?` diagnostics.
#
# L44-1/2/3 are reported by the emitter (compile mode), so their position is
# the node line; L44-4 is reported by the parser at the `?` itself, so the
# fourth argument pins the exact `line:column`.
set -u
ctast=${1:?usage: p44_try_errors.sh <ct-ast>}
pass=0
fail=0
check() {
    d=$1
    want=$2
    pos=${3:-}
    "$ctast" compile "test/ast/errors/$d/prog.ct" -o "/tmp/p44-$d.c" >/tmp/p44.out 2>/tmp/p44.err
    if [ $? -eq 0 ]; then
        echo "FAIL $d: rc=0"
        fail=$((fail + 1))
        return
    fi
    if [ -n "$pos" ]; then
        if ! grep -Fq "test/ast/errors/$d/prog.ct:$pos: error: $want" /tmp/p44.err; then
            echo "FAIL $d: missing '$pos: error: $want'"
            sed 's/^/  /' /tmp/p44.err
            fail=$((fail + 1))
            return
        fi
    elif ! grep -Fq "$want" /tmp/p44.err; then
        echo "FAIL $d: missing '$want'"
        sed 's/^/  /' /tmp/p44.err
        fail=$((fail + 1))
        return
    fi
    pass=$((pass + 1))
}
check p44_outer "postfix '?' needs a function returning Result"
check p44_error_type "expected error type 'int', got 'char*'"
check p44_operand "'?' needs a Result operand"
check p44_pos_cond "'?' is not allowed here" 4:13
check p44_pos_short "'?' is not allowed here" 4:22
check p44_pos_ternary "'?' is not allowed here" 4:25
check p44_pos_errdefer "'?' is not allowed here" 4:20
check p44_pos_closure "'?' is not allowed here" 4:37
check p44_pos_file "'?' is not allowed here" 2:29
echo "p44/errors: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
