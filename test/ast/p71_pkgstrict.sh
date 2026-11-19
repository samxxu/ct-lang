#!/bin/sh
# PH-71-R3: package-level strict is opt-in via `ct.pkg` (`strict = on`).
# With it on, `ct verify` rejects a dev-override (dir) lock row even without the
# CLI flag; without it, that gate does not fire (the CLI flag still does).
#
# Usage: sh test/ast/p71_pkgstrict.sh <ct-ast>
set -u
ctast=${1:?usage: p71_pkgstrict.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p71pk.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

mkdir -p "$work/p"
cat > "$work/p/ct.pkg" <<'PKG'
name = demo
version = 0.1.0
strict = on
PKG
cat > "$work/p/ct.lock" <<'LOCK'
# ct-lock 2
p 0.1.0 dir ../dev 0000000000000000 - -
LOCK

out=$work/on.out
( cd "$work/p" && "$ctast" verify ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "dev override (dir row)" "$out"; then
    echo "FAIL p71/pkgstrict: manifest strict=on did not gate verify" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

cat > "$work/p/ct.pkg" <<'PKG'
name = demo
version = 0.1.0
PKG
out=$work/off.out
( cd "$work/p" && "$ctast" verify ) >"$out" 2>&1
if grep -q "dev override (dir row)" "$out"; then
    echo "FAIL p71/pkgstrict: strict gate fired with no opt-in" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/cli.out
( cd "$work/p" && "$ctast" verify --strict ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "dev override (dir row)" "$out"; then
    echo "FAIL p71/pkgstrict: CLI --strict no longer gates" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p71/pkgstrict (manifest opt-in + CLI)"
