#!/bin/sh
# PH-81 / S1a: `box<T>` (E81-1, E81-4, E81-5; no `new` yet).
#
#   - E81-1: the box handle is two machine words, the shared `{refs, aux}`
#     header is 8 bytes immediately before the payload, and release runs the
#     payload's owning fields by static type;
#   - E81-4: `at()` is the borrowed view and a release invalidates it; the
#     sanitizer catches the post-release read (S1b fixture);
#   - E81-5: a reference cycle is the author's responsibility.
#
# This S1a probe builds through `box<T>::of`; S1b adds `new T { ... }` and its
# negatives. Usage: sh test/ast/p81_box.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p81_box.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p81box.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p81/box: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

run_case() {
    name=$1
    if ! "$ctast" --allow-c-boundary "test/ast/p81_box/$name.ct" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
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
    if ! cmp -s "$work/$name.out" "test/ast/p81_box/expected.$name.out"; then
        bad "$name behaviour" "$(diff -u "test/ast/p81_box/expected.$name.out" "$work/$name.out" | head -12)"; return
    fi
    for san in address undefined; do
        if ! "$cc" -Wall -Wextra -std=c99 -fsanitize=$san -g "$work/$name.c" \
                -o "$work/$name.$san" 2>"$work/$name.$san.cc.err"; then
            bad "$name -fsanitize=$san cc" "$(head -2 "$work/$name.$san.cc.err")"
        elif ! ASAN_OPTIONS=detect_leaks=0 "$work/$name.$san" >"$work/$name.$san.out" 2>"$work/$name.$san.err"; then
            bad "$name -fsanitize=$san run" "$(head -3 "$work/$name.$san.err")"
        elif [ -s "$work/$name.$san.err" ]; then
            bad "$name -fsanitize=$san clean stderr" "$(head -2 "$work/$name.$san.err")"
        elif ! cmp -s "$work/$name.$san.out" "test/ast/p81_box/expected.$name.out"; then
            bad "$name -fsanitize=$san behaviour" "stdout differs"
        else
            ok "$name -fsanitize=$san"
        fi
    done
    ok "$name (behaviour + sanitizers)"
}

run_case layout
run_case vecbox
run_case boxstr
run_case cycle

[ "$fail" -eq 0 ] && echo "p81_box: OK"
exit "$fail"
