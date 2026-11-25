#!/bin/sh
# S1a-0 C1: the map table and a binding's per-parameter arrays grow past their
# old fixed caps.
#
#   maps70:   70 `map trait` bindings (old MAX_MAPS = 64) are accepted, emit one
#             wrapper and one vtable each, and the boxed dispatch of the last one
#             runs.
#   params17: one map binding names 17 parameters (old MapBind.params[16],
#             `uses[16]`, `sizeofs[16]`); the wrapper takes 17 formals, the
#             recipe counts a use for the 17th, and the call returns its value.
#   mapjson:  `--emit-map` reports all 70 maps (the old table stopped at 64) and
#             names the last map's instance.
#
# Usage: sh test/ast/map_cap.sh <ct-ast>
set -u
ct=${1:?usage: map_cap.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/mapcap.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}
fail=0

bad() { printf 'FAIL %s: %s\n' "$1" "$2"; fail=1; }

run_case()
{
    name=$1
    if ! "$ct" "$w/$name.ct" -o "$w/$name.c" >"$w/$name.log" 2>&1; then
        bad "$name" "ct-ast rejected the source: $(tail -1 "$w/$name.log")"
        return 1
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$w/$name.c" -o "$w/$name.bin" \
            >"$w/$name.cc.log" 2>&1; then
        bad "$name" "generated C did not build: $(tail -1 "$w/$name.cc.log")"
        return 1
    fi
    if ! "$w/$name.bin"; then
        bad "$name" "program returned $?"
        return 1
    fi
    echo "ok   $name"
}

# --- maps70: 70 maps, one per instance (old MAX_MAPS = 64) -----------------
{
    printf 'trait Controller {\n    int send(char *buf, int len);\n}\n'
    printf 'struct Uart {\n    int fd;\n};\n'
    printf 'int mock_send(struct Uart *u, char *buf, int n) {\n'
    printf '    (void)buf;\n    return n + u->fd;\n}\n'
    i=0
    while [ "$i" -lt 70 ]; do
        printf 'struct Uart u%d;\n' "$i"
        i=$((i + 1))
    done
    i=0
    while [ "$i" -lt 70 ]; do
        printf 'map trait Controller for instance u%d {\n' "$i"
        printf '    send(buf, len) -> mock_send(&u%d, buf, len);\n}\n' "$i"
        i=$((i + 1))
    done
    printf 'int main(void)\n{\n    Controller c;\n    c = u69;\n'
    printf '    return c.send("x", 4) == 4 ? 0 : 1;\n}\n'
} >"$w/maps70.ct"
if run_case maps70; then
    if grep -q 'u69_Controller_vtable' "$w/maps70.c"; then
        echo "ok   maps70 (last map's vtable emitted)"
    else
        bad maps70 "no u69_Controller_vtable in the generated C"
    fi
fi

# --- params17: 17 named parameters in one binding (old 16) -----------------
{
    printf 'trait Many {\n    int run(int p0'
    i=1
    while [ "$i" -lt 17 ]; do printf ', int p%d' "$i"; i=$((i + 1)); done
    printf ');\n}\n'
    printf 'struct Host {\n    int v;\n};\nstruct Host h;\n'
    printf 'int f17(int p0'
    i=1
    while [ "$i" -lt 17 ]; do printf ', int p%d' "$i"; i=$((i + 1)); done
    printf ')\n{\n    return p0 + p16;\n}\n'
    printf 'map trait Many for instance h {\n    run(p0'
    i=1
    while [ "$i" -lt 17 ]; do printf ', p%d' "$i"; i=$((i + 1)); done
    printf ') -> f17(p0'
    i=1
    while [ "$i" -lt 17 ]; do printf ', p%d' "$i"; i=$((i + 1)); done
    printf ');\n}\n'
    printf 'int main(void)\n{\n    Many m = h;\n    int r = m.run(1'
    i=1
    while [ "$i" -lt 17 ]; do printf ', %d' $((i + 1)); i=$((i + 1)); done
    printf ');\n    return r == 18 ? 0 : 1;\n}\n'
} >"$w/params17.ct"
run_case params17

# --- mapjson: --emit-map lists every map --------------------------------
if ! "$ct" --emit-map - "$w/maps70.ct" -o "$w/maps70j.c" \
        >"$w/maps70.json" 2>"$w/maps70j.log"; then
    bad mapjson "ct-ast rejected --emit-map: $(tail -1 "$w/maps70j.log")"
else
    n=$(grep -o '"instance":"u[0-9][0-9]*"' "$w/maps70.json" | wc -l | tr -d ' ')
    if [ "$n" -eq 70 ]; then
        echo "ok   mapjson (70 maps in the JSON)"
    else
        bad mapjson "the map JSON lists $n instances, want 70"
    fi
    if grep -q '"symbol":"u69_Controller_send"' "$w/maps70.json"; then
        echo "ok   mapjson (last map's binding)"
    else
        bad mapjson "no u69_Controller_send in the map JSON"
    fi
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL S1a-0 map caps"
    exit 1
fi
echo "OK S1a-0 map caps"
