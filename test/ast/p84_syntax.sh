#!/usr/bin/env bash
# PH-84 S84a probe: the syntax and type contract of a minimal ADT.
#
# A payload-bearing `enum` is an ADT (D84-1): it parses as a named sum type, its
# tag is usable in every type position, `Type.Variant(args)` builds one variant
# with typed payloads, and the two forms never mix. The C-enum form must not
# move: the probe compiles and runs the existing enum fixture and checks the
# generated C is still an `enum`.
#
# Usage: bash test/ast/p84_syntax.sh <ct-ast>
#   E84-1 (payload enum is an ADT; the C enum stays a C enum)
#   E84-2 (construction typed; arity / type mismatch is a hard error)
set -u
# the C-enum invariants compile a fixture that carries #include lines
export CT_C_BOUNDARY=allow
CT=${1:?usage: p84_syntax.sh <ct-ast>}
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p84syn.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p84syntax: $1" >&2; }
dump() { sed 's/^/    /' "$tmp/o" >&2; }

# ok_check <label> <file> [check args…]
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

# bad_check <label> <file> <needle> <line|-> [check args…]
bad_check() {
    label=$1
    f=$2
    needle=$3
    line=$4
    shift 4
    if "$CT" check "$@" "$f" >"$tmp/o" 2>&1; then
        bad "$label: expected a diagnostic"
    elif ! grep -qF -- "$needle" "$tmp/o"; then
        bad "$label: missing '$needle'"
        dump
    elif [ "$line" != "-" ] && ! grep -qE ":$line:[0-9]+: error:" "$tmp/o"; then
        bad "$label: diagnostic is not positioned at $line"
        dump
    else
        ok
    fi
}

# ---- the accepted forms -----------------------------------------------------
cat >"$tmp/ok.ct" <<'CT'
enum Shape {
    Circle(int r),
    Rect(int w, int h),
}

Shape mk(int r)
{
    return Shape.Circle(r);
}

Shape zero(void)
{
    return Shape.Rect(0, 0);
}

int main(void)
{
    Shape s = Shape.Circle(2);
    Shape t = mk(3);
    Shape u = zero();
    Shape *p = &s;
    (void)t;
    (void)u;
    return p->tag + s.tag;
}
CT
ok_check "an ADT parses, types and constructs" "$tmp/ok.ct"
ok_check "the constructor answers 'struct Shape'" "$tmp/ok.ct" --types

# a zero-field variant is spelled with an empty payload list
cat >"$tmp/unit.ct" <<'CT'
enum Flag {
    Off(),
    Dim(int level),
}

int main(void)
{
    Flag f = Flag.Off();
    return f.tag;
}
CT
ok_check "a zero-field variant parses" "$tmp/unit.ct"
ok_check "a zero-field variant types" "$tmp/unit.ct" --types

# ---- construction is typed (E84-2) -----------------------------------------
cat >"$tmp/bad_assign.ct" <<'CT'
enum Shape { Circle(int r) }
int main(void)
{
    int n = Shape.Circle(4);
    return n;
}
CT
bad_check "the constructor answers the ADT type" "$tmp/bad_assign.ct" \
    "initializer: expected 'int', got 'struct Shape'" 4 --types

cat >"$tmp/arity0.ct" <<'CT'
enum Shape { Circle(int r) }
int main(void)
{
    Shape s = Shape.Circle();
    return 0;
}
CT
bad_check "a missing payload argument is an arity error" "$tmp/arity0.ct" \
    "'Shape.Circle' takes 1 argument, but 0 given" 4

cat >"$tmp/arity2.ct" <<'CT'
enum Shape { Circle(int r) }
int main(void)
{
    Shape s = Shape.Circle(1, 2);
    return 0;
}
CT
bad_check "an extra payload argument is an arity error" "$tmp/arity2.ct" \
    "'Shape.Circle' takes 1 argument, but 2 given" 4

cat >"$tmp/argtype.ct" <<'CT'
enum Shape { Circle(int r) }
int main(void)
{
    Shape s = Shape.Circle("x");
    return 0;
}
CT
bad_check "a payload type mismatch is a hard error" "$tmp/argtype.ct" \
    "argument 1 of 'Shape.Circle': expected 'int', got 'char *'" 4

cat >"$tmp/unknown.ct" <<'CT'
enum Shape { Circle(int r) }
int main(void)
{
    Shape s = Shape.Nope(1);
    return 0;
}
CT
bad_check "an unknown constructor variant is refused" "$tmp/unknown.ct" \
    "unknown variant 'Nope' of ADT 'Shape'" 4

# ---- the two forms never mix (D84-1 / R84-1) --------------------------------
cat >"$tmp/value.ct" <<'CT'
enum Shape { Circle(int r) = 1 }
int main(void)
{
    return 0;
}
CT
bad_check "an ADT variant cannot carry an explicit value" "$tmp/value.ct" \
    "an ADT variant cannot carry an explicit value" 1

cat >"$tmp/mixed.ct" <<'CT'
enum E { A, B(int x) }
int main(void)
{
    return 0;
}
CT
bad_check "a mixed payload / plain enum is refused" "$tmp/mixed.ct" \
    "every variant of an ADT must carry a payload list" 1

# ---- the C enum does not move (E84-1) --------------------------------------
if ! "$CT" "$root/test/ast/30_enum/prog.ct" -o "$tmp/enum.c" >"$tmp/o" 2>&1; then
    bad "the existing enum fixture no longer compiles"
    dump
elif ! grep -qE '^enum Color \{' "$tmp/enum.c"; then
    bad "a plain enum is no longer emitted as a C enum"
    grep -n 'Color' "$tmp/enum.c" | sed 's/^/    /' >&2
elif ! "$CC" -Wall -Wextra -std=c99 "$tmp/enum.c" -o "$tmp/enum.bin" >"$tmp/o" 2>&1; then
    bad "the C enum product no longer builds warning-free"
    dump
elif ! "$tmp/enum.bin" >"$tmp/enum.out" 2>&1 \
     || ! cmp -s "$tmp/enum.out" "$root/test/ast/30_enum/prog.expected.out"; then
    bad "the C enum behaviour changed: $(cat "$tmp/enum.out" 2>/dev/null)"
else
    ok
fi

echo "p84syntax: $pass passed, $fail failed"
[ "$fail" -eq 0 ] && echo "OK p84syntax"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
