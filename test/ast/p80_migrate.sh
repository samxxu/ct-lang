#!/bin/sh
# PH-80 S5a/S5b migration (E80-7): the old owning `Str` is reachable only as
# `std::str::Str` and the bare `Str` is the new borrowed view; the built-in
# layer's other consumers (`Vec` / `Option` / `Result`, the `Map<String,V>`
# key block) still behave.
#
# The S5b half that deletes the compatibility unit is NOT covered here; the
# probe pins the coexistence contract this stage ships.
#
# Usage: sh test/ast/p80_migrate.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p80_migrate.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p80migrate.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_STD_DIR="$root/lib/std"
export CT_STD_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/migrate: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

# 1. build mode: one unit holds the borrowed `Str` and the qualified legacy type.
mkdir -p "$work/b"
if ! "$ctast" build --emit-c --allow-c-boundary -I . test/ast/p80_migrate/coexist.ct \
        -o "$work/b" >"$work/b.log" 2>&1; then
    bad "coexist build-mode compile" "$(tail -2 "$work/b.log")"
elif ! "$cc" -Wall -Wextra -std=c99 -I "$work/b" "$work"/b/*.c -o "$work/b/prog" \
        2>"$work/b.cc.err"; then
    bad "coexist build-mode cc" "$(head -3 "$work/b.cc.err")"
elif [ -s "$work/b.cc.err" ]; then
    bad "coexist build-mode warning-free" "$(head -2 "$work/b.cc.err")"
elif ! "$work/b/prog" >"$work/b.out" 2>"$work/b.run.err"; then
    bad "coexist build-mode run" "$(head -2 "$work/b.run.err")"
elif ! cmp -s "$work/b.out" test/ast/p80_migrate/expected.coexist.out; then
    bad "coexist build-mode behaviour" "$(diff -u test/ast/p80_migrate/expected.coexist.out "$work/b.out" | head -8)"
else
    ok "coexist build mode (bare Str borrow + qualified legacy owning)"
fi

# 2. compile mode: the compatibility unit is spliced only on `std::str`.
if ! "$ctast" --allow-c-boundary test/ast/p80_migrate/coexist.ct -o "$work/c.c" \
        >"$work/c.log" 2>&1; then
    bad "coexist compile-mode compile" "$(tail -2 "$work/c.log")"
elif ! "$cc" -Wall -Wextra -std=c99 "$work/c.c" -o "$work/c" 2>"$work/c.cc.err"; then
    bad "coexist compile-mode cc" "$(head -3 "$work/c.cc.err")"
elif [ -s "$work/c.cc.err" ]; then
    bad "coexist compile-mode warning-free" "$(head -2 "$work/c.cc.err")"
elif ! "$work/c" >"$work/c.out" 2>"$work/c.run.err" \
     || ! cmp -s "$work/c.out" test/ast/p80_migrate/expected.coexist.out; then
    bad "coexist compile-mode behaviour" "stdout differs"
else
    ok "coexist compile mode (merged layer, namespace saved/restored)"
fi

# 3. the built-in layer's consumers still behave (Vec / Option / Result +
#    Map<String,V>, and an embedded-NUL key through the owning key block).
run_one() {
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
        bad "$name run" "$(head -2 "$work/$name.err")"; return
    fi
    if ! cmp -s "$work/$name.out" "$exp"; then
        bad "$name behaviour" "$(diff -u "$exp" "$work/$name.out" | head -8)"; return
    fi
    ok "$name"
}
run_one std_smoke test/ast/p80_migrate/std_smoke.ct test/ast/p80_migrate/expected.std_smoke.out
run_one embedded test/ast/p80_migrate/embedded.ct test/ast/p80_migrate/expected.embedded.out

# 4. negatives: the bare name is a borrow (no release), the legacy type has no
#    borrow API.
neg() {
    name=$1; pattern=$2
    if "$ctast" --allow-c-boundary "test/ast/p80_migrate/$name.ct" -o "$work/$name.c" \
            >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a negative"
    elif grep -Fq "$pattern" "$work/$name.log"; then
        ok "$name (rejected: $pattern)"
    else
        bad "$name" "missing diagnostic: $(head -2 "$work/$name.log")"
    fi
}
neg neg_release_view "no method 'release'"
neg neg_legacy_borrow_api "no method 'as_str'"

[ "$fail" -eq 0 ] && echo "p80_migrate: OK"
exit "$fail"
