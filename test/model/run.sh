#!/bin/sh
# PH-59 M1: model export -> fixture generator -> cc -> run.
set -u
CC="${CC:-cc}"
root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1
work="${TMPDIR:-/tmp}/ct-model-test.$$"
rm -rf "$work"; mkdir -p "$work" || exit 1
fails=0
ok() { echo "  ok    $1"; }
bad() { echo "  FAIL  $1: $2"; fails=$((fails+1)); }

ct="$work/ct-ast"
if ! "$CC" ${CC:+-std=c99} selfhost/l0/ctc.c -o "$work/ctc0" >/dev/null 2>&1; then
    echo "  L0 did not build"; exit 1
fi
# reuse the repository's bootstrap chain through check-ast's build path
if ! bash selfhost/check-ast.sh >/dev/null 2>&1; then
    echo "  bootstrap chain failed"; exit 1
fi
# check-ast leaves no reusable binary; build a local one the same way the gate does
if ! "$work/ctc0" selfhost/l1/ctc.ct -o "$work/l1.c" >/dev/null 2>&1; then
    echo "  L1 did not emit"; exit 1
fi
if ! "$CC" -std=c99 "$work/l1.c" -o "$work/l1" >/dev/null 2>&1; then
    echo "  L1 did not build"; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build -I selfhost/l2 selfhost/l2/driver.ct -o "$work/l2src" >/dev/null 2>&1; then
    echo "  L2 did not build"; exit 1
fi
if ! "$CC" -std=c99 "$work"/l2src/*.c -o "$work/l2" >/dev/null 2>&1; then
    echo "  L2 did not link"; exit 1
fi
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >/dev/null 2>&1; then
    echo "  ct-ast did not build"; exit 1
fi
if ! "$CC" -std=c99 "$work"/astsrc/*.c -o "$ct" >/dev/null 2>&1; then
    echo "  ct-ast did not link"; exit 1
fi

if "$ct" --emit-model "$work/m.json" test/model/case1/box.ct -o "$work/box.c" >/dev/null 2>"$work/m.err"; then
    ok "emit-model exits 0"
else
    bad "emit-model" "$(cat "$work/m.err")"
fi
if python3 -c 'import json,sys; m=json.load(open(sys.argv[1])); assert m["schema"]=="ct.model" and m["schema_version"]==1' "$work/m.json"; then
    ok "schema envelope"
else
    bad "schema" "bad envelope"
fi
if python3 - "$work/m.json" <<'PY'
import json,sys
m=json.load(open(sys.argv[1])); s=m["structs"]
box=next(x for x in s if x["name"].endswith("Box"))
assert [f["name"] for f in box["fields"]] == ["value","hidden","kind"]
assert all(f["loc"]["line"] > 0 for f in box["fields"])
assert box["fields"][1]["visibility"] == "unknown"
e=next(x for x in m["enums"] if x["name"].endswith("Kind"))
assert [x["name"] for x in e["members"]] == ["KIND_SMALL","KIND_LARGE"]
assert [x["value"] for x in e["members"]] == [1,7]
assert [f["name"] for f in m["functions"]] == ["box_get","box_add"]
PY
then
    ok "fields, enum members, function signatures"
else
    bad "model content" "field/enum/function assertion failed"
fi
if grep -q 'lib/std\|/tmp/' "$work/m.json"; then
    bad "paths" "absolute or builtin path leaked"
else
    ok "relative paths, no builtin layer"
fi
"$ct" --emit-model "$work/m2.json" test/model/case1/box.ct -o "$work/box2.c" >/dev/null 2>&1
if cmp -s "$work/m.json" "$work/m2.json"; then ok "deterministic"; else bad "deterministic" "differs"; fi
if bash test/model/gen.sh "$work/m.json" "$work/box_gen" >/dev/null 2>&1 \
   && "$CC" -std=c99 -I"$work" "$work/box_gen.c" test/model/case1/main.c -o "$work/prog" >/dev/null 2>&1 \
   && [ "$("$work/prog")" = "$(cat test/model/case1/main.expected.out)" ]; then
    ok "M1 end-to-end"
else
    bad "E2E" "generator/cc/run failed"
fi
if "$ct" --emit-model "$work/bad.json" /no/such/file.ct -o "$work/bad.c" >/dev/null 2>&1 || [ -e "$work/bad.json" ]; then
    bad "negative" "bad input left a model or exited 0"
else
    ok "negative input leaves no model"
fi
echo
echo "== summary: $((12-fails)) passed, $fails failed =="
[ "$fails" -eq 0 ]
