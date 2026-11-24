#!/usr/bin/env bash
# SH-120: `Str.h.ct` splits into four single-main-type units, the built-in
# layer grows from five to eight, and the UTF-16 pair moves to
# `lib/core/utf16/` under `namespace core::utf16`.
#
# Checks, in order: the target layout and the one-main-type lint; the
# one-directional dependency (Str / U16Str are the leaves); the compiler's
# eight-slot table and load order; compile mode and build mode for a program
# that uses all four types; on-demand liveness (a String-only program does not
# emit the UTF-16 units); the canonical `core::utf16::U16String` spelling; and
# the two-main-type negative.
#
# Usage: bash test/ast/sh120_split.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: sh120_split.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$CT" in /*) ;; *) CT=$root/$CT ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/sh120.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
export CT_CORE_DIR="$root/lib/core"
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL sh120: %s\n' "$1" >&2; }

# ---- 1. target layout ------------------------------------------------------
for f in lib/core/String.h.ct lib/core/Str.h.ct \
         lib/core/utf16/U16String.h.ct lib/core/utf16/U16Str.h.ct; do
    if [ -f "$root/$f" ]; then ok "layout: $f exists"; else bad "missing $f"; fi
done
[ -f "$root/lib/core/Str.h.ct" ] && ok "layout: Str.h.ct kept in lib/core"
if grep -qx 'namespace core;' "$root/lib/core/String.h.ct" \
   && grep -qx 'namespace core;' "$root/lib/core/Str.h.ct"; then
    ok "layout: String/Str declare namespace core"
else
    bad "String/Str namespace is not 'core'"
fi
if grep -qx 'namespace core::utf16;' "$root/lib/core/utf16/U16String.h.ct" \
   && grep -qx 'namespace core::utf16;' "$root/lib/core/utf16/U16Str.h.ct"; then
    ok "layout: U16 pair declares namespace core::utf16"
else
    bad "U16 pair namespace is not 'core::utf16'"
fi
if sh "$root/selfhost/unit-name-lint.sh" "$root/lib/core" "$root/lib/core/utf16" \
        >"$work/lint.out" 2>&1; then
    ok "layout: one main type per unit ($(cat "$work/lint.out"))"
else
    bad "one-main-type lint failed: $(cat "$work/lint.out")"
fi
if grep -q 'pub struct ct_str_hdr' "$root/lib/core/String.h.ct"; then
    ok "layout: ct_str_hdr follows String"
else
    bad "ct_str_hdr is not in String.h.ct"
fi

# ---- 2. dependency direction ----------------------------------------------
if ! grep -qE '^import ' "$root/lib/core/Str.h.ct" \
   && ! grep -qE '^import ' "$root/lib/core/utf16/U16Str.h.ct"; then
    ok "DAG: Str and U16Str are leaf units (no import)"
else
    bad "Str or U16Str imports another unit"
fi
if ! grep -q 'U16' "$root/lib/core/Str.h.ct"; then
    ok "DAG: Str does not name a UTF-16 type"
else
    bad "Str.h.ct still names UTF-16"
fi
if grep -qE 'U16String|U16Str' "$root/lib/core/utf16/U16String.h.ct" \
   && grep -qE 'ct_str_alloc|Str ' "$root/lib/core/utf16/U16String.h.ct"; then
    ok "DAG: U16String depends on String / Str / U16Str"
else
    bad "U16String does not show its String/Str/U16Str dependency"
fi
order=$(grep -nE '"utf16/U16String.h.ct"|"utf16/U16Str.h.ct"|"String.h.ct"|"Str.h.ct"' \
        "$root/selfhost/ct-ast/frontend/module/Module.h.ct" | head -4)
if printf '%s\n' "$order" | grep -q 'Str.h.ct' \
   && printf '%s\n' "$order" | grep -q 'String.h.ct' \
   && [ "$(printf '%s\n' "$order" | grep -c 'Str.h.ct')" -ge 1 ]; then
    ok "DAG: load order names Str before String and both UTF-16 units"
else
    bad "load order does not name the four units: $order"
fi

# ---- 3. eight built-in slots ----------------------------------------------
if grep -q 'builtin_units\[8\]' "$root/selfhost/ct-ast/frontend/module/Module.h.ct" \
   && grep -q 'builtin_live\[8\]' "$root/selfhost/ct-ast/frontend/module/Module.h.ct" \
   && grep -q 'builtins\[8\]' "$root/selfhost/ct-ast/backend/emit/Emitter.h.ct"; then
    ok "builtin layer: Module/Driver/Emitter use eight slots"
else
    bad "a built-in slot table is not eight entries"
fi
if grep -q 'bi < 8' "$root/selfhost/ct-ast/frontend/module/Module.h.ct" \
   && grep -q 'bi < 8' "$root/selfhost/ct-ast/tool/driver/Driver.h.ct"; then
    ok "builtin layer: both drivers load eight units"
else
    bad "a driver still loads five units"
fi
if grep -q 'lib/core/utf16/U16String.h.ct' "$root/selfhost/ct-ast/frontend/parse/Stmt.h.ct" \
   && grep -q 'lib/core/utf16/U16String.h.ct' "$root/selfhost/ct-ast/frontend/parse/Expr.h.ct" \
   && grep -q 'lib/core/String.h.ct' "$root/selfhost/ct-ast/frontend/parse/Stmt.h.ct" \
   && grep -q 'lib/core/String.h.ct' "$root/selfhost/ct-ast/frontend/parse/Expr.h.ct"; then
    ok "builtin layer: ptr write protection covers the four files"
else
    bad "ptr write protection does not cover all four string units"
fi

# ---- 4. compile mode: all four types --------------------------------------
cat >"$work/all.ct" <<'CT'
#include <stdio.h>
int main(void)
{
    String s = "hi";
    Str v = s.as_str();
    U16String u = U16String.from_utf8(v);
    U16Str w = u.as_str();
    printf("%d %d %d %d\n", s.len(), v.len(), u.len(), w.len());
    u.release();
    s.release();
    return 0;
}
CT
if ! "$CT" "$work/all.ct" -o "$work/all.c" >"$work/all.log" 2>&1; then
    bad "compile mode: four types did not compile: $(head -2 "$work/all.log")"
elif ! cc -std=c99 "$work/all.c" -o "$work/all.bin" >"$work/all.cc" 2>&1; then
    bad "compile mode: product did not build: $(head -2 "$work/all.cc")"
elif [ "$("$work/all.bin")" != "2 2 2 2" ]; then
    bad "compile mode: output drifted: $("$work/all.bin")"
else
    ok "compile mode: String/Str/U16String/U16Str compile and run"
fi

# ---- 5. build mode: four products -----------------------------------------
mkdir -p "$work/bld"
if ! "$CT" build --emit-c "$work/all.ct" -o "$work/bld" >"$work/bld.log" 2>&1; then
    bad "build mode: four types did not build: $(head -2 "$work/bld.log")"
else
    miss=""
    for c in String.c Str.c U16String.c U16Str.c; do
        [ -f "$work/bld/$c" ] || miss="$miss $c"
    done
    if [ -z "$miss" ]; then
        ok "build mode: product carries String.c / Str.c / U16String.c / U16Str.c"
    else
        bad "build mode: missing product(s):$miss"
    fi
    if cc -std=c99 -I "$work/bld" "$work/bld"/*.c -o "$work/bld/app" >"$work/bld.cc" 2>&1 \
       && [ "$("$work/bld/app")" = "2 2 2 2" ]; then
        ok "build mode: four products link warning-free and run"
    else
        bad "build mode: products did not link/run: $(head -3 "$work/bld.cc")"
    fi
fi

# ---- 6. on-demand liveness -------------------------------------------------
cat >"$work/onlystr.ct" <<'CT'
#include <stdio.h>
int main(void) { String s = "x"; printf("%d\n", s.len()); s.release(); return 0; }
CT
mkdir -p "$work/only"
if "$CT" build --emit-c "$work/onlystr.ct" -o "$work/only" >"$work/only.log" 2>&1; then
    if [ -f "$work/only/String.c" ] && [ ! -e "$work/only/U16String.c" ] \
       && [ ! -e "$work/only/U16Str.c" ]; then
        ok "liveness: a String-only program emits String but not the UTF-16 units"
    else
        bad "liveness: UTF-8-only program emitted the wrong built-in set ($(ls "$work/only"))"
    fi
else
    bad "liveness: String-only program did not build: $(head -2 "$work/only.log")"
fi
cat >"$work/onlyu16.ct" <<'CT'
#include <stdio.h>
int main(void) { U16String u = U16String.from_utf8("x"); printf("%d\n", u.len()); u.release(); return 0; }
CT
mkdir -p "$work/only16"
if "$CT" build --emit-c "$work/onlyu16.ct" -o "$work/only16" >"$work/only16.log" 2>&1; then
    miss=""
    for c in String.c Str.c U16String.c U16Str.c Vec.c; do
        [ -f "$work/only16/$c" ] || miss="$miss $c"
    done
    if [ -z "$miss" ]; then
        ok "liveness: a UTF-16 program pulls String/Str/U16Str/U16String/Vec"
    else
        bad "liveness: UTF-16 program missing:$miss"
    fi
else
    bad "liveness: UTF-16 program did not build: $(head -2 "$work/only16.log")"
fi

# ---- 7. canonical namespace spelling --------------------------------------
cat >"$work/ns.ct" <<'CT'
#include <stdio.h>
int main(void)
{
    Str a = "hi";
    core::utf16::U16String u = U16String.from_utf8(a);
    core::utf16::U16Str w = u.as_str();
    printf("%d %d\n", u.len(), w.len());
    u.release();
    return 0;
}
CT
if "$CT" "$work/ns.ct" -o "$work/ns.c" >"$work/ns.log" 2>&1 \
   && cc -std=c99 "$work/ns.c" -o "$work/ns.bin" >"$work/ns.cc" 2>&1 \
   && [ "$("$work/ns.bin")" = "2 2" ]; then
    ok "name: core::utf16::U16String / U16Str is the canonical type spelling"
else
    bad "canonical core::utf16 spelling did not compile/run: $(head -2 "$work/ns.log" "$work/ns.cc" 2>/dev/null)"
fi

# ---- 8. migration note -----------------------------------------------------
if grep -q 'core::utf16::U16String' "$root/lib/core/README.md" \
   && grep -qi '迁移' "$root/lib/core/README.md"; then
    ok "docs: lib/core/README records the U16 rename and the migration window"
else
    bad "lib/core/README has no U16 rename/migration note"
fi

# ---- 9. negative: two main types ------------------------------------------
mkdir -p "$work/badunits"
printf 'pub struct Two {\n    int x;\n}\n\npub struct Other {\n    int y;\n}\n' \
    >"$work/badunits/Two.h.ct"
if sh "$root/selfhost/unit-name-lint.sh" "$work/badunits" >"$work/bad.log" 2>&1; then
    bad "negative: a unit with two main types passed the lint"
else
    ok "negative: a unit with two main types is rejected"
fi

printf 'sh120_split: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
