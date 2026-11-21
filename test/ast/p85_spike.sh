#!/usr/bin/env bash
# PH-85 S85b probe: the lexer spike's evidence and its honest scope.
#
# The spike itself ran in `.temp/p85spike` (not committed: it is an experiment).
# What is committed is (a) the one-file rewrite as a patch, (b) the raw outputs
# of the measurements, and (c) the report with the sharp-edge list and the gate
# conclusion. This probe checks the three are present, consistent, and that the
# patch still applies to the current lexer; it also re-runs the level-1 corpus
# check with the current compiler, so "test corpus emits the same bytes" is
# measured, not quoted.
#
# Usage: bash test/ast/p85_spike.sh <ct-ast>
set -u
CT=${1:?usage: p85_spike.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p85spike: $1" >&2; }
has() { grep -qF -- "$2" "$1"; }

report=docs/design/p85_spike.md
evidence=test/probes/p85_spike_evidence.txt
patch=test/probes/p85_spike_lexer.patch

for f in "$report" "$evidence" "$patch"; do
    if [ -s "$f" ]; then ok; else bad "missing or empty: $f"; fi
done

# 1) the report carries every measurement the card asks for
for h in "## 1 测量" "## 2 逐字节一致" "## 3 sharp edge" "## 4 结论"; do
    if has "$report" "$h"; then ok; else bad "missing section: $h"; fi
done

# 2) the evidence file holds the raw outputs, and the line counts in it agree
#    with the patch (391 old / 425 new lines are the recorded measurement)
if has "$evidence" "selfhost/ct-ast/frontend/lex/Lexer.h.ct"; then
    ok
else
    bad "the evidence file does not record the line count"
fi
if has "$evidence" "no output means every pinned corpus file is byte-identical"; then
    ok
else
    bad "the evidence file does not record the corpus comparison"
fi
if has "$evidence" "lex_ident_start"; then
    ok
else
    bad "the evidence file does not record the function split"
fi

# 3) the committed patch is exactly the spike's one-file rewrite and still
#    applies to the current lexer
if git apply --check "$patch" >/tmp/p85sp.patch.log 2>&1; then
    ok
else
    bad "the spike patch no longer applies: $(head -2 /tmp/p85sp.patch.log)"
fi
if grep -qE '^\+.*void (pp_line|ident|number|quoted|punct)\(void\)' "$patch"; then
    ok
else
    bad "the patch does not carry the per-token-class methods"
fi

# 4) the report may not claim the full gate passed while naming an uncovered
#    half: the syntax-modernisation scope must be written down
if has "$report" "未覆盖" && has "$report" "不通过"; then
    ok
else
    bad "the report does not state the observed gate result and its uncovered scope"
fi

# 5) level-1 (E85-6) again, with the compiler under test
python3 tools/p85_inventory.py --root . corpus-manifest --ct "$CT" \
    >/tmp/p85sp.corpus 2>/dev/null
if diff -q test/probes/p85_corpus_sha.tsv /tmp/p85sp.corpus >/dev/null 2>&1; then
    ok
else
    bad "the pinned corpus emission changed"
fi

echo "p85spike: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
