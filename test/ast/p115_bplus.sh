#!/bin/sh
# SH-115: B+ type-check strengthening, and the CLI `--check-level` default.
#
# What this probe pins:
#   1) `ct build` defaults to `--check-level=warn`: a B finding is a warning,
#      the build still writes its products, and `--check-level=off` stays a
#      silent escape hatch whose products are byte-identical to the default.
#   2) a call through a function-pointer *field* (`o.add(...)`) is judged
#      against the field's prototype -- the residual path LANG-19 left open.
#   3) a struct brace initializer is judged item by item when the item is one
#      literal (`struct P p = { .x = "s" }`), at local and file scope.
#   4) shapes that already worked stay pinned: ADT payload, `match` binding,
#      generic-instance field write, and const/volatile normalization.
#   5) `ct check --types` and `ct build --check-level=warn` report the same
#      finding in the same words, at the same position.
#
# The two decision-blocked SH-60 sub-items (literal/const receiver mutability,
# unknown parameter type at the declaration point) are NOT asserted here: they
# need D-60-1 / D-60-2 and are out of this batch.
#
# Usage: sh test/ast/p115_bplus.sh <ct-ast>
set -u
CT=${1:?usage: p115_bplus.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p115b.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
pass=0
fail=0
export CT_C_BOUNDARY=allow
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p115: $1" >&2; }

# build <tag> <outdir> <src> [level] -- --level omitted means "use the default"
build() {
    tag=$1; dir=$2; src=$3; lvl=${4:-}
    mkdir -p "$dir"
    if [ -n "$lvl" ]; then
        "$CT" build --emit-c "--check-level=$lvl" "$src" -o "$dir" \
            >"$tmp/$tag.out" 2>"$tmp/$tag.err"
    else
        "$CT" build --emit-c "$src" -o "$dir" >"$tmp/$tag.out" 2>"$tmp/$tag.err"
    fi
    echo $? >"$tmp/$tag.rc"
}
# check <tag> <src> -- `ct check --types`
check() {
    tag=$1; src=$2
    "$CT" check --types "$src" >"$tmp/$tag.out" 2>"$tmp/$tag.err"
    echo $? >"$tmp/$tag.rc"
}
rc_is()    { [ "$(cat "$tmp/$1.rc")" = "$2" ]; }
has()      { grep -q "$2" "$tmp/$1.err"; }
hasnt()    { ! grep -q "$2" "$tmp/$1.err"; }
is_empty() { [ ! -s "$tmp/$1.err" ]; }

# ---- fixtures --------------------------------------------------------------
cat >"$tmp/mismatch.ct" <<'CT'
int f(void)
{
    return "x";
}

int main(void)
{
    return f() + 0;
}
CT

cat >"$tmp/fnfield.ct" <<'CT'
struct Ops {
    int (*add)(int, int);
};

int main(void)
{
    struct Ops o;
    o.add = 0;
    return o.add(1, "x");
}
CT

cat >"$tmp/fnfield_pos.ct" <<'CT'
struct Ops {
    int (*add)(int, int);
};

int main(void)
{
    struct Ops o;
    o.add = 0;
    return o.add(1, 2);
}
CT

cat >"$tmp/fnfield_arity.ct" <<'CT'
struct Ops {
    int (*add)(int, int);
};

int main(void)
{
    struct Ops o;
    o.add = 0;
    return o.add(1);
}
CT

cat >"$tmp/ptr_expr.ct" <<'CT'
struct Ops {
    int (*add)(int, int);
};

int main(void)
{
    struct Ops o;
    int (*p)(int, int) = o.add;
    o.add = 0;
    return (*p)(1, "x");
}
CT

cat >"$tmp/brace_local.ct" <<'CT'
struct P {
    int x;
    char *s;
};

int main(void)
{
    struct P p = { .x = "bad", .s = "ok" };
    return p.x;
}
CT

cat >"$tmp/brace_pos.ct" <<'CT'
struct P { int x; char *s; };

int main(void)
{
    struct P p = { "bad", "ok" };
    return p.x;
}
CT

cat >"$tmp/brace_global.ct" <<'CT'
struct P {
    int x;
};

struct P g = { .x = "bad" };

int main(void)
{
    return g.x;
}
CT

cat >"$tmp/brace_generic.ct" <<'CT'
struct Box<T> {
    T v;
}

int main(void)
{
    Box<int> b = { .v = "bad" };
    return b.v;
}
CT

cat >"$tmp/brace_ok.ct" <<'CT'
struct P {
    int x;
    char *s;
};

int main(void)
{
    struct P p = { .x = 1, .s = "ok" };
    return p.x;
}
CT

cat >"$tmp/adt.ct" <<'CT'
enum Shape {
    Circle(int r),
}

int main(void)
{
    Shape s = Shape.Circle("x");
    return 0;
}
CT

cat >"$tmp/adt_match.ct" <<'CT'
enum Shape { Circle(int r), Named(char *n) }

int f(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return r; }
        Shape.Named(n) => { return n; }
    }
}

int main(void)
{
    return f(Shape.Circle(2));
}
CT

cat >"$tmp/generic_assign.ct" <<'CT'
struct Box<T> {
    T v;
}

int main(void)
{
    Box<int> b;
    b.v = "s";
    return b.v;
}
CT

cat >"$tmp/const_ok.ct" <<'CT'
int f(const char *s)
{
    return s ? 1 : 0;
}

struct C {
    const char *s;
    volatile int n;
};

int main(void)
{
    char *p = "x";
    struct C c = { .s = "x", .n = 1 };
    return f(p) + (c.s != 0);
}
CT

# ---- 1) default warn, off escape, unchanged products -----------------------
build d0 "$tmp/d0" "$tmp/mismatch.ct"
build off "$tmp/off" "$tmp/mismatch.ct" off
build err "$tmp/err" "$tmp/mismatch.ct" error
build chk "$tmp/chk" "$tmp/mismatch.ct" error
check types "$tmp/mismatch.ct"

if rc_is d0 0 && has d0 "warning: return: expected 'int', got 'char \*'" \
   && [ -f "$tmp/d0/mismatch.c" ]; then
    ok; echo "  p115: default build reports a B warning and writes the product"
else
    bad "default build did not warn-and-continue: rc=$(cat "$tmp/d0.rc") $(head -3 "$tmp/d0.err" | tr '\n' ' ')"
fi
if rc_is off 0 && is_empty off; then
    ok; echo "  p115: --check-level=off is the silent escape hatch"
else
    bad "--check-level=off did not stay silent: rc=$(cat "$tmp/off.rc") $(head -3 "$tmp/off.err" | tr '\n' ' ')"
fi
if [ -f "$tmp/d0/mismatch.c" ] && [ -f "$tmp/off/mismatch.c" ] \
   && cmp -s "$tmp/d0/mismatch.c" "$tmp/off/mismatch.c"; then
    ok; echo "  p115: default warn emits the same C as off"
else
    bad "default warn changed the generated C"
fi
if [ "$(cat "$tmp/err.rc")" != "0" ] && has err "error: return: expected 'int', got 'char \*'" \
   && [ ! -f "$tmp/err/mismatch.c" ]; then
    ok; echo "  p115: --check-level=error fails before writing a product"
else
    bad "--check-level=error did not fail before the product"
fi
if [ "$(cat "$tmp/types.rc")" != "0" ] && has types "error: return: expected 'int', got 'char \*'"; then
    ok; echo "  p115: ct check --types keeps the A error"
else
    bad "ct check --types changed: rc=$(cat "$tmp/types.rc") $(head -2 "$tmp/types.err" | tr '\n' ' ')"
fi

# ---- 2) function-pointer field call ----------------------------------------
check fnfield_c "$tmp/fnfield.ct"
build fnfield_b "$tmp/fnfield_b" "$tmp/fnfield.ct"
build fnfield_o "$tmp/fnfield_o" "$tmp/fnfield.ct" off
check fnfield_pos_c "$tmp/fnfield_pos.ct"
check fnfield_arity_c "$tmp/fnfield_arity.ct"
check ptr_expr_c "$tmp/ptr_expr.ct"

if [ "$(cat "$tmp/fnfield_c.rc")" != "0" ] \
   && has fnfield_c ":9:21: error: argument 2: expected 'int', got 'char \*'"; then
    ok; echo "  p115: check --types judges a function-pointer field call"
else
    bad "fnptr field call not judged by check: rc=$(cat "$tmp/fnfield_c.rc") $(head -2 "$tmp/fnfield_c.err" | tr '\n' ' ')"
fi
if rc_is fnfield_b 0 && has fnfield_b ":9:21: warning: argument 2: expected 'int', got 'char \*'"; then
    ok; echo "  p115: build warn reports the same fnptr finding as a warning"
else
    bad "fnptr field not a build warning: rc=$(cat "$tmp/fnfield_b.rc") $(head -2 "$tmp/fnfield_b.err" | tr '\n' ' ')"
fi
if rc_is fnfield_o 0 && hasnt fnfield_o "argument 1"; then
    ok; echo "  p115: fnptr field check is silent at off"
else
    bad "fnptr field check leaked into off"
fi
if rc_is fnfield_pos_c 0 && is_empty fnfield_pos_c; then
    ok; echo "  p115: a legal fnptr field call stays silent"
else
    bad "a legal fnptr field call was diagnosed: $(head -2 "$tmp/fnfield_pos_c.err" | tr '\n' ' ')"
fi
if [ "$(cat "$tmp/fnfield_arity_c.rc")" != "0" ] \
   && has fnfield_arity_c "arity mismatch: 'add' takes more arguments, 1 given"; then
    ok; echo "  p115: fnptr field arity is judged too"
else
    bad "fnptr field arity not judged: $(head -2 "$tmp/fnfield_arity_c.err" | tr '\n' ' ')"
fi
if [ "$(cat "$tmp/ptr_expr_c.rc")" != "0" ] \
   && has ptr_expr_c ":10:20: error: argument 2: expected 'int', got 'char \*'"; then
    ok; echo "  p115: a pointer-expression callee (*p)(...) is judged"
else
    bad "pointer-expression call not judged: rc=$(cat "$tmp/ptr_expr_c.rc") $(head -2 "$tmp/ptr_expr_c.err" | tr '\n' ' ')"
fi

# ---- 3) struct brace initializer -------------------------------------------
check brace_c "$tmp/brace_local.ct"
build brace_b "$tmp/brace_b" "$tmp/brace_local.ct"
build brace_o "$tmp/brace_o" "$tmp/brace_local.ct" off
check brace_pos_c "$tmp/brace_pos.ct"
check brace_global_c "$tmp/brace_global.ct"
check brace_generic_c "$tmp/brace_generic.ct"
check brace_ok_c "$tmp/brace_ok.ct"

if [ "$(cat "$tmp/brace_c.rc")" != "0" ] \
   && has brace_c ":8:20: error: initializer: expected 'int', got 'char \*'"; then
    ok; echo "  p115: check --types judges a designated brace initializer"
else
    bad "brace initializer not judged by check: rc=$(cat "$tmp/brace_c.rc") $(head -2 "$tmp/brace_c.err" | tr '\n' ' ')"
fi
if rc_is brace_b 0 && has brace_b ":8:20: warning: initializer: expected 'int', got 'char \*'"; then
    ok; echo "  p115: build warn reports the same brace finding as a warning"
else
    bad "brace initializer not a build warning: rc=$(cat "$tmp/brace_b.rc") $(head -2 "$tmp/brace_b.err" | tr '\n' ' ')"
fi
if rc_is brace_o 0 && hasnt brace_o "initializer:"; then
    ok; echo "  p115: brace initializer check is silent at off"
else
    bad "brace initializer check leaked into off"
fi
if [ "$(cat "$tmp/brace_pos_c.rc")" != "0" ] \
   && has brace_pos_c ":5:20: error: initializer: expected 'int', got 'char \*'"; then
    ok; echo "  p115: a positional brace item is judged"
else
    bad "positional brace item not judged: $(head -2 "$tmp/brace_pos_c.err" | tr '\n' ' ')"
fi
if [ "$(cat "$tmp/brace_global_c.rc")" != "0" ] \
   && has brace_global_c ":5:16: error: initializer: expected 'int', got 'char \*'"; then
    ok; echo "  p115: a file-scope brace initializer is judged"
else
    bad "global brace initializer not judged: $(head -2 "$tmp/brace_global_c.err" | tr '\n' ' ')"
fi
if [ "$(cat "$tmp/brace_generic_c.rc")" != "0" ] \
   && has brace_generic_c ":7:20: error: initializer: expected 'int', got 'char \*'"; then
    ok; echo "  p115: a generic-instance brace initializer is judged"
else
    bad "generic brace initializer not judged: $(head -2 "$tmp/brace_generic_c.err" | tr '\n' ' ')"
fi
if rc_is brace_ok_c 0 && is_empty brace_ok_c; then
    ok; echo "  p115: a legal brace initializer stays silent"
else
    bad "a legal brace initializer was diagnosed: $(head -2 "$tmp/brace_ok_c.err" | tr '\n' ' ')"
fi

# ---- 4) already-covered shapes stay covered --------------------------------
check adt_c "$tmp/adt.ct"
check adt_match_c "$tmp/adt_match.ct"
check generic_assign_c "$tmp/generic_assign.ct"
check const_ok_c "$tmp/const_ok.ct"

if [ "$(cat "$tmp/adt_c.rc")" != "0" ] \
   && has adt_c "argument 1 of 'Shape.Circle': expected 'int', got 'char \*'"; then
    ok; echo "  p115: ADT payload mismatch is still judged"
else
    bad "ADT payload mismatch regressed: $(head -2 "$tmp/adt_c.err" | tr '\n' ' ')"
fi
if [ "$(cat "$tmp/adt_match_c.rc")" != "0" ] \
   && has adt_match_c "return: expected 'int', got 'char \*'"; then
    ok; echo "  p115: match binding types are still judged"
else
    bad "match binding regressed: $(head -2 "$tmp/adt_match_c.err" | tr '\n' ' ')"
fi
if [ "$(cat "$tmp/generic_assign_c.rc")" != "0" ] \
   && has generic_assign_c "assignment: expected 'int', got 'char \*'"; then
    ok; echo "  p115: a generic-instance field write is still judged"
else
    bad "generic-instance assignment regressed: $(head -2 "$tmp/generic_assign_c.err" | tr '\n' ' ')"
fi
if rc_is const_ok_c 0 && is_empty const_ok_c; then
    ok; echo "  p115: const/volatile qualifiers stay normalized (no false positive)"
else
    bad "const/volatile normalization regressed: $(head -2 "$tmp/const_ok_c.err" | tr '\n' ' ')"
fi

echo "p115: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
