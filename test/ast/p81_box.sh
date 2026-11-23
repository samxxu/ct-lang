#!/bin/sh
# PH-81 / S1: `Box<T>` + `new` (E81-1…E81-6), plus the LANG-24 Stage A alias.
#
#   - E81-1: the Box handle is two machine words, the shared `{refs, aux}`
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
#     / roadmap / D-016 agree with v0.88.3.
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
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
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
run_case alias
run_case ident

# LANG-24 Stage A: `box<T>` is the deprecated alias. Each use prints exactly one
# warning; the canonical `Box<T>` spelling is silent. The generated symbols stay
# `Box_*`, so the alias is a parse-level only spelling (v1.1 removes it).
if "$ctast" --allow-c-boundary test/ast/p81_box/alias.ct -o "$work/alias.warn.c" \
        >"$work/alias.warn.log" 2>&1; then
    nwarn=$(grep -cF "warning: 'box<T>' is deprecated; write 'Box<T>'" "$work/alias.warn.log")
    if [ "$nwarn" -eq 5 ]; then
        ok "box<T> alias warns once per use (5 alias tokens -> 5 warnings)"
    else
        bad "box<T> alias warning count" "expected 5, got $nwarn: $(head -4 "$work/alias.warn.log")"
    fi
else
    bad "box<T> alias compile" "$(head -4 "$work/alias.warn.log")"
fi
if "$ctast" --allow-c-boundary test/ast/p81_box/record.ct -o "$work/record.nowarn.c" \
        >"$work/record.nowarn.log" 2>&1; then
    if grep -Fq "deprecated" "$work/record.nowarn.log"; then
        bad "Box<T> canonical spelling silent" "$(head -4 "$work/record.nowarn.log")"
    else
        ok "Box<T> canonical spelling does not warn"
    fi
else
    bad "Box<T> canonical compile" "$(head -4 "$work/record.nowarn.log")"
fi

# LANG-24 Stage A: the generated C symbols are `Box_<payload>__*`; no old
# `box_Record` / `ct_box_hdr` spelling may survive.
if "$ctast" --allow-c-boundary test/ast/p81_box/record.ct -o "$work/record.sym.c" \
        >"$work/record.sym.log" 2>&1; then
    if grep -q 'Box_Record__new' "$work/record.sym.c" \
       && grep -q 'Box_Record__payload_release' "$work/record.sym.c"; then
        ok "--emit-c uses Box_Record__new / Box_Record__payload_release"
    else
        bad "--emit-c Box_* symbols" "$(grep -E 'Record__(new|payload_release)' "$work/record.sym.c" | head -3)"
    fi
    if grep -q 'box_Record' "$work/record.sym.c"; then
        bad "--emit-c has no box_Record" "$(grep -m1 'box_Record' "$work/record.sym.c")"
    else
        ok "--emit-c has no box_Record"
    fi
    if grep -q 'ct_box_hdr' "$work/record.sym.c"; then
        bad "--emit-c has no ct_box_hdr" "$(grep -m1 'ct_box_hdr' "$work/record.sym.c")"
    else
        ok "--emit-c has no ct_box_hdr"
    fi
else
    bad "--emit-c symbol fixture" "$(head -4 "$work/record.sym.log")"
fi

# LANG-24 Stage A: the built-in unit declares the PascalCase template.
if grep -q '^pub struct Box<T>' lib/core/Box.h.ct \
   && grep -q '^impl<T> Box<T>' lib/core/Box.h.ct; then
    ok "lib/core/Box.h.ct declares pub struct Box<T> and impl<T> Box<T>"
else
    bad "lib/core/Box.h.ct Box<T> declaration" "$(grep -n 'struct Box\|impl<T> Box' lib/core/Box.h.ct)"
fi

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
neg neg_box_slice "cannot be stored in Box<T>" "slice payload"
neg neg_box_str "a borrowed view cannot be boxed" "Str payload"
neg neg_field_str "cannot be a struct field" "borrowed Str field"
neg neg_raw_field "raw implementation fields" "raw .ptr on a box"
neg neg_new_global "only supported in a local initializer" "new at file scope"
neg neg_new_static "cannot initialize a static object" "new in a static local"

# E81-6: the written contract and the version落点 stay in step.
for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
         selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
    if grep -q '#define CTC_VERSION "0.88.3"' "$f"; then
        ok "$f CTC_VERSION 0.88.3"
    else
        bad "$f CTC_VERSION is not 0.88.3"
    fi
done
if grep -q 'v0\.88\.3' README.md && grep -q 'v0\.88\.3' docs/README.md; then
    ok "README / docs/README carry v0.88.3"
else
    bad "README version"
fi
if grep -q '^### 4\.71 .*Box<T>' docs/language-spec.md; then
    ok "spec has the Box<T>/new section (4.71)"
else
    bad "spec section 4.71 missing"
fi
if grep -q '^## 17\. .*Box<T>' docs/tutorial.md; then
    ok "tutorial has the Box<T>/new section (17)"
else
    bad "tutorial section 17 missing"
fi
if grep -q '`Box<T>`' docs/package-guide.md && grep -q '不是 C ABI' docs/package-guide.md; then
    ok "package-guide records the Box C ABI boundary"
else
    bad "package-guide Box C ABI note"
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
