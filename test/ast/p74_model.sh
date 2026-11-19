#!/bin/sh
# PH-74-R1/R2: the declaration model carries struct fields with line+column
# (J11) and describes the entry unit, not the builtin layer (SH-79 facet 2).
#
# Usage: sh test/ast/p74_model.sh <ct-ast>
set -u
ctast=${1:?usage: p74_model.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p74m.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

printf 'struct S { int a; };\nint f(void) { return 0; }\n' > "$work/m.ct"
mkdir -p "$work/out"
( cd "$work" && "$ctast" build --emit-c --emit-model model.json m.ct -o out ) >"$work/log" 2>&1 || {
    echo "FAIL p74/model: build failed" >&2
    sed 's/^/  /' "$work/log" | head -4 >&2
    exit 1
}
python3 - "$work/model.json" <<'PY' || exit 1
import json, sys
m = json.load(open(sys.argv[1]))
assert m["file"].endswith("m.ct"), m["file"]
s = [x for x in m["structs"] if x["name"] == "S"]
assert s, m["structs"]
f = s[0]["fields"][0]
assert f["name"] == "a" and f["loc"]["line"] == 1 and f["loc"]["col"] == 16, f
assert m["functions"] and m["functions"][0]["name"] == "f"
PY
[ $? -eq 0 ] || fail=1

[ "$fail" -eq 0 ] || exit 1
echo "OK p74/model (J11 loc + entry unit)"
