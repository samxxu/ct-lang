#!/bin/sh
# PH-80 S5a-1: `String` / `Str` layout and the refcount contract (E80-1, D-013 §3).
#
#   - the 16-byte handle and the 8-byte header (with `_Static_assert`s in the C);
#   - `refs = -1` is immortal: literal/empty release is a no-op and frees nothing;
#   - the explicit copy / retain / release trace at parameter, return, field,
#     `Vec` element, `own` / `delete` and literal positions;
#   - the borrowed `Str` has no Drop and the raw `.ptr` field is closed.
#
# Usage: sh test/ast/p80_layout.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p80_layout.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p80layout.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/layout: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

run_fixture() {
    name=$1; src=$2; exp=$3
    if ! "$ctast" --allow-c-boundary "$src" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
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
    if ! cmp -s "$work/$name.out" "$exp"; then
        bad "$name behaviour" "$(diff -u "$exp" "$work/$name.out" | head -8)"; return
    fi
    ok "$name (layout + refcount trace)"
}

run_fixture abi test/ast/p80_layout/abi.ct test/ast/p80_layout/expected.abi.out
run_fixture trace test/ast/p80_layout/trace.ct test/ast/p80_layout/expected.trace.out

neg() {
    name=$1; src=$2; pattern=$3
    if "$ctast" --allow-c-boundary "$src" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a negative"
    elif grep -Fq "$pattern" "$work/$name.log"; then
        ok "$name (rejected: $pattern)"
    else
        bad "$name" "missing diagnostic '$pattern': $(head -2 "$work/$name.log")"
    fi
}
neg neg_borrow_no_drop test/ast/p80_layout/neg_borrow_no_drop.ct "does not use trait 'Drop'"
neg neg_ptr_read test/ast/p80_layout/neg_ptr_read.ct "raw implementation field"

# Sanitizer: the same trace under ASan/UBSan, and a deliberate post-free read
# that must be caught (the sanitizer gate would be vacuous otherwise).
for san in address undefined; do
    if ! "$cc" -Wall -Wextra -std=c99 -fsanitize=$san -g "$work/trace.c" \
            -o "$work/trace.$san" 2>"$work/trace.$san.cc.err"; then
        bad "trace -fsanitize=$san cc" "$(head -2 "$work/trace.$san.cc.err")"
    elif ! ASAN_OPTIONS=detect_leaks=0 "$work/trace.$san" >"$work/trace.$san.out" 2>"$work/trace.$san.err"; then
        bad "trace -fsanitize=$san run" "$(head -3 "$work/trace.$san.err")"
    elif [ -s "$work/trace.$san.err" ]; then
        bad "trace -fsanitize=$san clean stderr" "$(head -2 "$work/trace.$san.err")"
    elif ! cmp -s "$work/trace.$san.out" test/ast/p80_layout/expected.trace.out; then
        bad "trace -fsanitize=$san behaviour" "stdout differs"
    else
        ok "trace -fsanitize=$san"
    fi
done
if "$ctast" --allow-c-boundary test/ast/p80_layout/uaf.ct -o "$work/uaf.c" >"$work/uaf.log" 2>&1 \
   && "$cc" -Wall -Wextra -std=c99 -fsanitize=address -g "$work/uaf.c" -o "$work/uaf" 2>"$work/uaf.cc.err"; then
    if ASAN_OPTIONS=detect_leaks=0 "$work/uaf" >"$work/uaf.out" 2>"$work/uaf.err"; then
        bad "asan sensitivity" "the post-free read was not caught"
    elif grep -Fq "heap-use-after-free" "$work/uaf.err"; then
        ok "asan sensitivity (post-free read -> heap-use-after-free)"
    else
        bad "asan sensitivity" "ASan did not report heap-use-after-free"
    fi
else
    bad "asan sensitivity build" "$(head -2 "$work/uaf.log" "$work/uaf.cc.err" 2>/dev/null)"
fi

[ "$fail" -eq 0 ] && echo "p80_layout: OK"
exit "$fail"
