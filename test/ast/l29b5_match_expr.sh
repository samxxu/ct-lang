#!/usr/bin/env bash
# LANG-29 S4 / B5 probe: `match` as an expression (`yield` semantics).
#
# E-l29b5-1: `return match (n) { … };` compiles and answers the arm's value.
#            Every value arm is `Pattern => expr` or `Pattern => { …; yield
#            expr; }`; the whole form is a normal expression (initialiser,
#            argument, return) and the statement form keeps working beside it.
# E-l29b5-2: the subject is evaluated exactly once (`next_node` counter).
# E-l29b5-3: an arm whose block ends in `return` diverges and needs no `yield`.
# E-l29b5-4: the generated C is a GNU statement expression with one match
#            temporary and one result temporary; no `yield` spelling survives.
# E-l29b5-5: `--types` stays clean on the fixture (the arm type is written
#            into the type stream).
# E-l29b5-6: the three `yield` negatives keep their positioned text: a block
#            arm with no value, a second `yield`, and two different arm types.
#            A `yield` outside an arm is named as such, not as an unknown name.
#
# Usage: bash test/ast/l29b5_match_expr.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: l29b5_match_expr.sh <ct-ast>}
abs_ct() {
    case "$1" in
        /*) printf '%s' "$1" ;;
        *) printf '%s/%s' "$PWD" "$1" ;;
    esac
}
CT=$(abs_ct "$CT")
CC=${CC:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/l29b5.XXXXXX")
trap 'rm -rf "$tmp"' EXIT

pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL l29b5: $1" >&2; }
dump() { sed 's/^/    /' "$1" >&2; }
has() { grep -qF -- "$2" "$1"; }
no()  { ! grep -qF -- "$2" "$1"; }

# ---- E-l29b5-1..4: the positive fixture -----------------------------------
src="$root/test/ast/302_adt_match_expr/prog.ct"
if ! "$CT" "$src" -o "$tmp/p.c" >"$tmp/o" 2>&1; then
    bad "the expression-match fixture did not compile"
    dump "$tmp/o"
else
    ok
fi

c="$tmp/p.c"
if [ -f "$c" ]; then
    if has "$c" "__ct_match" && has "$c" "__ct_mres"; then
        ok
    else
        bad "the expression match did not lower to a match + result temporary"
    fi
    if has "$c" "({ " && grep -qE '__ct_mres[0-9]+;' "$c"; then
        ok
    else
        bad "the expression match is not a GNU statement expression"
    fi
    if no "$c" "yield"; then
        ok
    else
        bad "the word 'yield' survived into the generated C"
    fi
    # the statement form is unchanged: the classic() body still matches a
    # statement (no result temporary for that match)
    if grep -q '__ct_match.*__attribute__((unused))' "$c"; then
        ok
    else
        bad "the statement-form match changed shape"
    fi
else
    bad "no product was written"
fi

# E-l29b5-1/6: warning-free C99 build, then behaviour
if [ -f "$c" ] && "$CC" -Wall -Wextra -std=c99 "$c" -o "$tmp/p.bin" \
        >"$tmp/cc.out" 2>"$tmp/cc.err"; then
    if [ -s "$tmp/cc.err" ]; then
        bad "the generated C is not warning-free:"; sed 's/^/    /' "$tmp/cc.err" >&2
    else
        ok
    fi
    if "$tmp/p.bin" >"$tmp/p.out" 2>&1 \
       && cmp -s "$tmp/p.out" "$root/test/ast/302_adt_match_expr/prog.expected.out"; then
        ok
    else
        bad "the program output drifted: $(cat "$tmp/p.out" 2>/dev/null | tr '\n' ' ')"
    fi
else
    bad "the generated C did not build: $(head -4 "$tmp/cc.err" 2>/dev/null)"
fi

# ---- E-l29b5-4: sanitizers ------------------------------------------------
if [ -f "$c" ]; then
    san="-fsanitize=address,undefined -fno-omit-frame-pointer"
    if "$CC" $san -Wall -Wextra -std=c99 "$c" -o "$tmp/p.san" >"$tmp/san.out" 2>&1 \
       && "$tmp/p.san" >"$tmp/san.run" 2>"$tmp/san.err"; then
        if [ -s "$tmp/san.err" ]; then
            bad "the sanitizer run reported:"; sed 's/^/    /' "$tmp/san.err" >&2
        else
            ok
        fi
    else
        bad "the sanitizer build/run failed"; dump "$tmp/san.err"
    fi
fi

# ---- E-l29b5-5: the type stream stays clean -------------------------------
if "$CT" check --types "$src" >"$tmp/types.log" 2>&1; then
    ok
else
    bad "--types is not clean on the fixture: $(head -3 "$tmp/types.log")"
fi

# ---- E-l29b5-6: the yield negatives --------------------------------------
neg() {
    name=$1
    pos=$2
    msg=$3
    rm -f "$tmp/n.c"
    if "$CT" "$root/test/ast/errors/$name.ct" -o "$tmp/n.c" >"$tmp/o" 2>&1; then
        bad "$name: expected a diagnostic, got exit 0"
    elif ! grep -qF "test/ast/errors/$name.ct:$pos: error: $msg" "$tmp/o"; then
        bad "$name: missing pinned diagnostic: $(head -2 "$tmp/o")"
    elif [ "$(grep -c 'error: ' "$tmp/o")" -ne 1 ]; then
        bad "$name: expected exactly one error: $(cat "$tmp/o")"
    elif [ -e "$tmp/n.c" ]; then
        bad "$name: a rejected program still wrote a product"
    else
        ok
    fi
}
neg l29b5_missing_yield 11:9  "an expression-match arm must yield a value (add 'yield <expr>;' or end with 'return')"
neg l29b5_multi_yield   11:30 "an expression-match arm yields exactly once"
neg l29b5_yield_type    12:9  "match arm yields 'char *', but an earlier arm yields 'int'"
neg l29b5_yield_outside 5:5   "'yield' is only allowed as the last statement of an expression-match arm"

if [ "$fail" -eq 0 ]; then
    echo "l29b5: $pass passed, 0 failed"
    echo "OK l29b5"
else
    echo "l29b5: $pass passed, $fail failed" >&2
    exit 1
fi
