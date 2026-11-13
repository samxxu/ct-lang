#!/bin/sh
# Phase 41 L41 diagnostics: one exact message per negative fixture.
set -u
ctast=$1
pass=0
fail=0
check() {
    name=$1
    want=$2
    if "$ctast" check "test/ast/errors/$name/prog.ct" >/tmp/p41e.out 2>/tmp/p41e.err; then
        echo "FAIL $name: expected non-zero"; fail=$((fail + 1)); return
    fi
    if ! grep -qF "$want" /tmp/p41e.err; then
        echo "FAIL $name: missing '$want'"; sed 's/^/  /' /tmp/p41e.err; fail=$((fail + 1)); return
    fi
    if ! grep -qE '^test/ast/errors/.*/prog\.ct:[0-9]+:[0-9]+: error: ' /tmp/p41e.err; then
        echo "FAIL $name: missing file:line:col"; sed 's/^/  /' /tmp/p41e.err; fail=$((fail + 1)); return
    fi
    pass=$((pass + 1))
}
check p41_atomic_bad_base "atomic supports only int, long, void * and bool"
check p41_atomic_double "use one atomic spelling, not both"
check p41_atomic_own_order "'own' must precede the type; an owned pointer cannot be atomic"
check p41_own_atomic "an owned value cannot be atomic: 'own' needs a struct that uses Drop"
check p41_atomic_return "an atomic value cannot be a return type"
check p41_atomic_typedef "an atomic value cannot be a typedef target"
check p41_atomic_lvalue "the first argument of 'ct_atomic_load' must be the address of an atomic variable"
check p41_cas_byvalue "pass &expected: a CAS needs the address of 'expected' to write the observed value back"
check p41_atomic_valuetype "atomic value type mismatch"
echo "p41/errors: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
