#!/bin/sh
# Phase 35 S0: the pre-implementation red baseline.
#
# The card fixes the base as "the parent of the first implementation commit",
# i.e. the Phase 34 close-out (abdc93b, ct-ast v0.34.0). Every probe below is what
# that compiler does today with a shape Phase 35 must accept (or reject with an
# L35-* diagnostic); the diff between this file and the post-slice run is the red
# proof.
#
# The four shapes in card section 2.2 were first probed on 2026-11-11 with a
# stray `;` after each trait body, so the recorded positions were the semicolon's
# ("expected a type (tok 4 ';')"), not the construct's. S0 re-probes the same
# shapes without it and records the positions the parser actually stops at.
#
# Usage: test/probes/p35_check_baseline.sh [ct-ast-binary]
# Default binary: $CT_AST or /tmp/p35base/ct-ast (the rebuild of the base commit).
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
ct=${1:-${CT_AST:-/tmp/p35base/ct-ast}}
fx="$root/test/probes/fixtures"
out="$root/test/probes/p35_check_baseline.txt"
old="$root/test/probes/p35_l35_5_old.txt"
work=${TMPDIR:-/tmp}/p35probe

if [ ! -x "$ct" ]; then
    echo "p35_check_baseline: no ct-ast binary at $ct" >&2
    exit 2
fi

base=$(cd "$root" && git rev-parse --short HEAD)

mkdir -p "$fx" "$work"

cat >"$fx/p35_trait_tparam.ct" <<'EOF'
/* P35 probe: a parameterised trait. */
/* Today the parser stops at the '<' after the trait name. */
/* E35-1: `trait Iter<T>` must become the instance `Iter_int`. */
trait Iter<T> {
    T next(void);
}

int main(void) { return 0; }
EOF

cat >"$fx/p35_impl_instance.ct" <<'EOF'
/* P35 probe: an impl over a trait instance. */
/* Today the parser stops at the '<' of the trait argument list. */
/* E35-1: the impl must register as Circle_Iter_int_next. */
trait Iter {
    int next(void);
}

struct Circle {
    int r;
}

impl Iter<int> for Circle {
    int next(void) { return 1; }
}

int main(void) { return 0; }
EOF

cat >"$fx/p35_bound_instance.ct" <<'EOF'
/* P35 probe: a bound naming a trait instance. */
/* Today the bound parser wants '>' right after the parameter name. */
/* E35-3: `T: Iter<int>` must store the normalised bound `Iter_int`. */
trait Iter {
    int next(void);
}

int f<T: Iter<int>>(T x) { return 0; }

int main(void) { return 0; }
EOF

cat >"$fx/p35_supertrait.ct" <<'EOF'
/* P35 baseline only: a supertrait declaration. */
/* Phase 35 does not do inheritance (D35-5); this file records what today's */
/* parser says, so T35-4 has a starting point and nothing else. */
trait Iter {
    int next(void);
}

trait Seq: Iter {
    int len(void);
}

int main(void) { return 0; }
EOF

cat >"$fx/p35_iface_mismatch.ct" <<'EOF'
/* P35 baseline: two interface values of different traits. */
/* Phase 35 adds no upcast, so the existing diagnostic stays (L35-5). */
trait Show { void show(void); }
trait Iter { int next(void); }

struct Circle { int r; } use Show;
struct Sq { int n; } use Iter;

impl Show for Circle { void show() { } }
impl Iter for Sq { int next() { return 1; } }

int main() {
    Circle c;
    Show sh = c;
    Iter it = sh;
    return 0;
}
EOF

{
    printf '# Phase 35 S0 probe baseline\n'
    printf '# baseline: %s\n' "$base"
    printf '# ct-ast:   %s\n' "$ct"
    printf '#\n'
    printf '# probe                                  rc  output\n'

    rc=0
    msg=$("$ct" "$fx/p35_trait_tparam.ct" -o "$work/a.c" 2>&1) || rc=$?
    printf 'A parameterised trait                  %-2s  %s\n' "$rc" "${msg#*probes/fixtures/}"

    rc=0
    msg=$("$ct" "$fx/p35_impl_instance.ct" -o "$work/b.c" 2>&1) || rc=$?
    printf 'B impl over a trait instance           %-2s  %s\n' "$rc" "${msg#*probes/fixtures/}"

    rc=0
    msg=$("$ct" "$fx/p35_bound_instance.ct" -o "$work/c.c" 2>&1) || rc=$?
    printf 'C bound naming a trait instance        %-2s  %s\n' "$rc" "${msg#*probes/fixtures/}"

    rc=0
    msg=$("$ct" "$fx/p35_supertrait.ct" -o "$work/d.c" 2>&1) || rc=$?
    printf 'D supertrait (T35-4, not this phase)   %-2s  %s\n' "$rc" "${msg#*probes/fixtures/}"

    rc=0
    msg=$("$ct" "$fx/p35_iface_mismatch.ct" -o "$work/e.c" 2>&1) || rc=$?
    printf 'E iface value of another trait (build) %-2s  %s\n' "$rc" "${msg#*probes/fixtures/}"

    rc=0
    msg=$("$ct" check "$fx/p35_iface_mismatch.ct" 2>&1) || rc=$?
    printf 'E iface value of another trait (check) %-2s  %s\n' "$rc" "${msg#*probes/fixtures/}"
} >"$out"

{
    printf '# L35-5 criteria running before Phase 35, archived by S0 at baseline %s\n' "$base"
    printf '#\n'
    printf '# The card recorded the l1/l2 `ct check` wording. The fixture under\n'
    printf '# test/ast/errors/ is run by ct-ast, which owns a different front end and\n'
    printf '# a different wording for the same refusal; both are pinned here so the\n'
    printf '# fixture asserts the one its gate actually prints.\n'
    printf '#\n'
    printf '# ct-ast (the binary check-ast gates; compile mode, then check mode):\n'
    printf '#   $ ct-ast test/probes/fixtures/p35_iface_mismatch.ct\n'
    "$ct" "$fx/p35_iface_mismatch.ct" -o "$work/e.c" 2>&1 | sed "s|$root/||; s|^|#   |"
    printf '#   $ ct-ast check test/probes/fixtures/p35_iface_mismatch.ct\n'
    "$ct" check "$fx/p35_iface_mismatch.ct" 2>&1 | sed "s|$root/||; s|^|#   |"
    printf '#\n'
    printf '# l1/l2 `ct check` (frozen layer, same fixture; not what the L35-5\n'
    printf '# fixture asserts, kept so the card wording has a home):\n'
    printf '#   $ ct check test/probes/fixtures/p35_iface_mismatch.ct\n'
    printf "#   test/probes/fixtures/p35_iface_mismatch.ct:1:1: error: 'sh' is an interface value of a different trait\n"
    printf '#\n# source anchors:\n'
    (cd "$root" && grep -n "interface type mismatch" selfhost/ct-ast/frontend/type/TypeCheck.h.ct)
    (cd "$root" && grep -n "is an interface value of a different trait" \
        selfhost/l1/ctc.ct selfhost/l2/core.ct | head -4)
} >"$old"

cat "$out"
