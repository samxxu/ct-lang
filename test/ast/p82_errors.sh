#!/bin/sh
# PH-82 / S82c: the direct-cycle warning's negative scope (E82-4, D-012 §2.5).
#
#   - `Vec<box<T>>`, a generic struct's `box<T>` field, a generic instance as a
#     box payload, an interface-typed field and a `box<typedef>` alias are not
#     edges, so their would-be rings do not report;
#   - a ring that needs four edges is outside the depth limit;
#   - an indirect ring that closes through a container is not reported;
#   - the repository corpus stays silent: every `box<` fixture except the
#     deliberate `p81_box/cycle.ct`, and the struct-heavy pattern/struct
#     fixtures, produce no `potential reference cycle`.
#
# Usage: sh test/ast/p82_errors.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p82_errors.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p82err.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p82/errors: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

cat >"$work/vec.ct" <<'CT'
struct B { int n; }
struct A { Vec<box<B>> v; }
int main(void) { return 0; }
CT

cat >"$work/generic.ct" <<'CT'
struct B { int n; }
struct G<T> { box<T> t; box<B> b; }
int main(void) { return 0; }
CT

cat >"$work/geninst.ct" <<'CT'
struct P { int n; }
struct Pair<X, Y> { X x; Y y; }
struct H { box<Pair<int,int>> p; }
int main(void) { return 0; }
CT

cat >"$work/iface.ct" <<'CT'
trait Shape { int area(); }
struct A { Shape s; }
int main(void) { return 0; }
CT

cat >"$work/alias.ct" <<'CT'
struct B { int n; }
typedef B BAlias;
struct A { box<BAlias> b; }
int main(void) { return 0; }
CT

cat >"$work/indirect.ct" <<'CT'
struct A { box<B> b; }
struct B { box<C> c; }
struct C { box<D> d; }
struct D { box<A> a; }
int main(void) { return 0; }
CT

# A ring that would close through a container: C -> A by box, A stores box<B>
# only in a Vec, so no A -> B edge and no cycle.
cat >"$work/container_ring.ct" <<'CT'
struct B { int n; }
struct A { Vec<box<B>> v; }
struct C { box<A> a; }
int main(void) { return 0; }
CT

silent() {   # silent <name>
    "$ctast" "$work/$1.ct" -o "$work/$1.c" >"$work/$1.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$1" "unexpected compile failure: $(head -2 "$work/$1.log")"
    elif grep -Fq "potential reference cycle" "$work/$1.log"; then
        bad "$1" "false positive: $(head -1 "$work/$1.log")"
    else
        ok "$1: no cycle warning"
    fi
}

silent vec
silent generic
silent geninst
silent iface
silent alias
silent indirect
silent container_ring

# The repository's struct-bearing fixtures that do not use box stay silent.
for f in test/ast/05_struct/prog.ct test/ast/15_composition/prog.ct \
         test/ast/28_iface_field/prog.ct test/patterns/composite/prog.ct \
         test/patterns/decorator/prog.ct; do
    [ -f "$f" ] || continue
    "$ctast" "$f" -o "$work/corpus.c" >"$work/corpus.log" 2>&1
    if grep -Fq "potential reference cycle" "$work/corpus.log"; then
        bad "corpus $f" "false positive: $(head -1 "$work/corpus.log")"
    else
        ok "corpus $f: no cycle warning"
    fi
done

# And the whole `box<` corpus has exactly one finding: the deliberate self
# loop under p81_box (E82-4's zero-false-positive side on the real corpus).
hits=""
for f in $(grep -rl 'box<' --include='*.ct' test/ examples/ lib/ 2>/dev/null); do
    case "$f" in lib/std/Box.h.ct) continue ;; esac
    "$ctast" "$f" -o "$work/corpus.c" >"$work/corpus.log" 2>&1
    grep -Fq "potential reference cycle" "$work/corpus.log" && hits="$hits $f"
done
if [ "$hits" = " test/ast/p81_box/cycle.ct" ]; then
    ok "box corpus: exactly one finding, the deliberate p81_box/cycle.ct self loop"
else
    bad "box corpus" "unexpected findings:$hits"
fi

[ "$fail" -eq 0 ] && echo "p82_errors: OK"
exit "$fail"
