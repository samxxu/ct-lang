#!/usr/bin/env bash
# v1-PH-2 S6 probe: generic ADTs (`enum Opt<T> { Some(T v), None() }`).
#
# The positive fixtures live under test/ast/308..314 (and the cross-unit case
# under test/modules/s6b_shadow); this probe pins the rejection half, the
# *instance* identity, and the S6b shadowing rule the fixtures cannot see from
# their stdout:
#   - two `Opt<int>` spellings are one layout (one `struct Opt_int {`), while
#     `Opt<char *>` is a second one;
#   - a bare generic ADT in a type position, a wrong arity, `void` as a type
#     argument, a recursive-by-value instance and a generic C enum are refused;
#   - `enum Option<T>` / `enum Result<T, E>` shadow the built-in generic
#     structs in their unit (`ct_adt_*` tags, built-in `Option_int` untouched),
#     while `enum Vec<T>` and the other built-ins stay a hard conflict;
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

# ---- `Option` / `Result` shadow the built-in generic structs --------------
# v1-PH-2 S6b: a unit's own `enum Option<T>` / `enum Result<T, E>` wins over
# the built-in layer for every spelling in that unit, and its C tag is the
# compiler-generated `ct_adt_*` spelling the built-in `Option_int` cannot
# collide with.
cat >"$tmp/shadow.ct" <<'CT'
enum Option<T> {
    Some(T v),
    None(),
}

enum Result<T, E> {
    Ok(T v),
    Err(E e),
}

int main(void)
{
    Option<int> a = Option<int>.Some(1);
    Option<int> b = Option<int>.None();
    Result<int, char *> r = Result<int, char *>.Err("x");
    match (a) {
        Option.Some(v) => { if (v != 1) return 1; }
        Option.None() => { return 1; }
    }
    match (b) {
        Option.Some(v) => { return 1; }
        Option.None() => { }
    }
    match (r) {
        Result.Ok(v) => { return 1; }
        Result.Err(e) => { }
    }
    return 0;
}
CT
compile_ok shadow_option "$tmp/shadow.ct"
n_adtopt=$(grep -c '^struct ct_adt_Option_int {' "$tmp/shadow_option.c" 2>/dev/null || true)
n_adtres=$(grep -c '^struct ct_adt_Result_int_char_p {' "$tmp/shadow_option.c" 2>/dev/null || true)
n_bopt=$(grep -c '^struct Option_int {' "$tmp/shadow_option.c" 2>/dev/null || true)
n_bres=$(grep -c '^struct Result_int_char_p {' "$tmp/shadow_option.c" 2>/dev/null || true)
if [ "${n_adtopt:-0}" -eq 1 ] && [ "${n_adtres:-0}" -eq 1 ] \
   && [ "${n_bopt:-0}" -eq 0 ] && [ "${n_bres:-0}" -eq 0 ]; then
    ok
else
    bad "shadow_option tags: expected ct_adt_* layouts only (Option=$n_adtopt Result=$n_adtres builtin-opt=$n_bopt builtin-res=$n_bres)"
fi

# ---- a unit without the declaration keeps the built-in layouts ------------
cat >"$tmp/builtin.ct" <<'CT'
int main(void)
{
    Option<int> a = { 1, 3 };
    Result<int, char *> r = { 1, 4, 0 };
    return a.unwrap() + r.unwrap();
}
CT
compile_ok builtin_unchanged "$tmp/builtin.ct"
n_bopt=$(grep -c '^struct Option_int {' "$tmp/builtin_unchanged.c" 2>/dev/null || true)
n_bres=$(grep -c '^struct Result_int_char_p {' "$tmp/builtin_unchanged.c" 2>/dev/null || true)
if [ "${n_bopt:-0}" -eq 1 ] && [ "${n_bres:-0}" -eq 1 ]; then
    ok
else
    bad "builtin_unchanged: the built-in layouts changed (Option=$n_bopt Result=$n_bres)"
fi

# ---- `?` still reads the built-in Result only -----------------------------
cat >"$tmp/qshadow.ct" <<'CT'
enum Result<T, E> {
    Ok(T v),
    Err(E e),
}

Result<int, char *> f(void)
{
    return Result<int, char *>.Ok(1);
}

int main(void)
{
    Result<int, char *> r = f();
    Result<int, char *> s = r?;
    (void)s;
    return 0;
}
CT
bad_case qshadow "$tmp/qshadow.ct" "'?' needs a Result operand"

# ---- only Option / Result are shadowable; another built-in stays a conflict
cat >"$tmp/vecshadow.ct" <<'CT'
enum Vec<T> {
    V(T v),
}

int main(void)
{
    return 0;
}
CT
bad_case vecshadow "$tmp/vecshadow.ct" \
    "generic ADT 'Vec' conflicts with an existing generic type of the same name"

echo "p86adtg: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
