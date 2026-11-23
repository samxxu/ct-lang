#!/bin/sh
# SH-114: a generic function template must be defined before its first
# instantiation (direction B). The two source orders are pinned, and the
# forward use gets a dedicated diagnostic instead of "undeclared variable".
#
# Usage: sh test/ast/p114_generic_order.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p114_generic_order.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p114order.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p114/generic-order: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
msg="generic template 'twice' must be defined before its first instantiation"

# Order 1: the template is defined first. Compile, run, compare.
if ( cd "$root" && "$ctast" test/ast/294_generic_order/prog.ct -o "$work/pos.c" ) \
        >"$work/pos.log" 2>&1; then
    if "${CC:-cc}" -Wall -Wextra -std=c99 "$work/pos.c" -o "$work/pos.bin" \
            >>"$work/pos.log" 2>&1; then
        if "$work/pos.bin" >"$work/pos.out" 2>&1; then
            if cmp -s "$work/pos.out" test/ast/294_generic_order/prog.expected.out; then
                ok "template before use compiles and runs"
            else
                bad "template-before-use output differs" "$(cat "$work/pos.out")"
            fi
        else
            bad "template-before-use program exited non-zero" "$(cat "$work/pos.out")"
        fi
    else
        bad "generated C did not build" "$(sed -n '1,4p' "$work/pos.log")"
    fi
else
    bad "template before use was refused" "$(sed -n '1,4p' "$work/pos.log")"
fi

# Order 2: the template comes after the use. Hard error, dedicated text,
# full file:line:col.
neg="test/ast/errors/generic_template_after.ct"
if ( cd "$root" && "$ctast" "$neg" -o "$work/neg.c" ) >"$work/neg.log" 2>&1; then
    bad "template after use was accepted" "exit 0; expected a positioned diagnostic"
else
    if grep -Fq "generic_template_after.ct:7:20: error: $msg" "$work/neg.log"; then
        ok "template after use gets the dedicated positioned diagnostic"
    else
        bad "template-after-use diagnostic differs" "$(sed -n '1,3p' "$work/neg.log")"
    fi
    if grep -Fq "use of an undeclared variable" "$work/neg.log"; then
        bad "template-after-use kept the generic undeclared-variable text"
    else
        ok "template-after-use does not fall back to the generic text"
    fi
fi

# A genuine typo keeps the old message.
cat >"$work/typo.ct" <<'EOF'
int main(void) { return missing; }
EOF
if ( cd "$work" && "$ctast" typo.ct -o typo.c ) >"$work/typo.log" 2>&1; then
    bad "a plain undeclared variable was accepted" "exit 0"
elif grep -Fq "use of an undeclared variable" "$work/typo.log" \
        && ! grep -Fq "$msg" "$work/typo.log"; then
    ok "a plain undeclared variable keeps the old diagnostic"
else
    bad "plain undeclared variable diagnostic changed" "$(sed -n '1,3p' "$work/typo.log")"
fi

# A generic-call shape whose template never exists also keeps the old message.
cat >"$work/notmpl.ct" <<'EOF'
int main(void) { return foo<int>(3); }
EOF
if ( cd "$work" && "$ctast" notmpl.ct -o notmpl.c ) >"$work/notmpl.log" 2>&1; then
    bad "a generic-call shape with no template was accepted" "exit 0"
elif grep -Fq "use of an undeclared variable" "$work/notmpl.log" \
        && ! grep -Fq "$msg" "$work/notmpl.log"; then
    ok "a missing generic name keeps the old diagnostic"
else
    bad "missing generic name diagnostic changed" "$(sed -n '1,3p' "$work/notmpl.log")"
fi

exit $fail
