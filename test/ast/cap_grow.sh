#!/bin/sh
# S1a-0 C1: parser / emitter / layout counting caps grow past their old
# fixed limits. Each case builds a source whose count is over the old cap,
# compiles it with ct-ast, builds the generated C with the host cc and runs it.
#
# Usage: sh test/ast/cap_grow.sh <ct-ast>
set -u
ct=${1:?usage: cap_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/capgrow.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}
fail=0

# run_case <name> <source> [expected exit]
run_case()
{
    name=$1
    src=$2
    want=${3:-0}
    if ! "$ct" "$src" -o "$w/$name.c" >"$w/$name.log" 2>&1; then
        echo "FAIL $name: ct-ast rejected the source: $(tail -1 "$w/$name.log")"
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$w/$name.c" -o "$w/$name.bin" \
            >"$w/$name.cc.log" 2>&1; then
        echo "FAIL $name: generated C did not build: $(tail -1 "$w/$name.cc.log")"
        return 1
    fi
    "$w/$name.bin"
    got=$?
    if [ "$got" -ne "$want" ]; then
        echo "FAIL $name: program returned $got (want $want)"
        return 1
    fi
    echo "ok   $name"
}

# MAX_CALLS: 9000 calls in one function (old cap 8192).
{
    echo 'int f(int x) { return x; }'
    echo 'int main(void)'
    echo '{'
    i=0
    while [ "$i" -lt 9000 ]; do
        echo "    f($i);"
        i=$((i + 1))
    done
    echo '    return 0;'
    echo '}'
} >"$w/calls.ct"
run_case calls "$w/calls.ct" 0 || fail=1

# MAX_LABELS: 100 labels and 100 gotos in one function (old cap 64 each).
{
    echo 'int main(void)'
    echo '{'
    echo '    int x = 0;'
    echo '    goto L0;'
    i=100
    echo "L$i: return x == 100 ? 0 : 1;"
    i=0
    while [ "$i" -lt 100 ]; do
        echo "L$i: x++; goto L$((i + 1));"
        i=$((i + 1))
    done
} >"$w/labels.ct"
echo '}' >>"$w/labels.ct"
run_case labels "$w/labels.ct" 0 || fail=1

# MAX_PARAMS: 100 parameters in one function and 100 arguments at the call
# (old cap 16). The function table row and the call argument frame both grow.
{
    printf 'int f(int a0'
    i=1
    while [ "$i" -lt 100 ]; do printf ', int a%d' "$i"; i=$((i + 1)); done
    printf ')\n{\n    return a0;\n}\n'
    printf 'int main(void)\n{\n    return f('
    i=0
    while [ "$i" -lt 100 ]; do
        if [ "$i" -gt 0 ]; then printf ', '; fi
        printf '%d' "$i"
        i=$((i + 1))
    done
    printf ') == 0 ? 0 : 1;\n}\n'
} >"$w/params.ct"
run_case params "$w/params.ct" 0 || fail=1

# MAX_PARAMS also covers a trait method's signature (MethodSig ptype/pann) and
# the map/emitter path that reads it: 20 parameters on one trait method.
{
    echo 'trait Big {'
    printf '    int f(int a0'
    i=1
    while [ "$i" -lt 20 ]; do printf ', int a%d' "$i"; i=$((i + 1)); done
    printf ');\n}\n'
    echo 'struct S { int x; } use Big;'
    echo 'impl Big for S {'
    printf '    int f(int a0'
    i=1
    while [ "$i" -lt 20 ]; do printf ', int a%d' "$i"; i=$((i + 1)); done
    printf ')\n    {\n        return a19;\n    }\n}\n'
    printf 'int main(void)\n{\n    struct S s = { .x = 0 };\n    return s.f('
    i=0
    while [ "$i" -lt 20 ]; do
        if [ "$i" -gt 0 ]; then printf ', '; fi
        printf '%d' "$i"
        i=$((i + 1))
    done
    printf ') == 19 ? 0 : 1;\n}\n'
} >"$w/method_params.ct"
run_case method_params "$w/method_params.ct" 0 || fail=1

# MAX_ARG_POS: a variadic call with 40 arguments (old position-table cap 32).
# The old code silently stopped recording positions past 32; now every
# argument keeps its own position.
{
    echo 'int vf(int n, ...)'
    echo '{'
    echo '    return n;'
    echo '}'
    echo 'int main(void)'
    echo '{'
    printf '    return vf(0'
    i=1
    while [ "$i" -lt 40 ]; do printf ', %d' "$i"; i=$((i + 1)); done
    printf ');\n}\n'
} >"$w/arg_pos.ct"
run_case arg_pos "$w/arg_pos.ct" 0 || fail=1

# MAX_METH_ANN: 300 inherent methods, each recorded in the ref/out
# annotation table (old cap 256).
{
    echo 'struct S { int x; };'
    echo 'impl S {'
    i=0
    while [ "$i" -lt 300 ]; do
        echo "    int m$i(int x) { return x; }"
        i=$((i + 1))
    done
    echo '}'
    echo 'int main(void) { return 0; }'
} >"$w/meth_ann.ct"
run_case meth_ann "$w/meth_ann.ct" 0 || fail=1

# MAX_LAYOUT_INSTS: 130 generic instances, plus an ADT payload that names the
# last one by value, so the layout walk reaches index 129 (old bound 128).
# MAX_LAYOUT_ADTS itself is shadowed by the C-class MAX_ADTS=64 (not opened in
# C1); the state array grows anyway.
{
    i=0
    while [ "$i" -lt 60 ]; do
        echo "enum E$i {"
        echo '    A(int x),'
        echo '    B(),'
        echo '}'
        i=$((i + 1))
    done
    echo 'struct G<T> { T x; };'
    i=0
    while [ "$i" -lt 130 ]; do
        echo "struct B$i { int v; };"
        i=$((i + 1))
    done
    echo 'enum Holder {'
    echo '    H(G<B129> g),'
    echo '    Null(),'
    echo '}'
    echo 'struct All {'
    i=0
    while [ "$i" -lt 130 ]; do
        echo "    G<B$i> f$i;"
        i=$((i + 1))
    done
    echo '};'
    echo 'int main(void) { return 0; }'
} >"$w/layout.ct"
run_case layout "$w/layout.ct" 0 || fail=1

# MAX_HOISTS: a six-level custom-subscript chain (five hoisted receivers; old
# cap 4). Each level is a `Ref_get` call whose receiver must be materialised.
{
    echo 'struct Ref { int n; }'
    echo 'impl Ref {'
    echo '    Ref get(int k) { struct Ref r; r.n = self->n + k; return r; }'
    echo '}'
    echo 'int main(void)'
    echo '{'
    echo '    struct Ref doc;'
    echo '    doc.n = 1;'
    echo '    struct Ref b = doc[1][1][1][1][1][1];'
    echo '    return b.n == 7 ? 0 : 1;'
    echo '}'
} >"$w/hoists.ct"
run_case hoists "$w/hoists.ct" 0 || fail=1

# MAX_INTOS: five chained `into` blocks in one statement (old cap 4).
{
    echo 'struct R { int n; }'
    echo 'int main(void)'
    echo '{'
    echo '    struct R r;'
    echo '    r.n = 0;'
    echo '    r into { .n = 1; } into { .n = 2; } into { .n = 3; } into { .n = 4; } into { .n = 5; };'
    echo '    return r.n == 5 ? 0 : 1;'
    echo '}'
} >"$w/intos.ct"
run_case intos "$w/intos.ct" 0 || fail=1

# ---------------------------------------------------------------------------
# S1a-0 C1: the module tables. A multi-unit build is the only way to exercise
# the import graph, so these three cases go through `ct build` (it composes
# and runs the host `cc` line) instead of the single-file `run_case` above.
# ---------------------------------------------------------------------------
export CC="${CC:-cc}"

run_build()
{
    name=$1
    src=$2
    shift 2
    if ! "$ct" build "$src" --outdir "$w/$name.gen" -o "$w/$name.bin" "$@" \
            >"$w/$name.out" 2>"$w/$name.err"; then
        echo "FAIL $name: ct-ast build rejected the source: $(tail -1 "$w/$name.err")"
        return 1
    fi
    "$w/$name.bin"
    got=$?
    if [ "$got" -ne 0 ]; then
        echo "FAIL $name: program returned $got (want 0)"
        return 1
    fi
    echo "ok   $name"
}

# MAX_IMPORTS: one unit imports 40 header units (old cap 32).
mkdir -p "$w/imports.src"
i=0
while [ "$i" -lt 40 ]; do
    printf 'pub int u%s(void) { return %s; }\n' "$i" "$i" \
        >"$w/imports.src/u$i.h.ct"
    i=$((i + 1))
done
{
    i=0
    while [ "$i" -lt 40 ]; do
        echo "import u$i;"
        i=$((i + 1))
    done
    echo 'int main(void) { return u39() == 39 ? 0 : 1; }'
} >"$w/imports.src/main.ct"
run_build imports "$w/imports.src/main.ct" || fail=1

# MAX_UNITS: a 70-unit import chain (old cap 64). Each unit has one import, so
# this fails on the unit table, not on MAX_IMPORTS.
mkdir -p "$w/units.src"
i=0
while [ "$i" -lt 70 ]; do
    if [ "$i" -eq 0 ]; then
        echo 'pub int f0(void) { return 0; }' >"$w/units.src/m0.h.ct"
    else
        p=$((i - 1))
        {
            echo "import m$p;"
            echo "pub int f$i(void) { return f$p() + 1; }"
        } >"$w/units.src/m$i.h.ct"
    fi
    i=$((i + 1))
done
{
    echo 'import m69;'
    echo 'int main(void) { return f69() == 69 ? 0 : 1; }'
} >"$w/units.src/main.ct"
run_build units "$w/units.src/main.ct" || fail=1

# MAX_INCDIRS: 20 `-I` roots (old cap 16). The roots are never read, so the
# case isolates the option table.
mkdir -p "$w/incdirs.src"
echo 'int main(void) { return 0; }' >"$w/incdirs.src/main.ct"
incs=
i=0
while [ "$i" -lt 20 ]; do
    mkdir -p "$w/incdirs.src/d$i"
    incs="$incs -I $w/incdirs.src/d$i"
    i=$((i + 1))
done
# shellcheck disable=SC2086
run_build incdirs "$w/incdirs.src/main.ct" $incs || fail=1

[ "$fail" -eq 0 ] || exit 1
echo "OK S1a-0 cap growth"
