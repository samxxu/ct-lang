#!/bin/sh
# S1a-0 C3: the ADT registry counts grow on demand instead of stopping at the
# old fixed caps. Each case builds a source over the old cap, compiles it with
# ct-ast, builds the generated C with the host cc and runs it.
#
#   MAX_ADTS          64  -> 65 ADTs in one build
#   MAX_ADT_VARIANTS  96  -> 97 variants in one ADT
#   MAX_ADT_FIELDS     8  -> 9 payload fields (and 9 match bindings)
#
# The last two cases are the shape regressions the growth must not disturb:
# a recursive ADT read back through `match`, and an ADT whose payload holds a
# generic instance by value.
#
# Usage: sh test/ast/cap_adt.sh <ct-ast>
set -u
ct=${1:?usage: cap_adt.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/capadt.XXXXXX") || exit 1
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
        echo "FAIL $name: ct-ast rejected the source: $(grep 'error: ' "$w/$name.log" | head -1)"
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

# MAX_ADTS: 65 ADTs (old cap 64). The last one is constructed and matched, so
# the row is not just parsed: it carries a usable tag and payload.
{
    i=0
    while [ "$i" -lt 65 ]; do
        printf 'enum E%d {\n    V(int x),\n    U(),\n}\n' "$i"
        i=$((i + 1))
    done
    cat <<'EOF'
int main(void)
{
    E64 e = E64.V(7);
    match (e) {
        E64.V(x) => { return x == 7 ? 0 : 1; }
        E64.U() => { return 1; }
    }
    return 1;
}
EOF
} >"$w/many_adts.ct"
run_case many_adts "$w/many_adts.ct" 0 || fail=1

# MAX_ADT_VARIANTS: 97 variants in one ADT (old cap 96). The match covers one
# arm and falls back to `_`, so the 97-row variant block is walked end to end.
{
    echo 'enum Big {'
    i=0
    while [ "$i" -lt 97 ]; do
        printf '    V%d(int x),\n' "$i"
        i=$((i + 1))
    done
    cat <<'EOF'
}
int main(void)
{
    Big b = Big.V96(3);
    match (b) {
        Big.V96(x) => { return x == 3 ? 0 : 1; }
        _ => { return 1; }
    }
    return 1;
}
EOF
} >"$w/many_variants.ct"
run_case many_variants "$w/many_variants.ct" 0 || fail=1

# MAX_ADT_FIELDS: nine payload fields (old cap 8) with nine match bindings.
# The sum proves every field survives the payload block and the binding block.
{
    cat <<'EOF'
enum Wide {
    Nine(int a1, int a2, int a3, int a4, int a5, int a6, int a7, int a8, int a9),
}
int main(void)
{
    Wide w = Wide.Nine(1, 2, 3, 4, 5, 6, 7, 8, 9);
    match (w) {
        Wide.Nine(a1, a2, a3, a4, a5, a6, a7, a8, a9) => {
            return a1 + a2 + a3 + a4 + a5 + a6 + a7 + a8 + a9 == 45 ? 0 : 1;
        }
    }
    return 1;
}
EOF
} >"$w/wide_fields.ct"
run_case wide_fields "$w/wide_fields.ct" 0 || fail=1

# Recursive ADT (pointer payload) read back through nested `match`: growth must
# not change the tag/payload layout or the pattern lowering.
{
    cat <<'EOF'
enum Tree {
    Leaf(int v),
    Node(Tree *l, Tree *r),
}
int main(void)
{
    Tree a = Tree.Leaf(1);
    Tree b = Tree.Leaf(2);
    Tree n = Tree.Node(&a, &b);
    match (n) {
        Tree.Leaf(v) => { return 1; }
        Tree.Node(l, r) => { return (l->tag == 0 && r->tag == 0) ? 0 : 1; }
    }
    return 1;
}
EOF
} >"$w/recursive.ct"
run_case recursive "$w/recursive.ct" 0 || fail=1

# Generic instance held by value in an ADT payload: the instance shell and the
# ADT layout keep their order after the registry grows.
{
    cat <<'EOF'
enum Bag {
    Empty(),
    Items(Vec<int> v),
}
int main(void)
{
    Vec<int> v;
    Bag b;
    v.h = 0;
    v.push(5);
    b = Bag.Items(v);
    match (b) {
        Bag.Items(x) => { return x.len() == 1 ? 0 : 1; }
        Bag.Empty() => { return 1; }
    }
    return 1;
}
EOF
} >"$w/generic_payload.ct"
run_case generic_payload "$w/generic_payload.ct" 0 || fail=1

echo "cap_adt: $fail failure(s)"
[ "$fail" -eq 0 ]
