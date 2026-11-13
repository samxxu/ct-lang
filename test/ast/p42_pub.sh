#!/bin/sh
# Phase 42 R1: method-level pub syntax and L42-1/2/3.
set -u
ctast=$1
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/pos.h.ct" <<'CT'
pub struct Counter {
    int n;
}
impl Counter {
    pub int get() { return self.n; }
    pub static Counter make() { Counter c = {0}; return c; }
    static pub int twice() { return 2; }
}
CT
cat > "$work/neg_scope.ct" <<'CT'
pub struct S { int n; }
impl S { pub int get() { return self.n; } }
CT
cat > "$work/neg_private.h.ct" <<'CT'
struct S { int n; }
impl S { pub int get() { return self.n; } }
CT
cat > "$work/neg_trait.h.ct" <<'CT'
pub trait T { int get(); }
pub struct S { int n; }
impl T for S { pub int get() { return self.n; } }
CT
cat > "$work/neg_block.h.ct" <<'CT'
pub struct S { int n; }
pub impl S { int get() { return self.n; } }
CT
pass=0
fail=0
if "$ctast" check "$work/pos.h.ct" >/dev/null 2>"$work/pos.err"; then pass=$((pass + 1)); else echo "FAIL pub-syntax: $(cat "$work/pos.err")"; fail=$((fail + 1)); fi
checkerr() {
    name=$1; want=$2
    if "$ctast" check "$work/$name" >/dev/null 2>"$work/e"; then
        echo "FAIL $name: expected error"; fail=$((fail + 1)); return
    fi
    if ! grep -qF "$want" "$work/e"; then
        echo "FAIL $name: missing '$want'"; sed 's/^/  /' "$work/e"; fail=$((fail + 1)); return
    fi
    pass=$((pass + 1))
}
checkerr neg_scope.ct "a pub method needs a pub struct in a .h.ct unit"
checkerr neg_private.h.ct "a pub method needs a pub struct in a .h.ct unit"
checkerr neg_trait.h.ct "a trait impl method cannot be pub"
checkerr neg_block.h.ct "a pub impl block is not supported; mark methods"
echo "p42/pub-syntax: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
