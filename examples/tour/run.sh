#!/usr/bin/env bash
#
# run.sh - compile and run every sample under examples/tour/, byte-comparing
# stdout (and, for the negative samples, stderr + exit code) with the checked-in
# expectations.
#
# The samples are grouped by feature; `cases.tsv` is the manifest:
#
#     feature|case|mode|l0|expect_exit|note
#
#   mode        compile | build | check | clean | pair | check-json
#               compile-warn (expects a byte-exact warning and still runs)
#               asan         (dangling/leak cases: compiled with -fsanitize=address)
#   l0          yes -> also compile+run the sample with the frozen L0 seed
#   expect_exit exit status the compiler/checker must return; for `asan` it
#               means "must die under ASan" (any non-zero status)
#
# The `asan` cases are skipped unless ASAN=1 is set, so a plain run never
# reports them as green; with ASAN=1 they must reproduce the diagnostic named
# in expected.asan (a fixed substring, since sanitizer stacks carry addresses).
#
# Usage:
#   bash examples/tour/run.sh                 # everything except asan cases
#   ASAN=1 bash examples/tour/run.sh          # everything, including asan cases
#   bash examples/tour/run.sh 04_             # only cases whose path contains "04_"
#   CT=/path/to/ct bash examples/tour/run.sh  # use an existing ct-ast binary
#   CC=clang bash examples/tour/run.sh
#
# Without CT, the runner uses `ct` from PATH; if that is missing it builds the
# bootstrap chain (L0 -> L1 -> L2 -> ct-ast) under $TMPDIR, exactly as
# selfhost/check-warnings.sh does. Nothing is written into the repository.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
here="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-cc}"
filter="${1:-}"

work="${TMPDIR:-/tmp}"
work="${work%/}/ct-tour-examples.$$"
rm -rf "$work"
mkdir -p "$work" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

pass=0
fail=0
skipped=0
failures=()

ok()   { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
skip() { skipped=$((skipped + 1)); printf '  skip  %s (%s)\n' "$1" "$2"; }

# bad <feature/case> <expected-vs-actual one-liner> [detail file]
bad() {
    fail=$((fail + 1))
    failures+=("$1 :: $2")
    printf '  FAIL  %s\n' "$1"
    printf '        %s\n' "$2"
    if [ -n "${3:-}" ] && [ -s "${3:-}" ]; then
        sed 's/^/        /' "$3"
    fi
}

# diffout <expected> <actual> : unified diff labelled by role, not temp paths
diffout() {
    diff -u -L "expected: $1" -L "actual: $2" "$1" "$2"
}

show() { sed 's/^/        /' "$1"; }

# ---------------------------------------------------------------------------
# manifest audit: every row must point at a real case directory with the files
# its mode needs, and every case directory must be listed exactly once.
# ---------------------------------------------------------------------------
echo "== manifest audit =="
audit_bad=0
audit_err() { printf '  audit FAIL: %s\n' "$1"; audit_bad=$((audit_bad + 1)); }
: >"$work/keys"

while IFS='|' read -r feature name mode l0flag want note; do
    case "$feature" in ''|'#'*) continue ;; esac
    label="$feature/$name"
    printf '%s\n' "$label" >>"$work/keys"

    dir="$here/$feature/$name"
    [ -d "$dir" ] || { audit_err "$label: missing directory"; continue; }

    case "$l0flag" in
        yes|no) : ;;
        *) audit_err "$label: l0 must be yes/no, got '$l0flag'" ;;
    esac
    case "$want" in
        0|1) : ;;
        *) audit_err "$label: expect_exit must be 0 or 1, got '$want'" ;;
    esac

    need=""
    case "$mode" in
        compile|pair|compile-warn|check|clean|check-json|asan) need="prog.ct" ;;
        build)          need="main.ct" ;;
        *) audit_err "$label: unknown mode '$mode'" ;;
    esac
    [ -z "$need" ] || [ -f "$dir/$need" ] || audit_err "$label: missing $need"

    if [ "$mode" = asan ]; then
        need="expected.asan"
        [ "$want" = 1 ] || audit_err "$label: asan mode expects exit 1 (must die under ASan)"
    elif [ "$want" = 0 ]; then
        case "$mode" in
            compile|build|compile-warn) need="expected.out" ;;
            clean) need="" ;;
            pair) need="expected.warn" ;;
            *) need="" ;;
        esac
    else
        case "$mode" in
            check|compile|build) need="expected.err" ;;
            *) need="" ;;
        esac
    fi
    [ -z "$need" ] || [ -f "$dir/$need" ] || audit_err "$label: missing $need"

    if [ "$mode" = compile-warn ] && [ ! -f "$dir/expected.warn" ]; then
        audit_err "$label: missing expected.warn"
    fi

    # negative cases must not be marked "run me on L0", and vice versa is fine
    if [ "$want" != 0 ] && [ "$l0flag" = yes ]; then
        audit_err "$label: a negative case cannot be marked l0=yes"
    fi
    if [ "$mode" = check-json ] && [ ! -f "$dir/expected.json" ]; then
        audit_err "$label: missing expected.json"
    fi
done <"$here/cases.tsv"

dups="$(sort "$work/keys" | uniq -d)"
[ -z "$dups" ] || audit_err "duplicate manifest rows: $dups"

find "$here" -mindepth 2 -maxdepth 2 -type d | sed "s#$here/##" | sort >"$work/dirs"
while IFS= read -r d; do
    grep -qxF "$d" "$work/keys" || audit_err "$d: directory has no manifest row"
done <"$work/dirs"

if [ "$audit_bad" -ne 0 ]; then
    printf 'audit: %d problem(s); fix cases.tsv before running\n' "$audit_bad"
    exit 1
fi
printf '  audit ok: %d cases, %d features\n' "$(wc -l <"$work/keys" | tr -d ' ')" \
    "$(cut -d/ -f1 "$work/keys" | sort -u | wc -l | tr -d ' ')"

echo
echo "== build the frozen L0 seed (selfhost/l0/ctc.c) =="
if ! "$CC" -Wall -Wextra -std=c99 "$root/selfhost/l0/ctc.c" -o "$work/ctc" 2>"$work/l0.log"; then
    echo "  L0 did not build:"; show "$work/l0.log"; exit 1
fi
l0="$work/ctc"
ok "L0 built"

echo
echo "== locate ct-ast =="
if [ -n "${CT:-}" ]; then
    ct="$CT"
elif command -v ct >/dev/null 2>&1; then
    ct="$(command -v ct)"
else
    echo "  no ct on PATH and CT is unset: building the bootstrap chain"
    if ! "$l0" "$root/selfhost/l1/ctc.ct" -o "$work/l1.c" 2>"$work/l1.log"; then
        echo "  L0 could not compile L1:"; show "$work/l1.log"; exit 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
        echo "  L1 did not build:"; show "$work/l1b.log"; exit 1
    fi
    mkdir -p "$work/l2src" "$work/astsrc"
    if ! "$work/l1" build "$root/selfhost/l2/driver.ct" -o "$work/l2src" >"$work/l2.out" 2>&1; then
        echo "  L1 could not build the split tree:"; show "$work/l2.out"; exit 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
        echo "  L2 did not build:"; show "$work/l2b.log"; exit 1
    fi
    if ! "$work/l2" build -I "$root/selfhost/ct-ast" "$root/selfhost/ct-ast/main.ct" \
            -o "$work/astsrc" >"$work/ast.out" 2>&1; then
        echo "  L2 could not build ct-ast:"; show "$work/ast.out"; exit 1
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
        echo "  ct-ast did not build:"; show "$work/astb.log"; exit 1
    fi
    ct="$work/ct-ast"
fi
printf '  ct: %s (%s)\n' "$ct" "$("$ct" -v 2>&1)"

echo
echo "== address sanitizer =="
asan=""
printf 'int main(void) { return 0; }\n' >"$work/asan_probe.c"
if "$CC" -fsanitize=address "$work/asan_probe.c" -o "$work/asan_probe" 2>"$work/asan_probe.log"; then
    asan=yes
    if [ "${ASAN:-}" = 1 ]; then
        echo "  available: crash cases will run (ASAN=1)"
    else
        echo "  available: crash cases are skipped; set ASAN=1 to run them"
    fi
else
    echo "  unavailable: $CC -fsanitize=address failed; crash cases are skipped"
fi

last_feature=""
while IFS='|' read -r feature name mode l0flag want note; do
    case "$feature" in ''|'#'*) continue ;; esac
    label="$feature/$name"
    [ -n "$filter" ] && case "$label" in *"$filter"*) : ;; *) continue ;; esac

    if [ "$feature" != "$last_feature" ]; then
        printf '\n== %s ==\n' "$feature"
        last_feature="$feature"
    fi

    dir="$here/$feature/$name"
    ( cd "$dir" || exit 1

      case "$mode" in
        compile)
          "$ct" prog.ct -o "$work/case.c" >"$work/c.out" 2>"$work/c.err"
          rc=$?
          if [ "$rc" -ne "$want" ]; then
              printf 'BAD|exit status: expected %s, got %s|%s\n' "$want" "$rc" "$(cat "$work/c.err")"; exit 0
          fi
          if [ "$want" -ne 0 ]; then
              if ! cmp -s "$work/c.err" expected.err; then
                  { printf 'stderr: expected the bytes of expected.err, got different bytes\n'
                    diffout expected.err "$work/c.err"; } >"$work/detail"
                  printf 'BAD|stderr mismatch|%s\n' "$(cat "$work/detail")"; exit 0
              fi
          else
              if ! "$CC" -Wall -Wextra -std=c99 "$work/case.c" -o "$work/prog" 2>"$work/cc.log"; then
                  printf 'BAD|cc: expected a binary, got a compile error|%s\n' "$(cat "$work/cc.log")"; exit 0
              fi
              if [ -s "$work/cc.log" ]; then
                  printf 'BAD|cc: expected zero warnings, got warnings|%s\n' "$(cat "$work/cc.log")"; exit 0
              fi
              if ! "$work/prog" >"$work/run.out" 2>"$work/run.err"; then
                  printf 'BAD|program: expected exit 0, got non-zero|%s\n' "$(cat "$work/run.err")"; exit 0
              fi
              if ! cmp -s "$work/run.out" expected.out; then
                  { printf 'stdout: expected the bytes of expected.out, got different bytes\n'
                    diffout expected.out "$work/run.out"; } >"$work/detail"
                  printf 'BAD|stdout mismatch|%s\n' "$(cat "$work/detail")"; exit 0
              fi
          fi
          # L0 must accept the same source (the feature is "L0 or ct-ast" tagged)
          if [ "$l0flag" = yes ]; then
              "$l0" prog.ct -o "$work/l0.c" >"$work/l0.out" 2>"$work/l0.err"
              rc=$?
              if [ "$rc" -ne 0 ]; then
                  printf 'BAD|L0: expected exit 0 (case is tagged l0=yes), got %s|%s\n' "$rc" "$(cat "$work/l0.err")"; exit 0
              fi
              # L0 predates the emitter's `(void)self;` fix, so its output may
              # warn about an unused `_self`; only the run result is asserted.
              if ! "$CC" -std=c99 "$work/l0.c" -o "$work/prog" 2>"$work/l0cc.log"; then
                  printf 'BAD|L0 cc: expected a binary, got a compile error|%s\n' "$(cat "$work/l0cc.log")"; exit 0
              fi
              if ! "$work/prog" >"$work/l0run.out" 2>"$work/l0run.err"; then
                  printf 'BAD|L0 program: expected exit 0, got non-zero|%s\n' "$(cat "$work/l0run.err")"; exit 0
              fi
              if ! cmp -s "$work/l0run.out" expected.out; then
                  { printf 'L0 stdout: expected the bytes of expected.out, got different bytes\n'
                    diffout expected.out "$work/l0run.out"; } >"$work/detail"
                  printf 'BAD|L0 stdout mismatch|%s\n' "$(cat "$work/detail")"; exit 0
              fi
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        compile-warn)
          # the compiler must accept the source, but print exactly expected.warn
          "$ct" prog.ct -o "$work/case.c" >"$work/c.out" 2>"$work/c.err"
          rc=$?
          if [ "$rc" -ne 0 ]; then
              printf 'BAD|compile exit status: expected 0 (warning only), got %s|%s\n' "$rc" "$(cat "$work/c.err")"; exit 0
          fi
          if ! cmp -s "$work/c.err" expected.warn; then
              { printf 'compiler stderr: expected the bytes of expected.warn, got different bytes\n'
                diffout expected.warn "$work/c.err"; } >"$work/detail"
              printf 'BAD|compiler warning mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          if ! "$CC" -Wall -Wextra -std=c99 "$work/case.c" -o "$work/prog" 2>"$work/cc.log"; then
              printf 'BAD|cc: expected a binary, got a compile error|%s\n' "$(cat "$work/cc.log")"; exit 0
          fi
          if [ -s "$work/cc.log" ]; then
              printf 'BAD|cc: expected zero warnings, got warnings|%s\n' "$(cat "$work/cc.log")"; exit 0
          fi
          if ! "$work/prog" >"$work/run.out" 2>"$work/run.err"; then
              printf 'BAD|program: expected exit 0, got non-zero|%s\n' "$(cat "$work/run.err")"; exit 0
          fi
          if ! cmp -s "$work/run.out" expected.out; then
              { printf 'stdout: expected the bytes of expected.out, got different bytes\n'
                diffout expected.out "$work/run.out"; } >"$work/detail"
              printf 'BAD|stdout mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        asan)
          # dangling pointers only show up under ASan: skip unless ASAN=1, so a
          # plain run never reports this case as green.
          if [ -z "$asan" ]; then
              printf 'SKIP|ASan unavailable\n'; exit 0
          fi
          if [ "${ASAN:-}" != 1 ]; then
              printf 'SKIP|set ASAN=1 to run the -fsanitize=address case\n'; exit 0
          fi
          "$ct" prog.ct -o "$work/case.c" >"$work/c.out" 2>"$work/c.err"
          rc=$?
          if [ "$rc" -ne 0 ]; then
              printf 'BAD|compile: expected exit 0, got %s|%s\n' "$rc" "$(cat "$work/c.err")"; exit 0
          fi
          if ! "$CC" -Wall -Wextra -std=c99 -fsanitize=address -g "$work/case.c" -o "$work/prog" 2>"$work/cc.log"; then
              printf 'BAD|cc -fsanitize=address: expected a binary, got a compile error|%s\n' "$(cat "$work/cc.log")"; exit 0
          fi
          if [ -s "$work/cc.log" ]; then
              printf 'BAD|cc: expected zero warnings, got warnings|%s\n' "$(cat "$work/cc.log")"; exit 0
          fi
          # run under `sh -c` so the outer shell does not print its own
          # "Abort trap" job notice into the verdict stream; the sanitizer's
          # report still lands in run.err.
          ASAN_OPTIONS=detect_stack_use_after_return=1 \
              sh -c '"$0" >"$1" 2>"$2"; exit $?' \
              "$work/prog" "$work/run.out" "$work/run.err" 2>/dev/null
          rc=$?
          if [ "$rc" -eq 0 ]; then
              printf 'BAD|asan run: expected a non-zero exit (the bug), got 0\n'; exit 0
          fi
          if [ -s "$work/run.out" ]; then
              printf 'BAD|asan stdout: expected empty, got output|%s\n' "$(cat "$work/run.out")"; exit 0
          fi
          if ! grep -qF "$(cat expected.asan)" "$work/run.err"; then
              { printf 'asan stderr: expected to contain "%s", got:\n' "$(cat expected.asan)"
                sed 's/^/  /' "$work/run.err"; } >"$work/detail"
              printf 'BAD|asan diagnostic missing|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          printf 'GOOD|%s (exit %s)|\n' "$mode" "$rc"
          ;;

        build)
          incs="-I ."
          for h in $(find . -name '*.shim.h'); do incs="$incs -I $(dirname "$h")"; done
          gen="$work/gen"
          rm -rf "$gen"; mkdir -p "$gen"
          "$ct" build --emit-c $incs main.ct -o "$gen" >"$work/b.out" 2>"$work/b.err"
          rc=$?
          if [ "$rc" -ne "$want" ]; then
              printf 'BAD|build exit status: expected %s, got %s|%s\n' "$want" "$rc" "$(cat "$work/b.err")"; exit 0
          fi
          if [ "$want" -ne 0 ]; then
              if ! cmp -s "$work/b.err" expected.err; then
                  { printf 'build stderr: expected the bytes of expected.err, got different bytes\n'
                    diffout expected.err "$work/b.err"; } >"$work/detail"
                  printf 'BAD|build stderr mismatch|%s\n' "$(cat "$work/detail")"; exit 0
              fi
              printf 'GOOD|%s|\n' "$mode"; exit 0
          fi
          srcs=""
          for f in "$gen"/*.c; do srcs="$srcs $f"; done
          for f in $(find . -name '*.shim.c'); do srcs="$srcs $f"; done
          if ! "$CC" -Wall -Wextra -std=c99 $incs $srcs -o "$work/prog" 2>"$work/cc.log"; then
              printf 'BAD|cc: expected a binary, got a compile error|%s\n' "$(cat "$work/cc.log")"; exit 0
          fi
          if [ -s "$work/cc.log" ]; then
              printf 'BAD|cc: expected zero warnings, got warnings|%s\n' "$(cat "$work/cc.log")"; exit 0
          fi
          if ! "$work/prog" >"$work/run.out" 2>"$work/run.err"; then
              printf 'BAD|program: expected exit 0, got non-zero|%s\n' "$(cat "$work/run.err")"; exit 0
          fi
          if ! cmp -s "$work/run.out" expected.out; then
              { printf 'stdout: expected the bytes of expected.out, got different bytes\n'
                diffout expected.out "$work/run.out"; } >"$work/detail"
              printf 'BAD|stdout mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        check)
          "$ct" check prog.ct >"$work/chk.out" 2>"$work/chk.err"
          rc=$?
          if [ "$rc" -ne "$want" ]; then
              printf 'BAD|ct check exit status: expected %s, got %s|%s\n' "$want" "$rc" "$(cat "$work/chk.err")"; exit 0
          fi
          if [ -s "$work/chk.out" ]; then
              printf 'BAD|ct check stdout: expected empty, got output|%s\n' "$(cat "$work/chk.out")"; exit 0
          fi
          if ! cmp -s "$work/chk.err" expected.err; then
              { printf 'ct check stderr: expected the bytes of expected.err, got different bytes\n'
                diffout expected.err "$work/chk.err"; } >"$work/detail"
              printf 'BAD|ct check stderr mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        clean)
          "$ct" check prog.ct >"$work/chk.out" 2>"$work/chk.err"
          rc=$?
          if [ "$rc" -ne 0 ]; then
              printf 'BAD|ct check exit status: expected 0, got %s|%s\n' "$rc" "$(cat "$work/chk.err")"; exit 0
          fi
          if [ -s "$work/chk.out" ] || [ -s "$work/chk.err" ]; then
              printf 'BAD|ct check output: expected silence, got output|%s%s\n' "$(cat "$work/chk.out")" "$(cat "$work/chk.err")"; exit 0
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        pair)
          # compile first: the same finding is a warning and the exit stays 0
          "$ct" prog.ct -o "$work/case.c" >"$work/c.out" 2>"$work/c.err"
          rc=$?
          if [ "$rc" -ne 0 ]; then
              printf 'BAD|compile exit status: expected 0, got %s|%s\n' "$rc" "$(cat "$work/c.err")"; exit 0
          fi
          if ! cmp -s "$work/c.err" expected.warn; then
              { printf 'compile stderr: expected the bytes of expected.warn, got different bytes\n'
                diffout expected.warn "$work/c.err"; } >"$work/detail"
              printf 'BAD|compile stderr mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          # then check: the same finding is an error and the exit is 1
          "$ct" check prog.ct >"$work/chk.out" 2>"$work/chk.err"
          rc=$?
          if [ "$rc" -ne 1 ]; then
              printf 'BAD|ct check exit status: expected 1, got %s|%s\n' "$rc" "$(cat "$work/chk.err")"; exit 0
          fi
          if ! cmp -s "$work/chk.err" expected.err; then
              { printf 'ct check stderr: expected the bytes of expected.err, got different bytes\n'
                diffout expected.err "$work/chk.err"; } >"$work/detail"
              printf 'BAD|ct check stderr mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        check-json)
          "$ct" check --diagnostics=json prog.ct >"$work/chk.out" 2>"$work/chk.err"
          rc=$?
          if [ "$rc" -ne 1 ]; then
              printf 'BAD|ct check exit status: expected 1, got %s|%s\n' "$rc" "$(cat "$work/chk.err")"; exit 0
          fi
          if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$work/chk.out"; then
              printf 'BAD|stdout: expected one JSON document, got unparsable output|%s\n' "$(cat "$work/chk.out")"; exit 0
          fi
          if ! cmp -s "$work/chk.out" expected.json; then
              { printf 'JSON: expected the bytes of expected.json, got different bytes\n'
                diffout expected.json "$work/chk.out"; } >"$work/detail"
              printf 'BAD|JSON mismatch|%s\n' "$(cat "$work/detail")"; exit 0
          fi
          printf 'GOOD|%s|\n' "$mode"
          ;;

        *)
          printf 'BAD|driver: unknown mode %s|\n' "$mode"; exit 0
          ;;
      esac
    ) >"$work/verdict" 2>&1

    verdict="$(cat "$work/verdict")"
    case "$verdict" in
        GOOD*) ok "$label" ;;
        SKIP*) skip "$label" "$(printf '%s' "$verdict" | cut -d'|' -f2)" ;;
        BAD*)
            msg="$(printf '%s' "$verdict" | cut -d'|' -f2)"
            detail="$(printf '%s' "$verdict" | cut -d'|' -f3-)"
            printf '%s\n' "$detail" >"$work/detail"
            bad "$label" "$msg" "$work/detail"
            printf '        case: %s\n' "$dir"
            printf '        rerun: bash examples/tour/run.sh %s\n' "$label"
            ;;
        *) bad "$label" "driver: expected a verdict, got none" "$work/verdict" ;;
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
printf 'tour: %d ok, %d failed, %d skipped\n' "$pass" "$fail" "$skipped"
[ "$fail" -eq 0 ]
