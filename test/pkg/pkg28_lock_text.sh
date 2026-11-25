#!/usr/bin/env bash
# S1a-0 C2d: the package manager's ct.lock text grows past the old 4096-byte
# MAX_LOCK. A root package declares 40 local dependencies (old MAX_LOCK held
# about 35 rows), so:
#   * `ct get` appends 41 v2 rows (the old accumulator stopped with
#     "ctc: ct.lock is too large to merge" / returned -1);
#   * the lock file is over 4096 bytes, so the old buffer could not hold it;
#   * `ct verify` re-reads all 41 rows;
#   * `ct update` reads and rewrites the over-4096-byte lock (the old
#     `char buf[MAX_LOCK]` / `char out[MAX_LOCK]` path refused it);
#   * `ct build` reads the same rows through the build-time lock reader.
#
# The fixture is staged under mktemp -d, so the worktree is never written.
# `CT_AST` is required and an absent binary is an explicit failure (D-010-C).
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg28_lock_text.sh

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
ct="${CT_AST:-}"

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg28: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg28.XXXXXX")" || exit 1
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

ndep=40
printf 'ct: %s\n' "$ct"

# --- fixture: one root package with 40 local deps -------------------------
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

# --- ct get: 41 rows, over the old 4096-byte lock buffer ------------------
if run_ct get ../pkgs/root >"$work/get.out" 2>"$work/get.err"; then
    ok "ct get accepts a 40-dep manifest"
else
    bad "ct get failed: $(cat "$work/get.err")"
fi
n="$(lock_rows)"
n="${n:-0}"
if [ "$n" -eq $((ndep + 1)) ]; then
    ok "ct.lock lists all $((ndep + 1)) packages"
else
    bad "ct.lock has $n row(s), want $((ndep + 1))"
fi
if [ -f "$proj/ct.lock" ]; then
    lockbytes=$(wc -c <"$proj/ct.lock" | tr -d ' ')
    if [ "$lockbytes" -gt 4096 ]; then
        ok "ct.lock is $lockbytes bytes (over the old MAX_LOCK 4096)"
    else
        bad "ct.lock is only $lockbytes bytes; the fixture did not exceed MAX_LOCK"
    fi
else
    bad "ct.lock is missing"
fi

# --- ct verify: the 41-row lock round-trips ------------------------------
if run_ct verify >"$work/verify.out" 2>"$work/verify.err"; then
    if grep -Fq "verified $((ndep + 1)) package(s)" "$work/verify.out"; then
        ok "ct verify accepts all $((ndep + 1)) rows"
    else
        bad "ct verify said: $(cat "$work/verify.out")"
    fi
else
    bad "ct verify failed: $(cat "$work/verify.err")"
fi

# --- ct update: read + rewrite the over-4096-byte lock -------------------
if run_ct update >"$work/update.out" 2>"$work/update.err"; then
    if grep -Fq "updated $((ndep + 1)) package(s)" "$work/update.out"; then
        ok "ct update rewrites the over-4096-byte lock"
    else
        bad "ct update said: $(cat "$work/update.out")"
    fi
    n="$(lock_rows)"
    n="${n:-0}"
    if [ "$n" -eq $((ndep + 1)) ]; then
        ok "ct update keeps all $((ndep + 1)) rows"
    else
        bad "ct update left $n row(s), want $((ndep + 1))"
    fi
else
    bad "ct update failed: $(cat "$work/update.err")"
fi

# --- ct build: the build-time lock reader sees every row ----------------
if run_ct build main.ct -o "$work/main.bin" >"$work/build.out" 2>"$work/build.err" \
        && [ -x "$work/main.bin" ] && "$work/main.bin"; then
    ok "ct build reads the 41-row lock"
else
    bad "ct build failed: $(cat "$work/build.err")"
fi

if [ "$fail" -ne 0 ]; then
    echo "FAIL S1a-0 lock text"
    exit 1
fi
echo "OK S1a-0 lock text"
