#!/bin/sh
#
# AST capacity acceptance probes.
#
#   ./test/acceptance/run.sh                    build the live compiler (L0->L1->L2), probe it
#   CT=/path/to/ctc ./test/acceptance/run.sh    probe a prebuilt compiler
#
# This is NOT part of ./test/run.sh on purpose: the probes describe capabilities
# L0 does not have yet, so they are PENDING, not failures. run.sh's green must
# keep meaning "the compiler is correct", not "the compiler is complete".
#
# Why probes and not one program: L0 has no error recovery (the first error
# terminates), so compiling ast_spike.ct whole would reveal only the first gap.
# Each construct is isolated into its own translation unit and compiled on its
# own; the union of the results is the complete gap list.
#
# Verdicts, following selfhost/check-archive.sh:
#   PASS        in BASELINE and passing
#   PENDING     not in BASELINE and failing  -> a capability still to build
#   NEW PASS    not in BASELINE and passing  -> promote it into BASELINE
#   REGRESSION  in BASELINE but failing      -> the verdict is FAIL
#
# A PASS means the probe compiles *and* runs *and* prints the expected value, so
# a construct that merely "compiles and segfaults" is still PENDING -- silent
# passthrough must not count as support.
#
set -u

ROOT=$(cd "$(dirname "$0")/../.." && pwd)
CC=${CC:-cc}
CFLAGS="-Wall -Wextra -std=c99"
TMP=$(mktemp -d) || exit 1
trap 'rm -rf "$TMP"' EXIT

cd "$ROOT" || exit 1

CT=${CT:-}
if [ -z "$CT" ]; then
    # The live compiler is L2: ctc.c (L0) is frozen, so every new capability lands
    # on the CT side (selfhost/src/**), which L1 builds into L2, and L0 builds L1
    # from. Probing L0 instead is still possible via `CT=<l0 binary>`, but its
    # PENDING verdicts are then expected, not failures.
    if ! $CC $CFLAGS ctc.c -o "$TMP/ctc-l0" 2>"$TMP/build.log"; then
        echo "building ctc.c (L0) failed:"
        sed 's/^/    /' "$TMP/build.log"
        exit 1
    fi
    if ! "$TMP/ctc-l0" selfhost/ctc.ct -o "$TMP/ctc-l1.c" 2>"$TMP/build.log"; then
        echo "L0 could not compile L1 (selfhost/ctc.ct):"
        sed 's/^/    /' "$TMP/build.log"
        exit 1
    fi
    if ! $CC $CFLAGS "$TMP/ctc-l1.c" -o "$TMP/ctc-l1" 2>"$TMP/build.log"; then
        echo "building L1 failed:"
        sed 's/^/    /' "$TMP/build.log"
        exit 1
    fi
    mkdir -p "$TMP/l2src"
    if ! "$TMP/ctc-l1" build selfhost/src/driver.ct -o "$TMP/l2src" 2>"$TMP/build.log"; then
        echo "L1 could not build selfhost/src/**:"
        sed 's/^/    /' "$TMP/build.log"
        exit 1
    fi
    if ! $CC $CFLAGS "$TMP/l2src"/*.c -o "$TMP/ctc-l2" 2>"$TMP/build.log"; then
        echo "building L2 failed:"
        sed 's/^/    /' "$TMP/build.log"
        exit 1
    fi
    CT="$TMP/ctc-l2"
fi

# Probes that must pass today: the boxing surface the live compiler (L2) already
# reaches. Type/pointer interface-field assignment, plus the boxing control group.
BASELINE="p06_iface_value_field_assign p08_ptr_iface_field_assign p09_iface_local_from_value p10_iface_local_from_ptr p11_iface_return"

n_pass=0
n_pending=0
n_new=0
n_regress=0

first_line() {
    head -n 1 "$1" 2>/dev/null | tr -d '\r'
}

# A compiler's first `error:` line; falls back to the first line when the log
# holds only warnings (so a warning never masks the real failure detail).
first_error() {
    e=$(grep -m1 'error:' "$1" 2>/dev/null | tr -d '\r')
    [ -n "$e" ] || e=$(first_line "$1")
    printf '%s' "$e"
}

# run_bin NAME -- run $TMP/NAME.bin, capturing stdout and the exit code without
# letting the shell print a "Segmentation fault" job message for signal deaths.
run_bin() {
    ( "$TMP/$1.bin" >"$TMP/$1.out" 2>&1; echo $? >"$TMP/$1.rc" ) 2>/dev/null
    cat "$TMP/$1.rc"
}

in_baseline() {
    for b in $BASELINE; do
        [ "$b" = "$1" ] && return 0
    done
    return 1
}

# Shared prelude: the trait under test plus one concrete leaf implementation.
PRELUDE='
#include <stdio.h>
trait Node { int eval(); }
struct Leaf { int v; } use Node;
impl Node for Leaf { int eval() { return self->v; } }
'

report() {
    # report NAME VERDICT DETAIL
    if [ "$2" = PASS ]; then
        if in_baseline "$1"; then
            printf 'PASS        %s\n' "$1"
            n_pass=$((n_pass + 1))
        else
            printf 'NEW PASS    %s  (promote into BASELINE)\n' "$1"
            n_new=$((n_new + 1))
        fi
    else
        if in_baseline "$1"; then
            printf 'REGRESSION  %s  (%s)\n' "$1" "$3"
            n_regress=$((n_regress + 1))
        else
            printf 'PENDING     %s  (%s)\n' "$1" "$3"
            n_pending=$((n_pending + 1))
        fi
    fi
}

# run_probe NAME EXPECTED_OUTPUT  (program read from stdin)
run_probe() {
    name="$1"
    want="$2"
    printf '%s\n%s\n' "$PRELUDE" "$(cat)" >"$TMP/$name.ct"

    if ! "$CT" "$TMP/$name.ct" -o "$TMP/$name.c" 2>"$TMP/$name.err"; then
        report "$name" FAIL "ctc: $(first_error "$TMP/$name.err")"
        return
    fi
    if ! $CC $CFLAGS "$TMP/$name.c" -o "$TMP/$name.bin" 2>"$TMP/$name.cc.err"; then
        report "$name" FAIL "cc:  $(first_error "$TMP/$name.cc.err")"
        return
    fi
    rc=$(run_bin "$name")
    if [ "$rc" -ne 0 ]; then
        report "$name" FAIL "run: exited $rc (built but does not run)"
    elif [ -n "$want" ] && [ "$(cat "$TMP/$name.out")" != "$want" ]; then
        report "$name" FAIL "run: got '$(cat "$TMP/$name.out")', want '$want'"
    else
        report "$name" PASS ""
    fi
}

echo "compiler: $CT"
echo "== interface collections (the AST container need) =="

run_probe p01_iface_array_value '' <<'EOF'
int main(void) {
    Node kids[2];
    (void)kids;
    return 0;
}
EOF

run_probe p02_iface_array_ptr '' <<'EOF'
int main(void) {
    Node *kids[2];
    (void)kids;
    return 0;
}
EOF

run_probe p03_iface_array_elem_assign '7' <<'EOF'
int main(void) {
    Leaf a = { .v = 7 };
    Node kids[2];
    kids[0] = a;
    printf("%d\n", kids[0].eval());
    return 0;
}
EOF

run_probe p04_iface_array_elem_dispatch '9' <<'EOF'
int main(void) {
    Leaf a = { .v = 9 };
    Node kids[1];
    kids[0] = a;
    printf("%d\n", kids[0].eval());
    return 0;
}
EOF

echo "== interface fields (the AST edge need) =="

run_probe p05_iface_value_field_construct '3' <<'EOF'
struct Pair { Node l; Node r; } use Node;
impl Node for Pair { int eval() { return self->l.eval() + self->r.eval(); } }
int main(void) {
    Leaf a = { .v = 1 };
    Leaf b = { .v = 2 };
    struct Pair p = { .l = a, .r = b };
    printf("%d\n", p.eval());
    return 0;
}
EOF

run_probe p06_iface_value_field_assign '3' <<'EOF'
struct Pair { Node l; Node r; } use Node;
impl Node for Pair { int eval() { return self->l.eval() + self->r.eval(); } }
int main(void) {
    Leaf a = { .v = 1 };
    Leaf b = { .v = 2 };
    struct Pair p;
    p.l = a;
    p.r = b;
    printf("%d\n", p.eval());
    return 0;
}
EOF

run_probe p07_ptr_iface_field_construct '3' <<'EOF'
struct Link { Node *l; Node *r; } use Node;
impl Node for Link { int eval() { return self->l->eval() + self->r->eval(); } }
int main(void) {
    Leaf a = { .v = 1 };
    Leaf b = { .v = 2 };
    struct Link p = { .l = &a, .r = &b };
    printf("%d\n", p.eval());
    return 0;
}
EOF

run_probe p08_ptr_iface_field_assign '3' <<'EOF'
struct Link { Node *l; Node *r; } use Node;
impl Node for Link { int eval() { return self->l->eval() + self->r->eval(); } }
int main(void) {
    Leaf a = { .v = 1 };
    Leaf b = { .v = 2 };
    struct Link p;
    p.l = &a;
    p.r = &b;
    printf("%d\n", p.eval());
    return 0;
}
EOF

echo "== interface locals and returns (boxing control group) =="

run_probe p09_iface_local_from_value '7' <<'EOF'
int main(void) {
    Leaf a = { .v = 7 };
    Node n = a;
    printf("%d\n", n.eval());
    return 0;
}
EOF

run_probe p10_iface_local_from_ptr '8' <<'EOF'
int main(void) {
    Leaf a = { .v = 8 };
    Node n = &a;
    printf("%d\n", n.eval());
    return 0;
}
EOF

run_probe p11_iface_return '9' <<'EOF'
Node make(int v) {
    Leaf a = { .v = v };
    return a;
}
int main(void) {
    Node n = make(9);
    printf("%d\n", n.eval());
    return 0;
}
EOF

echo "== the whole target program =="
if ! "$CT" test/acceptance/ast_spike.ct -o "$TMP/spike.c" 2>"$TMP/spike.err"; then
    report ast_spike FAIL "ctc: $(first_error "$TMP/spike.err")"
elif ! $CC $CFLAGS "$TMP/spike.c" -o "$TMP/spike.bin" 2>"$TMP/spike.cc.err"; then
    report ast_spike FAIL "cc:  $(first_error "$TMP/spike.cc.err")"
else
    rc=$(run_bin spike)
    if [ "$rc" -ne 0 ]; then
        report ast_spike FAIL "run: exited $rc (built but does not run)"
    elif [ "$(cat "$TMP/spike.out")" != "5" ]; then
        report ast_spike FAIL "run: got '$(cat "$TMP/spike.out")', want '5'"
    else
        report ast_spike PASS ""
    fi
fi

echo
echo "== summary: $n_pass pass, $n_new new, $n_pending pending, $n_regress regression =="
[ "$n_regress" -eq 0 ]
