#!/bin/sh
# PH-80 S5b migration (E80-7): the old owning `Str` and its compatibility unit
# are deleted; the built-in `String` / `Str` pair is the only string layer and
# the built-in layer's other consumers (`Vec` / `Option` / `Result`, the
# `Map<String,V>` key block) still behave.
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
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
cc=${CC:-cc}
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/migrate: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

# 1. the compatibility unit is gone, and no built-in source keeps the namespace.
if [ -e lib/core/StrLegacy.h.ct ]; then
    bad "compat unit deleted" "lib/core/StrLegacy.h.ct still exists"
else
    ok "compat unit deleted (lib/core/StrLegacy.h.ct absent)"
fi
if grep -q 'namespace std::str' lib/core/*.ct; then
    bad "no legacy namespace" "$(grep -n 'namespace std::str' lib/core/*.ct | head -2)"
else
    ok "no built-in source declares namespace std::str"
fi
if grep -q '::str_from\|::str_len' lib/core/*.ct; then
    bad "no legacy API spelling" "$(grep -n '::str_from' lib/core/*.ct | head -2)"
else
    ok "no built-in source names the legacy API"
fi

# 2. build mode: a unit using both new types compiles, links and runs; the
#    layer is spliced exactly as any other build.
run_one() {
    name=$1; src=$2; exp=$3; mode=$4
    if [ "$mode" = "build" ]; then
        mkdir -p "$work/$name"
        if ! "$ctast" build --emit-c --allow-c-boundary -I . "$src" -o "$work/$name" \
                >"$work/$name.log" 2>&1; then
            bad "$name build compile" "$(tail -2 "$work/$name.log")"; return
        fi
        if ! "$cc" -Wall -Wextra -std=c99 -I "$work/$name" "$work/$name"/*.c \
                -o "$work/$name/prog" 2>"$work/$name.cc.err"; then
            bad "$name build cc" "$(head -3 "$work/$name.cc.err")"; return
        fi
        if [ -s "$work/$name.cc.err" ]; then
            bad "$name build warning-free" "$(head -2 "$work/$name.cc.err")"; return
        fi
        if ! "$work/$name/prog" >"$work/$name.out" 2>"$work/$name.run.err"; then
            bad "$name build run" "$(head -2 "$work/$name.run.err")"; return
        fi
    else
        if ! "$ctast" --allow-c-boundary "$src" -o "$work/$name.c" \
                >"$work/$name.log" 2>&1; then
            bad "$name compile" "$(tail -2 "$work/$name.log")"; return
        fi
        if ! "$cc" -Wall -Wextra -std=c99 "$work/$name.c" -o "$work/$name" \
                2>"$work/$name.cc.err"; then
            bad "$name cc" "$(head -3 "$work/$name.cc.err")"; return
        fi
        if [ -s "$work/$name.cc.err" ]; then
            bad "$name warning-free" "$(head -2 "$work/$name.cc.err")"; return
        fi
        if ! "$work/$name" >"$work/$name.out" 2>"$work/$name.err"; then
            bad "$name run" "$(head -2 "$work/$name.err")"; return
        fi
    fi
    if ! cmp -s "$work/$name.out" "$exp"; then
        bad "$name behaviour" "$(diff -u "$exp" "$work/$name.out" | head -8)"; return
    fi
    ok "$name"
}

run_one post test/ast/p80_migrate/post.ct test/ast/p80_migrate/expected.post.out build
run_one post_compile test/ast/p80_migrate/post.ct test/ast/p80_migrate/expected.post.out compile
run_one std_smoke test/ast/p80_migrate/std_smoke.ct test/ast/p80_migrate/expected.std_smoke.out compile
run_one embedded test/ast/p80_migrate/embedded.ct test/ast/p80_migrate/expected.embedded.out compile

# 3. negatives: the bare name is a borrow (no release), and the deleted legacy
#    type has no spelling at all.
neg() {
    name=$1; pattern=$2
    if "$ctast" --allow-c-boundary "test/ast/p80_migrate/$name.ct" -o "$work/$name.c" \
            >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a negative"
    elif grep -Fq "$pattern" "$work/$name.log"; then
        ok "$name (rejected: $pattern)"
    else
        bad "$name" "missing diagnostic '$pattern': $(head -2 "$work/$name.log")"
    fi
}
neg neg_release_view "no method 'release'"
neg neg_legacy_gone "qualified type names are not supported"

[ "$fail" -eq 0 ] && echo "p80_migrate: OK"
exit "$fail"
