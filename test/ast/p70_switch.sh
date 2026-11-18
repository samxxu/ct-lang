#!/bin/sh
# PH-70-R3: duplicate/overlapping `case` values are an error under
# `ct check --semantics`; distinct values and `default` stay silent.
#
# Usage: sh test/ast/p70_switch.sh <ct-ast>
set -u
ctast=${1:?usage: p70_switch.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p70s.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/dup.ct" <<'CT'
int main(void){ int x = 1; switch (x) { case 1: break; case 1: break; } return 0; }
CT
cat > "$work/ok.ct" <<'CT'
int main(void){ int x = 1; switch (x) { case 1: break; case 2: break; default: break; } return 0; }
CT

out=$work/dup.out
( cd "$root" && "$ctast" check --semantics "$work/dup.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "duplicate case value" "$out"; then
    echo "FAIL p70/switch: duplicate case not diagnosed" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

out=$work/ok.out
( cd "$root" && "$ctast" check --semantics "$work/ok.ct" ) >"$out" 2>&1 || {
    echo "FAIL p70/switch: legal switch rejected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p70/switch (duplicate case)"
