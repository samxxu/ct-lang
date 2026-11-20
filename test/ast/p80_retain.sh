#!/bin/sh
# PH-80 SH-102 (D-013 §3): the automatic retain / release contract.
#
#   - the refcount trace at every destination the contract names: a by-value
#     `String` / `U16String` parameter, a local copy, a field assignment, a
#     move / non-local return, a reassignment and a scope exit;
#   - `refs = -1` (immortal literal / empty) is skipped;
#   - the same trace under ASan / UBSan, because the failing baseline was a
#     heap-use-after-free, not a wrong number;
#   - the two negatives the contract closes: a borrowed view escaping as an
#     owning handle, and releasing a borrowed container view (a double free).
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

if ! "$ctast" --allow-c-boundary test/ast/p80_retain/retain.ct -o "$work/retain.c" >"$work/retain.log" 2>&1; then
    bad "retain compile" "$(sed -n '1,4p' "$work/retain.log")"
elif ! "$cc" -Wall -Wextra -std=c99 "$work/retain.c" -o "$work/retain" 2>"$work/retain.cc.err"; then
    bad "retain cc" "$(sed -n '1,4p' "$work/retain.cc.err")"
elif [ -s "$work/retain.cc.err" ]; then
    bad "retain warning-free cc" "$(head -2 "$work/retain.cc.err")"
elif ! "$work/retain" >"$work/retain.out" 2>"$work/retain.err"; then
    bad "retain run" "non-zero exit: $(head -2 "$work/retain.err")"
elif ! cmp -s "$work/retain.out" test/ast/p80_retain/expected.retain.out; then
    bad "retain behaviour" "$(diff -u test/ast/p80_retain/expected.retain.out "$work/retain.out" | head -12)"
else
    ok "retain (automatic retain / release trace)"
fi

for san in address undefined; do
    if ! "$cc" -Wall -Wextra -std=c99 -fsanitize=$san -g "$work/retain.c" \
            -o "$work/retain.$san" 2>"$work/retain.$san.cc.err"; then
        bad "retain -fsanitize=$san cc" "$(head -2 "$work/retain.$san.cc.err")"
    elif ! ASAN_OPTIONS=detect_leaks=0 "$work/retain.$san" >"$work/retain.$san.out" 2>"$work/retain.$san.err"; then
        bad "retain -fsanitize=$san run" "$(head -3 "$work/retain.$san.err")"
    elif [ -s "$work/retain.$san.err" ]; then
        bad "retain -fsanitize=$san clean stderr" "$(head -2 "$work/retain.$san.err")"
    elif ! cmp -s "$work/retain.$san.out" test/ast/p80_retain/expected.retain.out; then
        bad "retain -fsanitize=$san behaviour" "stdout differs"
    else
        ok "retain -fsanitize=$san"
    fi
done

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

[ "$fail" -eq 0 ] && echo "p80_retain: OK"
exit "$fail"
