#!/bin/sh
# PH-76 (S1–S3): `expr$name` materialises a method-call hop once, then the
# chain continues on the declared variable. Only statement expressions accept
# it; own/borrow/const targets and non-call bases are refused; the target type
# must equal the hop's return type.
#
# Usage: sh test/ast/p76_chain.sh <ct-ast>
set -u
ctast=${1:?usage: p76_chain.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p76c.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

run_ok() { # name expected-exit file
    name=$1; want=$2; file=$3
    ( cd "$work" && "$ctast" build -o "$work/$name" "$file" ) >"$work/$name.build" 2>&1 || {
        echo "FAIL p76/chain: $name build failed" >&2
        sed 's/^/  /' "$work/$name.build" | head -4 >&2
        fail=1
        return
    }
    "$work/$name"; got=$?
    [ "$got" = "$want" ] || { echo "FAIL p76/chain: $name exit $got want $want" >&2; fail=1; }
}

cat > "$work/tail.ct" <<'CT'
trait M { int m(void); }
struct S { int v; } use M;
impl M for S { int m(void) { return self->v; } }
int main(void) { struct S s = { 1 }; int x; s.m()$x; return x; }
CT
run_ok tail 1 tail.ct

cat > "$work/multi.ct" <<'CT'
struct B;
trait Make { struct B make(void); }
trait N { int n(void); }
struct A { int v; } use Make;
struct B { int w; } use N;
impl Make for A { struct B make(void) { struct B b = {}; b.w = 7; return b; } }
impl N for B { int n(void) { return self->w; } }
int main(void) {
    struct A a = { 5 };
    struct B x;
    int y;
    a.make()$x.n()$y;
    return (x.w == 7 && y == 7) ? 0 : 1;
}
CT
run_ok multi 0 multi.ct

cat > "$work/type.ct" <<'CT'
struct B;
trait Make { struct B make(void); }
struct A { int v; } use Make;
struct B { int w; };
impl Make for A { struct B make(void) { struct B b = {}; return b; } }
int main(void) { struct A a = { 5 }; int x; a.make()$x; return 0; }
CT
( cd "$work" && "$ctast" check --types type.ct ) >"$work/type.log" 2>&1
if [ $? -eq 0 ] || ! grep -q "'\$' target: expected 'int', got 'struct B'" "$work/type.log"; then
    echo "FAIL p76/chain: type mismatch not diagnosed" >&2
    sed 's/^/  /' "$work/type.log" | head -4 >&2
    fail=1
fi

cat > "$work/const.ct" <<'CT'
trait M { int m(void); }
struct S { int v; } use M;
impl M for S { int m(void) { return self->v; } }
int main(void) { struct S s = { 1 }; const int x = 0; s.m()$x; return 0; }
CT
( cd "$work" && "$ctast" check --types const.ct ) >"$work/const.log" 2>&1
if [ $? -eq 0 ] || ! grep -q "const value cannot be a '\$' target" "$work/const.log"; then
    echo "FAIL p76/chain: const target not refused" >&2
    sed 's/^/  /' "$work/const.log" | head -4 >&2
    fail=1
fi

cat > "$work/noncall.ct" <<'CT'
trait M { int m(void); }
struct S { int v; } use M;
impl M for S { int m(void) { return self->v; } }
int main(void) { struct S s = { 1 }; int x; x$x; return 0; }
CT
( cd "$work" && "$ctast" check noncall.ct ) >"$work/noncall.log" 2>&1
if [ $? -eq 0 ] || ! grep -q "must follow a method call" "$work/noncall.log"; then
    echo "FAIL p76/chain: non-call base accepted" >&2
    sed 's/^/  /' "$work/noncall.log" | head -4 >&2
    fail=1
fi

cat > "$work/arg.ct" <<'CT'
trait M { int m(void); }
struct S { int v; } use M;
impl M for S { int m(void) { return self->v; } }
int take(int v) { return v; }
int main(void) { struct S s = { 1 }; int x; return take(s.m()$x); }
CT
( cd "$work" && "$ctast" check arg.ct ) >"$work/arg.log" 2>&1
if [ $? -eq 0 ] || ! grep -q "only allowed in a statement expression" "$work/arg.log"; then
    echo "FAIL p76/chain: argument-position '$' accepted" >&2
    sed 's/^/  /' "$work/arg.log" | head -4 >&2
    fail=1
fi

cat > "$work/void.ct" <<'CT'
trait V { void v(void); }
struct S { int n; } use V;
impl V for S { void v(void) { } }
int main(void) { struct S s = {}; int x; s.v()$x; return 0; }
CT
( cd "$work" && "$ctast" check --types void.ct ) >"$work/void.log" 2>&1
if [ $? -eq 0 ] || ! grep -q "void" "$work/void.log"; then
    echo "FAIL p76/chain: void-returning hop accepted" >&2
    sed 's/^/  /' "$work/void.log" | head -4 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p76/chain (tail, multi-hop, type/const/non-call/argument negatives)"
