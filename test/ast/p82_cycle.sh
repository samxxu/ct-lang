#!/bin/sh
# PH-82 / S82b: the direct `Box<X>` field-cycle warning (E82-3, E82-6).
#
#   - only `Box<X>` fields are edges; adjacent edges count one; the walk stops
#     at three edges, so a self loop, A -> B -> A and A -> B -> C -> A are hit
#     and a four-edge ring is not;
#   - a repeated payload field is one edge, and a cycle is reported once;
#   - `warn` (the default) keeps exit 0; `leaks = error` fails the build;
#   - the wording says "may leak ... unless the cycle is broken by hand" and
#     never "will leak" (D-012); `--debug-leaks` is not a cycle detector;
#   - the repository's whole `Box<` corpus produces exactly one finding: the
#     deliberate `test/ast/p81_box/cycle.ct` self loop.
#
# Usage: sh test/ast/p82_cycle.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p82_cycle.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p82cyc.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p82/cycle: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

cat >"$work/self.ct" <<'CT'
struct C { Box<C> self; Box<int> i; }
int main(void) { return 0; }
CT

cat >"$work/two.ct" <<'CT'
struct A { Box<B> b; Box<B> b2; }
struct B { Box<A> a; }
int main(void) { return 0; }
CT

cat >"$work/three.ct" <<'CT'
struct A { Box<B> b; }
struct B { Box<C> c; }
struct C { Box<A> a; }
int main(void) { return 0; }
CT

cat >"$work/four.ct" <<'CT'
struct A { Box<B> b; }
struct B { Box<C> c; }
struct C { Box<D> d; }
struct D { Box<A> a; }
int main(void) { return 0; }
CT

cat >"$work/oneway.ct" <<'CT'
struct A { Box<B> b; }
struct B { int n; }
struct D { Box<A> a; }
int main(void) { return 0; }
CT

cat >"$work/pointer.ct" <<'CT'
struct A { B *p; }
struct B { Box<A> a; }
int main(void) { return 0; }
CT

compile() {   # compile <name>; result in $work/<name>.log, exit in $rc
    "$ctast" "$work/$1.ct" -o "$work/$1.c" >"$work/$1.log" 2>&1
    rc=$?
}

# 1) self loop: C -> C; warn keeps exit 0.
compile self
if [ "$rc" -eq 0 ] && grep -Fq "warning: potential reference cycle: C -> C" "$work/self.log"; then
    ok "self loop C -> C is reported as a warning"
else
    bad "self loop" "exit $rc: $(head -2 "$work/self.log")"
fi

# 2) two-edge cycle: reported once even with two payload fields.
compile two
if [ "$rc" -eq 0 ] && [ "$(grep -cF 'potential reference cycle: A -> B -> A' "$work/two.log")" -eq 1 ]; then
    ok "A -> B -> A is reported once (duplicate payload field is one edge)"
else
    bad "two-edge cycle" "exit $rc: $(head -3 "$work/two.log")"
fi

# 3) three-edge cycle: hit at the depth limit.
compile three
if [ "$rc" -eq 0 ] && grep -Fq "potential reference cycle: A -> B -> C -> A" "$work/three.log"; then
    ok "A -> B -> C -> A is reported (depth limit 3)"
else
    bad "three-edge cycle" "exit $rc: $(head -2 "$work/three.log")"
fi

# 4) a four-edge ring is outside the limit (D-012, R82-2).
compile four
if [ "$rc" -eq 0 ] && ! grep -Fq "potential reference cycle" "$work/four.log"; then
    ok "a four-edge ring is not reported (limit is 3 edges)"
else
    bad "depth limit" "exit $rc: $(head -2 "$work/four.log")"
fi

# 5) a one-way Box chain is not a cycle.
compile oneway
if [ "$rc" -eq 0 ] && ! grep -Fq "potential reference cycle" "$work/oneway.log"; then
    ok "a one-way chain (D -> A -> B) is not reported"
else
    bad "one-way" "exit $rc: $(head -2 "$work/oneway.log")"
fi

# 6) only Box fields count: a plain pointer field is not an edge.
compile pointer
if [ "$rc" -eq 0 ] && ! grep -Fq "potential reference cycle" "$work/pointer.log"; then
    ok "a plain pointer field is not a Box edge (A * B -> A alone is not a cycle)"
else
    bad "pointer field" "exit $rc: $(head -2 "$work/pointer.log")"
fi

# 7) wording: "may leak ... unless the cycle is broken by hand", never "will
#    leak" (E82-6).
if grep -Fq "may leak unless the cycle is broken by hand" "$work/two.log" \
        && ! grep -Fq "will leak" "$work/two.log"; then
    ok "wording says may leak unless broken by hand, never will leak"
else
    bad "wording" "$(head -2 "$work/two.log")"
fi

# 8) `ct check` raises the finding (existing check policy) with a column, and
#    the JSON record names the class.
"$ctast" check --allow-c-boundary --diagnostics=json "$work/two.ct" \
    >"$work/two.json" 2>"$work/two.check.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq '"type":"potential_cycle"' "$work/two.json" \
        && grep -Fq '"severity":"error"' "$work/two.json" \
        && grep -Fq '"col":' "$work/two.json"; then
    ok "ct check: potential_cycle JSON carries severity error and col"
else
    bad "check JSON" "exit $rc: $(head -2 "$work/two.json" "$work/two.check.err")"
fi
"$ctast" check --allow-c-boundary "$work/two.ct" >"$work/two.check.out" 2>"$work/two.check.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -Eq 'two\.ct:[0-9]+:[0-9]+: error: potential reference cycle' "$work/two.check.err"; then
    ok "ct check: text finding is file:line:col: error:"
else
    bad "check text" "exit $rc: $(head -2 "$work/two.check.err")"
fi

# 9) `leaks = error` turns the same warning into a build failure, before a
#    product is written; the warn package keeps exit 0 and the product.
mkdir -p "$work/warn" "$work/err"
cp "$work/two.ct" "$work/warn/prog.ct"
cp "$work/two.ct" "$work/err/prog.ct"
printf 'name = demo\nleaks = warn\n' >"$work/warn/ct.pkg"
printf 'name = demo\nleaks = error\n' >"$work/err/ct.pkg"
mkdir -p "$work/warn/out" "$work/err/out"
"$ctast" build -I "$work/warn" --emit-c -o "$work/warn/out" "$work/warn/prog.ct" \
    >"$work/warn/build.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$work/warn/out/prog.c" ] \
        && grep -Fq "warning: potential reference cycle" "$work/warn/build.log"; then
    ok "leaks = warn: build exits 0 and writes the product"
else
    bad "warn build" "exit $rc: $(head -2 "$work/warn/build.log")"
fi
"$ctast" build -I "$work/err" --emit-c -o "$work/err/out" "$work/err/prog.ct" \
    >"$work/err/build.log" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq "error: potential reference cycle" "$work/err/build.log"; then
    ok "leaks = error: build exits 1 with error: on the cycle"
else
    bad "error build" "exit $rc: $(head -2 "$work/err/build.log")"
fi
if [ -e "$work/err/out/prog.c" ]; then
    bad "error build artifact" "a failed build still wrote prog.c"
else
    ok "leaks = error: no .c product is written"
fi

# 10) the repository's `Box<` corpus has exactly one finding: the deliberate
#     self loop. Every other fixture with a Box field stays silent (E82-4's
#     zero-false-positive side, on the corpus that can actually carry one).
hits=""
for f in $(grep -rl 'Box<' --include='*.ct' test/ examples/ lib/ 2>/dev/null); do
    case "$f" in lib/core/Box.h.ct) continue ;; esac
    "$ctast" "$f" -o "$work/corpus.c" >"$work/corpus.log" 2>&1
    grep -Fq "potential reference cycle" "$work/corpus.log" && hits="$hits $f"
done
if [ "$hits" = " test/ast/p81_box/cycle.ct" ]; then
    ok "corpus: exactly one finding, the deliberate p81_box/cycle.ct self loop"
else
    bad "corpus zero false positives" "unexpected findings:$hits"
fi

[ "$fail" -eq 0 ] && echo "p82_cycle: OK"
exit "$fail"
