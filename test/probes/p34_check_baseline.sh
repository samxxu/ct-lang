#!/bin/sh
# Phase 34 S0: the pre-implementation red baseline.
#
# The card fixes the base as "the parent of the first implementation commit",
# i.e. the Phase 33 close-out (66b8d00). Every probe below is what that
# compiler does today with a shape Phase 34 must accept (or reject with L34-3);
# the diff between this file and the post-slice run is the red proof.
#
# Usage: test/probes/p34_check_baseline.sh [ct-ast-binary]
# Default binary: $CT_AST or /tmp/p34base/ct-ast (the rebuild of the base commit).
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
ct=${1:-${CT_AST:-/tmp/p34base/ct-ast}}
fx="$root/test/probes/fixtures"
out="$root/test/probes/p34_check_baseline.txt"
old="$root/test/probes/p34_l26_2_old.txt"
work=${TMPDIR:-/tmp}/p34probe

if [ ! -x "$ct" ]; then
    echo "p34_check_baseline: no ct-ast binary at $ct" >&2
    exit 2
fi

base=$(cd "$root" && git rev-parse HEAD)

mkdir -p "$fx" "$work"

cat >"$fx/p34_pub.ct" <<'EOF'
/* P34 probe: a pub generic function. */
/* Today the parser rejects it at the name (L26-2). */
/* A: `pub T id<T>(T x)` must export the template body. */
/* B: a consumer unit calls id<int>(3). */
pub T id<T>(T x)
{
    return x;
}

int main(void)
{
    return id<int>(3);
}
EOF

cat >"$fx/p34_inherent.ct" <<'EOF'
/* P34 probe: a non-generic inherent impl. */
/* Today `impl Counter { ... }` is read as a trait impl of an unknown trait. */
pub struct Counter {
    int n;
}

impl Counter {
    int get() { return self->n; }
}

int main(void) { return 0; }
EOF

cat >"$fx/p34_enum.ct" <<'EOF'
/* P34 probe: a generic enum (L34-3 must name it). */
/* Today the parser stops at the `<` as an unexpected token. */
enum Option<T> {
    int has;
    T value;
}

int main(void) { return 0; }
EOF

cat >"$fx/p34_opt_iface.ct" <<'EOF'
/* P34 probe: Option<Show> already monomorphises today. */
/* This is not a new P34 capability; the phase only pins the API and shape. */
trait Show {
    int show();
}

struct Circle {
    int r;
} use Show;

impl Show for Circle {
    int show() { return self->r; }
}

struct Option<T> {
    int has;
    T value;
}

int main(void)
{
    Option<Show> o;
    o.has = 1;
    return o.has;
}
EOF

{
    printf '# Phase 34 S0 probe baseline\n'
    printf '# baseline: %s\n' "$base"
    printf '# ct-ast:   %s\n' "$ct"
    printf '#\n'
    printf '# probe                         rc  output\n'

    rc=0
    msg=$("$ct" "$fx/p34_pub.ct" 2>&1) || rc=$?
    printf 'A pub generic function         %-2s  %s\n' "$rc" "$msg"

    rc=0
    msg=$("$ct" "$fx/p34_inherent.ct" 2>&1) || rc=$?
    printf 'B non-generic inherent impl    %-2s  %s\n' "$rc" "$msg"

    rc=0
    msg=$("$ct" "$fx/p34_enum.ct" 2>&1) || rc=$?
    printf 'C generic enum                 %-2s  %s\n' "$rc" "$msg"

    rc=0
    msg=$(cd "$root" && grep -r "struct Option" lib/std 2>&1) || rc=$?
    printf 'D lib/std Option type          %-2s  %s\n' "$rc" "${msg:-<no match>}"

    rc=0
    msg=$("$ct" "$fx/p34_opt_iface.ct" -o "$work/opt_iface.c" 2>&1) || rc=$?
    shape=$(grep -c 'struct Option_Show__iface {' "$work/opt_iface.c" 2>/dev/null || printf 0)
    printf 'E Option<Show>                 %-2s  %s (struct Option_Show__iface x%s)\n' \
        "$rc" "${msg:-<compiled>}" "$shape"
} >"$out"

{
    printf '# L26-2 old criteria, archived by Phase 34 S0 at baseline %s\n' "$base"
    printf '#\n'
    printf '# code (the refusal):\n'
    (cd "$root" && grep -n 'generic functions cannot be pub' \
        selfhost/ct-ast/frontend/parse/Parser.h.ct)
    printf '#\n# executable assertions:\n'
    (cd "$root" && grep -n 'p26_diag generic_pub \|p26_chk generic_pub ' selfhost/check-ast.sh)
    (cd "$root" && grep -n 'E29-13 / B6\|p29b6.err' selfhost/check-ast.sh)
    printf '#\n# fixtures that must be promoted:\n'
    (cd "$root" && grep -rn 'pub T id<T>\|pub T ' \
        test/ast/errors/generic_pub.ct test/modules/errors/generic_struct_pub_fn.ct)
    printf '#\n# superseded wording (language-spec):\n'
    (cd "$root" && grep -n 'generic functions cannot be pub' docs/language-spec.md)
} >"$old"

cat "$out"
