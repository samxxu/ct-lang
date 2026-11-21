#!/usr/bin/env bash
# PH-84 S84b probe (rejection half): the frozen `match` diagnostics.
#
# Exhaustiveness is the point of the construct, so every way of losing it is a
# hard error at the offending position: a missing variant without `_`, a
# duplicate arm, a variant from another ADT, a binding count that disagrees with
# the payload, a wildcard that is not last, and a subject that is not an ADT.
#
# Usage: bash test/ast/p84_errors.sh <ct-ast>
#   E84-3 (missing / duplicate / unknown branches are positioned errors)
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: p84_errors.sh <ct-ast>}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p84err.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
dump() { sed 's/^/    /' "$tmp/o" >&2; }

# bad_case <label> <file> <needle> <line|-> [check args…]
bad_case() {
    label=$1
    f=$2
    needle=$3
    line=$4
    shift 4
    if "$CT" check "$@" "$f" >"$tmp/o" 2>&1; then
        fail=$((fail + 1)); echo "FAIL p84errors: $label: expected a diagnostic" >&2
    elif ! grep -qF -- "$needle" "$tmp/o"; then
        fail=$((fail + 1)); echo "FAIL p84errors: $label: missing '$needle'" >&2; dump
    elif [ "$line" != "-" ] && ! grep -qE ":$line:[0-9]+: error:" "$tmp/o"; then
        fail=$((fail + 1)); echo "FAIL p84errors: $label: not positioned at line $line" >&2; dump
    else
        pass=$((pass + 1))
    fi
}

# ---- a missing variant (no wildcard) ---------------------------------------
cat >"$tmp/missing.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
    }
    return 0;
}
CT
# the match keyword is at 5:5
bad_case "a missing variant is an error" "$tmp/missing.ct" \
    "match does not cover variant 'Shape.Rect'" 5

# ---- a duplicate arm --------------------------------------------------------
cat >"$tmp/dup.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Circle(x) => { return x; }
        Shape.Rect(w, h) => { return w * h; }
    }
    return 0;
}
CT
bad_case "a duplicate variant arm is an error" "$tmp/dup.ct" \
    "duplicate match arm for variant 'Shape.Circle'" 7

# ---- a variant from another ADT --------------------------------------------
cat >"$tmp/other.ct" <<'CT'
enum A { X(int n) }
enum B { Y(int n) }

int f(A a)
{
    match (a) {
        B.Y(n) => { return n; }
    }
    return 0;
}
CT
bad_case "a variant of another ADT is an error" "$tmp/other.ct" \
    "match arm names ADT 'B', but the subject is 'A'" 7

# ---- an unknown variant -----------------------------------------------------
cat >"$tmp/unknown.ct" <<'CT'
enum Shape { Circle(int r) }

int area(Shape s)
{
    match (s) {
        Shape.Nope(r) => { return r; }
    }
    return 0;
}
CT
bad_case "an unknown arm variant is an error" "$tmp/unknown.ct" \
    "unknown variant 'Nope' of ADT 'Shape'" 6

# ---- a binding count that disagrees with the payload -----------------------
cat >"$tmp/arity.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        Shape.Circle(r, q) => { return r; }
        Shape.Rect(w, h) => { return w * h; }
    }
    return 0;
}
CT
bad_case "a wrong binding count is an error" "$tmp/arity.ct" \
    "match arm for 'Shape.Circle' binds 2 names, but the variant has 1 field" 6

# ---- the wildcard must be explicit and last --------------------------------
cat >"$tmp/late.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        _ => { return 0; }
        Shape.Circle(r) => { return 3 * r * r; }
    }
    return 0;
}
CT
bad_case "a wildcard before another arm is an error" "$tmp/late.ct" \
    "a wildcard match arm must be the last arm" 7

cat >"$tmp/twowild.ct" <<'CT'
enum Shape { Circle(int r), Rect(int w, int h) }

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        _ => { return 0; }
        _ => { return 1; }
    }
    return 0;
}
CT
bad_case "a second wildcard is an error" "$tmp/twowild.ct" \
    "duplicate wildcard match arm" 8

# ---- a duplicate binding ---------------------------------------------------
cat >"$tmp/dupbind.ct" <<'CT'
enum Pair { Two(int a, int b) }

int f(Pair p)
{
    match (p) {
        Pair.Two(x, x) => { return x; }
    }
    return 0;
}
CT
bad_case "a duplicate binding is an error" "$tmp/dupbind.ct" \
    "duplicate binding 'x' in a match arm" 6

# ---- a subject that is not an ADT ------------------------------------------
cat >"$tmp/nonadt.ct" <<'CT'
int f(int n)
{
    match (n) {
        _ => { return 0; }
    }
    return n;
}

int main(void)
{
    return f(1);
}
CT
bad_case "a non-ADT subject is an error" "$tmp/nonadt.ct" \
    "match needs an ADT value, but 'int' is not an ADT" 3

# ---- a pointer-to-non-ADT subject ------------------------------------------
cat >"$tmp/nonadtp.ct" <<'CT'
int f(int *n)
{
    match (n) {
        _ => { return 0; }
    }
    return *n;
}

int main(void)
{
    int v = 1;
    return f(&v);
}
CT
bad_case "a pointer to a non-ADT is an error" "$tmp/nonadtp.ct" \
    "match needs an ADT value, but 'int *' is not an ADT" 3

# ---- the alias subject reaches the ordinary missing-variant diagnostic ----
cat >"$tmp/aliasmissing.ct" <<'CT'
typedef enum Shape { Circle(int r), Rect(int w, int h) } Alias;

int area(Alias a)
{
    match (a) {
        Shape.Circle(r) => { return 3 * r * r; }
    }
    return 0;
}
CT
bad_case "an alias subject still gets the missing-variant error" "$tmp/aliasmissing.ct" \
    "match does not cover variant 'Shape.Rect'" 5

# ---- an alias of a non-ADT is not silently accepted -----------------------
cat >"$tmp/aliasint.ct" <<'CT'
typedef int Num;

int f(Num n)
{
    match (n) {
        _ => { return 0; }
    }
    return n;
}

int main(void)
{
    return f(1);
}
CT
bad_case "an alias of a non-ADT subject is an error" "$tmp/aliasint.ct" \
    "match needs an ADT value, but 'Num' is not an ADT" 5

# ---- every diagnostic is the only one (no fallback cascade) -----------------
if [ "$(grep -c 'error:' "$tmp/o")" -gt 2 ]; then
    fail=$((fail + 1)); echo "FAIL p84errors: a rejection cascaded into several errors" >&2
else
    pass=$((pass + 1))
fi

echo "p84errors: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK p84errors"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
