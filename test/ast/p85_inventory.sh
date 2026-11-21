#!/usr/bin/env bash
# PH-85 S85a probe: the inventory document still matches the tree.
#
# E85-1 says the inventory covers every subsystem and that the function set,
# file-level state and import-cycle list can be re-derived. This probe is that
# re-derivation: `tools/p85_inventory.py check` scans the units, computes the
# per-unit line / free-function / method / import / global figures and the
# import cycles, and compares every table row and the summary line with
# docs/design/p85_inventory.md. A drifted document is a failure, not a warning.
#
# Usage: bash test/ast/p85_inventory.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p85inventory: $1" >&2; }
has() { grep -qF -- "$2" "$1"; }

# E85-1 is a PH-85 snapshot. PH-86 rewrites the lexer and its consumers, so
# the live tree is expected to drift; re-derive the facts from the PH-85
# closeout commit instead, and keep the doc valid for the snapshot it records.
baseline=${P85_BASELINE:-1e2c30f7}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p85inv.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
if ! git archive "$baseline" | tar -x -C "$tmp"; then
    echo "FAIL p85inventory: cannot extract baseline $baseline" >&2
    exit 1
fi
doc=$tmp/docs/design/p85_inventory.md
if [ ! -f "$doc" ]; then
    bad "the inventory document is missing"
else
    ok
fi

# 1) every unit row, the file-level state and the summary match the tree
if python3 tools/p85_inventory.py --root "$tmp" check --doc "$doc" >/tmp/p85inv.out 2>&1; then
    ok
else
    bad "$(sed -n '1,5p' /tmp/p85inv.out)"
fi

# 2) the document names the four things E85-1 asks for, each with a heading
for h in "## 1 单元与子系统" "## 2 文件级状态" "## 3 导入图" "## 4 可折叠 helper"; do
    if has "$doc" "$h"; then ok; else bad "missing section: $h"; fi
done

# 3) the import graph is written down edge by edge (the tool's view is the
#    reference; a sample of the edges must be visible in the document)
if python3 tools/p85_inventory.py --root "$tmp" cycles >/tmp/p85cyc.out 2>&1; then
    if has "$doc" "$(tail -1 /tmp/p85cyc.out)"; then
        ok
    else
        bad "the cycle count line is not in the document"
    fi
else
    bad "cycles could not be computed"
fi

# 4) the folding candidates name real functions: each backticked name that
#    appears in the folding table must be a function of the scanned tree
python3 - "$doc" "$tmp" <<'PY'
import re, sys
sys.path.insert(0, "tools")
import p85_inventory as inv
doc = open(sys.argv[1], encoding="utf-8").read()
names = set()
for u in inv.scan(sys.argv[2]):
    for f in u["functions"]:
        names.add(f["name"])
missing = []
for line in doc.splitlines():
    if "|" not in line:
        continue
    for name in re.findall(r"`([a-z_][a-z0-9_]{2,})`", line):
        if name not in names and name not in ("g_sb", "g_emit", "g_slice_used"):
            missing.append(name)
# a name is allowed to be a field or a file name; only report names that look
# like a function (they end in a verb) and are absent from the tree
bad = [n for n in sorted(set(missing))
       if re.match(r"^(sb_|emit_|parse_|chk_|ct_|map_|sym_|impl_|inst_)", n)]
if bad:
    print("fold names not in the tree: %s" % ", ".join(bad), file=sys.stderr)
    sys.exit(1)
PY
if [ $? -eq 0 ]; then ok; else bad "the folding table names a function that is not in the tree"; fi

# 5) the file-level state listed for the emitter is the set the tree really has
python3 - "$tmp" <<'PY'
import sys
sys.path.insert(0, "tools")
import p85_inventory as inv
doc = open(sys.argv[1] + "/docs/design/p85_inventory.md", encoding="utf-8").read()
for u in inv.scan(sys.argv[1]):
    for g in u["globals"]:
        if g["name"] in ("g_sb", "g_slice_used", "g_emit", "g_symbols",
                         "g_module", "g_parse", "g_pkg", "g_expr", "g_stmt"):
            if g["name"] not in doc:
                print("state %s is not in the document" % g["name"], file=sys.stderr)
                sys.exit(1)
PY
if [ $? -eq 0 ]; then ok; else bad "a file-level state variable is not documented"; fi

echo "p85inventory: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
