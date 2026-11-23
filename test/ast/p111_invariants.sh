#!/bin/sh
# SH-111: lowering invariants, five positive classes and their negative probes.
#
# The rules themselves are docs/design/lowering-invariants.md. The emitter
# asserts the mechanical subset before the first byte is written:
#
#   I1  a return / break / continue cleanup edge is a finite chain of releases
#       and materialised deferred bodies, never a control transfer and never a
#       goto's `b` slot;
#   I2  on one edge, every deferred body runs before every release (defers
#       LIFO, then auto-drop LIFO);
#   I3  a normal exit never carries an `errdefer` body;
#   I4  every materialised receiver has one distinct temporary name.
#
# A program the parser accepts cannot break these rules, so the negative half
# uses the documented test seam `CT_EMIT_INVARIANT_FAULT`: it injects exactly
# one AST fault before the independent walk, which must then report it with a
# source position. The variable is unset for every normal compiler run.
#
# Usage: sh test/ast/p111_invariants.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p111_invariants.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p111inv.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p111/invariants: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

# ---- five positive classes ------------------------------------------------

cat >"$work/ret.ct" <<'CT'
#include <stdio.h>
#include <stdlib.h>

struct R { int id; } use Drop;

impl Drop for R {
    void drop() { printf("drop\n"); }
}

int f(void)
{
    own struct R *r = malloc(sizeof(struct R));
    r->id = 1;
    defer { printf("defer\n"); }
    return 0;
}

int main(void) { printf("rc=%d\n", f()); return 0; }
CT
cat >"$work/ret.expected" <<'EOF'
defer
drop
rc=0
EOF

cat >"$work/brk.ct" <<'CT'
#include <stdio.h>

int main(void)
{
    for (int i = 0; i < 3; i++) {
        defer { printf("d%d\n", i); }
        if (i == 1) break;
        printf("b%d\n", i);
    }
    printf("end\n");
    return 0;
}
CT
cat >"$work/brk.expected" <<'EOF'
b0
d0
d1
end
EOF

cat >"$work/cont.ct" <<'CT'
#include <stdio.h>

int main(void)
{
    for (int i = 0; i < 3; i++) {
        defer { printf("c%d\n", i); }
        if (i == 1) continue;
        printf("b%d\n", i);
    }
    printf("end\n");
    return 0;
}
CT
cat >"$work/cont.expected" <<'EOF'
b0
c0
c1
b2
c2
end
EOF

cat >"$work/err.ct" <<'CT'
#include <stdio.h>

Result<int, char *> fail(void) { return err: (Result<int, char *>){0, 0, "e"}; }

Result<int, char *> run(void)
{
    defer { printf("defer\n"); }
    errdefer { printf("errdefer\n"); }
    int v = fail()?;
    return (Result<int, char *>){1, v, 0};
}

int main(void) { printf("ok=%d\n", run().ok); return 0; }
CT
cat >"$work/err.expected" <<'EOF'
errdefer
defer
ok=0
EOF

cat >"$work/chain.ct" <<'CT'
#include <stdio.h>

trait H { H tap(int n); int get(); }

struct R { int s; } use H;

impl H for R {
    H tap(int n) { self->s = self->s + n; return self; }
    int get() { return self->s; }
}

int main(void)
{
    R x;
    x.s = 1;
    H h = x;
    int got = h.tap(2)->tap(3)->get();
    printf("%d\n", got);
    return 0;
}
CT
cat >"$work/chain.expected" <<'EOF'
6
EOF

run_positive() {
    name=$1
    if ! "$ctast" "$work/$name.ct" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name compiles" "$(sed -n '1,4p' "$work/$name.log")"
        return 1
    fi
    if [ -s "$work/$name.log" ]; then
        bad "$name is quiet" "$(sed -n '1,4p' "$work/$name.log")"
        return 1
    fi
    if ! "${CC:-cc}" -Wall -Wextra -std=c99 "$work/$name.c" -o "$work/$name.bin" \
            >"$work/$name.cc" 2>&1; then
        bad "$name C builds warning-free" "$(sed -n '1,4p' "$work/$name.cc")"
        return 1
    fi
    if ! "$work/$name.bin" >"$work/$name.out" 2>&1; then
        bad "$name runs" "$(cat "$work/$name.out")"
        return 1
    fi
    if ! cmp -s "$work/$name.out" "$work/$name.expected"; then
        bad "$name output" "$(diff "$work/$name.expected" "$work/$name.out" | head -6 | tr '\n' ' ')"
        return 1
    fi
    ok "$name (positive: cleanup edge / temporary chain)"
}

run_positive ret
run_positive brk
run_positive cont
run_positive err
run_positive chain

# The chain really is materialised, not emitted as an unaddressable rvalue.
if grep -q '__ct_tmp' "$work/chain.c"; then
    ok "the receiver chain is materialised into __ct_tmpN"
else
    bad "the receiver chain was not materialised"
fi

# ---- six negatives, one injected AST fault each ---------------------------

expect_fault() {
    src=$1
    fault=$2
    msg=$3
    label=$4
    if CT_EMIT_INVARIANT_FAULT="$fault" "$ctast" "$work/$src.ct" -o "$work/fault.c" \
            >"$work/fault.out" 2>"$work/fault.err"; then
        bad "$label is refused" "exit 0; the injected fault was not detected"
        return
    fi
    if ! grep -Fq "$msg" "$work/fault.err"; then
        bad "$label diagnostic" "$(sed -n '1,3p' "$work/fault.err")"
        return
    fi
    if ! grep -Eq '\.ct:[0-9]+:[0-9]+: error: ' "$work/fault.err"; then
        bad "$label position" "$(sed -n '1,3p' "$work/fault.err")"
        return
    fi
    ok "$label"
}

expect_fault ret cleanup-jump \
    "lowering invariant I1: control transfer inside a cleanup edge" \
    "I1 rejects a jump on a return cleanup edge"
expect_fault ret cleanup-cycle \
    "lowering invariant I1: a cleanup edge is cyclic" \
    "I1 rejects a cyclic cleanup edge"
expect_fault ret cleanup-drop-first \
    "lowering invariant I2: a deferred body runs after a release on the same edge" \
    "I2 rejects a defer that runs after a release"
expect_fault err errdefer-normal \
    "lowering invariant I3: an errdefer body runs on a normal exit" \
    "I3 rejects an errdefer on a normal exit"
expect_fault chain temp-missing \
    "lowering invariant I4: a hoisted receiver has no temporary name" \
    "I4 rejects an unnamed hoisted receiver"
expect_fault chain temp-dup \
    "lowering invariant I4: two hoisted receivers share a temporary name" \
    "I4 rejects a temporary-name collision"

echo "p111/invariants: $fail failure(s)"
[ "$fail" -eq 0 ] || exit 1
exit 0
