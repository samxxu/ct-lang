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
#   6) the split compiler: L1 builds the multi-unit tree selfhost/src/** into L2,
#      and L2 compiles the sample identically as well
#   7) the shipped entry (Phase 10.7): L2 builds ct-ast from selfhost/ast/main.ct,
#      and that binary answers to `ct`, with `ctc` kept as a compatibility alias
#   8) the incremental cache (Phase 6.3): a second `build` of unchanged sources
#      reuses the artifacts, and a changed dependency invalidates them
#   9) prints where to go next
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

# --------------------------------- 6) the split compiler: L1 builds selfhost/src/**
banner "6) the split compiler: L1 builds selfhost/src/** into L2"
say "selfhost/src/** is the same compiler partitioned across units, written in the"
say "multi-file CT that L1 implements. L1 builds it with a single 'build' command:"
l2src="$work/l2src"
l2_bin="$work/ctc-l2"
rm -rf "$l2src"
mkdir -p "$l2src"

if run "L1 building the split tree" "$l1" build selfhost/src/driver.ct -o "$l2src"; then
    say "The units it wrote:"
    printf '\n'
    ls -1 "$l2src" | sed 's/^/    /'
    printf '\n+ %s -Wall -Wextra -std=c99 %s/*.c -o %s\n' "$CC" "$l2src" "$l2_bin"
    if "$CC" -Wall -Wextra -std=c99 "$l2src"/*.c -o "$l2_bin" 2>"$work/l2.log" &&
       [ ! -s "$work/l2.log" ]; then
        note "ok (warning-free)"
        say "Sanity check: L2 compiles the same sample, and must match L0 identically."
        printf '\n+ %s %s -o %s\n' "$l2_bin" "$sample_abs" "$out_c"
        if "$l2_bin" "$sample_abs" -o "$out_c" && cmp -s "$out_c" "$l0_c"; then
            note "L2 compiles your program identically as well."
        else
            printf 'FAIL: L2%s output differs\n' "'"
            fail=1
        fi
    else
        printf 'FAIL: L2 did not build warning-free\n'
        sed 's/^/    /' "$work/l2.log"
        fail=1
    fi
else
    printf 'FAIL: L1 could not build selfhost/src/**\n'
fi

# ------------------------------------- 7) the shipped entry `ct` (Phase 10.7)
banner "7) the shipped entry: ct-ast answers to 'ct'"
say "Phase 10.7: the installed compiler is built from selfhost/ast/main.ct (ct-ast);"
say "L2 stays as the regression oracle. The identity comes from argv[0]:"
ast_src="$work/astsrc"
ast_bin="$work/ct-ast-bin"
ct_bin="$work/ct"
alias_bin="$work/ctc"
rm -rf "$ast_src"
mkdir -p "$ast_src"

if run "L2 building the AST compiler" "$l2_bin" build selfhost/ast/main.ct -o "$ast_src"; then
    printf '\n+ %s -Wall -Wextra -std=c99 %s/*.c -o %s\n' "$CC" "$ast_src" "$ast_bin"
    if "$CC" -Wall -Wextra -std=c99 "$ast_src"/*.c -o "$ast_bin" 2>"$work/ast.log" &&
       [ ! -s "$work/ast.log" ]; then
        note "ok (warning-free)"
    else
        printf 'FAIL: ct-ast did not build warning-free\n'
        sed 's/^/    /' "$work/ast.log"
        fail=1
    fi
else
    printf 'FAIL: L2 could not build selfhost/ast/main.ct\n'
    fail=1
fi
cp "$ast_bin" "$ct_bin"
cp "$ast_bin" "$alias_bin"

printf '\n+ %s -v\n' "$ct_bin"
ct_ver="$("$ct_bin" -v)"
printf '\n+ %s -v\n' "$alias_bin"
ctc_ver="$("$alias_bin" -v)"
case "$ct_ver" in
    ct\ v*) note "ok: $ct_ver" ;;
    *) printf 'FAIL: expected a "ct v..." version line, got "%s"\n' "$ct_ver"; fail=1 ;;
esac
case "$ctc_ver" in
    ctc\ v*) note "ok: $ctc_ver" ;;
    *) printf 'FAIL: expected a "ctc v..." version line, got "%s"\n' "$ctc_ver"; fail=1 ;;
esac

say "It compiles through both the explicit and the default subcommand:"
printf '\n+ %s compile %s -o %s\n' "$ct_bin" "$sample_abs" "$out_c"
if "$ct_bin" compile "$sample_abs" -o "$out_c" &&
   "$CC" -Wall -Wextra -std=c99 "$out_c" -o "$work/ct-sample.bin" 2>"$work/ct-sample.cc" &&
   "$work/ct-sample.bin" >"$work/ct-sample.out" 2>&1; then
    note "ok: 'ct compile' writes C that builds and runs."
else
    printf 'FAIL: ct compile output did not build or run\n'
    sed 's/^/    /' "$work/ct-sample.cc"
    fail=1
fi
printf '\n+ %s %s -o %s\n' "$ct_bin" "$sample_abs" "$out_c"
if "$ct_bin" "$sample_abs" -o "$out_c" &&
   "$CC" -Wall -Wextra -std=c99 "$out_c" -o "$work/ct-sample.bin" 2>"$work/ct-sample.cc" &&
   "$work/ct-sample.bin" >"$work/ct-sample.out" 2>&1; then
    note "ok: the default subcommand ('ct <file>') behaves the same."
else
    printf 'FAIL: ct <file> output did not build or run\n'
    sed 's/^/    /' "$work/ct-sample.cc"
    fail=1
fi

say "The usage line follows the same identity:"
printf '\n+ %s -h\n' "$ct_bin"
ct_help="$("$ct_bin" -h 2>&1)"
case "$ct_help" in
    usage:\ ct\ *) note "ok: it starts with 'usage: ct'." ;;
    *) printf 'FAIL: expected a "usage: ct ..." line, got "%s"\n' \
           "$(printf '%s' "$ct_help" | head -n 1)"; fail=1 ;;
esac
printf '\n+ %s -h\n' "$alias_bin"
ctc_help="$("$alias_bin" -h 2>&1)"
case "$ctc_help" in
    usage:\ ctc\ *) note "ok: the alias still starts with 'usage: ctc'." ;;
    *) printf 'FAIL: expected a "usage: ctc ..." line, got "%s"\n' \
           "$(printf '%s' "$ctc_help" | head -n 1)"; fail=1 ;;
esac

say "'ct build' drives the multi-file mode under the ct identity:"
ctbuild="$work/ct-id-build"
rm -rf "$ctbuild"
mkdir -p "$ctbuild"
printf '\n+ %s build test/modules/split/main.ct -o %s\n' "$ct_bin" "$ctbuild"
if "$ct_bin" build test/modules/split/main.ct -o "$ctbuild" >"$work/ct-build.out" 2>&1 &&
   "$CC" "$ctbuild"/*.c -o "$work/ct-id.bin" 2>"$work/ct-id.cc" &&
   "$work/ct-id.bin" >"$work/ct-id.out" 2>&1 &&
   cmp -s "$work/ct-id.out" test/modules/split/expected.out; then
    note "ok: it built the multi-unit fixture and the program runs."
else
    printf 'FAIL: ct build did not produce a working multi-unit program\n'
    sed 's/^/    /' "$work/ct-build.out"
    fail=1
fi

say "'ctc compile' and 'ct compile' agree on the same input:"
ct_out="$work/ct-id-ct.c"
ctc_out="$work/ct-id-ctc.c"
printf '\n+ %s compile %s -o %s\n' "$ct_bin" "$sample_abs" "$ct_out"
printf '\n+ %s compile %s -o %s\n' "$alias_bin" "$sample_abs" "$ctc_out"
if "$ct_bin" compile "$sample_abs" -o "$ct_out" &&
   "$alias_bin" compile "$sample_abs" -o "$ctc_out" &&
   cmp -s "$ct_out" "$ctc_out"; then
    note "ok: both identities emit the same C."
else
    printf 'FAIL: ct compile and ctc compile disagree\n'
    fail=1
fi

# ------------------------------------------- 8) the incremental cache (Phase 6.3)
banner "8) the incremental cache: a second build reuses unchanged units"
say "Phase 6.3: 'build' stamps every unit with a key -- its path, mtime, size, the"
say "run's options and its dependencies' keys -- under <outdir>/.ctcache/. When the"
say "key still matches and the .c/.h are on disk, the unit is not regenerated."
cachesrc="$work/cachesrc"
cacheout="$work/cacheout"
rm -rf "$cachesrc" "$cacheout"
mkdir -p "$cachesrc" "$cacheout"
cp test/modules/split/*.ct "$cachesrc/"

# mtime <file> : seconds since the epoch, portable across GNU and BSD stat
mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

printf '\n+ %s build %s -o %s   (cold cache)\n' "$ct_bin" "$cachesrc/main.ct" "$cacheout"
"$ct_bin" build "$cachesrc/main.ct" -o "$cacheout" >/dev/null || fail=1
if [ -f "$cacheout/main.c" ] && [ -f "$cacheout/main.h" ]; then
    # Back-date the artifacts: if a second build rewrites them, their mtime moves.
    touch -t 200001010000 "$cacheout/main.c" "$cacheout/shapes.c" "$cacheout/impl_dog.c"
    before="$(mtime "$cacheout/main.c")"
    printf '\n+ %s build %s -o %s   (warm cache, sources untouched)\n' \
        "$ct_bin" "$cachesrc/main.ct" "$cacheout"
    "$ct_bin" build "$cachesrc/main.ct" -o "$cacheout" >/dev/null || fail=1
    if [ "$(mtime "$cacheout/main.c")" = "$before" ]; then
        note "reused: the artifacts were not regenerated (their mtime is unchanged)"
    else
        printf 'FAIL: an unchanged unit was recompiled\n'
        fail=1
    fi

    printf '\n+ touch -t 201001010000 %s/shapes.h.ct   (a dependency changes)\n' "$cachesrc"
    touch -t 201001010000 "$cachesrc/shapes.h.ct"
    printf '\n+ %s build %s -o %s   (the key no longer matches)\n' \
        "$ct_bin" "$cachesrc/main.ct" "$cacheout"
    "$ct_bin" build "$cachesrc/main.ct" -o "$cacheout" >/dev/null || fail=1
    if [ "$(mtime "$cacheout/main.c")" != "$before" ]; then
        note "invalidated: the touched unit and its dependants were rebuilt"
    else
        printf 'FAIL: a changed source was not rebuilt\n'
        fail=1
    fi
else
    printf 'FAIL: the cold build produced no main.c/main.h\n'
    fail=1
fi

# ------------------------------------------------------------------- 9) next
banner "9) where to go next"
say "  your own file      bash selfhost/ct-tour.sh path/to/your.ct"
say "  full test suite    ./test/run.sh                    (build, unit, goldens, examples, errors)"
say "  bootstrap gates    bash selfhost/check-goldens.sh   (L1 vs goldens, plus L1' vs goldens)"
say "  shipped compiler   selfhost/ast/main.ct             (ct-ast: the ct entry since Phase 10.7)"
say "  split compiler     selfhost/src/**                  (L2, the frozen regression oracle)"
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
