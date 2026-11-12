#!/bin/sh
# Phase 32 S0: the pre-implementation red baseline.
#
# Every probe below is accepted by today's `ct check` (the type pass does not
# exist yet) and `check --types` is an unknown option. After S1 the same probes
# must report the L32-* diagnostics, so the diff between this file and the
# post-S1 run is the red proof.
#
# Usage: test/probes/p32_check_baseline.sh [ct-ast-binary]
# Default binary: $CT_AST or /tmp/ct-ast (the v0.26.4 build of the Phase 31
# close-out commit).
set -u

root=$(cd "$(dirname "$0")/../.." && pwd)
ct=${1:-${CT_AST:-/tmp/ct-ast}}
fx="$root/test/probes/fixtures"
out="$root/test/probes/p32_check_baseline.txt"

if [ ! -x "$ct" ]; then
    echo "p32_check_baseline: no ct-ast binary at $ct" >&2
    exit 2
fi

mkdir -p "$fx"

cat >"$fx/p32_assign.ct" <<'EOF'
int main(void) {
    int x = "s";
    return 0;
}
EOF

cat >"$fx/p32_return.ct" <<'EOF'
int f(void) { return "s"; }
int main(void) { return 0; }
EOF

cat >"$fx/p32_push.ct" <<'EOF'
int main(void) {
    Vec<int> v;
    v.push("s");
    return 0;
}
EOF

cat >"$fx/p32_container.ct" <<'EOF'
int main(void) {
    Vec<int> v;
    Map<char *, int> m;
    v.set(0, "s");
    m.put("a", "b");
    return 0;
}
EOF

cat >"$fx/p32_struct.ct" <<'EOF'
struct A { int x; }
struct B { int y; }
int main(void) {
    struct A a;
    struct B b;
    a = b;
    return 0;
}
EOF

cat >"$fx/p32_ret_void.ct" <<'EOF'
int f(void) { return; }
void g(void) { return 1; }
int main(void) { return 0; }
EOF

cat >"$fx/p32_ok.ct" <<'EOF'
trait Show { int show(); }
struct Circle { int r; } use Show;
struct A { int x; }
impl Show for Circle { int show() { return self->r; } }
int main(void) {
    char *s = "hi";
    char *p = 0;
    int x = 1.5;
    void *v = s;
    struct Circle c;
    Show sh = c;
    struct A *pa;
    char *pc = pa;
    return 0;
}
EOF

cat >"$fx/p32_iface.ct" <<'EOF'
trait Show { int show(); }
struct Other { int x; }
struct Circ { int r; } use Show;
impl Show for Circ { int show() { return self->r; } }
int main(void) {
    struct Other o;
    Show sh = o;
    return 0;
}
EOF

cat >"$fx/p32_void_actual.ct" <<'EOF'
void f(void) { }
int main(void) {
    int x = f();
    Vec<int> v;
    v.push(f());
    return x;
}
EOF

cat >"$fx/p32_void_var.ct" <<'EOF'
int main(void) {
    void x;
    return 0;
}
EOF

cat >"$fx/p32_vec_void.ct" <<'EOF'
int main(void) {
    Vec<void> v;
    return 0;
}
EOF

cat >"$fx/p32_generic.ct" <<'EOF'
T id<T>(T x) { return x; }
int main(void) {
    int n = id(1);
    return n == 1 ? 0 : 1;
}
EOF

cp "$root/test/ast/errors/check_iface_use.ct" "$fx/" 2>/dev/null || true

run() {
    f=$1
    for m in check types; do
        if [ "$m" = check ]; then
            err=$(cd "$root" && "$ct" check "$fx/$f" 2>&1 >/dev/null)
        else
            err=$(cd "$root" && "$ct" check --types "$fx/$f" 2>&1 >/dev/null)
        fi
        rc=$?
        first=$(printf '%s\n' "$err" | grep -v '^$' | head -1)
        printf '%-22s %-13s rc=%s  %s\n' "$f" "check $([ "$m" = types ] && echo --types)" "$rc" "$first"
    done
}

{
    echo "# Phase 32 S0 baseline (ct-ast v0.26.4 at the Phase 31 close-out commit)"
    echo "# binary: $ct"
    echo "# fields: probe  mode  rc  first stderr line"
    for f in p32_assign.ct p32_return.ct p32_push.ct p32_container.ct \
             p32_struct.ct p32_ret_void.ct p32_ok.ct p32_iface.ct \
             p32_void_actual.ct p32_void_var.ct p32_vec_void.ct p32_generic.ct; do
        run "$f"
    done
} >"$out"

echo "wrote $out"
grep -c 'rc=' "$out"
