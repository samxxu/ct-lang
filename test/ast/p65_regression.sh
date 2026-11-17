#!/usr/bin/env bash
# PH-65 R6 probe: the four CT-tree directories keep the pre-PH-65 behaviour
# (policy `allow`), and an external project sees the new default: strict by
# default, `--c-boundary=allow` on request, end to end through `ct build`.
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

# 1) The four grandfathered directories resolve to allow from the repo root.
for f in selfhost/ct-ast/main.ct lib/std/Str.h.ct test/cases/01_trait_basic.ct \
         examples/37_nested_pattern/nested_pattern.ct; do
    got=$( cd "$root" && env -u CT_C_BOUNDARY "$CT" --show-c-boundary "$f" 2>"$tmp/e" )
    if [ "$got" != "allow" ]; then
        echo "FAIL p65/regression: $f resolved to '$got' (want allow)" >&2
        fail=1
    fi
done

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

# 3) Report the grandfathered surface (the card's 688 files); fail only on zero.
n=$( cd "$root" && find selfhost lib/std test examples -name '*.ct' 2>/dev/null | wc -l | tr -d ' ' )
if [ "$n" -lt 600 ]; then
    echo "FAIL p65/regression: only $n .ct files under the grandfathered dirs" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p65/regression ($n grandfathered .ct sources)"
exit "$fail"
