#!/bin/sh
# D-028 / v1-PH-2 S2 probe: the user-type subscript protocol by key type.
#
#   JSACCESS_1_no_int_get : only `get(char *)` + `x[0]` is a hard error that
#                           lists the candidate signature (D52-6 no longer
#                           silently answers an empty value).
#   JSACCESS_2_no_candidate: a key type no candidate declares.
#   INDEX_1_no_candidate  : same case, pinned from the REQ-INDEX-1 side.
#   INDEX_2_ambiguous     : two candidates with the same key.
#   INDEX_3_set_mismatch  : `set` exists but its key type does not match.
#   INDEX_L1..L6          : `+=` / `++` / `&x[k]` are hard errors with the
#                           frozen v0-PH-52 text, in both the value and the
#                           borrow form (D-028 §1.5 "all hard errors").
#   shape                 : the C products name the selected versions with the
#                           D-028 suffix (first overload keeps `<T>_<name>`).
#
# Usage: sh test/ast/p52_index.sh <ct-ast> [cc]
set -u
ctast=${1:?usage: p52_index.sh <ct-ast> [cc]}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p52-index.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
export CT_C_BOUNDARY=allow
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok   $*"; }

compile() {
    name=$1
    src=$2
    if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
            "$src" -o "$tmp/$name.c" ) >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail_msg "$name: ct-ast failed:"; sed 's/^/  /' "$tmp/$name.err" >&2
        return 1
    fi
    return 0
}

run_bin() {
    name=$1
    if ! "$cc" -Wall -Wextra -std=c99 "$tmp/$name.c" -o "$tmp/$name.bin" \
            2>"$tmp/$name.cc"; then
        fail_msg "$name: generated C did not build:"; sed 's/^/  /' "$tmp/$name.cc" >&2
        return 1
    fi
    [ -s "$tmp/$name.cc" ] && { fail_msg "$name: generated C is not warning-free"; return 1; }
    if ! "$tmp/$name.bin" >"$tmp/$name.txt" 2>&1; then
        fail_msg "$name: the program exited non-zero"; return 1
    fi
    if ! diff -u "$root/test/ast/$name/prog.expected.out" "$tmp/$name.txt" \
            >"$tmp/$name.diff"; then
        fail_msg "$name: output drifted:"; head -8 "$tmp/$name.diff" >&2
        return 1
    fi
    return 0
}

# --- positive shape: key-type dispatch, not declaration order -------------
if compile jsaccess_overload_both test/ast/jsaccess_overload_both/prog.ct; then
    if grep -Fq 'J_get(&j, "a")' "$tmp/jsaccess_overload_both.c" \
       && grep -Fq 'J_get$int(&j, 0)' "$tmp/jsaccess_overload_both.c"; then
        ok_msg "INDEX_shape  jsaccess: j[\"a\"] -> J_get, j[0] -> J_get\$int"
    else
        fail_msg "INDEX_shape: the two key types did not select two versions"
    fi
    run_bin jsaccess_overload_both || true
fi
if compile index_overload_both test/ast/index_overload_both/prog.ct; then
    if grep -Fq 'Vault_get(&b, 2)' "$tmp/index_overload_both.c" \
       && grep -Fq 'Vault_get$char_2a(&b, "new")' "$tmp/index_overload_both.c" \
       && grep -Fq 'Vault_set(&b, 0, 5)' "$tmp/index_overload_both.c" \
       && grep -Fq 'Vault_set$char_2a$int(&b, "x", 9)' "$tmp/index_overload_both.c"; then
        ok_msg "INDEX_shape  overload: read and write both dispatch by key type"
    else
        fail_msg "INDEX_shape: read/write overload naming is wrong"
    fi
    run_bin index_overload_both || true
fi
if compile index_borrow_write test/ast/index_borrow_write/prog.ct; then
    if grep -Fq '(*Buf_get(&b, 0)) = 7;' "$tmp/index_borrow_write.c"; then
        ok_msg "INDEX_shape  borrow: *x[0] = 7 writes through the returned pointer"
    else
        fail_msg "INDEX_shape: the borrow write shape changed"
    fi
    run_bin index_borrow_write || true
fi
if compile index_borrow_assign test/ast/index_borrow_assign/prog.ct; then
    if grep -Fq '(*Buf_get(&b, 1)) = 5;' "$tmp/index_borrow_assign.c"; then
        ok_msg "INDEX_shape  borrow write: x[k] = v becomes *get(k) = v without set"
    else
        fail_msg "INDEX_shape: x[k] = v did not become a borrow write"
    fi
    run_bin index_borrow_assign || true
fi

# --- LIR path: the same names, printed from the lowerer -------------------
# D-028 §1.7: the AST emitter and LIR must carry the same suffix. Build mode
# with `--ir=on` prints a body from LIR only when the seam matches, and
# CT_LIR_DEBUG=1 names every body it printed; a fallback would say "not in
# this unit's lowered set" instead.
lir_case() {
    name=$1
    marker=$2
    d="$tmp/lir-$name"
    rm -rf "$d"
    mkdir -p "$d"
    if ! ( cd "$d" && CT_LIR_DEBUG=1 "$ctast" build --ir=on \
            "$root/test/ast/$name/prog.ct" -o "$d/prog" ) \
            >"$tmp/lir-$name.log" 2>&1; then
        fail_msg "INDEX_LIR: $name did not build with --ir=on: $(sed -n '1,3p' "$tmp/lir-$name.log" | tr '\n' ' ')"
        return
    fi
    if ! "$d/prog" >"$tmp/lir-$name.txt" 2>&1; then
        fail_msg "INDEX_LIR: $name exited non-zero"
        return
    fi
    if ! diff -u "$root/test/ast/$name/prog.expected.out" "$tmp/lir-$name.txt" \
            >"$tmp/lir-$name.diff"; then
        fail_msg "INDEX_LIR: $name output drifted"
        return
    fi
    if ! grep -Fq "$marker" "$tmp/lir-$name.log"; then
        fail_msg "INDEX_LIR: $name did not print the overload body from LIR"
        return
    fi
    ok_msg "INDEX_LIR  $name: overload body printed from LIR ($marker)"
}
lir_case jsaccess_overload_both "body 'J_get\$int' printed"
lir_case index_overload_both "body 'Vault_set\$char_2a\$int' printed"
lir_case index_borrow_assign "body 'Buf_get' printed"

# --- negative diagnostics -------------------------------------------------
neg() {
    name=$1
    want=$2
    label=$3
    if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg-$name.c" ) \
            >"$tmp/neg-$name.out" 2>"$tmp/neg-$name.err"; then
        fail_msg "$label: expected a diagnostic, got exit 0"
        return
    fi
    if ! grep -Fq -- "$want" "$tmp/neg-$name.err"; then
        fail_msg "$label: $(sed -n '1,3p' "$tmp/neg-$name.err" | tr '\n' ' ')"
        return
    fi
    if [ "$(grep -c 'error:' "$tmp/neg-$name.err")" -ne 1 ]; then
        fail_msg "$label: expected exactly one diagnostic"
        return
    fi
    if [ -e "$tmp/neg-$name.c" ]; then
        fail_msg "$label: a rejected subscript still wrote a product"
        return
    fi
    ok_msg "$label"
}

neg index_no_int_get \
    "type 'J' has no subscript matching 'get(int)': candidates are 'int get(char *)'" \
    "JSACCESS_1_no_int_get"
neg index_no_int_get \
    "type 'J' has no subscript matching 'get(int)': candidates are 'int get(char *)'" \
    "INDEX_1_no_candidate"
neg index_wrong_key_type \
    "type 'K' has no subscript matching 'get(int)': candidates are 'long get(long)'" \
    "JSACCESS_2_no_candidate"
neg index_ambiguous \
    "type 'A' has an ambiguous subscript: candidates are 'int get(int)', 'int get(int)'" \
    "INDEX_2_ambiguous"
neg index_set_mismatch \
    "type 'W' has no writable subscript matching 'set(int, V)': candidates are 'void set(char *, int)'" \
    "INDEX_3_set_mismatch"

# --- += / ++ / &x[k] : one hard error each, value and borrow form --------
form_err() {
    name=$1
    body=$2
    want=$3
    label=$4
    cat >"$tmp/$name.ct" <<EOF
struct S {
    int n;
}

impl S {
    int get(char *k)
    {
        (void)k;
        return self->n;
    }
    int *get(int i)
    {
        return &self->n + i;
    }
    void set(char *k, int v)
    {
        (void)k;
        self->n = v;
    }
}

int main(void)
{
    S s;
    s.n = 1;
    $body
    return 0;
}
EOF
    if ( cd "$tmp" && "$ctast" "$tmp/$name.ct" -o "$tmp/$name.c" ) \
            >"$tmp/$name.out" 2>"$tmp/$name.err"; then
        fail_msg "$label: accepted (expected a hard error)"
    elif ! grep -Fq -- "$want" "$tmp/$name.err"; then
        fail_msg "$label: $(sed -n '1,2p' "$tmp/$name.err" | tr '\n' ' ')"
    elif [ -e "$tmp/$name.c" ]; then
        fail_msg "$label: a rejected form still wrote a product"
    else
        ok_msg "$label"
    fi
}
form_err index_l1 's["k"] += 1;' \
    "a custom subscript supports only '='; use set(k, v)" "INDEX_L1  value form: += is a hard error"
form_err index_l2 's["k"]++;' \
    "a custom subscript supports only '='; use set(k, v)" "INDEX_L2  value form: ++ is a hard error"
form_err index_l3 'int *p = &s["k"]; (void)p;' \
    "cannot take the address of a custom subscript; bind it to a local first" \
    "INDEX_L3  value form: &x[k] is a hard error"
form_err index_l4 's[0] += 1;' \
    "a custom subscript supports only '='; use set(k, v)" "INDEX_L4  borrow form: += is a hard error"
form_err index_l5 's[0]++;' \
    "a custom subscript supports only '='; use set(k, v)" "INDEX_L5  borrow form: ++ is a hard error"
form_err index_l6 'int *p = &s[0]; (void)p;' \
    "cannot take the address of a custom subscript; bind it to a local first" \
    "INDEX_L6  borrow form: &x[k] is a hard error"

echo "p52/index: $fail failure(s)"
[ "$fail" -eq 0 ]
