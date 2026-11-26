#!/usr/bin/env bash
# v1-PH-2 S6 probe: generic ADTs (`enum Opt<T> { Some(T v), None() }`).
#
# The positive fixtures live under test/ast/308..312; this probe pins the
# rejection half and the *instance* identity promises the fixtures cannot see
# from their stdout:
#   - two `Opt<int>` spellings are one layout (one `struct Opt_int {`), while
#     `Opt<char *>` is a second one;
#   - a bare generic ADT in a type position, a wrong arity, `void` as a type
#     argument, a recursive-by-value instance, a generic C enum and a name that
#     already belongs to a built-in generic struct are all refused;
#   - boxing / vector storage of an instance builds and runs (the fixtures cover
#     the behaviour; this probe only needs the compile to succeed).
#
# Usage: bash test/ast/p86_adt_generic.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: p86_adt_generic.sh <ct-ast>}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p86adtg.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p86adtg: $1" >&2; }
dump() { sed 's/^/    /' "$tmp/o" >&2; }

# compile <label> <file>: the source must produce C.
compile_ok() {
    label=$1
    f=$2
    if "$CT" "$f" -o "$tmp/$label.c" >"$tmp/o" 2>&1; then
        ok
    else
        bad "$label: expected a clean compile"
        dump
    fi
}

# bad_case <label> <file> <needle>
bad_case() {
    label=$1
    f=$2
    needle=$3
    if "$CT" "$f" -o "$tmp/$label.c" >"$tmp/o" 2>&1; then
        bad "$label: expected a diagnostic"
    elif ! grep -qF -- "$needle" "$tmp/o"; then
        bad "$label: missing '$needle'"
        dump
    else
        ok
    fi
}

# ---- an instance is one layout ---------------------------------------------
cat >"$tmp/dedup.ct" <<'CT'
enum Opt<T> {
    Some(T v),
    None(),
}

int main(void)
{
    Opt<int> a = Opt<int>.Some(1);
    Opt<int> b = Opt<int>.Some(2);
    Opt<char *> c = Opt<char *>.Some("x");
    Opt<int> d = Opt<int>.None();
    match (a) {
        Opt.Some(x) => { if (x != 1) return 1; }
        Opt.None() => { return 1; }
    }
    match (b) {
        Opt.Some(x) => { if (x != 2) return 1; }
        Opt.None() => { return 1; }
    }
    match (d) {
        Opt.Some(x) => { return 1; }
        Opt.None() => { }
    }
    (void)c;
    return 0;
}
CT
compile_ok dedup "$tmp/dedup.ct"
n_int=$(grep -c '^struct Opt_int {' "$tmp/dedup.c" 2>/dev/null || true)
n_str=$(grep -c '^struct Opt_char_p {' "$tmp/dedup.c" 2>/dev/null || true)
if [ "${n_int:-0}" -ne 1 ] || [ "${n_str:-0}" -ne 1 ]; then
    bad "dedup: expected one layout per instance (Opt_int=$n_int Opt_char_p=$n_str)"
else
    ok
fi

# ---- boxing / vector storage of an instance --------------------------------
cat >"$tmp/containers.ct" <<'CT'
enum Opt<T> {
    Some(T v),
    None(),
}

int main(void)
{
    Vec<Opt<int>> v;
    v.h = 0;
    v.push(Opt<int>.Some(1));
    Box<Opt<int>> b = Box<Opt<int>>::of(v.get(0));
    b.release();
    (void)v.release();
    return 0;
}
CT
compile_ok containers "$tmp/containers.ct"

# ---- a bare generic ADT in a type position --------------------------------
cat >"$tmp/bare.ct" <<'CT'
enum Opt<T> {
    Some(T v),
    None(),
}

int main(void)
{
    Opt o;
    (void)o;
    return 0;
}
CT
bad_case bare "$tmp/bare.ct" "generic ADT 'Opt' needs type arguments in a type position"

# ---- wrong arity -----------------------------------------------------------
cat >"$tmp/arity.ct" <<'CT'
enum Opt<T> {
    Some(T v),
    None(),
}

int main(void)
{
    Opt<int, int> o = Opt<int, int>.Some(1);
    (void)o;
    return 0;
}
CT
bad_case arity "$tmp/arity.ct" "generic ADT 'Opt' takes 1 type arguments, 2 given"

# ---- `void` cannot be a type argument -------------------------------------
cat >"$tmp/voidarg.ct" <<'CT'
enum Opt<T> {
    Some(T v),
    None(),
}

int main(void)
{
    Opt<void> o;
    (void)o;
    return 0;
}
CT
bad_case voidarg "$tmp/voidarg.ct" "type argument 'void' cannot instantiate a generic struct"

# ---- recursion by value is not a layout ------------------------------------
cat >"$tmp/recursive.ct" <<'CT'
enum List<T> {
    Cons(T v, List<T> next),
    Nil(),
}

int main(void)
{
    List<int> l = List<int>.Nil();
    (void)l;
    return 0;
}
CT
bad_case recursive "$tmp/recursive.ct" "recursive by value"

# ---- a generic C enum keeps the L34-3 rejection ---------------------------
cat >"$tmp/genericenum.ct" <<'CT'
enum Color<T> {
    Red,
    Green,
}

int main(void)
{
    return 0;
}
CT
bad_case genericenum "$tmp/genericenum.ct" "generic enums are not supported"

# ---- a built-in generic struct already owns `Option` ---------------------
cat >"$tmp/collision.ct" <<'CT'
enum Option<T> {
    Some(T v),
    None(),
}

int main(void)
{
    return 0;
}
CT
bad_case collision "$tmp/collision.ct" \
    "generic ADT 'Option' conflicts with an existing generic type of the same name"

echo "p86adtg: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
