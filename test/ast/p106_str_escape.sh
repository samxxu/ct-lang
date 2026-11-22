#!/bin/sh
# SH-106: the borrowed `Str` view escape lint.
#
# `Str` / `U16Str` are borrowed views with no Drop; a view of a local owning
# `String` / `U16String` dies at the frame's exit and a view of a temporary
# owner dies at the end of the full expression. Both shapes are a warning in
# `ct build` / `ct compile` and an error under `ct check`, exactly like E79-6's
# `slice escape` (the two share the `Var` lifetime bits).
#
# Negatives: local owner returned, temporary receiver returned, a local view
# binding returned, `s[i]`/`get`, a view of a view, a declaration / an
# assignment of a temporary view, the UTF-16 pair, and a `str_slice` hand-off.
# Positives (must stay silent): an immortal literal view, the owner still in
# scope, a parameter borrow, a field borrow, a file-scope owner, an owning
# local bound to an immortal literal, and the `ct: allow-escape` opt-out.
#
# Usage: sh test/ast/p106_str_escape.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p106_str_escape.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p106escape.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p106/escape: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1
d=test/ast/p106_str_escape

build_one() {
    "$ctast" build "$d/$1.ct" -o "$work/$1.bin" >"$work/$1.log" 2>&1
}
check_one() {
    "$ctast" check "$d/$1.ct" >"$work/$1.check.log" 2>&1
}
check_types_one() {
    "$ctast" check --types "$d/$1.ct" >"$work/$1.checktypes.log" 2>&1
}
expect_warn() {
    if ! build_one "$1"; then
        bad "$1" "the warning fixture did not build: $(sed -n '1,3p' "$work/$1.log")"
    elif ! grep -Fq "borrowed '$2' view escapes" "$work/$1.log"; then
        bad "$1" "warning missing: $(sed -n '1,3p' "$work/$1.log")"
    else
        ok "$1 ($3)"
    fi
}
expect_silent() {
    if ! build_one "$1"; then
        bad "$1" "the fixture did not build: $(sed -n '1,3p' "$work/$1.log")"
    elif grep -Fq "view escapes" "$work/$1.log"; then
        bad "$1" "unexpected escape warning: $(sed -n '1,3p' "$work/$1.log")"
    else
        ok "$1 ($2)"
    fi
}
expect_check_error() {
    if check_one "$1"; then
        bad "$1" "ct check accepted the escape"
    elif ! grep -Fq "error: borrowed '$2' view escapes" "$work/$1.check.log"; then
        bad "$1" "ct check did not report an error: $(sed -n '1,3p' "$work/$1.check.log")"
    else
        ok "$1 (ct check reports an error)"
    fi
}
expect_check_types_error() {
    if check_types_one "$1"; then
        bad "$1" "ct check --types accepted the escape"
    elif ! grep -Fq "error: borrowed '$2' view escapes" "$work/$1.checktypes.log"; then
        bad "$1" "ct check --types did not report an error: $(sed -n '1,3p' "$work/$1.checktypes.log")"
    else
        ok "$1 (ct check --types reports an error)"
    fi
}
expect_check_types_ok() {
    if ! check_types_one "$1"; then
        bad "$1" "ct check --types rejected a safe view: $(sed -n '1,3p' "$work/$1.checktypes.log")"
    elif grep -Fq "view escapes" "$work/$1.checktypes.log"; then
        bad "$1" "ct check --types still warned: $(sed -n '1,3p' "$work/$1.checktypes.log")"
    else
        ok "$1 (ct check --types is clean)"
    fi
}
expect_check_ok() {
    if ! check_one "$1"; then
        bad "$1" "ct check rejected a safe view: $(sed -n '1,3p' "$work/$1.check.log")"
    elif grep -Fq "view escapes" "$work/$1.check.log"; then
        bad "$1" "ct check still warned: $(sed -n '1,3p' "$work/$1.check.log")"
    else
        ok "$1 (ct check is clean)"
    fi
}

# --- negatives: a view whose owner dies before the view -------------------
expect_warn ret_local Str "a local owning String returned"
expect_warn ret_temp Str "a temporary owning String returned"
expect_warn ret_local_var Str "a local view binding returned"
expect_warn ret_local_get Str "s.get(i) from a local owner"
expect_warn ret_view_slice Str "a sub-view of a local view"
expect_warn bind_temp Str "a declaration of a temporary view"
expect_warn assign_temp Str "an assignment of a temporary view"
expect_warn ret_u16str U16Str "the UTF-16 pair has the same shape"
expect_warn ret_str_slice Str "the free str_slice of a local view"

# --- the same findings under `ct check` (warnings become errors) ----------
expect_check_error ret_local Str
expect_check_error ret_temp Str
expect_check_error bind_temp Str

# --- `ct check --types` follows the same severity -------------------------
expect_check_types_error ret_local Str
expect_check_types_error ret_temp Str
expect_check_types_error bind_temp Str

# --- positives: the owner outlives the view ------------------------------
expect_silent ret_literal "an immortal literal view"
expect_silent owner_scope "the owning String is still in scope"
expect_silent ret_param "a parameter borrow"
expect_silent ret_field "a field borrow"
expect_silent ret_global "a file-scope owner"
expect_silent ret_immortal_owner "an owning local bound to an immortal literal"
expect_silent allow_escape "the ct: allow-escape opt-out"

# --- and `ct check` stays clean on the safe shapes -----------------------
expect_check_ok owner_scope
expect_check_ok ret_param
expect_check_ok allow_escape
expect_check_types_ok owner_scope
expect_check_types_ok ret_param
expect_check_types_ok allow_escape

[ "$fail" -eq 0 ] && echo "p106_str_escape: OK"
exit "$fail"
