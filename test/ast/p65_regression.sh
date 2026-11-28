#!/usr/bin/env bash
# PH-65 R6 probe, flipped by v1-PH-2 S9 and extended by D-032 (Q-2): the
# global default is strict.
#   1. the two internal layers (selfhost/ct-ast, lib/core incl. utf16/) resolve
#      allow through their own manifest, every other in-repo tree (test /
#      examples) resolves to strict, selfhost/ct-ast keeps only the three shims
#      that carry a C declaration (Module / ModuleBoundary / Pkg) with system
#      includes in the units' `.h.ct`, and lib/core keeps no shim at all (D-032
#      M3); the registered C-interop fixtures stay the only per-file allow rows;
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

# 1b) D-032 M2: the internal layer keeps only the three shims that carry a C
#     declaration (Module / ModuleBoundary `realpath`, Pkg `CT_ROR`); every
#     other unit's system includes live in its own `.h.ct`. The predicate is a
#     function so the real tree (green) and a synthetic include-only tree (red)
#     run the same check.
internal_shims_ok() {
    tree=$1
    names=$( cd "$tree" && find . -name '*.shim.h' -type f | sed 's#.*/##; s/\.shim\.h$//' \
             | LC_ALL=C sort | tr '\n' ' ' )
    [ "$names" = "Module ModuleBoundary Pkg " ] || return 1
    # A retired include-only shim would put a system include back on the
    # boundary; the three retained shims carry declarations only.
    if ( cd "$tree" && find . -name '*.shim.h' -type f -exec \
             grep -lE '^[[:space:]]*#include[[:space:]]*<' {} + ) 2>/dev/null \
            | grep -q .; then
        return 1
    fi
    return 0
}
if ! internal_shims_ok "$root/selfhost/ct-ast"; then
    echo "FAIL p65/regression: selfhost/ct-ast must keep exactly the Module / ModuleBoundary / Pkg shims, none with an include" >&2
    fail=1
fi
# The retired shims' system headers are now in the units themselves (sample the
# distinctive ones: lexer assert, TIR time, Pkg dirent).
for pair in \
    "selfhost/ct-ast/frontend/lex/Lexer.h.ct:#include <assert.h>" \
    "selfhost/ct-ast/backend/tir/TGraph.h.ct:#include <time.h>" \
    "selfhost/ct-ast/tool/pkg/Pkg.h.ct:#include <dirent.h>"; do
    f=${pair%%:*}; h=${pair#*:}
    if ! grep -qF -- "$h" "$root/$f"; then
        echo "FAIL p65/regression: $f lost '$h' (M2 moves it back into the unit)" >&2
        fail=1
    fi
done
# Negative fixtures for the predicate above: both a retired include-only shim
# under the three allowed names and an extra shim base must go red.
mkdir -p "$tmp/neg-inc" "$tmp/neg-extra"
: >"$tmp/neg-inc/Module.shim.h"
: >"$tmp/neg-inc/ModuleBoundary.shim.h"
printf '#include <stdio.h>\n' >"$tmp/neg-inc/Pkg.shim.h"
if internal_shims_ok "$tmp/neg-inc"; then
    echo "FAIL p65/regression: an include in a retained shim did not go red" >&2
    fail=1
fi
: >"$tmp/neg-extra/Module.shim.h"
: >"$tmp/neg-extra/ModuleBoundary.shim.h"
: >"$tmp/neg-extra/Pkg.shim.h"
: >"$tmp/neg-extra/Lexer.shim.h"
if internal_shims_ok "$tmp/neg-extra"; then
    echo "FAIL p65/regression: an extra retired shim did not go red" >&2
    fail=1
fi

# 1c) D-032 M3: the built-in layer keeps no shim (8 -> 0). Its system includes
#     live at the top of each `.h.ct`, and the package root `lib/core/ct.pkg`
#     (allow) covers `utf16/` -- no per-subdirectory manifest. The predicate is
#     a function so the real tree (green) and a synthetic stray shim (red) run
#     the same check.
core_shims_ok() {
    tree=$1
    if ( cd "$tree" && find . -name '*.shim.h' -type f | grep -q . ); then
        return 1
    fi
    return 0
}
if ! core_shims_ok "$root/lib/core"; then
    echo "FAIL p65/regression: lib/core must keep no shim (D-032 M3: 8 -> 0)" >&2
    fail=1
fi
# The retired shims' system headers are now in the units themselves (sample the
# distinctive ones: Vec stdio, U16String stdint / stdio).
for pair in \
    "lib/core/Vec.h.ct:#include <stdio.h>" \
    "lib/core/String.h.ct:#include <string.h>" \
    "lib/core/utf16/U16String.h.ct:#include <stdint.h>"; do
    f=${pair%%:*}; h=${pair#*:}
    if ! grep -qF -- "$h" "$root/$f"; then
        echo "FAIL p65/regression: $f lost '$h' (M3 moves it back into the unit)" >&2
        fail=1
    fi
done
# The root manifest is the only one: utf16/ must not grow a second ct.pkg.
if [ -e "$root/lib/core/utf16/ct.pkg" ]; then
    echo "FAIL p65/regression: lib/core/utf16/ct.pkg exists (the package root already covers the subtree)" >&2
    fail=1
fi
# Negative fixture: a stray include-only shim under lib/core must go red.
mkdir -p "$tmp/neg-core/utf16"
: >"$tmp/neg-core/Vec.shim.h"
: >"$tmp/neg-core/utf16/U16Str.shim.h"
if core_shims_ok "$tmp/neg-core"; then
    echo "FAIL p65/regression: a stray lib/core shim did not go red" >&2
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

[ "$fail" -eq 0 ] && echo "OK p65/regression (global default strict; selfhost/ct-ast keeps only the three C-declaration shims)"
exit "$fail"
