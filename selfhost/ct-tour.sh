#!/usr/bin/env bash
#
# ct-tour.sh - a hands-on tour: compile a CT program, then walk the bootstrap chain.
#
# What it does, in order:
#   0) shows the sample CT program it is going to compile
#   1) builds L0      -- the frozen C compiler (ctc.c), warning-free
#   2) L0 compiles the sample .ct into C -> shows the generated C, builds it, runs it
#   3) builds L1      -- the same compiler rewritten in CT (selfhost/ctc.ct), compiled by L0
#   4) L1 compiles the same sample -> the output must be byte-identical with L0's
#   5) true self-hosting: L1 compiles itself into L1', and L1' compiles the sample too
#   6) prints where to go next
#
# Usage:
#   bash selfhost/ct-tour.sh                 # tour with the built-in sample
#   bash selfhost/ct-tour.sh path/to/my.ct   # tour with your own CT file
#   CC=clang bash selfhost/ct-tour.sh
#
# Everything it writes lands under $TMPDIR/ct-tour; the repository itself is never
# modified. Exits non-zero if any step fails.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-gcc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-tour"
rm -rf "$work"
mkdir -p "$work"

l0="$work/ctc-l0"           # C compiler built from ctc.c
l1_c="$work/ctc-l1.c"       # selfhost/ctc.ct compiled by L0
l1="$work/ctc-l1"           # that, built
self_c="$work/ctc-self.c"   # selfhost/ctc.ct compiled by L1
self_bin="$work/ctc-self"   # that, built (= L1')

sample="$work/tour_sample.ct"
out_c="$work/tour_sample.c"
out_h="$work/tour_sample.h"
l0_c="$work/from-l0.c"      # L0's output, kept for the byte-for-byte comparison
l0_h="$work/from-l0.h"
bin="$work/tour_sample.bin"

fail=0

banner() {
    printf '\n=============================================================\n%s\n=============================================================\n' "$1"
}

say() {
    printf '%s\n' "$*"
}

note() {
    printf '    %s\n' "$*"
}

# run <what> <cmd...> : echo the command, run it, fail the tour if it returns non-zero
run() {
    local what="$1"
    shift
    printf '\n+ %s\n' "$*"
    if ! "$@"; then
        printf 'FAIL: %s\n' "$what"
        fail=1
        return 1
    fi
    return 0
}

# build <out> <src> : build a compiler source; it must be warning-free
build_clean() {
    local out="$1" src="$2" log="$work/build.log"
    printf '\n+ %s -Wall -Wextra -std=c99 %s -o %s\n' "$CC" "$src" "$out"
    if ! "$CC" -Wall -Wextra -std=c99 "$src" -o "$out" 2>"$log"; then
        printf 'FAIL: %s did not build\n' "$src"
        sed 's/^/    /' "$log"
        fail=1
        return 1
    fi
    if [ -s "$log" ]; then
        printf 'FAIL: %s did not build warning-free\n' "$src"
        sed 's/^/    /' "$log"
        fail=1
        return 1
    fi
    note "ok (warning-free)"
}

# ---------------------------------------------------------------- the sample
if [ "$#" -ge 1 ]; then
    [ -f "$1" ] || { printf 'ct-tour: no such file: %s\n' "$1" >&2; exit 1; }
    sample_abs="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
    own=1
else
    sample_abs="$sample"
    own=0
    cat >"$sample" <<'EOF'
// tour_sample.ct - a tiny CT program: one trait, one struct, one impl, three calls.
// CT is C plus traits: a trait declares the interface, a struct "use"s it, and an
// impl supplies the methods. Compile it with:  bash selfhost/ct-tour.sh
#include <stdio.h>
#include <stdlib.h>

trait Shape {
    int area();
    int scaled(int k);
    void describe(char *tag);
}

struct Rect {
    int w;
    int h;
} use Shape;

impl Shape for Rect {
    int area() {
        return self->w * self->h;
    }
    int scaled(int k) {
        int a = self->area();
        return a * k;
    }
    void describe(char *tag) {
        int a = self->area();
        int s = self->scaled(2);
        printf("%s: %dx%d area=%d scaled2=%d\n", tag, self->w, self->h, a, s);
    }
}

int main() {
    Rect r = { .w = 3, .h = 4 };
    r.describe("rect");
    return 0;
}
EOF
fi

# ---------------------------------------------------------------- 0) the input
banner "0) the CT program you are about to compile"
if [ "$own" -eq 1 ]; then
    say "Using your file: $sample_abs"
else
    say "Using the built-in sample: $sample_abs"
    say "(pass your own file as the first argument to tour it instead)"
fi
printf '\n'
sed 's/^/    /' "$sample_abs"

# ------------------------------------------------------------------- 1) L0
banner "1) build L0 - the frozen C compiler (ctc.c)"
say "L0 is plain C, built by your host compiler. It is frozen: bug fixes only."
build_clean "$l0" ctc.c || exit 1

# ------------------------------------------------------- 2) L0 compiles it
banner "2) L0 compiles your CT program into C"
run "L0 compiling the sample" "$l0" "$sample_abs" -o "$out_c" || exit 1
cp "$out_c" "$l0_c"
cp "$out_h" "$l0_h"
say "Wrote $out_c and $out_h."
say "The .c is self-contained; the .h carries types only (vtables, structs)."
printf '\n'
say "Head of the generated C - the trait became a vtable + iface, and 'use'"
say "added a hidden __shape_vptr field to the struct:"
printf '\n'
sed -n '1,34p' "$out_c" | sed 's/^/    | /'

printf '\n+ %s -Wall -Wextra %s -o %s\n' "$CC" "$out_c" "$bin"
if ! "$CC" -Wall -Wextra "$out_c" -o "$bin"; then
    printf 'FAIL: the generated C did not build\n'
    exit 1
fi
say "Now run it:"
printf '\n+ %s\n' "$bin"
"$bin" || fail=1

# ------------------------------------------------------------------- 3) L1
banner "3) bootstrap: build L1 - the same compiler, written in CT"
say "selfhost/ctc.ct is the compiler rewritten in CT. L0 compiles it:"
run "L0 compiling L1" "$l0" selfhost/ctc.ct -o "$l1_c" || exit 1
build_clean "$l1" "$l1_c" || exit 1
say "L1 is a working compiler binary now - CT source compiled by C source."

# ------------------------------------------------- 4) L1 == L0, byte for byte
banner "4) L1 compiles your program too - and must match L0 byte for byte"
run "L1 compiling the sample" "$l1" "$sample_abs" -o "$out_c" || exit 1
if cmp -s "$out_c" "$l0_c" && cmp -s "$out_h" "$l0_h"; then
    say "IDENTICAL: the C written by L0 and by L1 is the same, byte for byte."
    say "That is the whole point of Phase 1 - one compiler, two languages of origin."
else
    say "DIFFERENT - that is a bug, not a lesson. First lines of the diff:"
    diff "$l0_c" "$out_c" | head -n 20 | sed 's/^/    /'
    fail=1
fi

# ------------------------------------------- 5) true self-hosting: L1 -> L1'
banner "5) true self-hosting: L1 compiles itself into L1'"
run "L1 compiling itself" "$l1" selfhost/ctc.ct -o "$self_c" || exit 1
build_clean "$self_bin" "$self_c" || exit 1
say "L1' is L1's output compiled by L1 - a compiler that built itself. Sanity check:"
printf '\n+ %s %s -o %s\n' "$self_bin" "$sample_abs" "$out_c"
if "$self_bin" "$sample_abs" -o "$out_c" && cmp -s "$out_c" "$l0_c"; then
    note "L1' compiles your program identically as well."
else
    printf 'FAIL: L1%s output differs\n' "'"
    fail=1
fi

# ------------------------------------------------------------------- 6) next
banner "6) where to go next"
say "  your own file      bash selfhost/ct-tour.sh path/to/your.ct"
say "  full test suite    ./test/run.sh                    (build, unit, goldens, examples, errors)"
say "  bootstrap gates    bash selfhost/check-goldens.sh   (L1 vs goldens, plus L1' vs goldens)"
say "  syntax reference   docs/language-spec.md"
say "  runnable examples  examples/01_greeter ... 06_iface_field  (<name>.ct + <name>.expected.out)"
say "  editor comfort     editors/vscode                   (highlighting only, no build step)"
printf '\n'
say "Artifacts from this tour: $work"

banner "VERDICT"
if [ "$fail" -eq 0 ]; then
    say "ct-tour: OK - you compiled CT with C, then CT with CT, and the outputs matched."
else
    say "ct-tour: FAIL - see the messages above."
fi
exit "$fail"
