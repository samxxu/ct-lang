#!/usr/bin/env bash
# PH-65 R6 probe, flipped by v1-PH-2 S9 and extended by D-032 (Q-2): the
# global default is strict.
#   1. the two internal layers (selfhost/ct-ast, lib/core incl. utf16/) resolve
#      allow through their own manifest, every other in-repo tree (test /
#      examples) resolves to strict, and selfhost + lib/core carry no direct
#      `#include`; the registered C-interop fixtures stay the only per-file
#      allow rows;
#   2. an external project sees strict by default and `--c-boundary=allow` on
#      request, end to end through `ct build`;
#   3. a plain `.ct` with no include is unaffected (it builds under the default).
# Usage: bash test/ast/p65_regression.sh <ct-ast>
set -u
CT=${1:?usage: p65_regression.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65reg.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/proj"

# 1) The two internal layers resolve allow through their own manifest
#    (D-032 / Q-2); every other tree is still strict from the repo root. 01
#    had a corpus-pinned include and is an explicit allow row, so sample a
#    plain case instead of it.
for f in selfhost/ct-ast/main.ct lib/core/String.h.ct \
         lib/core/utf16/U16Str.h.ct; do
    got=$( cd "$root" && env -u CT_C_BOUNDARY "$CT" --show-c-boundary "$f" 2>"$tmp/e" )
    if [ "$got" != "allow" ]; then
        echo "FAIL p65/regression: $f resolved to '$got' (want allow)" >&2
        fail=1
    fi
done
for f in test/cases/02_multi_trait.ct examples/37_nested_pattern/nested_pattern.ct; do
    got=$( cd "$root" && env -u CT_C_BOUNDARY "$CT" --show-c-boundary "$f" 2>"$tmp/e" )
    if [ "$got" != "strict" ]; then
        echo "FAIL p65/regression: $f resolved to '$got' (want strict)" >&2
        fail=1
    fi
done

# 1b) The compiler and the built-in layer are migrated to `.m.ct` boundary
#     units: no strict `.ct` / `.h.ct` may carry a direct include there.
ninc=$( cd "$root" && grep -rlE '^[[:space:]]*#include[[:space:]]*<' selfhost lib/core --include='*.ct' | grep -v '/cbound/' | wc -l | tr -d ' ' )
if [ "$ninc" != "0" ]; then
    echo "FAIL p65/regression: $ninc selfhost/lib/core unit(s) still carry a direct system #include" >&2
    ( cd "$root" && grep -rlE '^[[:space:]]*#include[[:space:]]*<' selfhost lib/core --include='*.ct' | grep -v '/cbound/' | head -5 ) >&2
    fail=1
fi

# 2) An external project: strict rejects a direct include, allow builds and runs.
cat >"$tmp/proj/app.ct" <<'CT'
#include <stdio.h>

int main(void)
{
    printf("external ok\n");
    return 0;
}
CT
( cd "$tmp/proj" && env -u CT_C_BOUNDARY "$CT" build app.ct -o app ) \
    >"$tmp/strict.log" 2>"$tmp/strict.err"
rc=$?
if [ "$rc" -ne 1 ] || ! grep -q "a strict C boundary forbids '#include'" "$tmp/strict.err"; then
    echo "FAIL p65/regression: external default is not strict (rc=$rc)" >&2
    sed 's/^/  /' "$tmp/strict.err" | head -3 >&2
    fail=1
fi
if ! ( cd "$tmp/proj" && env -u CT_C_BOUNDARY "$CT" build --c-boundary=allow app.ct -o app ) \
        >"$tmp/allow.log" 2>"$tmp/allow.err"; then
    echo "FAIL p65/regression: --c-boundary=allow did not build the external project" >&2
    sed 's/^/  /' "$tmp/allow.err" | head -3 >&2
    fail=1
elif [ ! -x "$tmp/proj/app" ] || [ "$("$tmp/proj/app")" != "external ok" ]; then
    echo "FAIL p65/regression: the allowed external binary did not run" >&2
    fail=1
fi

# 3) A plain `.ct` with no include builds under the default (the flip changed
#    the boundary policy, not ordinary programs).
cat >"$tmp/proj/plain.ct" <<'CT'
int main(void) { return 0; }
CT
if ! ( cd "$tmp/proj" && env -u CT_C_BOUNDARY "$CT" build plain.ct -o plain ) \
        >"$tmp/plain.log" 2>"$tmp/plain.err"; then
    echo "FAIL p65/regression: a plain .ct without includes no longer builds" >&2
    sed 's/^/  /' "$tmp/plain.err" | head -3 >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p65/regression (global default strict; selfhost + lib/core carry no direct include)"
exit "$fail"
