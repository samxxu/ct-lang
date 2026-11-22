#!/bin/sh
# LANG-23 probe: `Drop` / `Handback` have visible declarations in lib/core, stay
# reserved built-in traits (no vtable, no MAX_TRAITS entry), and `AutoDrop` is a
# mechanism, not a trait.
#
# The declarations are declaration-only: the parser validates them but discards
# the row, so every existing name-based built-in path stays in charge and the
# generated C for `use Drop` / `impl Drop` is unchanged.
#
# Usage: sh test/ast/lang23_builtin_traits.sh <ct-ast>
set -u
ctast=${1:?usage: lang23_builtin_traits.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/lang23.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
export CT_C_BOUNDARY=allow
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL lang23: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=$((fail + 1)); }

# 1. The visible declarations exist; AutoDrop is not among them.
for t in Drop Handback; do
    if grep -q "pub trait $t {" lib/core/Vec.h.ct; then
        ok "lib/core declares $t"
    else
        bad "lib/core has no visible 'pub trait $t'"
    fi
done
if grep -rq 'trait AutoDrop' lib/core/*.h.ct; then
    bad "lib/core declares AutoDrop (it is an own mechanism, not a trait)"
else
    ok "AutoDrop is not a trait declaration"
fi

# 2. `use Drop` / `impl Drop` keep their behaviour and emit no vtable/vptr.
cat > "$work/drop.ct" <<'CT'
#include <stdio.h>
struct Res { int x; } use Drop;
impl Drop for Res {
    void drop() { printf("drop %d\n", self->x); }
}
int main() {
    Res r = { 1 };
    return r.x;
}
CT
if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$work/drop.ct" -o "$work/drop.c" ) \
        >"$work/drop.log" 2>&1; then
    bad "use Drop / impl Drop did not compile" "$(head -3 "$work/drop.log")"
else
    ok "use Drop / impl Drop compile"
    if grep -q 'Res_Drop_drop' "$work/drop.c"; then
        ok "impl Drop still emits Res_Drop_drop"
    else
        bad "impl Drop stopped emitting Res_Drop_drop"
    fi
    if grep -q 'Drop_vtbl\|Drop_iface\|Drop_vptr' "$work/drop.c"; then
        bad "the built-in Drop declaration leaked a vtable/vptr"
    else
        ok "no Drop vtable/vptr"
    fi
fi

# 3. A user unit still may not redefine either reserved trait.
for t in Drop Handback; do
    cat > "$work/bad_$t.ct" <<CT
trait $t { void ${t}x(); }
int main() { return 0; }
CT
    if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" check "$work/bad_$t.ct" ) \
            >"$work/bad_$t.log" 2>&1; then
        bad "user 'trait $t' was accepted"
    elif grep -q "'$t' is a reserved built-in trait and cannot be defined" "$work/bad_$t.log"; then
        ok "user 'trait $t' is refused with the reserved-name message"
    else
        bad "user 'trait $t' failed for the wrong reason" "$(head -2 "$work/bad_$t.log")"
    fi
done

# 4. The discarded declarations do not consume MAX_TRAITS (64). Exactly 64 user
#    traits plus `use Drop` must still compile; if the two built-in declarations
#    were counted, the 65th/66th row would be refused.
{
    i=0
    while [ "$i" -lt 64 ]; do
        printf 'trait T%d { void m%d(); }\n' "$i" "$i"
        i=$((i + 1))
    done
    cat <<'CT'
struct S { int x; } use Drop;
impl Drop for S { void drop() { } }
int main() { return 0; }
CT
} > "$work/maxtraits.ct"
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" check "$work/maxtraits.ct" ) \
        >"$work/maxtraits.log" 2>&1; then
    ok "MAX_TRAITS is unchanged (64 user traits + use Drop compile)"
else
    bad "the built-in declarations consumed MAX_TRAITS" "$(head -2 "$work/maxtraits.log")"
fi

# 5. `AutoDrop` stays an ordinary user trait, not a reserved name.
cat > "$work/autodrop.ct" <<'CT'
trait AutoDrop { void on_auto_drop(); }
int main() { return 0; }
CT
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" check "$work/autodrop.ct" ) \
        >"$work/autodrop.log" 2>&1; then
    ok "user 'trait AutoDrop' is not reserved"
else
    bad "user 'trait AutoDrop' was refused" "$(head -2 "$work/autodrop.log")"
fi

echo "lang23: $fail failure(s)"
[ "$fail" -eq 0 ]
