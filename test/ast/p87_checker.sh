#!/usr/bin/env bash
# PH-87 S87b probe: the checker's node-kind dispatch is sliced, and the
# `match` spelling is proven feasible + pinned as a negative.
#
# `TypeCheck::expr_type` used to be a chain of `if (nodes[n].kind == N_X)` with
# 20 branches. PH-87 splits it into 15 `tc_expr_*` slices and reads the kind
# once. This probe:
#   1) inventories the slice set and the 20 covered kinds;
#   2) proves the inventory catches a missing slice (mutation self-test);
#   3) runs the typed-view feasibility fixture (ADT + exhaustive `match`, the
#      shape the slices become once the bootstrap can parse it);
#   4) pins the language-level missing-arm negative verbatim;
#   5) checks the battle/evidence that records why the spelling cannot land in
#      ct-ast's own source in v0.87.0 (L2 bootstrap has no ADT/match).
#
# Usage: bash test/ast/p87_checker.sh <ct-ast>
set -u
CT=${1:?usage: p87_checker.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p87checker.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p87checker: $1" >&2; }

tc=selfhost/ct-ast/frontend/type/TypeCheck.h.ct
if [ ! -f "$tc" ]; then
    echo "FAIL p87checker: $tc is missing" >&2
    exit 1
fi

cat >"$tmp/check.py" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
problems = []
m = re.search(r'^    int expr_type\(int n, char \*out, int cap\)\n    \{\n(.*?)\n    \}\n', src, re.S | re.M)
if not m:
    print("the expr_type definition is missing", file=sys.stderr)
    sys.exit(1)
body = m.group(1)
if body.count("self->arena->nodes[n].kind") != 1:
    problems.append("the dispatch must read nodes[n].kind exactly once, found %d"
                    % body.count("self->arena->nodes[n].kind"))
if "switch (" in body:
    problems.append("a switch is still in the dispatch")
if re.search(r'case N_', body):
    problems.append("a case label is still in the dispatch")
helpers = sorted(set(re.findall(r'^static int (tc_expr_\w+)\(struct TypeCheck \*self', src, re.M)))
want_helpers = sorted(["tc_expr_adtctor", "tc_expr_var", "tc_expr_index", "tc_expr_addr",
                       "tc_expr_mcall", "tc_expr_call", "tc_expr_member_or_arrow",
                       "tc_expr_box", "tc_expr_newobj", "tc_expr_num", "tc_expr_fnum",
                       "tc_expr_str", "tc_expr_cast", "tc_expr_sizeof", "tc_expr_into",
                       "tc_expr_match"])
if helpers != want_helpers:
    problems.append("the slice set drifted: %s" % ",".join(helpers))
calls = sorted(set(re.findall(r'\b(tc_expr_\w+)\(self', body)))
if calls != helpers:
    problems.append("dispatch calls and helpers differ: calls=%s helpers=%s" % (calls, helpers))
kinds = sorted(set(re.findall(r'k == (N_\w+)', body)))
want_kinds = sorted(["N_ADTCTOR", "N_VAR", "N_INDEX", "N_ADDR", "N_MCALL", "N_CALL",
                     "N_MEMBER", "N_ARROW", "N_BOX", "N_NEWOBJ", "N_NUM", "N_FNUM",
                     "N_STR", "N_CAST", "N_COMPOUND", "N_VAARG", "N_SIZEOF",
                     "N_OFFSETOF", "N_INTO", "N_INTO_SELF", "N_MATCH"])
if kinds != want_kinds:
    problems.append("covered kinds differ: %s" % ",".join(kinds))
if problems:
    for p in problems:
        print(p, file=sys.stderr)
    sys.exit(1)
print("slices=%d kinds=%d" % (len(helpers), len(kinds)))
PY

# 1) the slice inventory
if out=$(python3 "$tmp/check.py" "$tc" 2>"$tmp/check.err"); then
    ok; echo "  p87checker: $out"
else
    bad "$(head -2 "$tmp/check.err" | tr '\n' ' ')"
fi

# 2) the check must be able to fail: delete one dispatch line in a copy
python3 - "$tc" "$tmp/mutated.h.ct" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
needle = "        if (k == N_VAR) return tc_expr_var(self, n, out, cap);\n"
if needle not in src:
    print("the mutation target is missing", file=sys.stderr)
    sys.exit(2)
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(needle, "", 1))
PY
if [ $? -ne 0 ]; then
    bad "could not build the missing-slice negative"
elif python3 "$tmp/check.py" "$tmp/mutated.h.ct" >/dev/null 2>&1; then
    bad "a missing dispatch slice survived the inventory (the probe is blind)"
else
    ok
    echo "  p87checker: missing-slice negative is red"
fi

# 3) the typed-view feasibility fixture: compile and run
if "$CT" build test/ast/p87_checker/prog.ct -o "$tmp/prog" >"$tmp/build.out" 2>"$tmp/build.err" \
   && "$tmp/prog" >"$tmp/prog.out" 2>"$tmp/prog.err" \
   && diff -u test/ast/p87_checker/prog.expected.out "$tmp/prog.out" >"$tmp/diff.txt" 2>&1; then
    ok
else
    bad "the typed-view fixture differs: $(head -3 "$tmp/diff.txt" "$tmp/build.err" 2>/dev/null | tr '\n' ' ')"
fi

# 4) the language-level missing-arm negative, verbatim
if "$CT" check test/ast/p87_checker/missing_arm.ct >"$tmp/miss.out" 2>"$tmp/miss.err"; then
    bad "an incomplete match compiled"
else
    needle=$(cat test/ast/p87_checker/missing_arm.expected.err)
    if grep -Fq "$needle" "$tmp/miss.err"; then
        ok
    else
        bad "the missing-arm diagnostic changed: $(head -2 "$tmp/miss.err" | tr '\n' ' ')"
    fi
fi

# 5) the blocker (L2 has no ADT/match) is on disk with its raw output
evidence=test/probes/p87_l2_adt_evidence.txt
verdict=battle/p87-kind-match/verdict.md
if [ -s "$evidence" ] && grep -Fq "enum NodeKind {" "$evidence" \
   && grep -Fq "AdtCtor(int n)," "$evidence" \
   && grep -Fq "20 errors generated." "$evidence"; then
    ok
else
    bad "$evidence is missing the L2 bootstrap raw output"
fi
if [ -s "$verdict" ] && grep -Fq "移交 PH-88" "$verdict"; then
    ok
else
    bad "$verdict is missing the PH-88 hand-off"
fi

echo "p87checker: $pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then echo "OK p87checker"; fi
[ "$fail" -eq 0 ]
