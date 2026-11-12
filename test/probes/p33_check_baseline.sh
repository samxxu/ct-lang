#!/bin/sh
# Phase 33 S0: the pre-implementation red baseline.
#
# The card names the Phase 31 close-out as the base commit; Phase 32 landed on
# top of it before Phase 33 started, so the rebuild here is at the Phase 32
# close-out (8ec7a1d's successor, recorded below) -- the first implementation
# commit's parent. Every probe is what today's compiler does with the shape
# Phase 33 must accept (or reject with an L33-* diagnostic); the diff between
# this file and the post-slice run is the red proof.
#
# Usage: test/probes/p33_check_baseline.sh [ct-ast-binary]
# Default binary: $CT_AST or /tmp/ctb/ct-ast (the rebuild of the base commit).
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
ct=${1:-${CT_AST:-/tmp/ctb/ct-ast}}
fx="$root/test/probes/fixtures"
out="$root/test/probes/p33_check_baseline.txt"
work=${TMPDIR:-/tmp}/p33probe

if [ ! -x "$ct" ]; then
    echo "p33_check_baseline: no ct-ast binary at $ct" >&2
    exit 2
fi

mkdir -p "$fx" "$work"

cat >"$fx/p33_bound.ct" <<'EOF'
/* P33 probe: a bounded generic struct. */
/* Today the struct parser rejects the bound at the ':' (5:13). */
/* A: struct Box<T: Show> */
/* B: Box<Circle> must satisfy Show after Phase 33 O1. */
struct Box<T: Show> {
    T value;
}
int main(void) { return 0; }
EOF

cat >"$fx/p33_nested.ct" <<'EOF'
/* P33 probe: nested impl pattern. */
struct Box<T> {
    T value;
}

impl<T> Box<Box<T>> {
    int depth() { return 1; }
}

int main(void) {
    Box<Box<int>> b;
    b.depth();
    return 0;
}
EOF

cat >"$fx/p33_implbound.ct" <<'EOF'
/* P33 probe: a bound on the impl itself is not a thing (L33-2). */
struct Box<T> {
    T value;
}

/* today: the impl pattern parser rejects the bound at the ':' */
/* A: impl<T: Show> Box<T> */
/* B: after Phase 33 S3 this is L33-2. */
impl<T: Show> Box<T> {
    int depth() { return 1; }
}
int main(void) { return 0; }
EOF

cat >"$fx/p33_inherit.ct" <<'EOF'
/* P33 probe: a struct bound must reach the impl<T> Box<T> body. */
trait Show {
    int show();
}
struct Circle {
    int r;
} use Show;
impl Show for Circle {
    int show() { return self->r; }
}
struct Box<T> {
    T value;
}

impl<T> Box<T> {
    int show()
    {
        return self->value.show();
    }
}
int main(void)
{
    Box<Circle> b;
    return b.show();
}
EOF

cat >"$fx/p33_enc.ct" <<'EOF'
/* P33 probe: the encoded instance tag of Box<int>. */
struct Box<T> {
    T value;
}
int main(void)
{
    Box<int> b;
    b.value = 1;
    return b.value;
}
EOF

cat >"$fx/p33_boundalt.ct" <<'EOF'
/* P33 probe: the `use Show` alternative on the struct itself. */
trait Show {
    int show();
}
struct Circle {
    int r;
} use Show;
impl Show for Circle {
    int show() { return self->r; }
}
struct Box<T> {
    T value;
} use Show;
impl Show for Box {
    int show() { return 0; }
}
int main(void)
{
    Box<Circle> b;
    Box<Box<Circle>> n;
    return b.show() + n.show();
}
EOF

cat >"$fx/p33_pseudo.ct" <<'EOF'
/* P33 probe: the pseudo instance the nested pattern registers today. */
struct Box<T> {
    T value;
}
impl<T> Box<Box<T>> {
    int depth() { return 1; }
}
int main(void)
{
    Box<Box<int>> b;
    return b.value.value;
}
EOF

cat >"$fx/p33_wild.ct" <<'EOF'
/* P33 probe: a wildcard pattern is silently accepted today. */
struct Box<T> {
    T value;
}
impl<T> Box<_> {
    int depth() { return 1; }
}
int main(void) { return 0; }
EOF

cat >"$fx/p33_suffix.ct" <<'EOF'
/* P33 probe: a pointer suffix in a pattern. */
struct Box<T> {
    T value;
}
impl<T> Box<T *> {
    int depth() { return 1; }
}
int main(void) { return 0; }
EOF

cat >"$fx/p33_fnptrpat.ct" <<'EOF'
/* P33 probe: a function-pointer pattern. */
struct Box<T> {
    T value;
}
impl<T> Box<int (*)(int)> {
    int depth() { return 1; }
}
int main(void) { return 0; }
EOF

cat >"$fx/p33_drop.ct" <<'EOF'
/* P33 probe: the built-in Drop carries no vtable. */
struct A {
    int v;
} use Drop;
impl Drop for A {
    void drop() { }
}
int main(void)
{
    A a;
    a.v = 1;
    return 0;
}
EOF

cat >"$fx/p33_gtrait.ct" <<'EOF'
/* P33 probe: a generic trait (Phase 35, not this phase). */
trait Show<T> {
    int show();
}
int main(void) { return 0; }
EOF

run() {
    f=$1
    mode=$2
    err=$(cd "$root" && "$ct" $mode "$fx/$f" 2>&1 >/dev/null)
    rc=$?
    printf '%-22s %-9s rc=%s  %s\n' "$f" "$mode" "$rc" \
        "$(printf '%s\n' "$err" | grep -v '^$' | head -1)"
}

emit() {
    f=$1
    d="$work/$f"
    rm -rf "$d"
    mkdir -p "$d"
    err=$(cd "$root" && "$ct" "$fx/$f" -o "$d/x.c" 2>&1 >/dev/null)
    rc=$?
    printf '%-22s %-9s rc=%s  %s\n' "$f" "compile" "$rc" \
        "$(printf '%s\n' "$err" | grep -v '^$' | head -1)"
    printf '%-22s %-9s tags: %s\n' "$f" "grep" \
        "$(grep -o 'struct Box_[A-Za-z0-9_]*' "$d/x.c" 2>/dev/null | sort -u | tr '\n' ' ')"
    if [ -f "$d/x.c" ]; then
        printf '%-22s %-9s vtable: %s\n' "$f" "grep" \
            "$(grep -o 'Box_[A-Za-z0-9_]*_Show_vtable' "$d/x.c" 2>/dev/null | sort -u | tr '\n' ' ')"
    fi
}

{
    echo "# Phase 33 S0 baseline (ct-ast $("$ct" --version | awk '{print $2}') at 69f2396, the Phase 32 close-out)"
    echo "# binary: $ct"
    echo "# fields: probe  mode  rc  first stderr line"
    run p33_bound.ct check
    run p33_nested.ct check
    emit p33_nested.ct
    run p33_implbound.ct check
    run p33_inherit.ct check
    emit p33_inherit.ct
    emit p33_enc.ct
    run p33_boundalt.ct check
    emit p33_boundalt.ct
    emit p33_pseudo.ct
    run p33_wild.ct check
    run p33_suffix.ct check
    run p33_fnptrpat.ct check
    run p33_gtrait.ct check
    # Drop / Handback: the built-in semantics set a flag, never a vtable.
    rm -rf "$work/drop"
    mkdir -p "$work/drop"
    err=$(cd "$root" && "$ct" build --emit-c "$fx/p33_drop.ct" -o "$work/drop" 2>&1 >/dev/null)
    rc=$?
    printf '%-22s %-9s rc=%s  %s\n' "p33_drop.ct" "build" "$rc" \
        "$(printf '%s\n' "$err" | grep -v '^$' | head -1)"
    printf '%-22s %-9s symbols: %s\n' "p33_drop.ct" "grep" \
        "$(grep -ho 'A_Drop_drop\|Drop_vtbl\|A_Drop_vtable' "$work/drop"/*.c 2>/dev/null | sort -u | tr '\n' ' ')"
    # O3 red proof: D31-5, the cross-unit element hard error (fixture from P31).
    err=$(cd "$root" && "$ct" build test/modules/p31_cross_unit_owned/main.ct -o "$work/d315" 2>&1 >/dev/null)
    rc=$?
    printf '%-22s %-9s rc=%s  %s\n' "p31_cross_unit_owned" "build" "$rc" \
        "$(printf '%s\n' "$err" | grep -v '^$' | head -1)"
} >"$out"

echo "wrote $out"
grep -c 'rc=' "$out"
