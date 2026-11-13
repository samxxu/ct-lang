#!/usr/bin/env bash
# Phase 37 probe: signature mismatch is a hard error for build/check and a
# warning for compile; the missing-method path stays a hard error.
# Usage: bash test/ast/p37_probe.sh <ct-ast-binary>
set -u
CT=${1:?usage: p37_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p37-probe.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

for name in p37_sig_return p37_sig_param p37_sig_arity; do
    src="$root/test/ast/errors/$name.ct"
    out="$tmp/$name"
    mkdir -p "$out"
    build_err="$tmp/$name.build.err"
    "$CT" build --emit-c "$src" -o "$out" >/dev/null 2>"$build_err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "FAIL $name build: expected non-zero, got 0" >&2
        fail=1
    elif ! grep -Fq "error: signature mismatch" "$build_err"; then
        echo "FAIL $name build: missing 'error: signature mismatch'" >&2
        sed 's/^/  /' "$build_err" >&2
        fail=1
    elif find "$out" -name '*.c' | grep -q .; then
        echo "FAIL $name build: wrote a .c despite the hard error" >&2
        find "$out" -name '*.c' >&2
        fail=1
    fi

    compile_err="$tmp/$name.compile.err"
    "$CT" compile "$src" -o "$tmp/$name.c" >/dev/null 2>"$compile_err"
    rc=$?
    if [ "$rc" -ne 0 ]; then
        echo "FAIL $name compile: expected 0, got $rc" >&2
        sed 's/^/  /' "$compile_err" >&2
        fail=1
    elif ! grep -Fq "warning: signature mismatch" "$compile_err"; then
        echo "FAIL $name compile: missing 'warning: signature mismatch'" >&2
        sed 's/^/  /' "$compile_err" >&2
        fail=1
    fi

    check_err="$tmp/$name.check.err"
    "$CT" check "$src" >/dev/null 2>"$check_err"
    rc=$?
    if [ "$rc" -ne 1 ]; then
        echo "FAIL $name check: expected 1, got $rc" >&2
        fail=1
    elif ! grep -Fq "error: signature mismatch" "$check_err"; then
        echo "FAIL $name check: missing 'error: signature mismatch'" >&2
        sed 's/^/  /' "$check_err" >&2
        fail=1
    fi
done

src="$root/test/ast/errors/p37_missing.ct"
"$CT" check "$src" >/dev/null 2>"$tmp/missing.err"
rc=$?
if [ "$rc" -ne 1 ] || ! grep -Fq "is not implemented for struct 'Box'" "$tmp/missing.err"; then
    echo "FAIL p37_missing: expected the existing 'not implemented' hard error" >&2
    sed 's/^/  /' "$tmp/missing.err" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "p37_probe: OK"
fi
exit "$fail"
