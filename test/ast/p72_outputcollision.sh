#!/bin/sh
# PH-72-R3 (LANG-11): two units with the same base name would emit the same
# `.c`; the build must refuse with both paths instead of overwriting.
#
# Usage: sh test/ast/p72_outputcollision.sh <ct-ast>
set -u
ctast=${1:?usage: p72_outputcollision.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p72col.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

mkdir -p "$work/lib" "$work/app" "$work/out"
cat > "$work/lib/cfg.h.ct" <<'CT'
pub extern int K;
CT
cat > "$work/lib/cfg.ct" <<'CT'
int K = 5;
CT
cat > "$work/app/main.ct" <<'CT'
import lib::cfg;
int main(void) { return K; }
CT

out=$work/bad.log
( cd "$root" && "$ctast" build -I "$work" "$work/app/main.ct" "$work/lib/cfg.ct" -o "$work/out" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "both emit 'cfg.c'" "$out"; then
    echo "FAIL p72/collision: same-base units not refused" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

mkdir -p "$work/okout"
cat > "$work/p.ct" <<'CT'
int p(void) { return 1; }
CT
cat > "$work/q.ct" <<'CT'
int q(void) { return 2; }
CT
( cd "$root" && "$ctast" build --emit-c -o "$work/okout" "$work/p.ct" "$work/q.ct" ) >"$work/ok.log" 2>&1 || {
    echo "FAIL p72/collision: distinct bases rejected" >&2
    sed 's/^/  /' "$work/ok.log" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/collision (same-base refused)"
