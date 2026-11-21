#!/usr/bin/env bash
# PH-85 S85c probe: M0 is a pure move.
#
# J1  the body-hash multiset of the tree equals the pre-M0 baseline: every
#     moved function body is byte-identical and no function body was added,
#     edited or dropped;
# A2  the product set is the frozen baseline plus exactly the six new units;
# J4  no import cycle exists (the baseline has none);
# E85-6  the test corpus still emits byte-identical C: `test/cases/*.ct` and
#     `examples/**/*.ct` are compiled again and compared with the pre-M0
#     sha256 manifest in `test/probes/p85_corpus_sha.tsv`.
#
# Usage: bash test/ast/p85_m0.sh <ct-ast>
set -u
CT=${1:?usage: p85_m0.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p85m0: $1" >&2; }

# The M0 claim is a PH-85 snapshot: later phases rewrite bodies by design, so
# re-derive it from the PH-85 closeout commit, not the live tree.
baseline=${P85_BASELINE:-1e2c30f7}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p85m0.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
if ! git archive "$baseline" | tar -x -C "$tmp"; then
    echo "FAIL p85m0: cannot extract baseline $baseline" >&2
    exit 1
fi

# 1) J1 + A2 + J4, against the committed baseline and map
if python3 tools/p85_inventory.py --root "$tmp" m0 >/tmp/p85m0.out 2>&1; then
    ok
else
    bad "$(sed -n '1,6p' /tmp/p85m0.out)"
fi

# 2) the map is a real old -> new table with six rows and both sides exist
python3 - "$tmp" <<'PY'
import os, sys
base = sys.argv[1]
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(base, "test/probes/p85_m0_mapping.tsv"))
        if l.strip() and not l.startswith("#")]
if len(rows) != 6:
    print("map has %d rows, expected 6" % len(rows), file=sys.stderr)
    sys.exit(1)
for old, new in rows:
    for p in (old, new):
        if not os.path.exists(os.path.join(base, p)):
            print("mapped path is missing: %s" % p, file=sys.stderr)
            sys.exit(1)
    if new.split("/")[-1][:1].islower():
        print("unit name is not PascalCase: %s" % new, file=sys.stderr)
        sys.exit(1)
if not os.path.exists(os.path.join(base, "test/probes/p85_m0_baseline.json")):
    print("baseline json is missing", file=sys.stderr)
    sys.exit(1)
PY
if [ $? -eq 0 ]; then ok; else bad "the baseline / map set is not intact"; fi

# 3) E85-6 level 1: the pinned corpus emits the same bytes as before M0
python3 tools/p85_inventory.py --root . corpus-manifest --ct "$CT" \
    >/tmp/p85corpus.new 2>/dev/null
if diff -q test/probes/p85_corpus_sha.tsv /tmp/p85corpus.new >/dev/null 2>&1; then
    ok
else
    bad "the test corpus emission changed: $(diff test/probes/p85_corpus_sha.tsv /tmp/p85corpus.new | head -4 | tr '\n' ' ')"
fi

# 4) the moved units carry no `use`/trait of their own and no import back to
#    the host (the "no new cycle" property, asserted at the source level)
python3 - "$tmp" <<'PY'
import os, sys
sys.path.insert(0, "tools")
import p85_inventory as inv
base = sys.argv[1]
units = {u["path"]: u for u in inv.scan(base)}
edges = inv.import_edges(list(units.values()))
rows = [l.rstrip("\n").split("\t") for l in open(os.path.join(base, "test/probes/p85_m0_mapping.tsv"))
        if l.strip() and not l.startswith("#")]
bad = 0
for host, new in rows:
    if host in edges.get(new, ()):
        print("%s imports its host %s" % (new, host), file=sys.stderr)
        bad += 1
    if not units[new]["functions"]:
        print("%s carries no function" % new, file=sys.stderr)
        bad += 1
    for f in units[new]["functions"]:
        if f["kind"] != "free":
            print("%s carries a method (%s)" % (new, f["name"]), file=sys.stderr)
            bad += 1
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then ok; else bad "a moved unit violates the pure-move shape"; fi

echo "p85m0: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
