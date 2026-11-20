#!/bin/sh
# PH-82 / S82c: `/* ct: allow-cycle */` suppresses the direct-cycle warning
# (E82-5, D-012 J-3).
#
#   - the marker only counts on the `struct` declaration's own line: a marker
#     above the struct, or on a field's line, does not suppress;
#   - a marker on any participant of a cycle suppresses that cycle, and an
#     unrelated marker does not;
#   - `ct check` still reports the suppression point as a `note:` (auditable),
#     while `ct compile` stays quiet;
#   - `leaks = error` does not resurrect a suppressed cycle, and removing the
#     marker makes the warning (and the build failure) come back.
#
# Usage: sh test/ast/p82_allow.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p82_allow.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p82allow.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p82/allow: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

# The documented tree pattern: the marker sits on the struct line.
cat >"$work/tree.ct" <<'CT'
struct Node {                 /* ct: allow-cycle */
    box<Node> first_child;
    Node *parent;
}
int main(void) { return 0; }
CT

cat >"$work/tree_nomark.ct" <<'CT'
struct Node {
    box<Node> first_child;
    Node *parent;
}
int main(void) { return 0; }
CT

# A self loop with the marker on the line above the struct: not suppressed.
cat >"$work/above.ct" <<'CT'
/* ct: allow-cycle */
struct N { box<N> child; }
int main(void) { return 0; }
CT

# A self loop with the marker on a field line: not suppressed either.
cat >"$work/fieldmark.ct" <<'CT'
struct M {
    box<M> child;  /* ct: allow-cycle */
}
int main(void) { return 0; }
CT

# Marker on the second participant of A -> B -> A: the cycle is suppressed.
cat >"$work/partner.ct" <<'CT'
struct A { box<B> b; }
struct B { box<A> a; }        /* ct: allow-cycle */
int main(void) { return 0; }
CT

# Marker on an unrelated struct: A -> B -> A is still reported.
cat >"$work/unrelated.ct" <<'CT'
struct A { box<B> b; }
struct B { box<A> a; }
struct Z { int n; }           /* ct: allow-cycle */
int main(void) { return 0; }
CT

compile() {   # compile <name>
    "$ctast" "$work/$1.ct" -o "$work/$1.c" >"$work/$1.log" 2>&1
    rc=$?
}

# 1) same-line marker suppresses.
compile tree
if [ "$rc" -eq 0 ] && ! grep -Fq "potential reference cycle" "$work/tree.log"; then
    ok "same-line marker suppresses the tree pattern's self loop"
else
    bad "tree pattern" "exit $rc: $(head -2 "$work/tree.log")"
fi

# 2) removing the marker brings the warning back.
compile tree_nomark
if [ "$rc" -eq 0 ] && grep -Fq "potential reference cycle: Node -> Node" "$work/tree_nomark.log"; then
    ok "removing the marker brings the warning back"
else
    bad "marker removed" "exit $rc: $(head -2 "$work/tree_nomark.log")"
fi

# 3) the marker above the struct does not count (same line only).
compile above
if [ "$rc" -eq 0 ] && grep -Fq "potential reference cycle: N -> N" "$work/above.log"; then
    ok "a marker on the line above the struct does not suppress"
else
    bad "marker above" "exit $rc: $(head -2 "$work/above.log")"
fi

# 4) a marker on a field's line does not count either.
compile fieldmark
if [ "$rc" -eq 0 ] && grep -Fq "potential reference cycle: M -> M" "$work/fieldmark.log"; then
    ok "a marker on a field line does not suppress"
else
    bad "marker on field" "exit $rc: $(head -2 "$work/fieldmark.log")"
fi

# 5) any participant's marker suppresses the whole cycle.
compile partner
if [ "$rc" -eq 0 ] && ! grep -Fq "potential reference cycle" "$work/partner.log"; then
    ok "a marker on one participant suppresses A -> B -> A"
else
    bad "participant marker" "exit $rc: $(head -2 "$work/partner.log")"
fi

# 6) an unrelated marker suppresses nothing.
compile unrelated
if [ "$rc" -eq 0 ] && grep -Fq "potential reference cycle: A -> B -> A" "$work/unrelated.log"; then
    ok "a marker on an unrelated struct does not suppress"
else
    bad "unrelated marker" "exit $rc: $(head -2 "$work/unrelated.log")"
fi

# 7) `ct check` reports the suppression point (file:line:col: note:) and still
#    exits 0; compile stays silent about it.
"$ctast" check --allow-c-boundary "$work/tree.ct" >"$work/tree.check.out" 2>"$work/tree.check.err"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$work/tree.check.out" ] \
        && grep -Fq "note: reference cycle suppressed by 'ct: allow-cycle': Node -> Node" "$work/tree.check.err" \
        && grep -Eq 'tree\.ct:1:[0-9]+: note:' "$work/tree.check.err"; then
    ok "ct check: reports the suppressed point as a note and exits 0"
else
    bad "check suppression point" "exit $rc: $(head -2 "$work/tree.check.err")"
fi
if [ -s "$work/tree.log" ]; then
    bad "compile quiet" "compile printed a suppression note: $(head -1 "$work/tree.log")"
else
    ok "ct compile: a suppressed cycle produces no note"
fi

# 8) `leaks = error` keeps a suppressed cycle from failing the build; removing
#    the marker makes the same build fail.
mkdir -p "$work/err"
cp "$work/tree.ct" "$work/err/allow.ct"
cp "$work/tree_nomark.ct" "$work/err/deny.ct"
printf 'name = demo\nleaks = error\n' >"$work/err/ct.pkg"
mkdir -p "$work/err/out1" "$work/err/out2"
"$ctast" build -I "$work/err" --emit-c -o "$work/err/out1" "$work/err/allow.ct" \
    >"$work/err/allow.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$work/err/out1/allow.c" ] \
        && ! grep -Fq "potential reference cycle" "$work/err/allow.log"; then
    ok "leaks = error: a suppressed cycle does not fail the build"
else
    bad "suppressed + error" "exit $rc: $(head -2 "$work/err/allow.log")"
fi
"$ctast" build -I "$work/err" --emit-c -o "$work/err/out2" "$work/err/deny.ct" \
    >"$work/err/deny.log" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq "error: potential reference cycle" "$work/err/deny.log"; then
    ok "leaks = error: removing the marker makes the build fail again"
else
    bad "removed marker + error" "exit $rc: $(head -2 "$work/err/deny.log")"
fi

[ "$fail" -eq 0 ] && echo "p82_allow: OK"
exit "$fail"
