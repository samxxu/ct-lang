#!/usr/bin/env bash
#
# check-archive.sh - the Phase 2+ diff oracle for the self-hosted compiler.
#
# Phase 0.3 moved the namespaces / multi-file / import / Drop / #line and
# warning-diagnostic fixtures out of ctc.c into test/archive/ and left them there,
# unrun, as the byte-for-byte baseline for redoing those features in CT. This
# script is that baseline, turned into a ratchet:
#
#   PASS        in the baseline and matching
#   NEW         matching but not in the baseline -> promote it below
#   PENDING     not matching yet -> a slice still to do
#   REGRESSION  in the baseline but no longer matching -> the verdict is FAIL
#
# Promote a case in the same commit that makes it match. Never demote one to turn
# the script green: a baseline case that stops matching is a real regression.
#
# The goldens are self-describing, which is what makes a byte-for-byte diff
# possible at all:
#   * line 1 of a *.expected.c records the input path the old compiler was invoked
#     with ("from <path> -- do not edit"), and the provenance banner is copied
#     into the output. So each case is staged in a temp tree at exactly that path
#     and compiled with exactly that relative path -- otherwise line 1 would
#     differ and nothing could ever match.
#   * the *.expected.h include guard is derived from the output basename, so the
#     output is named after the case.
#
# The compiler under test is L2, not L1. Steps 1-3 build L1 (= selfhost/ctc.ct
# compiled by L0); from Phase 3 on, L1 is a frozen seed and every new capability
# is implemented in the multi-unit tree selfhost/src/**, which L1 builds into L2.
# Step 3b does exactly that and then hands L2 to groups 4-7, so promoting a case
# here means "the current compiler source restores this feature". L1's own corpus
# is still checked byte for byte by check-goldens.sh steps 4-5, and its agreement
# with L2 on the split tree by step 7 there.
#
# Groups:
#   4  single-unit goldens   test/archive/cases/*.ct   full byte diff of .c and .h
#   5  diagnostics           test/archive/errors/*.ct  non-zero exit + message
#   6  multi-unit goldens    test/archive/{import,multifile}/
#        one .h/.c pair per unit, produced by a single `ctc build <unit.ct>... -o
#        <dir>` invocation over the whole directory (multi-file mode: the .c
#        includes its own .h). One build per directory; each unit is staged at the
#        path its golden records, exactly as in group 4.
#   7  designed cases        test/modules/*/{build,compile}.args
#        no archive oracle backs these: they pin semantics added after the
#        over-reach strip (`foo.h.ct` file names, `-I` import roots, `--line` /
#        `--no-line`, `--diagnostics` leak warnings). Each fixture dir holds a
#        build.args or compile.args (the arguments after `build`, or the whole
#        compile-mode line, repo-relative) plus its own *.expected.c/*.expected.h
#        to byte-diff and, for positive cases, an expected.out to link-and-run
#        against. Optional expected.stderr / expected.stdout byte-diff what the
#        *compiler* printed (expected.out is the linked program's output), and an
#        expected.noartifacts marker asserts a failing run left no .c/.h behind.
#        A fixture with an expected.err is a negative case (the command must fail
#        with that message).
#
# Usage:  bash selfhost/check-archive.sh        (or ./selfhost/check-archive.sh once +x)
#         CC=clang bash selfhost/check-archive.sh
#
# Exits non-zero only when a baseline case regressed. PENDING cases are the
# remaining climb and do NOT fail the run.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-gcc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-archive"
rm -rf "$work"
mkdir -p "$work"

l0="$work/ctc-l0"
l1_c="$work/ctc-l1.c"
l1="$work/ctc-l1"

# Cases this compiler already reproduces. Keep in lockstep with the commit that
# promotes a case from PENDING to PASS.
baseline_cases="
19_namespace
20_namespace_nested
22_drop
"
baseline_errors="
ns_path_nested
namespace_bad_path
namespace_path_too_long
ns_qualified_name
drop_reserved
drop_impl_undefined_struct
drop_impl_not_used
drop_impl_no_method
drop_impl_no_body
too_many_warnings
"
baseline_multi="
test/archive/import/app
test/archive/import/shapes
test/archive/multifile/app
test/archive/multifile/calc
"
# designed cases: no archive oracle backs these, they pin the new semantics of
# `foo.h.ct` file names, `-I` import roots, the `--line` / `--no-line` overrides
# of the per-mode `#line` default, the `--diagnostics` leak warnings and the
# multi-error recovery, byte-diffed against their own goldens plus an end-to-end
# run (see group 7).
# `split` additionally pins the cross-unit OO contract the selfhost split relies
# on: a `pub trait`/`pub struct` in a header unit, its `impl` (with a `static`
# vtable) in another unit, and a third unit dispatching through an
# accessor-returned pointer.
baseline_designed="
hdr
inc
inc_missing
precedence
split
noline
line
leak
leak_json
leak_build
multi_err
multi_err_build
dup_trait
dup_struct
sig_mismatch
sig_mismatch_json
"

in_list() {
    case " $(echo $2) " in
        *" $1 "*) return 0 ;;
        *) return 1 ;;
    esac
}

banner() {
    printf '\n=============================================================\n%s\n=============================================================\n' "$1"
}

run() {
    local label="$1"
    shift
    printf '\n--- %s\n+ %s\n' "$label" "$*"
    "$@"
    return $?
}

first_line() {
    printf '%s' "$1" | head -n 1
}

# Byte-compare two generated files, ignoring the compiler version in the
# provenance banner. The archive was produced by an older build (v0.0.1), and a
# version bump does not change generated code — only that one token is
# normalized, everything else must still match byte for byte.
same_modulo_version() {
    sed 's/\(Generated by ctc\) v[0-9][0-9.]*/\1 vX/' "$1" >"$work/norm-a"
    sed 's/\(Generated by ctc\) v[0-9][0-9.]*/\1 vX/' "$2" >"$work/norm-b"
    cmp -s "$work/norm-a" "$work/norm-b"
}

# ---------------------------------------------------------------- 1) L0
banner "1) build L0 (ctc.c) warning-free"
if ! run "build L0" "$CC" -Wall -Wextra -std=c99 ctc.c -o "$l0"; then
    echo "FATAL: L0 did not build; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------- 2) L0 compiles the compiler
banner "2) L0 compiles the self-hosted compiler (selfhost/ctc.ct -> $l1_c)"
if ! run "L0 compile selfhost/ctc.ct" "$l0" selfhost/ctc.ct -o "$l1_c"; then
    echo "FATAL: L0 could not compile selfhost/ctc.ct; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------------------- 3) build it
banner "3) build it warning-free ($l1_c -> $l1)"
if ! run "build the self-hosted compiler" "$CC" -Wall -Wextra -std=c99 "$l1_c" -o "$l1"; then
    echo "FATAL: the self-hosted compiler did not build; cannot continue." >&2
    exit 1
fi

fail=0
l2_ok=0

# ------------------------------------------------- 3b) build L2 (the compiler under test)
# Steps 1-3 build L1 = selfhost/ctc.ct compiled by L0. Since Phase 3 L1 is a
# *frozen seed*: new capabilities are implemented in the multi-unit tree
# selfhost/src/**, which L1 builds into L2. The ratchet below therefore runs L2,
# not L1 -- that is what "the compiler restores this feature" now means. L1's own
# corpus (test/cases) is still checked by check-goldens.sh steps 4-5.
banner "3b) L2 built by L1 from the split tree (selfhost/src/**)"
l2src="$work/l2src"
l2="$work/ctc-l2"
l2_log="$work/ctc-l2.log"
rm -rf "$l2src"
mkdir -p "$l2src"

if ! run "L1 builds the split tree" "$l1" build selfhost/src/driver.ct -o "$l2src"; then
    printf 'FAIL: L1 could not build selfhost/src/**\n'
    fail=1
elif ! run "build L2" "$CC" -Wall -Wextra -std=c99 "$l2src"/*.c -o "$l2" 2>"$l2_log" ||
     [ -s "$l2_log" ]; then
    printf 'FAIL: L2 did not build warning-free:\n'
    sed 's/^/    /' "$l2_log"
    fail=1
else
    printf 'OK: L2 built warning-free from the split tree -- the ratchet runs L2\n'
    l2_ok=1
fi

# ------------------------------------------- 4) single-unit goldens
banner "4) single-unit goldens (test/archive/cases/*.ct)"
npass=0; nnew=0; npending=0; nregress=0

for exp_c in test/archive/cases/*.expected.c; do
    base="$(basename "$exp_c" .expected.c)"
    exp_h="test/archive/cases/$base.expected.h"
    src="test/archive/cases/$base.ct"

    if [ ! -f "$src" ]; then
        printf 'SKIP        %s  (no %s)\n' "$base" "$src"
        continue
    fi

    rel="$(sed -n '1s/^.* from \(.*\) -- do not edit.*$/\1/p' "$exp_c")"
    if [ -z "$rel" ]; then
        printf 'SKIP        %s  (its golden records no provenance path)\n' "$base"
        continue
    fi

    # stage the input at the exact path the golden was produced from, and compile
    # with that relative path so the banner matches too
    stage="$work/$base"
    mkdir -p "$stage/$(dirname "$rel")" "$stage/_out"
    cp "$src" "$stage/$rel"
    outc="$stage/_out/$base.c"
    outh="$stage/_out/$base.h"
    rm -f "$outc" "$outh"

    err="$(cd "$stage" && "$l2" "$rel" -o "$outc" 2>&1 >/dev/null)"
    rc=$?

    matched=0
    if [ "$rc" -eq 0 ] && [ -f "$outc" ] && [ -f "$outh" ] &&
       same_modulo_version "$outc" "$exp_c" && same_modulo_version "$outh" "$exp_h"; then
        matched=1
    fi

    if in_list "$base" "$baseline_cases"; then
        if [ "$matched" -eq 1 ]; then
            printf 'PASS        %s\n' "$base"
            npass=$((npass + 1))
        else
            printf 'REGRESSION  %s' "$base"
            if [ "$rc" -ne 0 ]; then
                printf '  (exit %d: %s)' "$rc" "$(first_line "$err")"
            else
                printf '  (.c or .h no longer matches the golden)'
            fi
            printf '\n'
            nregress=$((nregress + 1))
            fail=1
        fi
    else
        if [ "$matched" -eq 1 ]; then
            printf 'NEW         %s  (promote it in the baseline)\n' "$base"
            nnew=$((nnew + 1))
        else
            printf 'PENDING     %s' "$base"
            if [ "$rc" -ne 0 ] && [ -n "$err" ]; then
                printf '  (%s)' "$(first_line "$err")"
            else
                printf '  (output differs from the golden)'
            fi
            printf '\n'
            npending=$((npending + 1))
        fi
    fi
done

# ---------------------------------------------------------- 5) diagnostics
banner "5) diagnostics (test/archive/errors/*.ct)"
epass=0; enew=0; epending=0; eregress=0

for ct in test/archive/errors/*.ct; do
    base="$(basename "$ct" .ct)"
    expected="test/archive/errors/$base.expected-err"
    log="$work/$base.err"

    "$l2" "$ct" -o "$work/$base.out.c" 2>"$log"
    rc=$?

    matched=0
    # same convention as test/run.sh: non-zero exit, every diagnostic carries a
    # position, and every non-comment line of the expected file appears in stderr
    if [ "$rc" -ne 0 ] && grep -Eq ':[0-9]+:[0-9]+: error: ' "$log"; then
        matched=1
        if [ -f "$expected" ]; then
            while IFS= read -r want; do
                case "$want" in '' | '#'*) continue ;; esac
                if ! grep -Fq -- "$want" "$log"; then
                    matched=0
                    break
                fi
            done <"$expected"
        fi
    fi

    if in_list "$base" "$baseline_errors"; then
        if [ "$matched" -eq 1 ]; then
            printf 'PASS        %s\n' "$base"
            epass=$((epass + 1))
        else
            printf 'REGRESSION  %s  (got: %s)\n' "$base" "$(first_line "$(cat "$log")")"
            eregress=$((eregress + 1))
            fail=1
        fi
    else
        if [ "$matched" -eq 1 ]; then
            printf 'NEW         %s  (promote it in the baseline)\n' "$base"
            enew=$((enew + 1))
        else
            printf 'PENDING     %s  (got: %s)\n' "$base" "$(first_line "$(cat "$log")")"
            epending=$((epending + 1))
        fi
    fi
done

# --------------------------------------------------------- 6) multi-unit
banner "6) multi-unit goldens (one 'build' per directory: test/archive/{import,multifile})"
kpass=0; knew=0; kpending=0; kregress=0

for dir in test/archive/import test/archive/multifile; do
    # one build per directory, over every unit its goldens know about
    units=""
    for exp_c in "$dir"/*.expected.c; do
        [ -f "$exp_c" ] || continue
        units="$units $(basename "$exp_c" .expected.c)"
    done
    [ -n "$units" ] || continue

    stage="$work/multi-${dir##*/}"
    outdir="$stage/_out"
    mkdir -p "$outdir"
    rels=""
    for b in $units; do
        rel="$(sed -n '1s/^.* from \(.*\) -- do not edit.*$/\1/p' "$dir/$b.expected.c")"
        if [ -z "$rel" ]; then
            printf 'SKIP        %s/%s  (its golden records no provenance path)\n' "$dir" "$b"
            rels=""
            break
        fi
        mkdir -p "$stage/$(dirname "$rel")"
        cp "$dir/$b.ct" "$stage/$rel"
        rels="$rels $rel"
    done
    [ -n "$rels" ] || continue

    err="$(cd "$stage" && "$l2" build $rels -o "$outdir" 2>&1 >/dev/null)"
    rc=$?

    for b in $units; do
        exp_c="$dir/$b.expected.c"
        exp_h="$dir/$b.expected.h"
        got_c="$outdir/$b.c"
        got_h="$outdir/$b.h"

        matched=0
        if [ "$rc" -eq 0 ] && [ -f "$got_c" ] && [ -f "$got_h" ] &&
           same_modulo_version "$got_c" "$exp_c" && same_modulo_version "$got_h" "$exp_h"; then
            matched=1
        fi

        if in_list "$dir/$b" "$baseline_multi"; then
            if [ "$matched" -eq 1 ]; then
                printf 'PASS        %s/%s\n' "$dir" "$b"
                kpass=$((kpass + 1))
            else
                printf 'REGRESSION  %s/%s' "$dir" "$b"
                if [ "$rc" -ne 0 ]; then
                    printf '  (exit %d: %s)' "$rc" "$(first_line "$err")"
                else
                    printf '  (.c or .h no longer matches the golden)'
                fi
                printf '\n'
                kregress=$((kregress + 1))
                fail=1
            fi
        else
            if [ "$matched" -eq 1 ]; then
                printf 'NEW         %s/%s  (promote it in the baseline)\n' "$dir" "$b"
                knew=$((knew + 1))
            else
                printf 'PENDING     %s/%s' "$dir" "$b"
                if [ "$rc" -ne 0 ] && [ -n "$err" ]; then
                    printf '  (%s)' "$(first_line "$err")"
                else
                    printf '  (output differs from the golden)'
                fi
                printf '\n'
                kpending=$((kpending + 1))
            fi
        fi
    done
done

# ------------------------------------------------- 7) designed module cases
banner "7) designed module cases (test/modules/*/{build,compile}.args)"
zpass=0; znew=0; zpending=0; zregress=0

for fdir in test/modules/*/; do
    [ -d "$fdir" ] || continue
    fdir="${fdir%/}"
    name="${fdir#test/modules/}"
    if [ -f "$fdir/compile.args" ]; then mode=compile
    elif [ -f "$fdir/build.args" ]; then mode=build
    else continue; fi
    args="$(cat "$fdir/$mode.args")"
    outdir="$work/mod-$name"
    log="$work/mod-$name.log"
    rm -rf "$outdir"
    mkdir -p "$outdir"

    errfile="$fdir/expected.err"
    matched=0
    detail=""

    # build mode compiles into $outdir and its args carry no `-o` (the runner
    # appends it); compile mode runs its args verbatim from a staging copy so the
    # recorded banner path matches, and its args name both the input and `-o`.
    # The compiler's own stdout/stderr are kept for the optional expected.stdout
    # / expected.stderr assertions below (expected.out is the *program's* output).
    if [ "$mode" = compile ]; then
        stage="$outdir/src"
        mkdir -p "$stage"
        cp "$fdir"/*.ct "$stage"/ 2>/dev/null
        ( cd "$stage" && "$l2" $args ) >"$work/mod-$name.stdout" 2>"$log"
        rc=$?
        runc="$stage"
    else
        "$l2" build $args -o "$outdir" >"$work/mod-$name.stdout" 2>"$log"
        rc=$?
        runc="$outdir"
    fi

    if [ -f "$errfile" ]; then
        # a negative case: the command must fail, and every non-comment line of
        # expected.err must appear on stderr (the same convention as group 5)
        detail="(got: $(first_line "$(cat "$log")"))"
        if [ "$rc" -ne 0 ]; then
            matched=1
            while IFS= read -r want; do
                case "$want" in '' | '#'*) continue ;; esac
                if ! grep -Fq -- "$want" "$log"; then matched=0; break; fi
            done <"$errfile"
        fi
    else
        # a positive case: byte-diff every unit pair, then link and run
        detail="(exit $rc: $(first_line "$(cat "$log")"))"
        matched=1
        if [ "$rc" -ne 0 ]; then
            matched=0
        else
            for exp_c in "$fdir"/*.expected.c; do
                [ -f "$exp_c" ] || continue
                b="$(basename "$exp_c" .expected.c)"
                if ! same_modulo_version "$runc/$b.c" "$exp_c" ||
                   ! same_modulo_version "$runc/$b.h" "$fdir/$b.expected.h"; then
                    matched=0
                    detail="($b.c or $b.h differs from its golden)"
                    break
                fi
            done
        fi
        outfile="$fdir/expected.out"
        if [ "$matched" -eq 1 ] && [ -f "$outfile" ]; then
            exe="$work/mod-$name.bin"
            if "$CC" "$runc"/*.c -o "$exe" >/dev/null 2>&1; then
                if ! "$exe" >"$work/mod-$name.out" 2>&1 ||
                   ! cmp -s "$work/mod-$name.out" "$outfile"; then
                    matched=0
                    detail="(the linked program's output differs from expected.out)"
                fi
            else
                matched=0
                detail="(the generated C did not link)"
            fi
        fi
    fi

    # Compiler-output assertions: byte-exact against what the compiler printed.
    # (expected.out above is what the linked *program* prints.)
    if [ "$matched" -eq 1 ] && [ -f "$fdir/expected.stderr" ] &&
       ! cmp -s "$log" "$fdir/expected.stderr"; then
        matched=0
        detail="(compiler stderr differs from expected.stderr)"
    fi
    if [ "$matched" -eq 1 ] && [ -f "$fdir/expected.stdout" ] &&
       ! cmp -s "$work/mod-$name.stdout" "$fdir/expected.stdout"; then
        matched=0
        detail="(compiler stdout differs from expected.stdout)"
    fi
    if [ "$matched" -eq 1 ] && [ -f "$fdir/expected.noartifacts" ] &&
       ls "$runc"/*.c "$runc"/*.h >/dev/null 2>&1; then
        matched=0
        detail="(an artifact survived a failing compile)"
    fi

    if in_list "$name" "$baseline_designed"; then
        if [ "$matched" -eq 1 ]; then
            printf 'PASS        %s\n' "$name"
            zpass=$((zpass + 1))
        else
            printf 'REGRESSION  %s  %s\n' "$name" "$detail"
            zregress=$((zregress + 1))
            fail=1
        fi
    else
        if [ "$matched" -eq 1 ]; then
            printf 'NEW         %s  (promote it in the baseline)\n' "$name"
            znew=$((znew + 1))
        else
            printf 'PENDING     %s  %s\n' "$name" "$detail"
            zpending=$((zpending + 1))
        fi
    fi
done

# --------------------------------------------------------------- verdict
banner "VERDICT"
printf 'single-unit goldens: %d pass, %d new, %d pending, %d regression\n' \
    "$npass" "$nnew" "$npending" "$nregress"
printf 'diagnostics:         %d pass, %d new, %d pending, %d regression\n' \
    "$epass" "$enew" "$epending" "$eregress"
printf 'multi-unit goldens:  %d pass, %d new, %d pending, %d regression\n' \
    "$kpass" "$knew" "$kpending" "$kregress"
printf 'designed cases:      %d pass, %d new, %d pending, %d regression\n' \
    "$zpass" "$znew" "$zpending" "$zregress"
if [ "$l2_ok" -eq 1 ]; then
    printf 'L2 (split tree):     built warning-free\n'
else
    printf 'L2 (split tree):     FAILED to build\n'
fi

if [ "$fail" -eq 0 ]; then
    printf 'check-archive: OK (no regression)\n'
else
    printf 'check-archive: FAIL (%d regression(s))\n' "$((nregress + eregress + kregress + zregress))"
fi

exit "$fail"
