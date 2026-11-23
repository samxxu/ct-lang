#!/usr/bin/env bash
#
# check-install.sh - acceptance for v1-PH-0 S1/S2 (a task check, not a hard gate).
#
# Gate 13 proves the seed is frozen and reproducible. This script proves the
# other half of D-022: the installed `ct` is built from that seed, in a clean
# copy of the tree, with no L0 -> L1 -> L2 walk, and it is still a working
# compiler. It deliberately runs against `git archive HEAD` rather than the
# working tree, so an uncommitted edit cannot make the acceptance green.
#
# Asserted:
#   A. install.sh names bootstrap/ct-ast and no longer walks selfhost/l0..l2;
#   B. a clean copy installs into a fresh prefix (CT_SOURCE_DIR, no download);
#      `ct -v` equals CTC_VERSION, the `ctc` alias answers too, and the
#      installed binary compiles and runs a program;
#   C. the clean copy never printed an L0/L1/L2 build step;
#   D. check-ast.sh and ct-tour.sh build ct-ast from the seed while keeping the
#      L1/L2 regression oracle (D-022 section 4).
#
# Usage: bash selfhost/check-install.sh
# Exit: 0 all assertions pass, 1 any failure. This script is NOT registered in
# selfhost/check-all.sh: the count stays at 13 gates.
set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
work="$(mktemp -d "${TMPDIR:-/tmp}/ct-install-check.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s%s\n' "$1" "${2:+: $2}"; fail=$((fail + 1)); }

# --- a clean copy of exactly what is committed ------------------------------
src="$work/src"
mkdir -p "$src"
if ! git archive HEAD | tar -x -C "$src"; then
    bad "cannot export HEAD with git archive"
    printf 'check-install: FAIL\n'
    exit 1
fi

version="$(sed -n 's/^#define CTC_VERSION "\([0-9][0-9.]*\)"$/\1/p' "$src/selfhost/l0/ctc.c" | head -n 1)"
[ -n "$version" ] || { bad "no CTC_VERSION in selfhost/l0/ctc.c"; exit 1; }

# --- A. the script's own build path ----------------------------------------
if grep -Eq 'selfhost/l[012]|l[012]_src|ast_src' "$src/install.sh"; then
    bad "install.sh still references the L0/L1/L2 chain" \
        "$(grep -nE 'selfhost/l[012]|l[012]_src|ast_src' "$src/install.sh" | head -n 3 | tr '\n' ' ')"
elif ! grep -q 'bootstrap/ct-ast' "$src/install.sh"; then
    bad "install.sh does not build from bootstrap/ct-ast"
else
    ok "install.sh builds from bootstrap/ct-ast and names no L0/L1/L2 step"
fi

# --- C. nothing in the clean tree builds the old chain for ct-ast -----------
if grep -Eq 'building L[012]|\bL2 could not build|L0 could not compile L1' "$src/install.sh"; then
    bad "install.sh still contains a bootstrap-chain step"
else
    ok "install.sh contains no bootstrap-chain step"
fi

# --- D. the gate harnesses build ct-ast from the seed, not from L2 ----------
if ! grep -q 'bootstrap/ct-ast' "$src/selfhost/check-ast.sh"; then
    bad "check-ast.sh does not build ct-ast from bootstrap/ct-ast"
elif grep -q '"\$work/l2" build -I selfhost/ct-ast' "$src/selfhost/check-ast.sh"; then
    bad "check-ast.sh still lets L2 build ct-ast"
else
    ok "check-ast.sh builds ct-ast from the seed"
fi
if grep -q 'selfhost/l2/driver.ct' "$src/selfhost/check-ast.sh"; then
    ok "check-ast.sh still builds the L1/L2 regression oracle"
else
    bad "check-ast.sh dropped the L1/L2 oracle build"
fi
if ! grep -q 'bootstrap/ct-ast' "$src/selfhost/ct-tour.sh"; then
    bad "ct-tour.sh step 7 does not build ct-ast from bootstrap/ct-ast"
elif grep -q 'L2 building the AST compiler' "$src/selfhost/ct-tour.sh"; then
    bad "ct-tour.sh step 7 still says L2 builds the AST compiler"
else
    ok "ct-tour.sh step 7 builds ct-ast from the seed"
fi
if grep -q 'L1 building the split tree' "$src/selfhost/ct-tour.sh"; then
    ok "ct-tour.sh step 6 still demonstrates the L1 -> L2 oracle"
else
    bad "ct-tour.sh dropped the L1 -> L2 oracle step"
fi

# --- B. clean-copy install --------------------------------------------------
prefix="$work/prefix"
if ! ( cd "$src" && CT_SOURCE_DIR="$src" sh ./install.sh --prefix "$prefix" ) \
        >"$work/install.log" 2>&1; then
    bad "a clean-copy install failed" "$(tail -n 3 "$work/install.log" | tr '\n' ' ')"
else
    ok "a clean-copy install succeeded (no download, no prior build)"
    if [ ! -x "$prefix/ct" ]; then
        bad "the install wrote no $prefix/ct"
    else
        got="$("$prefix/ct" -v 2>&1)"
        if [ "$got" = "ct v$version" ]; then
            ok "installed ct -v = '$got' (CTC_VERSION $version)"
        else
            bad "installed ct -v is '$got', expected 'ct v$version'"
        fi
        if [ -x "$prefix/ctc" ] && [ "$("$prefix/ctc" -v 2>&1)" = "ctc v$version" ]; then
            ok "installed ctc alias answers 'ctc v$version'"
        else
            bad "the ctc compatibility alias is missing or wrong" \
                "$([ -e "$prefix/ctc" ] && "$prefix/ctc" -v 2>&1 || echo missing)"
        fi

        # Still a compiler, not just a version string: compile, link, run.
        cat >"$work/hello.ct" <<'CTEOF'
#include <stdio.h>

int main(void)
{
    printf("seed-ok\n");
    return 0;
}
CTEOF
        if CT_C_BOUNDARY=allow "$prefix/ct" "$work/hello.ct" -o "$work/hello.c" >"$work/hello.log" 2>&1 &&
           "$CC" -Wall -Wextra -std=c99 "$work/hello.c" -o "$work/hello.bin" >>"$work/hello.log" 2>&1 &&
           [ "$("$work/hello.bin")" = "seed-ok" ]; then
            ok "the installed ct compiles, links and runs a program"
        else
            bad "the installed ct did not compile a trivial program" \
                "$(tail -n 3 "$work/hello.log" | tr '\n' ' ')"
        fi
    fi
fi

echo
if [ "$fail" -eq 0 ]; then
    printf 'check-install: OK (seed-built ct, clean copy, version %s)\n' "$version"
else
    printf 'check-install: FAIL (%d failure(s))\n' "$fail"
fi
[ "$fail" -eq 0 ]
