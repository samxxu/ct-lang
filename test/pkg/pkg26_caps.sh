#!/usr/bin/env bash
# S1a-0 C1: the package-manager counting caps grow past their old limits.
#
#   pkg26-digest: a package tree with 4100 regular files (old
#                 MAX_DIGEST_FILES=4096) is digested by `ct index refresh`;
#                 before the change the row fails with "cannot compute the
#                 tree digest of ...".
#   pkg26-rows:   a package list with 1030 valid rows (old MAX_INDEX_ROWS=1024)
#                 generates 1030 index rows; before the change refresh stops
#                 at the 1025th row with "package list has more than 1024
#                 rows".
#
# The fixture is staged under mktemp -d, so the worktree is never written.
# `CT_AST` is required and an absent binary is an explicit failure (D-010-C).
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg26_caps.sh

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
ct="${CT_AST:-}"

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg26: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg26.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

manifest() # <dir> <name>
{
    mkdir -p "$1" || return 1
    printf 'name = %s\npublisher = ct\nversion = 0.1.0\nns-root = .\n' "$2" \
        >"$1/ct.pkg"
}

# --- pkg26-digest: more files than the old 4096 row cap --------------------
big="$work/bigfiles"
manifest "$big" bigfiles || exit 1
i=0
while [ "$i" -lt 4100 ]; do
    printf 'x' >"$big/f$i.dat"
    i=$((i + 1))
done
printf '%s x v0.1.0\n' "$big" >"$work/digest.list"
if "$ct" index refresh --packages "$work/digest.list" \
        --out "$work/digest.index" >"$work/digest.out" 2>&1; then
    if grep -q '^bigfiles 0\.1\.0 ct x v0\.1\.0 sha256:' "$work/digest.index"; then
        ok "digest: 4100 files hash into one index row"
    else
        bad "digest: index row missing or malformed: $(head -1 "$work/digest.index")"
    fi
else
    bad "digest: index refresh rejected a 4100-file tree: $(tail -2 "$work/digest.out" | tr '\n' ' ')"
fi

# --- pkg26-rows: more rows than the old 1024 row cap -----------------------
mkdir -p "$work/pkgs" || exit 1
: >"$work/rows.list"
i=0
while [ "$i" -lt 1030 ]; do
    name=$(printf 'p%04d' "$i")
    manifest "$work/pkgs/$name" "$name" || exit 1
    printf '%s x v0.1.0\n' "$work/pkgs/$name" >>"$work/rows.list"
    i=$((i + 1))
done
if "$ct" index refresh --packages "$work/rows.list" \
        --out "$work/rows.index" >"$work/rows.out" 2>&1; then
    got=$(wc -l <"$work/rows.index" | tr -d ' ')
    if [ "$got" = "1030" ]; then
        ok "rows: 1030 list rows produce 1030 index rows"
    else
        bad "rows: index has $got rows (want 1030)"
    fi
else
    bad "rows: index refresh rejected 1030 rows: $(tail -2 "$work/rows.out" | tr '\n' ' ')"
fi

if [ "$fail" -eq 0 ]; then
    printf 'pkg26: OK (digest files, index rows)\n'
    exit 0
fi
printf 'pkg26: FAIL (%d assertion(s))\n' "$fail"
exit 1
