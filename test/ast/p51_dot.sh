#!/bin/sh
# PH-51 probe: `.` on a pointer receiver is L51-1 (D51-1 selection A); `->`
# and the legitimate `.` receivers (struct value, interface pointer, type host)
# are untouched (E51-1/2/3).
#
# E51-1: the generic (`Vec<int> *`) and non-generic (`struct S *`) forms exit 1
#        with the L51-1 wording and leave no `.c`.
# E51-2: the `->` fixture (plus a value `.` and an interface-pointer `.`) runs
#        with the same output; the generated C is byte-identical to the HEAD
#        snapshot (checked manually; the gate pins the emitted argument forms).
# E51-3: the product must contain `S_bump(p,` / `Vec_int_push(vp,` and never
#        `S_bump(&p` / `Vec_int_push(&p`.
set -u
ctast=${1:?usage: p51_dot.sh <ct-ast> [cc]}
cc=${2:-cc}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p51-dot.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
fail_msg() { echo "FAIL $*" >&2; fail=$((fail + 1)); }
ok_msg() { echo "ok $*"; }

# --- E51-2/E51-3: the arrow / value / interface-path fixture ---------------
if ! ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
        test/ast/p51_arrow_ok/prog.ct -o "$tmp/arrow.c" ) \
        >"$tmp/arrow.out" 2>"$tmp/arrow.err"; then
    fail_msg "the arrow fixture did not compile:"; sed 's/^/  /' "$tmp/arrow.err" >&2
elif ! "$cc" -Wall -Wextra -std=c99 "$tmp/arrow.c" -o "$tmp/arrow.bin" 2>"$tmp/arrow.cc"; then
    fail_msg "the arrow product did not build:"; sed 's/^/  /' "$tmp/arrow.cc" >&2
elif [ -s "$tmp/arrow.cc" ]; then
    fail_msg "the arrow product is not warning-free:"; sed 's/^/  /' "$tmp/arrow.cc" >&2
elif ! "$tmp/arrow.bin" >"$tmp/arrow.txt" 2>&1; then
    fail_msg "the arrow product exited non-zero"
elif ! ( cd "$root" && diff -u test/ast/p51_arrow_ok/prog.expected.out "$tmp/arrow.txt" ) \
        >"$tmp/arrow.diff"; then
    fail_msg "the arrow fixture output drifted:"; head -12 "$tmp/arrow.diff" >&2
elif ! grep -Fq 'S_bump(p, 2);' "$tmp/arrow.c"; then
    fail_msg "the non-generic arrow call does not pass the pointer"
elif ! grep -Fq 'Vec_int_push(vp, 4);' "$tmp/arrow.c"; then
    fail_msg "the generic arrow call does not pass the pointer"
elif grep -Fq 'S_bump(&p' "$tmp/arrow.c"; then
    fail_msg "the non-generic arrow product still takes '&p'"
elif grep -Fq 'Vec_int_push(&p' "$tmp/arrow.c"; then
    fail_msg "the generic arrow product still takes '&p'"
elif ! grep -Fq 'S_bump(&s, 1);' "$tmp/arrow.c"; then
    fail_msg "the value-receiver '.' call no longer takes the value's address"
elif ! grep -Fq 'ip.vt->show' "$tmp/arrow.c" && ! grep -Fq 'ip->vt->show' "$tmp/arrow.c"; then
    fail_msg "the interface-pointer '.' call is no longer a vt dispatch"
else
    ok_msg "E51-2/E51-3 arrow and value/interface '.' paths unchanged"
fi

# --- E51-1: the rejected pointer-receiver spellings ------------------------
p51_neg() {
    name=$1
    wtext=$2
    wpos=$3
    if ( cd "$root" && CT_STD_DIR="$root/lib/std" "$ctast" \
            "test/ast/errors/$name.ct" -o "$tmp/neg.c" ) \
            >"$tmp/neg.out" 2>"$tmp/neg.err"; then
        fail_msg "$name: expected a diagnostic, got exit 0"
    elif ! grep -Fq "$wtext" "$tmp/neg.err"; then
        fail_msg "$name: $(cat "$tmp/neg.err")"
    elif grep -Fiq 'undeclared' "$tmp/neg.err"; then
        fail_msg "$name: fell back to 'undeclared': $(cat "$tmp/neg.err")"
    elif [ "$(grep -c 'error:' "$tmp/neg.err")" -ne 1 ]; then
        fail_msg "$name: expected exactly one diagnostic: $(cat "$tmp/neg.err")"
    elif ! grep -Fq "test/ast/errors/$name.ct:$wpos: error:" "$tmp/neg.err"; then
        fail_msg "$name: expected the diagnostic at $wpos: $(cat "$tmp/neg.err")"
    elif [ -e "$tmp/neg.c" ]; then
        fail_msg "$name: a rejected receiver still wrote a product"
    else
        ok_msg "$name ($wpos)"
    fi
}
p51_neg p51_dot_generic "'.' cannot call method 'push' through a pointer receiver; use '->push()'" 9:7
p51_neg p51_dot_inherent "'.' cannot call method 'bump' through a pointer receiver; use '->bump()'" 18:7
p51_neg p51_dot_trait "'.' cannot call method 'value' through a pointer receiver; use '->value()'" 22:14

echo "p51/dot: $fail failure(s)"
[ "$fail" -eq 0 ]
