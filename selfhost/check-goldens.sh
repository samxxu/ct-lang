#!/usr/bin/env bash
#
# check-goldens.sh - the incremental golden oracle for L1 (selfhost/ctc.ct).
#
# One command that answers "how far has L1 got?":
#   1) build L0 from ctc.c (warning-free)
#   2) L0 compiles L1            (selfhost/ctc.ct -> <tmp>/ctc-l1.c)
#   3) build L1 warning-free
#   4) L1 compiles every test/cases/*.ct into <tmp>/<case>.c -- the golden
#      basename, so the .h include guard matches -- and both outputs are compared
#      byte for byte with the committed .expected.c / .expected.h
#   5) [self-hosting] L1 compiles itself into L1', L1' is built warning-free and
#      runs over the same corpus; every output must still be byte-identical
#
# The goldens are the oracle: L1 climbed them one feature family at a time. The
# baseline below lists the cases L1 matches, and it is a ratchet:
#
#   PASS        in the baseline, byte-identical
#   NEW         byte-identical but not in the baseline -> promote it below
#   PENDING     not in the baseline and not matching yet -> a family still to do
#   REGRESSION  in the baseline but no longer matching -> the verdict is FAIL
#
# Promote a case in the same commit that makes it pass. Never demote one to turn
# the script green: a baseline case that stops matching is a real regression, not
# a fixture to edit.
#
# Usage:  bash selfhost/check-goldens.sh       (or ./selfhost/check-goldens.sh after chmod +x)
#         CC=clang bash selfhost/check-goldens.sh
#
# Exits non-zero when a baseline case regressed or when the self-hosted rebuild
# disagrees with the goldens (step 5). PENDING cases are the remaining climb and
# do NOT fail the run.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-gcc}"
work="${TMPDIR:-/tmp}"
work="${work%/}"

l1_c="$work/ctc-l1.c"
l1_bin="$work/ctc-l1"
self_c="$work/l1-self.c"
self_bin="$work/l1-self"
self_log="$work/l1-self.log"
outdir="$work/ctc-goldens"

# Cases L1 already matches byte for byte. Keep this list in lockstep with the
# commit that promotes a case from PENDING to PASS.
baseline="
01_trait_basic
02_multi_trait
03_passthrough
04_signatures
05_declarations
06_name_collision
07_positional_init
08_self_call
09_pointer_receiver
10_uninit_decl
11_value_param
12_pointer_param
13_signature_types
14_scope_shadow
15_composition
16_arrays
17_heap
18_polymorphism
21_empty_init_iface
23_file_scope
24_receiver_forms
25_rvalue_receiver
26_method_body_dispatch
27_static_file_scope
28_iface_field
"

in_baseline() {
    case " $(echo $baseline) " in
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

# ---------------------------------------------------------------- 1) L0
banner "1) build L0 (ctc.c) warning-free"
if ! run "build L0" "$CC" -Wall -Wextra -std=c99 ctc.c -o ctc; then
    echo "FATAL: L0 did not build; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------------- 2) L0 compiles L1
banner "2) L0 compiles L1 (selfhost/ctc.ct -> $l1_c)"
if ! run "L0 compile L1" ./ctc selfhost/ctc.ct -o "$l1_c"; then
    echo "FATAL: L0 could not compile L1; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------------------- 3) build L1
banner "3) build L1 warning-free ($l1_c -> $l1_bin)"
if ! run "build L1" "$CC" -Wall -Wextra -std=c99 "$l1_c" -o "$l1_bin"; then
    echo "FATAL: L1 did not build; cannot continue." >&2
    exit 1
fi

# ------------------------------------------------- 4) L1 vs every golden
banner "4) L1 vs the goldens (test/cases/*.ct)"
rm -rf "$outdir"
mkdir -p "$outdir"

npass=0
nnew=0
npending=0
nregress=0
fail=0

for f in test/cases/*.ct; do
    b="$(basename "$f" .ct)"
    exp_c="test/cases/$b.expected.c"
    exp_h="test/cases/$b.expected.h"
    got_c="$outdir/$b.c"
    got_h="$outdir/$b.h"

    rm -f "$got_c" "$got_h"
    err="$("$l1_bin" "$f" -o "$got_c" 2>&1 >/dev/null)"
    rc=$?
    err_first="$(printf '%s' "$err" | head -n 1)"

    matched=0
    if [ "$rc" -eq 0 ] && [ -f "$got_c" ] && [ -f "$got_h" ] &&
       cmp -s "$got_c" "$exp_c" && cmp -s "$got_h" "$exp_h"; then
        matched=1
    fi

    if in_baseline "$b"; then
        if [ "$matched" -eq 1 ]; then
            printf 'PASS        %s\n' "$b"
            npass=$((npass + 1))
        else
            printf 'REGRESSION  %s' "$b"
            if [ "$rc" -ne 0 ]; then
                printf '  (L1 exit %d: %s)' "$rc" "$err_first"
            else
                printf '  (.c or .h no longer matches the golden)'
            fi
            printf '\n'
            nregress=$((nregress + 1))
            fail=1
        fi
    else
        if [ "$matched" -eq 1 ]; then
            printf 'NEW         %s  (promote it in the baseline)\n' "$b"
            nnew=$((nnew + 1))
        else
            printf 'PENDING     %s' "$b"
            if [ "$rc" -ne 0 ] && [ -n "$err_first" ]; then
                printf '  (%s)' "$err_first"
            else
                printf '  (output differs from the golden)'
            fi
            printf '\n'
            npending=$((npending + 1))
        fi
    fi
done

# ------------------------------------------------- 5) L1' vs every golden
# The stronger claim: L1 compiles itself into L1', and L1' reproduces the same
# corpus. A failure here means L1 mis-compiles something L1 is written in, i.e. a
# real defect the goldens alone would not catch -- so it fails the gate.
banner "5) L1' (L1 compiling itself) vs the goldens"
nselfpass=0
nselffail=0

if ! run "L1 compiles itself" "$l1_bin" selfhost/ctc.ct -o "$self_c"; then
    printf 'FAIL: L1 could not compile itself\n'
    fail=1
elif ! run "build L1'" "$CC" -Wall -Wextra -std=c99 "$self_c" -o "$self_bin" 2>"$self_log" ||
     [ -s "$self_log" ]; then
    printf 'FAIL: the self-compiled L1 did not build warning-free:\n'
    sed 's/^/    /' "$self_log"
    fail=1
else
    for f in test/cases/*.ct; do
        b="$(basename "$f" .ct)"
        exp_c="test/cases/$b.expected.c"
        exp_h="test/cases/$b.expected.h"
        got_c="$outdir/$b.c"
        got_h="$outdir/$b.h"

        rm -f "$got_c" "$got_h"
        err="$("$self_bin" "$f" -o "$got_c" 2>&1 >/dev/null)"
        rc=$?
        if [ "$rc" -eq 0 ] && [ -f "$got_c" ] && [ -f "$got_h" ] &&
           cmp -s "$got_c" "$exp_c" && cmp -s "$got_h" "$exp_h"; then
            nselfpass=$((nselfpass + 1))
        else
            printf "L1' MISMATCH  %s  (%s)\n" "$b" \
                "$(printf '%s' "$err" | head -n 1)"
            nselffail=$((nselffail + 1))
        fi
    done
    if [ "$nselffail" -ne 0 ]; then
        printf "L1' reproduces only %d of %d goldens\n" \
            "$nselfpass" "$((nselfpass + nselffail))"
        fail=1
    fi
fi

# --------------------------------------------------------------- verdict
banner "VERDICT"
printf 'L1 golden coverage: %d pass, %d new, %d pending, %d regression (of %d cases)\n' \
    "$npass" "$nnew" "$npending" "$nregress" \
    "$((npass + nnew + npending + nregress))"
printf "L1' (self-hosted rebuild): %d passed, %d failed\n" "$nselfpass" "$nselffail"

if [ "$fail" -eq 0 ]; then
    printf 'check-goldens: OK (no regression, and the self-hosted rebuild agrees)\n'
else
    printf 'check-goldens: FAIL (%d baseline regression(s), %d self-hosted mismatch(es))\n' \
        "$nregress" "$nselffail"
fi

exit "$fail"
