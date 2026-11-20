#!/bin/sh
# PH-80 SH-102 (D-013 §3): the automatic retain / release contract.
#
#   - the refcount trace at every destination the contract names: a by-value
#     `String` / `U16String` parameter, a local copy, a field assignment, a
#     move / non-local return, a reassignment and a scope exit;
#   - round 2: nested `break` / `continue` release every scope they leave, a
#     field reassignment releases the old value, a struct literal retains an
#     owning element, and every declarator of a multi-declarator line retains;
#   - `refs = -1` (immortal literal / empty) is skipped;
#   - the same traces under ASan / UBSan, because the failing baselines were
#     heap-use-after-free / double free, not wrong numbers;
#   - the negatives the contract closes: a borrowed view escaping as an owning
#     handle, releasing a borrowed container view (a double free), and a `goto`
#     across an owning `String` scope (a hard error, no silent leak).
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
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
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
            bad "$name -fsanitize=$san run" "$(head -3 "$work/$name.$san.err")"
        elif [ -s "$work/$name.$san.err" ]; then
            bad "$name -fsanitize=$san clean stderr" "$(head -2 "$work/$name.$san.err")"
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

[ "$fail" -eq 0 ] && echo "p80_retain: OK"
exit "$fail"
