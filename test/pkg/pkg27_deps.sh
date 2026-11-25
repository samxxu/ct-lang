#!/usr/bin/env bash
# S1a-0 C1: the package manager's dependency caps grow past the old limit.
#
# A root package declares 20 local dependencies (old MAX_PKG_DEPS = 16), so:
#   * `ct get` reads a 20-dep manifest, walks every dependency, records 21
#     packages and writes 21 v2 lock rows;
#   * `ct verify` re-reads the 21-row lock (old: "ct.lock lists more than 16
#     packages");
#   * `ct build` reads the same 21 rows through the build-time lock reader;
#   * `ct install` re-reads them and prints a store-backed build command.
#
# The fixture is staged under mktemp -d, so the worktree is never written.
# `CT_AST` is required and an absent binary is an explicit failure (D-010-C).
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg27_deps.sh

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
ct="${CT_AST:-}"

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg27: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg27.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

proj="$work/proj"
home="$work/home"
cthome="$work/cthome"
mkdir -p "$proj" "$home" "$cthome" "$work/pkgs" || exit 1

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

run_ct() { # <args...>
    ( cd "$proj" || exit 1
      env -u CT_INDEX -u CT_REGISTRY \
          HOME="$home" CT_HOME="$cthome" \
          GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
          "$ct" "$@" )
}

lock_rows() {
    awk 'NR > 1 && NF > 0 { n++ } END { print n + 0 }' "$proj/ct.lock" 2>/dev/null
}

ndep=20
printf 'ct: %s\n' "$ct"

# --- fixture: one root package with 20 local deps -------------------------
i=0
while [ "$i" -lt "$ndep" ]; do
    d=$(printf '%s/pkgs/d%02d' "$work" "$i")
    mkdir -p "$d" || exit 1
    printf 'name = d%02d\npublisher = ct\nversion = 0.1.0\nns-root = .\n' "$i" \
        >"$d/ct.pkg"
    printf 'int d%02d_value(void) { return %d; }\n' "$i" "$i" >"$d/d.c"
    i=$((i + 1))
done
mkdir -p "$work/pkgs/root" || exit 1
{
    printf 'name = root\npublisher = ct\nversion = 0.1.0\nns-root = .\n'
    i=0
    while [ "$i" -lt "$ndep" ]; do
        printf 'dep = ../d%02d@^0.1.0\n' "$i"
        i=$((i + 1))
    done
} >"$work/pkgs/root/ct.pkg"
printf 'name = app\nversion = 0.1.0\n' >"$proj/ct.pkg"
printf 'int main(void) { return 0; }\n' >"$proj/main.ct"

# --- ct get: 20 deps in one manifest, 21 rows in the lock ----------------
if run_ct get ../pkgs/root >"$work/get.out" 2>"$work/get.err"; then
    ok "ct get accepts a 20-dep manifest"
else
    bad "ct get failed: $(cat "$work/get.err")"
fi
n="$(lock_rows)"
n="${n:-0}"
if [ "$n" -eq $((ndep + 1)) ]; then
    ok "ct.lock lists all $((ndep + 1)) packages"
else
    bad "ct.lock has $n row(s), want $((ndep + 1))"
    sed 's/^/        /' "$proj/ct.lock" 2>/dev/null
fi
i=0
missing=0
while [ "$i" -lt "$ndep" ]; do
    grep -q "^ct/d$(printf '%02d' "$i") 0.1.0 " "$proj/ct.lock" 2>/dev/null \
        || missing=$((missing + 1))
    i=$((i + 1))
done
if [ "$missing" -eq 0 ]; then
    ok "every dependency has a lock row"
else
    bad "$missing dependency row(s) are missing from ct.lock"
fi
if [ -f "$cthome/pkg/ct/root/0.1.0/ct.pkg" ]; then
    ok "the store holds the root package"
else
    bad "the store copy of root is missing"
fi

# --- ct verify: the 21-row lock round-trips -------------------
if run_ct verify >"$work/verify.out" 2>"$work/verify.err"; then
    if grep -Fq "verified $((ndep + 1)) package(s)" "$work/verify.out"; then
        ok "ct verify accepts all $((ndep + 1)) rows"
    else
        bad "ct verify said: $(cat "$work/verify.out")"
    fi
else
    bad "ct verify failed: $(cat "$work/verify.err")"
fi

# --- ct build: the build-time lock reader sees every row ----------------
if run_ct build main.ct -o "$work/main.bin" >"$work/build.out" 2>"$work/build.err" \
        && [ -x "$work/main.bin" ] && "$work/main.bin"; then
    ok "ct build reads the 21-row lock"
else
    bad "ct build failed: $(cat "$work/build.err")"
fi

# --- ct install: re-reads the lock and prints a build command -----------
if run_ct install >"$work/install.out" 2>"$work/install.err"; then
    if grep -Fq "# lock-format: v2" "$work/install.out"; then
        ok "ct install prints a store-backed build command"
    else
        bad "ct install printed no v2 build command: $(cat "$work/install.out")"
    fi
else
    bad "ct install failed: $(cat "$work/install.err")"
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL S1a-0 pkg deps"
    exit 1
fi
echo "OK S1a-0 pkg deps"
