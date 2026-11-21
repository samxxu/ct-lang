#!/usr/bin/env bash
# PH-84 S84b probe: the `match` statement's accepted forms.
#
# `match` is a statement (no expression form in this phase): the branches name a
# variant with its bindings, there is no fallthrough, and the wildcard `_` is an
# explicitly written fallback. Exhaustiveness and the `--types` lint for an
# unnecessary `_` are pinned here; the rejection half lives in p84_errors.sh.
#
# Usage: bash test/ast/p84_match.sh <ct-ast>
#   E84-3 (a full variant list passes)
#   E84-4 (`_` is written out; the lint names an unnecessary one)
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: p84_match.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p84mat.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p84match: $1" >&2; }
dump() { sed 's/^/    /' "$tmp/o" >&2; }

ok_check() {
    label=$1
    f=$2
    shift 2
    if "$CT" check "$@" "$f" >"$tmp/o" 2>&1; then
        ok
    else
        bad "$label: expected a clean check"
        dump
    fi
}

# ---- the exhaustive form ----------------------------------------------------
cat >"$tmp/full.ct" <<'CT'
enum Shape {
    Circle(int r),
    Rect(int w, int h),
}

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}

int main(void)
{
    return area(Shape.Circle(2));
}
CT
ok_check "an exhaustive match passes" "$tmp/full.ct"

# the arms may be written in any order; the last one is still the fallback
cat >"$tmp/order.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        Shape.Rect(w, h) => { return w * h; }
        Shape.Circle(r) => { return 3 * r * r; }
    }
}

int main(void)
{
    return area(Shape.Rect(2, 3));
}
CT
ok_check "the arm order is free" "$tmp/order.ct"

# a pointer subject reaches the same variants
cat >"$tmp/ptr.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape *s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}

int main(void)
{
    Shape s = Shape.Circle(2);
    return area(&s);
}
CT
ok_check "a pointer subject matches" "$tmp/ptr.ct"

# zero-field variants take an empty binding list
cat >"$tmp/unit.ct" <<'CT'
enum Flag { Off(), On(int level) }

int value(Flag f)
{
    match (f) {
        Flag.Off() => { return 0; }
        Flag.On(n) => { return n; }
    }
}

int main(void)
{
    return value(Flag.Off());
}
CT
ok_check "a zero-field variant arm parses" "$tmp/unit.ct"

# a wildcard is an explicit fallback; it may cover the remaining variants
cat >"$tmp/wild.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h), Line(int n) }

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        _ => { return 0; }
    }
}

int main(void)
{
    return area(Shape.Line(1));
}
CT
ok_check "an explicit wildcard covers the rest" "$tmp/wild.ct"

# nested matches, and a match inside a loop keep working
cat >"$tmp/nested.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }
enum Wrap { One(Shape s), None() }

int area(Wrap w)
{
    match (w) {
        Wrap.One(s) => {
            match (s) {
                Shape.Circle(r) => { return 3 * r * r; }
                Shape.Rect(a, b) => { return a * b; }
            }
        }
        Wrap.None() => { return 0; }
    }
}

int main(void)
{
    return area(Wrap.One(Shape.Rect(2, 3)));
}
CT
ok_check "a nested match passes" "$tmp/nested.ct"

cat >"$tmp/loop.ct" <<'CT'
enum E { A(int n), B(char *s) }

int count(E e)
{
    int total = 0;
    int i;
    for (i = 0; i < 3; i++) {
        match (e) {
            E.A(n) => { if (n == 1) { break; } total = total + n; }
            E.B(s) => { total = total + 10; }
        }
    }
    return total;
}

int main(void)
{
    return count(E.A(1));
}
CT
ok_check "break inside an arm keeps the loop's meaning" "$tmp/loop.ct"

# `match` stays an ordinary identifier: only `match (...) {` is the statement
cat >"$tmp/name.ct" <<'CT'
int match(int x)
{
    return x + 1;
}

int main(void)
{
    int n = match(1);
    match(2);
    return n;
}
CT
ok_check "'match' is still usable as a function name" "$tmp/name.ct"

# ---- the `--types` lint (R84-2) --------------------------------------------
cat >"$tmp/redundant.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
        _ => { return 0; }
    }
}

int main(void)
{
    return area(Shape.Circle(2));
}
CT
if "$CT" check "$tmp/redundant.ct" >"$tmp/o" 2>&1; then
    ok
else
    bad "a redundant '_' is only a --types lint, not a plain-check error"
    dump
fi
if "$CT" check --types "$tmp/redundant.ct" >"$tmp/o" 2>&1; then
    bad "ct check --types did not lint the unnecessary '_'"
elif ! grep -qF "match covers every variant of 'Shape'; the wildcard arm is unnecessary" "$tmp/o"; then
    bad "the redundant wildcard lint has the wrong text"
    dump
elif ! grep -qE ':[0-9]+:[0-9]+: (error|warning):' "$tmp/o"; then
    bad "the redundant wildcard lint is not positioned"
    dump
else
    ok
fi

echo "p84match: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK p84match"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
