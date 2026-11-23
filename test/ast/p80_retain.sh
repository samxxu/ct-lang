#!/bin/sh
# PH-80 SH-102 (D-013 §3): the automatic retain / release contract.
#
#   - the refcount trace at every destination the contract names: a by-value
#     `String` / `U16String` parameter, a local copy, a field assignment, a
#     move / non-local return, a reassignment and a scope exit;
#   - round 2: nested `break` / `continue` release every scope they leave, a
#     field reassignment releases the old value, a struct literal retains an
#     owning element, and every declarator of a multi-declarator line retains;
#   - round 3 (R6a/R6b): a field release only ever touches definitely defined
#     storage (a branch / loop / switch definition that cannot be proven is a
#     hard error), a loop reassignment releases the previous value, and the
#     shapes that cannot be modelled (`h = other`, a goto over an owning
#     struct, `p->tag` aliasing) are refused or registered;
#   - round 4: the branch merge keeps a field defined when it was defined
#     before the `if` (or in both arms), so `{ 0 }` / straight-line definitions
#     are not rejected by a later conditional assignment;
#   - `refs = -1` (immortal literal / empty) is skipped;
#   - the same traces under ASan / UBSan, because the failing baselines were
#     heap-use-after-free / double free, not wrong numbers;
#   - the negatives the contract closes: a borrowed view escaping as an owning
#     handle, releasing a borrowed container view (a double free), and a `goto`
#     across an owning `String` scope (a hard error, no silent leak).
#   - SH-117 P-5.2…P-5.6: the `out` / `ref` owning assignment keeps the same
#     retain → hold old → write → release-old order (old value released, alias
#     self-assignment safe), a `ref String` assignment is legal, an explicit
#     release through a `ref` alias is refused, `out` assignments on the error
#     path stay visible to the caller, and the borrowed types allowed as
#     `out` / `ref` (`Str`, `int[]`) keep their immutability / bounds rules.
#     The same positive cases run under ASan / UBSan.
#
# Usage: sh test/ast/p80_retain.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p80_retain.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p80retain.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/retain: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

run_case() {
    name=$1
    if ! "$ctast" --allow-c-boundary "test/ast/p80_retain/$name.ct" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name compile" "$(sed -n '1,4p' "$work/$name.log")"; return
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$work/$name.c" -o "$work/$name" 2>"$work/$name.cc.err"; then
        bad "$name cc" "$(sed -n '1,4p' "$work/$name.cc.err")"; return
    fi
    if [ -s "$work/$name.cc.err" ]; then
        bad "$name warning-free cc" "$(head -2 "$work/$name.cc.err")"; return
    fi
    if ! "$work/$name" >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name run" "non-zero exit: $(head -2 "$work/$name.err")"; return
    fi
    if ! cmp -s "$work/$name.out" "test/ast/p80_retain/expected.$name.out"; then
        bad "$name behaviour" "$(diff -u "test/ast/p80_retain/expected.$name.out" "$work/$name.out" | head -12)"; return
    fi
    for san in address undefined; do
        if ! "$cc" -Wall -Wextra -std=c99 -fsanitize=$san -g "$work/$name.c" \
                -o "$work/$name.$san" 2>"$work/$name.$san.cc.err"; then
            bad "$name -fsanitize=$san cc" "$(head -2 "$work/$name.$san.cc.err")"
        elif ! ASAN_OPTIONS=detect_leaks=0 "$work/$name.$san" >"$work/$name.$san.out" 2>"$work/$name.$san.err"; then
            bad "$name -fsanitize=$san run" "$(cat "$work/$name.$san.err")"
        elif [ -s "$work/$name.$san.err" ]; then
            bad "$name -fsanitize=$san clean stderr" "$(cat "$work/$name.$san.err")"
        elif ! cmp -s "$work/$name.$san.out" "test/ast/p80_retain/expected.$name.out"; then
            bad "$name -fsanitize=$san behaviour" "stdout differs"
        else
            ok "$name -fsanitize=$san"
        fi
    done
    ok "$name (automatic retain / release trace)"
}

run_case retain
run_case jump
run_case field_reassign
run_case struct_lit
run_case multi_decl
run_case field_loop0
run_case field_loop_pre
run_case field_loop_long
run_case field_shadow
run_case field_ptr
run_case field_branch_init
run_case field_branch_straight
run_case field_branch_else
run_case field_branch_two
# P-5.2 / P-5.3 / P-5.4 / P-5.5 (SH-117): the `out` / `ref` owning assignment
# trace, the `ref` assignment, the error-path handover and the borrowed-type
# whitelist. Every positive case also runs under ASan / UBSan (P-5.6).
run_case out_ref_owning
run_case ref_assign
run_case out_error_path
run_case borrow_out_ref

# P-5.5 (SH-117): a write through `ref int[]` stays a checked place. The index
# is out of bounds at run time, so the generated C traps instead of touching
# the caller's array.
trap_case() {
    name=$1
    if ! "$ctast" --allow-c-boundary "test/ast/p80_retain/$name.ct" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name compile" "$(sed -n '1,4p' "$work/$name.log")"; return
    fi
    if ! "$cc" -Wall -Wextra -std=c99 "$work/$name.c" -o "$work/$name" 2>"$work/$name.cc.err"; then
        bad "$name cc" "$(sed -n '1,4p' "$work/$name.cc.err")"; return
    fi
    "$work/$name" >"$work/$name.out" 2>"$work/$name.err"
    if [ $? -eq 0 ]; then
        bad "$name" "did not trap (exit 0)"
    elif ! grep -Fq "slice index 5 out of bounds (length 2)" "$work/$name.err"; then
        bad "$name" "wrong trap: $(head -2 "$work/$name.err")"
    else
        ok "$name (out-of-bounds ref slice write trapped)"
    fi
}
trap_case trap_ref_slice_oob

# J-4b (SH-117): `ref` / `out` may be stored in a longer-lived position; the
# language does not borrow-check that store, so the probe pins the residual --
# the compiler accepts the fixture and ASan reports the use-after-free once the
# owner dies before the stored view. This is the storage negative the contract
# names, not a compile-time rejection.
asan_escape_case() {
    name=$1
    if ! "$ctast" --allow-c-boundary "test/ast/p80_retain/$name.ct" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name compile" "$(sed -n '1,4p' "$work/$name.log")"; return
    fi
    if ! "$cc" -Wall -Wextra -std=c99 -fsanitize=address -g "$work/$name.c" -o "$work/$name" 2>"$work/$name.cc.err"; then
        bad "$name asan cc" "$(sed -n '1,4p' "$work/$name.cc.err")"; return
    fi
    ASAN_OPTIONS=detect_leaks=0 "$work/$name" >"$work/$name.out" 2>"$work/$name.err"
    if [ $? -eq 0 ]; then
        bad "$name" "ran clean; ASan did not catch the stored ref escape"
    elif ! grep -Fq "heap-use-after-free" "$work/$name.err"; then
        bad "$name" "wrong ASan report: $(head -2 "$work/$name.err")"
    else
        ok "$name (J-4b store escape is caught by ASan, not the type checker)"
    fi
}
asan_escape_case escape_ref_store

neg() {
    name=$1; src=$2; pattern=$3; why=$4
    if "$ctast" --allow-c-boundary "$src" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a negative ($why)"
    elif grep -Fq "$pattern" "$work/$name.log"; then
        ok "$name (rejected: $why)"
    else
        bad "$name" "missing diagnostic '$pattern': $(head -2 "$work/$name.log")"
    fi
}
neg neg_escape test/ast/p80_retain/neg_escape.ct \
    "cannot return a borrowed view as an owning string" "escape of a borrowed view"
neg neg_double_free test/ast/p80_retain/neg_double_free.ct \
    "cannot release a borrowed container view" "double free of a borrowed element"
neg neg_goto test/ast/p80_retain/neg_goto.ct \
    "a goto cannot cross an owning String scope" "goto across an owning String scope"
neg field_branch0 test/ast/p80_retain/field_branch0.ct \
    "may be undefined before this assignment" "R6a: branch-defined field reassigned"
neg field_branch_rt test/ast/p80_retain/field_branch_rt.ct \
    "may be undefined before this assignment" "R6a: run-time branch-defined field reassigned"
neg field_switch test/ast/p80_retain/field_switch.ct \
    "may be undefined before this assignment" "R6a: switch-defined field reassigned"
neg field_loop_bare test/ast/p80_retain/field_loop_bare.ct \
    "may be undefined before this assignment" "R6b: bare struct loop reassignment"
neg field_copy test/ast/p80_retain/field_copy.ct \
    "whole-struct assignment" "C-4: whole-struct copy of an owning field"
neg field_goto_struct test/ast/p80_retain/field_goto_struct.ct \
    "a goto cannot cross an owning String scope" "C-4: goto over a struct with an owning field"
# P-5.3 (SH-117): a `ref` alias carries no ownership; the assignment site
# releases the old value, so an explicit release through the alias is refused.
neg neg_ref_release test/ast/p80_retain/neg_ref_release.ct \
    "cannot release through a 'ref' parameter" "P-5.3: explicit release through ref"
# P-5.5 (SH-117): the borrowed types accepted as out/ref keep their own
# immutability and shape rules.
neg neg_out_str_write test/ast/p80_retain/neg_out_str_write.ct \
    "read-only subscript" "P-5.5: write through out Str"
neg neg_ref_slice_const test/ast/p80_retain/neg_ref_slice_const.ct \
    "cannot write to an element of a const slice" "P-5.5: const slice write behind a parameter"
neg neg_ref_array test/ast/p80_retain/neg_ref_array.ct \
    "ref/out parameters cannot be arrays or function pointers" "P-5.5: C array as ref"

[ "$fail" -eq 0 ] && echo "p80_retain: OK"
exit "$fail"
