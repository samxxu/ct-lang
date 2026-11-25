#!/bin/sh
# S1a-0 C1: closures, generic instances, generic templates/impls and type
# aliases grow past their old caps.
set -u
ct=${1:?usage: table_tables_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/tables.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}

run_case()
{
    name=$1
    if ! "$ct" "$w/$name.ct" -o "$w/$name.c" >"$w/$name.log" 2>&1; then
        echo "FAIL $name: build stopped: $(tail -1 "$w/$name.log")"
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$w/$name.c" -o "$w/$name.bin" \
            >"$w/$name.cc.log" 2>&1; then
        echo "FAIL $name: generated C did not build: $(tail -1 "$w/$name.cc.log")"
        return 1
    fi
    if "$w/$name.bin"; then echo "ok   $name"; else
        echo "FAIL $name: program returned $?"
        return 1
    fi
}

# 70 closure literals (MAX_CLOSURES = 64). One per function: the emitter has
# its own per-frame binding cap, which is a separate slice.
{
    i=0
    while [ "$i" -lt 70 ]; do
        echo "int f$i(void)"
        echo '{'
        echo '    int v = 7;'
        echo '    int (*c)(void) = () => v;'
        echo '    return c();'
        echo '}'
        i=$((i + 1))
    done
    echo 'int main(void) { return f69() == 7 ? 0 : 1; }'
} >"$w/closures.ct"

# 70 generic-function instances (MAX_GENERIC_INSTS = 64)
{
    echo 'T id<T>(T x) { return x; }'
    i=0
    while [ "$i" -lt 70 ]; do
        echo "struct A$i { int v; };"
        i=$((i + 1))
    done
    echo 'int main(void)'
    echo '{'
    i=0
    while [ "$i" -lt 70 ]; do
        echo "    struct A$i a$i = { .v = $i };"
        i=$((i + 1))
    done
    i=0
    while [ "$i" -lt 70 ]; do
        echo "    id<struct A$i>(a$i);"
        i=$((i + 1))
    done
    echo '    return 0;'
    echo '}'
} >"$w/ginsts.ct"

# 70 generic struct templates (MAX_STRUCT_TPLS = 64)
{
    i=0
    while [ "$i" -lt 70 ]; do
        echo "struct G$i<T> { T x; };"
        i=$((i + 1))
    done
    echo 'int main(void) { return 0; }'
} >"$w/tmpls.ct"

# 70 generic impl blocks against 70 templates (MAX_STRUCT_IMPLS = 64)
{
    i=0
    while [ "$i" -lt 70 ]; do
        echo "struct H$i<T> { T x; };"
        echo "impl<T> H$i<T> { T get() { return self->x; } }"
        i=$((i + 1))
    done
    echo 'int main(void) { return 0; }'
} >"$w/impls.ct"

# 300 type aliases: local table (MAX_TYPE_ALIASES = 64) and the build-wide
# registry (MAX_GLOBAL_TYPE_ALIASES = 256). Aliases live in a .h.ct unit, so
# this case is a two-unit `build`.
mkdir -p "$w/aliases"
{
    i=0
    while [ "$i" -lt 300 ]; do
        echo "pub type A$i = int;"
        i=$((i + 1))
    done
} >"$w/aliases/gen.h.ct"
{
    echo 'import gen;'
    echo 'int main(void)'
    echo '{'
    echo '    A299 x = 299;'
    echo '    return x == 299 ? 0 : 1;'
    echo '}'
} >"$w/aliases/prog.ct"

# 130 generic instances of one template (MAX_STRUCT_INSTS global = 128)
{
    echo 'struct G<T> { T x; };'
    i=0
    while [ "$i" -lt 130 ]; do
        echo "struct B$i { int v; };"
        i=$((i + 1))
    done
    echo 'int main(void)'
    echo '{'
    i=0
    while [ "$i" -lt 130 ]; do
        echo "    G<struct B$i> g$i;"
        i=$((i + 1))
    done
    echo '    return 0;'
    echo '}'
} >"$w/insts.ct"

for c in closures ginsts tmpls impls insts; do
    run_case "$c" || exit 1
done

# aliases: build mode (the alias unit is a .h.ct header)
mkdir -p "$w/aliases/out"
if ! "$ct" build --emit-c -I "$w/aliases" "$w/aliases/prog.ct" -o "$w/aliases/out"         >"$w/aliases.log" 2>&1; then
    echo "FAIL aliases: build stopped: $(tail -1 "$w/aliases.log")"
    exit 1
fi
if ! "$cc" -Wall -Wextra -std=c99 -I "$w/aliases/out" "$w/aliases/out"/*.c         -o "$w/aliases.bin" >"$w/aliases.cc.log" 2>&1; then
    echo "FAIL aliases: generated C did not build: $(tail -1 "$w/aliases.cc.log")"
    exit 1
fi
if "$w/aliases.bin"; then echo "ok   aliases"; else
    echo "FAIL aliases: program returned $?"
    exit 1
fi
