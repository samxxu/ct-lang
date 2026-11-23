#!/bin/sh
# TEST-25 probe: white-box unit tests for ct-ast's pure slice helpers.
#
# ct-ast is Ct source; its `em_*` / `ctype_*` / `tc_expr_*` slices are `static`
# inside one emitted translation unit, and the compiler offers no way to import
# a unit for testing. So the probe uses the same recipe as the L0 unit layer:
# build the C tree once, then include the generated unit in a small C harness
# and link every other unit normally. No gtest and no third-party framework.
#
# The three harnesses live beside this script:
#   test25_unit_typecheck.c   tc_expr_num / tc_expr_fnum / type_key
#   test25_unit_expr.c        ctype_adtctor / ctype_opt / ctype_slice_get /
#                             ctype_slice_range
#   test25_unit_emitter.c     em_expr_num / map_clean_type / map_recipe_callee
#
# Usage: sh test/ast/test25_unit.sh <generated-source-dir> [cc]
# Exit code 0 means every assertion passed.
set -u
src=${1:?usage: test25_unit.sh <generated-source-dir> [cc]}
cc=${2:-${CC:-cc}}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
if [ ! -d "$src" ]; then
    echo "FAIL test25unit: generated source dir '$src' is missing" >&2
    exit 1
fi
tmp=$(mktemp -d "${TMPDIR:-/tmp}/test25unit.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM

cflags="-Wall -Wextra -std=c99"
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL test25unit: $1" >&2; }

# Compile the generated tree once; the harness object supplies the included
# unit, so its normal object is dropped from the link line.
mkdir -p "$tmp/obj"
objects=""
for f in "$src"/*.c; do
    [ -f "$f" ] || continue
    b=$(basename "$f" .c)
    [ "$b" = main ] && continue
    if ! $cc $cflags -I "$src" -c "$f" -o "$tmp/obj/$b.o" 2>"$tmp/obj-$b.err"; then
        bad "generated $b.c did not compile: $(head -2 "$tmp/obj-$b.err" | tr '\n' ' ')"
        exit 1
    fi
    objects="$objects $tmp/obj/$b.o"
done
if [ -z "$objects" ]; then
    bad "the generated source dir holds no unit .c files"
    exit 1
fi

# Include the generated unit under test rather than linking it twice.
for harness in typecheck expr emitter; do
    case "$harness" in
        typecheck) unit=TypeCheck ;;
        expr)      unit=Expr ;;
        emitter)   unit=Emitter ;;
    esac
    link=""
    for o in $objects; do
        case "$o" in
            */"$unit".o) continue ;;
        esac
        link="$link $o"
    done
    srcfile="test/ast/test25_unit_$harness.c"
    if [ ! -f "$srcfile" ]; then
        bad "$srcfile is missing"
        continue
    fi
    if ! $cc $cflags -I "$src" "$srcfile" $link -o "$tmp/$harness" \
            2>"$tmp/$harness.build"; then
        bad "$harness harness did not build: $(head -3 "$tmp/$harness.build" | tr '\n' ' ')"
        continue
    fi
    if "$tmp/$harness" >"$tmp/$harness.out" 2>&1; then
        if grep -q '0 failed$' "$tmp/$harness.out"; then
            ok
            printf '  test25unit %s: %s\n' "$harness" "$(tail -1 "$tmp/$harness.out")"
        else
            bad "$harness did not report 0 failed: $(tail -2 "$tmp/$harness.out" | tr '\n' ' ')"
        fi
    else
        bad "$harness assertions failed: $(tail -3 "$tmp/$harness.out" | tr '\n' ' ')"
    fi
done

echo "test25unit: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
