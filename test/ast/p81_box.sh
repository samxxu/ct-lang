#!/bin/sh
# PH-81 / S1: `box<T>` + `new` (E81-1…E81-6).
#
#   - E81-1: the box handle is two machine words, the shared `{refs, aux}`
#     header is 8 bytes immediately before the payload, and release runs the
#     payload's owning fields by static type;
#   - E81-2: `new T { ... }` accepts a named struct only, shares the brace
#     initializer with `T x = { ... }` (positional, designated and nested);
#   - E81-3: `new String` / arrays / containers / built-in handles and a
#     borrowed `Str` payload / field are hard errors;
#   - E81-4: `at()` is the borrowed view and a release invalidates it; the
#     sanitizer catches the post-release read;
#   - E81-5: a reference cycle is the author's responsibility (the probe shows
#     the refs the compiler leaves behind) and no cycle detection is claimed;
#   - E81-6: the same generated code passes ASan/UBSan warning-free, and the
#     five CTC_VERSION sites / README / spec 4.71 / tutorial 17 / package-guide
#     / roadmap / D-016 agree with v0.86.0.
#
# `new` is contextual: `int new;`, `r.new`, a parameter named `new` and
# `new = ...` stay identifiers (ctx.ct); the construction form is refused in a
# global / static initializer because it allocates at run time.
#
# Usage: sh test/ast/p81_box.sh <ct-ast>
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
run_case record
run_case vecbox
run_case boxstr
run_case cycle
run_case ctx

# E81-4: the borrowed view is invalidated by release; ASan must catch it.
if "$ctast" --allow-c-boundary test/ast/p81_box/uaf.ct -o "$work/uaf.c" >"$work/uaf.log" 2>&1 \
   && "$cc" -Wall -Wextra -std=c99 -fsanitize=address -g "$work/uaf.c" -o "$work/uaf" 2>"$work/uaf.cc.err"; then
    if ASAN_OPTIONS=detect_leaks=0 "$work/uaf" >"$work/uaf.out" 2>"$work/uaf.err"; then
        bad "asan sensitivity" "the post-release read was not caught"
    elif grep -Fq "heap-use-after-free" "$work/uaf.err"; then
        ok "asan sensitivity (at() view after release -> heap-use-after-free)"
    else
        bad "asan sensitivity" "ASan did not report heap-use-after-free"
    fi
else
    bad "asan sensitivity build" "$(head -2 "$work/uaf.log" "$work/uaf.cc.err" 2>/dev/null)"
fi

neg() {
    name=$1; pattern=$2; why=$3
    if "$ctast" --allow-c-boundary "test/ast/p81_box/$name.ct" -o "$work/$name.c" >"$work/$name.log" 2>&1; then
        bad "$name" "accepted a negative ($why)"
    elif grep -Fq "$pattern" "$work/$name.log"; then
        ok "$name (rejected: $why)"
    else
        bad "$name" "missing diagnostic '$pattern': $(head -2 "$work/$name.log")"
    fi
}

neg neg_new_string "'new String' / 'new Str' is not supported" "new of a built-in handle"
neg neg_new_int "'new' only accepts a named struct type" "new of a scalar"
neg neg_new_vec "instantiate the generic first and box the value" "new of a container"
neg neg_new_no_brace "needs a brace initializer" "new without a brace list"
neg neg_box_slice "cannot be stored in box<T>" "slice payload"
neg neg_box_str "a borrowed view cannot be boxed" "Str payload"
neg neg_field_str "cannot be a struct field" "borrowed Str field"
neg neg_raw_field "raw implementation fields" "raw .ptr on a box"
neg neg_new_global "only supported in a local initializer" "new at file scope"
neg neg_new_static "cannot initialize a static object" "new in a static local"

# E81-6: the written contract and the version落点 stay in step.
for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
         selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
    if grep -q '#define CTC_VERSION "0.86.0"' "$f"; then
        ok "$f CTC_VERSION 0.86.0"
    else
        bad "$f CTC_VERSION is not 0.86.0"
    fi
done
if grep -q 'v0\.86\.0' README.md && grep -q 'v0\.86\.0' docs/README.md; then
    ok "README / docs/README carry v0.86.0"
else
    bad "README version"
fi
if grep -q '^### 4\.71 .*box<T>' docs/language-spec.md; then
    ok "spec has the box<T>/new section (4.71)"
else
    bad "spec section 4.71 missing"
fi
if grep -q '^## 17\. .*box<T>' docs/tutorial.md; then
    ok "tutorial has the box<T>/new section (17)"
else
    bad "tutorial section 17 missing"
fi
if grep -q '`box<T>`' docs/package-guide.md && grep -q '不是 C ABI' docs/package-guide.md; then
    ok "package-guide records the box C ABI boundary"
else
    bad "package-guide box C ABI note"
fi
if grep -q 'Phase 81' docs/roadmap.md && grep -q 'v0\.81\.0' docs/roadmap.md; then
    ok "roadmap lists Phase 81 with v0.81.0"
else
    bad "roadmap Phase 81 row"
fi
if [ -f docs/decisions/D-016.md ] && grep -q '^## 8' docs/decisions/D-016.md; then
    ok "D-016 records the PH-81 design decision"
else
    bad "D-016 missing"
fi

[ "$fail" -eq 0 ] && echo "p81_box: OK"
exit "$fail"
