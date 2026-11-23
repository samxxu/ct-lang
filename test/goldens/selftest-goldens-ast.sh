#!/usr/bin/env bash
# Negative fixture for gate 12 (SH-105 / 8.3): a changed golden must turn the
# static-golden gate red.  Also proves the missing/extra coverage failures and
# the banner-version normalisation (a different version token must stay green).
#
# Usage: bash test/goldens/selftest-goldens-ast.sh <ct-ast-binary>
set -u
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1
CT="${1:?usage: selftest-goldens-ast.sh <ct-ast-binary>}"
gate="$root/selfhost/check-goldens-ast.sh"
work="$(mktemp -d "${TMPDIR:-/tmp}/ct-ast-goldens-selftest.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

run() { # dir expected-rc label pattern
    dir=$1; want=$2; label=$3; pattern=$4
    if CHECK_GOLDENS_AST_DIR="$dir" bash "$gate" "$CT" >"$work/out" 2>"$work/err"; then
        got=0
    else
        got=1
    fi
    if [ "$got" -ne "$want" ]; then
        echo "FAIL selftest $label: exit=$got want=$want" >&2
        cat "$work/out" "$work/err" >&2
        fail=1
        return
    fi
    if ! grep -qF "$pattern" "$work/out" "$work/err"; then
        echo "FAIL selftest $label: missing diagnostic '$pattern'" >&2
        cat "$work/out" "$work/err" >&2
        fail=1
    fi
}

copy_goldens() {
    rm -rf "$work/gold"
    cp -R "$root/test/goldens/ast" "$work/gold"
}

# 0) the untouched tree is green.
copy_goldens
run "$work/gold" 0 "clean" "check-goldens-ast: 25/25"

# 1) a changed golden is red.
copy_goldens
printf '\n/* negative: a changed golden must be red */\n' >>"$work/gold/01_trait_basic.c"
run "$work/gold" 1 "changed-golden" "FAIL 01_trait_basic"

# 2) a missing golden is red.
copy_goldens
rm -f "$work/gold/02_multi_trait.c"
run "$work/gold" 1 "missing-golden" "golden missing"

# 3) an extra golden without a case is red.
copy_goldens
printf '/* orphan */\n' >"$work/gold/99_no_such_case.c"
run "$work/gold" 1 "extra-golden" "golden has no test/cases"

# 4) a version bump in the banner alone must stay green (normalisation works).
copy_goldens
sed -E 's/v[0-9]+\.[0-9]+\.[0-9]+/v9.9.9/g' "$work/gold/03_passthrough.c" >"$work/gold/03_passthrough.c.tmp" &&
    mv "$work/gold/03_passthrough.c.tmp" "$work/gold/03_passthrough.c"
run "$work/gold" 0 "version-normalised" "check-goldens-ast: 25/25"

if [ "$fail" -eq 0 ]; then
    echo "OK goldens-ast/selftest (changed/missing/extra red, clean/version-normalised green)"
fi
exit "$fail"
