#!/bin/sh
#
# check-tsan.sh - Phase 41 ThreadSanitizer gate for the atomic runtime.
#
# Independent of check-all.sh (ASan/UBSan and TSan cannot share a process).
# The nightly workflow runs it on Linux; a host whose compiler has no TSan
# support reports SKIP instead of failing.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1
CC="${CC:-cc}"
work="$(mktemp -d "${CT_SHORT_TMP:-/tmp}/cttsan.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

printf 'int main(void) { return 0; }\n' > "$work/tsan.c"
if ! "$CC" -fsanitize=thread "$work/tsan.c" -o "$work/tsan" 2>"$work/tsan.cc"; then
    echo "SKIP: tsan unsupported by $CC"
    sed 's/^/  /' "$work/tsan.cc" | head -5
    exit 0
fi

echo "cc: $CC"
echo
echo "== build ct-ast (frozen seed) =="
# v1-PH-0 S2b: the runtime probes below need the shipped compiler. The
# L0 -> L1 -> L2 walk can no longer build ct-ast after `match`.
if ! CC="$CC" CFLAGS="-Wall -Wextra -std=c99" \
        sh "$root/selfhost/seed-ct.sh" build "$work/ct-ast" >"$work/ast.out" 2>&1; then
    echo "FAIL ct-ast: $(cat "$work/ast.out")"; exit 1
fi

pass=0
fail=0
for d in p41_cancel_flag p41_refcount; do
    if ! "$work/ct-ast" "test/ast/$d/prog.ct" -o "$work/$d.c" 2>"$work/$d.ct.err"; then
        echo "FAIL $d: ct-ast: $(cat "$work/$d.ct.err")"; fail=$((fail + 1)); continue
    fi
    if ! "$CC" -std=c11 -O1 -g -fsanitize=thread -pthread "$work/$d.c" -o "$work/$d.bin" 2>"$work/$d.cc"; then
        echo "FAIL $d: cc: $(cat "$work/$d.cc")"; fail=$((fail + 1)); continue
    fi
    if ! TSAN_OPTIONS=halt_on_error=1:exitcode=66 "$work/$d.bin" >"$work/$d.out" 2>"$work/$d.tsan"; then
        echo "FAIL $d: tsan/run rc=$?"; sed 's/^/  /' "$work/$d.tsan" | head -20; fail=$((fail + 1)); continue
    fi
    if grep -q 'WARNING: ThreadSanitizer' "$work/$d.tsan"; then
        echo "FAIL $d: tsan report"; sed 's/^/  /' "$work/$d.tsan" | head -20; fail=$((fail + 1)); continue
    fi
    if ! diff -u "test/ast/$d/prog.expected.out" "$work/$d.out" >"$work/$d.diff"; then
        echo "FAIL $d: output differs"; sed 's/^/  /' "$work/$d.diff"; fail=$((fail + 1)); continue
    fi
    pass=$((pass + 1))
done
echo
echo "check-tsan: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
