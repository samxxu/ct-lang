#!/usr/bin/env bash
#
# run.sh - compile and run every sample under examples/c-superset/, byte-comparing
# stdout (and, for the negative samples, the compiler's stderr) with the checked-in
# expectations.
#
# The samples are grouped by feature; `cases.tsv` is the manifest:
#
#     feature|case|mode|l0|expect_exit|note
#
#   mode        run    ct <case>.ct -o x.c -> cc -Wall -Wextra -std=c99 -> run
#                      -> stdout must be byte-identical to <case>.out.
#                      If <case>.orig.c exists it is compiled with the same cc
#                      flags and must produce the same stdout: that is the
#                      "the C source passes through unchanged" evidence.
#               neg    the ct compile must fail with expect_exit and its stderr
#                      must contain every line of <case>.err.
#               ccfail the ct compile succeeds, but the generated C must fail in
#                      cc (used for a failing _Static_assert, which per spec is
#                      the C compiler's verdict, not ct's).
#   l0          yes -> also compile+run the sample with the frozen L0 seed
#                      (selfhost/l0/ctc.c). L0's C may warn about an unused
#                      `_self`; only "compiles, runs, same stdout" is asserted.
#               no  -> negative or ct-ast-only sample.
#   expect_exit status the compiler/cc must return for `neg` / `ccfail`; 0 for
#               `run`.
#
# Usage:
#   bash examples/c-superset/run.sh              # every case
#   bash examples/c-superset/run.sh s04_         # cases whose path contains s04_
#   CT=/path/to/ct bash examples/c-superset/run.sh
#   CC=clang bash examples/c-superset/run.sh
#
# Without CT the runner takes the in-tree ./ctc if it is recent enough, otherwise
# `ct` from PATH if recent enough, and otherwise builds the bootstrap chain
# (L0 -> L1 -> L2 -> ct-ast) under $TMPDIR, exactly as selfhost/check-warnings.sh
# does. Nothing is written into the repository.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-cc}"
filter="${1:-}"

work="${TMPDIR:-/tmp}"
work="${work%/}/ct-csuperset.$$"
rm -rf "$work"
mkdir -p "$work" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

pass=0
fail=0
l0_ok=0
l0_fail=0
failures=()

ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
l0ok() { l0_ok=$((l0_ok + 1)); printf '        l0 ok\n'; }
l0bad(){ l0_fail=$((l0_fail + 1)); printf '        l0 FAIL: %s\n' "$1"; }

bad() {
    fail=$((fail + 1))
    failures+=("$1 :: $2")
    printf '  FAIL  %s\n' "$1"
    printf '        %s\n' "$2"
    if [ -n "${3:-}" ] && [ -s "${3:-}" ]; then
        sed 's/^/        /' "$3"
    fi
}

diffout() {
    diff -u -L "expected: $1" -L "actual: $2" "$1" "$2"
}

show() { sed 's/^/        /' "$1"; }

# version_at_least <compiler> <major> <minor> <patch>
version_at_least() {
    v="$("$1" -v 2>/dev/null | awk 'NF {print $NF; exit}')"
    v="${v#v}"
    [ -n "$v" ] || return 1
    printf '%s\n' "$v" | awk -F. -v a="$2" -v b="$3" -v c="$4" '
        { if ($1+0 > a+0) exit 0
          if ($1+0 < a+0) exit 1
          if (($2+0) > b+0) exit 0
          if (($2+0) < b+0) exit 1
          if (($3+0) >= c+0) exit 0
          exit 1 }'
}

# ---------------------------------------------------------------------------
# manifest audit
# ---------------------------------------------------------------------------
echo "== manifest audit =="
audit_bad=0
audit_err() { printf '  audit FAIL: %s\n' "$1"; audit_bad=$((audit_bad + 1)); }
: >"$work/keys"

while IFS='|' read -r feature name mode l0flag want note; do
    case "$feature" in ''|'#'*) continue ;; esac
    label="$feature/$name"
    printf '%s\n' "$label" >>"$work/keys"

    src="$here/$feature/$name.ct"
    [ -f "$src" ] || audit_err "$label: missing $feature/$name.ct"
    [ -d "$here/$feature" ] || audit_err "$label: missing feature directory"

    case "$l0flag" in
        yes|no) : ;;
        *) audit_err "$label: l0 must be yes/no, got '$l0flag'" ;;
    esac
    case "$mode" in
        run)    [ "$want" = 0 ] || audit_err "$label: run mode expects exit 0" ;;
        neg)    [ "$want" = 1 ] || audit_err "$label: neg mode expects exit 1" ;;
        ccfail) [ "$want" = 1 ] || audit_err "$label: ccfail mode expects exit 1" ;;
        *) audit_err "$label: unknown mode '$mode'" ;;
    esac

    case "$mode" in
        run)    need="$name.out" ;;
        neg)    need="$name.err" ;;
        ccfail) need="$name.ccerr" ;;
    esac
    [ -z "${need:-}" ] || [ -f "$here/$feature/$need" ] || audit_err "$label: missing $feature/$need"

    if [ "$mode" != run ] && [ "$l0flag" = yes ]; then
        audit_err "$label: a negative case cannot be marked l0=yes"
    fi
done <"$here/cases.tsv"

dups="$(sort "$work/keys" | uniq -d)"
[ -z "$dups" ] || audit_err "duplicate manifest rows: $dups"

find "$here" -mindepth 2 -maxdepth 2 -type f -name '*.ct' | sed "s#$here/##; s#\.ct\$##" | sort >"$work/sources"
sort "$work/keys" >"$work/keys.sorted"
while IFS= read -r s; do
    grep -qxF "$s" "$work/keys.sorted" || audit_err "$s.ct: file has no manifest row"
done <"$work/sources"

if [ "$audit_bad" -ne 0 ]; then
    printf 'audit: %d problem(s); fix cases.tsv before running\n' "$audit_bad"
    exit 1
fi
printf '  audit ok: %d cases, %d features\n' \
    "$(wc -l <"$work/keys" | tr -d ' ')" \
    "$(cut -d/ -f1 "$work/keys" | sort -u | wc -l | tr -d ' ')"

# ---------------------------------------------------------------------------
# L0 seed
# ---------------------------------------------------------------------------
echo
echo "== build the frozen L0 seed (selfhost/l0/ctc.c) =="
if ! "$CC" -Wall -Wextra -std=c99 "$root/selfhost/l0/ctc.c" -o "$work/l0" 2>"$work/l0.log"; then
    echo "  L0 did not build:"; show "$work/l0.log"; exit 1
fi
printf '  ok    L0 built\n'

# ---------------------------------------------------------------------------
# locate ct-ast
# ---------------------------------------------------------------------------
echo
echo "== locate ct =="
ct=""
if [ -n "${CT:-}" ]; then
    ct="$CT"
elif [ -x "$root/ctc" ] && version_at_least "$root/ctc" 0 23 0; then
    ct="$root/ctc"
elif command -v ct >/dev/null 2>&1 && version_at_least "$(command -v ct)" 0 23 0; then
    ct="$(command -v ct)"
else
    if [ -n "${CT:-}" ]; then
        echo "  CT=$CT is not usable"; exit 1
    fi
    echo "  no ct >= 0.23 on PATH and CT is unset: building the bootstrap chain"
    if ! "$work/l0" "$root/selfhost/l1/ctc.ct" -o "$work/l1.c" 2>"$work/l1.log"; then
        echo "  L0 could not compile L1:"; show "$work/l1.log"; exit 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
        echo "  L1 did not build:"; show "$work/l1b.log"; exit 1
    fi
    mkdir -p "$work/l2src" "$work/astsrc"
    if ! ( cd "$work" && "$work/l1" build "$root/selfhost/l2/driver.ct" \
            -o "$work/l2src" ) >"$work/l2.out" 2>&1; then
        echo "  L1 could not build the split tree:"; show "$work/l2.out"; exit 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
        echo "  L2 did not build:"; show "$work/l2b.log"; exit 1
    fi
    if ! ( cd "$work" && "$work/l2" build -I "$root/selfhost/ct-ast" \
            "$root/selfhost/ct-ast/main.ct" -o "$work/astsrc" ) >"$work/ast.out" 2>&1; then
        echo "  L2 could not build ct-ast:"; show "$work/ast.out"; exit 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
        echo "  ct-ast did not build:"; show "$work/astb.log"; exit 1
    fi
    ct="$work/ct-ast"
fi
printf '  ct: %s (%s)\n' "$ct" "$("$ct" -v 2>&1)"

# ---------------------------------------------------------------------------
# run the manifest
# ---------------------------------------------------------------------------
last_feature=""
while IFS='|' read -r feature name mode l0flag want note; do
    case "$feature" in ''|'#'*) continue ;; esac
    label="$feature/$name"
    [ -n "$filter" ] && case "$label" in *"$filter"*) : ;; *) continue ;; esac

    if [ "$feature" != "$last_feature" ]; then
        printf '\n== %s ==\n' "$feature"
        last_feature="$feature"
    fi

    dir="$here/$feature"
    src="$dir/$name.ct"
    gen="$work/$feature-$name.c"
    prog="$work/$feature-$name"

    case "$mode" in
        run)
            "$ct" "$src" -o "$gen" >"$work/c.out" 2>"$work/c.err"
            rc=$?
            if [ "$rc" -ne 0 ]; then
                bad "$label" "ct compile: expected exit 0, got $rc" "$work/c.err"
                continue
            fi
            if ! "$CC" -Wall -Wextra -std=c99 -I "$dir" "$gen" -o "$prog" 2>"$work/cc.log"; then
                bad "$label" "cc: expected a binary, got a compile error" "$work/cc.log"
                continue
            fi
            if [ -s "$work/cc.log" ]; then
                bad "$label" "cc: expected zero warnings, got warnings" "$work/cc.log"
                continue
            fi
            if ! "$prog" >"$work/run.out" 2>"$work/run.err"; then
                bad "$label" "program: expected exit 0, got non-zero" "$work/run.err"
                continue
            fi
            if ! cmp -s "$work/run.out" "$dir/$name.out"; then
                { printf 'stdout: expected the bytes of %s.out, got different bytes\n' "$name"
                  diffout "$dir/$name.out" "$work/run.out"; } >"$work/detail"
                bad "$label" "stdout mismatch" "$work/detail"
                continue
            fi

            if [ -f "$dir/$name.orig.c" ]; then
                if ! cmp -s "$src" "$dir/$name.orig.c"; then
                    bad "$label" "zero-rewrite: $name.ct is not byte-identical to $name.orig.c"
                    continue
                fi
                "$CC" -Wall -Wextra -std=c99 -I "$dir" "$dir/$name.orig.c" -o "$prog.orig" 2>"$work/origcc.log"
                if [ $? -ne 0 ]; then
                    bad "$label" "zero-rewrite: the .orig.c did not compile with cc" "$work/origcc.log"
                    continue
                fi
                if [ -s "$work/origcc.log" ]; then
                    bad "$label" "zero-rewrite: cc warned on the .orig.c" "$work/origcc.log"
                    continue
                fi
                "$prog.orig" >"$work/orig.out" 2>"$work/orig.err"
                if [ $? -ne 0 ]; then
                    bad "$label" "zero-rewrite: the .orig.c program exited non-zero" "$work/orig.err"
                    continue
                fi
                if ! cmp -s "$work/orig.out" "$dir/$name.out"; then
                    { printf 'zero-rewrite stdout: .orig.c and expected.out disagree\n'
                      diffout "$dir/$name.out" "$work/orig.out"; } >"$work/detail"
                    bad "$label" "zero-rewrite stdout mismatch" "$work/detail"
                    continue
                fi
            fi

            ok "$label"

            if [ "$l0flag" = yes ]; then
                "$work/l0" "$src" -o "$work/l0-$feature-$name.c" >"$work/l0.out" 2>"$work/l0.err"
                lrc=$?
                if [ "$lrc" -ne 0 ]; then
                    l0bad "L0 compile exit $lrc"
                elif ! "$CC" -std=c99 -I "$dir" "$work/l0-$feature-$name.c" -o "$prog.l0" 2>"$work/l0cc.log"; then
                    l0bad "L0 output did not compile"
                elif ! "$prog.l0" >"$work/l0run.out" 2>"$work/l0run.err"; then
                    l0bad "L0 program exited non-zero"
                elif ! cmp -s "$work/l0run.out" "$dir/$name.out"; then
                    { printf 'L0 stdout differs from expected.out\n'
                      diffout "$dir/$name.out" "$work/l0run.out"; } >"$work/l0detail"
                    l0bad "stdout mismatch"
                    show "$work/l0detail"
                else
                    l0ok
                fi
            fi
            ;;

        neg)
            "$ct" "$src" -o "$gen" >"$work/c.out" 2>"$work/c.err"
            rc=$?
            if [ "$rc" -ne "$want" ]; then
                bad "$label" "ct compile: expected exit $want, got $rc" "$work/c.err"
                continue
            fi
            missing=""
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                grep -qF -- "$line" "$work/c.err" || missing="$missing$line
"
            done <"$dir/$name.err"
            if [ -n "$missing" ]; then
                { printf 'stderr: missing expected line(s):\n%s\n' "$missing"
                  diffout "$dir/$name.err" "$work/c.err"; } >"$work/detail"
                bad "$label" "ct stderr mismatch" "$work/detail"
                continue
            fi
            ok "$label"
            ;;

        ccfail)
            "$ct" "$src" -o "$gen" >"$work/c.out" 2>"$work/c.err"
            rc=$?
            if [ "$rc" -ne 0 ]; then
                bad "$label" "ct compile: expected exit 0 (the C compiler must decide), got $rc" "$work/c.err"
                continue
            fi
            "$CC" -Wall -Wextra -std=c99 -I "$dir" "$gen" -o "$prog" >"$work/cc.out" 2>"$work/cc.err"
            rc=$?
            if [ "$rc" -eq 0 ]; then
                bad "$label" "cc: expected a failure, got a binary"
                continue
            fi
            missing=""
            while IFS= read -r line; do
                [ -z "$line" ] && continue
                grep -qF -- "$line" "$work/cc.err" || missing="$missing$line
"
            done <"$dir/$name.ccerr"
            if [ -n "$missing" ]; then
                { printf 'cc stderr: missing expected line(s):\n%s\n' "$missing"
                  diffout "$dir/$name.ccerr" "$work/cc.err"; } >"$work/detail"
                bad "$label" "cc stderr mismatch" "$work/detail"
                continue
            fi
            ok "$label"
            ;;

        *)
            bad "$label" "driver: unknown mode $mode"
            continue
            ;;
    esac
done <"$here/cases.tsv"

echo
if [ "$fail" -ne 0 ]; then
    echo "failed:"
    for f in "${failures[@]}"; do
        printf '  - %s\n' "$f"
    done
    echo
fi
printf 'c-superset: %d ok, %d failed; l0 recompile: %d ok, %d failed\n' \
    "$pass" "$fail" "$l0_ok" "$l0_fail"
[ "$fail" -eq 0 ] && [ "$l0_fail" -eq 0 ]
