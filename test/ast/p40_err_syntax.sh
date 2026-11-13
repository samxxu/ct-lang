#!/usr/bin/env bash
# R1 probe: err: markers after return/break/continue, 5 positives + 5
# negatives (L40-1..4 and loop-outside). Syntax only: `ct check`.
set -u
CT=${1:?usage: p40_err_syntax.sh <ct-ast>}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p40-r1.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
pos() {
    n=$1
    printf '%s\n' "$2" > "$tmp/p$n.ct"
    "$CT" check "$tmp/p$n.ct" >"$tmp/p$n.out" 2>"$tmp/p$n.err"
    if [ "$?" -ne 0 ]; then
        echo "FAIL p40/r1 positive $n" >&2
        sed 's/^/  /' "$tmp/p$n.err" >&2
        fail=1
    fi
}
neg() {
    n=$1
    msg=$2
    printf '%s\n' "$3" > "$tmp/n$n.ct"
    "$CT" check "$tmp/n$n.ct" >"$tmp/n$n.out" 2>"$tmp/n$n.err"
    if [ "$?" -eq 0 ]; then
        echo "FAIL p40/r1 negative $n: expected non-zero" >&2
        fail=1
    elif ! grep -Fq -- "$msg" "$tmp/n$n.err"; then
        echo "FAIL p40/r1 negative $n: missing '$msg'" >&2
        sed 's/^/  /' "$tmp/n$n.err" >&2
        fail=1
    fi
}
pos 1 'int f(void) { return err: 1; }'
pos 2 'void f(void) { return err:; }'
pos 3 'int f(void) { while (1) { break err:; } return 0; }'
pos 4 'int f(void) { while (1) { continue err:; } return 0; }'
pos 5 'int f(void) { int err = 1; return err; }'
neg 1 'an error return needs a value' 'int f(void) { return err:; }'
neg 2 'a void function cannot return a value' 'void f(void) { return err: 1; }'
neg 3 'err: break/continue is only allowed in a loop' 'int f(void) { break err:; return 0; }'
neg 4 'err: break is not allowed in a switch' 'int f(void) { switch (1) { case 1: break err:; } return 0; }'
neg 5 'err: break/continue is only allowed in a loop' 'int f(void) { continue err:; return 0; }'
if [ "$fail" -eq 0 ]; then echo "p40_r1: OK"; fi
exit "$fail"
