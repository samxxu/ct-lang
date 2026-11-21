#!/usr/bin/env bash
# PH-87 S87a probe: the parser's node-kind dispatch is rewritten as one slice
# per kind.
#
# `Expr::static_ctype` used to be a `switch (arena->nodes[n].kind)` with the
# bodies inline. PH-87 splits it into 13 `ctype_*` functions and reads the kind
# once, so the dispatch is a slice table and a missing kind is visible. This
# probe:
#   1) inventories the slice set and the covered kinds;
#   2) proves the inventory actually catches a missing slice (it deletes one
#      dispatch line in a temporary copy and requires the same check to fail);
#   3) compiles, type-checks and runs a fixture that walks the sliced shapes.
#
# Usage: bash test/ast/p87_parser.sh <ct-ast>
set -u
CT=${1:?usage: p87_parser.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p87parser.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p87parser: $1" >&2; }

expr=selfhost/ct-ast/frontend/parse/Expr.h.ct
if [ ! -f "$expr" ]; then
    echo "FAIL p87parser: $expr is missing" >&2
    exit 1
fi

cat >"$tmp/check.py" <<'PY'
import re, sys
path = sys.argv[1]
src = open(path, encoding="utf-8").read()
problems = []
m = re.search(r'^    int static_ctype\(int n, char \*out, int cap, int \*array_depth, int depth\)\n    \{\n(.*?)\n    \}\n', src, re.S | re.M)
if not m:
    print("the static_ctype definition is missing", file=sys.stderr)
    sys.exit(1)
body = m.group(1)
if body.count("self->arena->nodes[n].kind") != 1:
    problems.append("the dispatch must read nodes[n].kind exactly once, found %d"
                    % body.count("self->arena->nodes[n].kind"))
if "switch (" in body:
    problems.append("a switch is still in the dispatch")
if re.search(r'case N_', body):
    problems.append("a case label is still in the dispatch")
helpers = sorted(set(re.findall(r'^static int (ctype_\w+)\(struct Expr \*self', src, re.M)))
want_helpers = ["ctype_adtctor", "ctype_var", "ctype_try", "ctype_index", "ctype_deref",
                "ctype_addr", "ctype_member_or_arrow", "ctype_call", "ctype_opt",
                "ctype_mcall", "ctype_slice_index", "ctype_slice_get", "ctype_slice_range"]
if helpers != sorted(want_helpers):
    problems.append("the slice set drifted: %s" % ",".join(helpers))
calls = sorted(set(re.findall(r'\b(ctype_\w+)\(self', body)))
if calls != helpers:
    problems.append("dispatch calls and helpers differ: calls=%s helpers=%s" % (calls, helpers))
kinds = sorted(set(re.findall(r'k == (N_\w+)', body)))
want_kinds = sorted(["N_ADTCTOR", "N_VAR", "N_TRY", "N_INDEX", "N_DEREF", "N_ADDR",
                     "N_MEMBER", "N_ARROW", "N_CALL", "N_OPT", "N_MCALL",
                     "N_SLICE_INDEX", "N_SLICE_GET", "N_SLICE_RANGE"])
if kinds != want_kinds:
    problems.append("covered kinds differ: %s" % ",".join(kinds))
if problems:
    for p in problems:
        print(p, file=sys.stderr)
    sys.exit(1)
print("slices=%d kinds=%d" % (len(helpers), len(kinds)))
PY

# 1) the slice inventory
if out=$(python3 "$tmp/check.py" "$expr" 2>"$tmp/check.err"); then
    ok; echo "  p87parser: $out"
else
    bad "$(head -2 "$tmp/check.err" | tr '\n' ' ')"
fi

# 2) the check must be able to fail: delete one dispatch line in a copy
python3 - "$expr" "$tmp/mutated.h.ct" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
needle = "        if (k == N_VAR) return ctype_var(self, n, out, cap, array_depth, depth);\n"
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
    echo "  p87parser: missing-slice negative is red"
fi

# 3) the sliced shapes type-check, compile and run
if [ ! -f test/ast/p87_parser/prog.ct ]; then
    bad "test/ast/p87_parser/prog.ct is missing"
else
    if CT_C_BOUNDARY=allow "$CT" check test/ast/p87_parser/prog.ct >"$tmp/check.out" 2>"$tmp/check.err"; then
        ok
    else
        bad "ct check rejected the fixture: $(head -2 "$tmp/check.err" | tr '\n' ' ')"
    fi
    if "$CT" build test/ast/p87_parser/prog.ct -o "$tmp/prog" >"$tmp/build.out" 2>"$tmp/build.err" \
       && "$tmp/prog" >"$tmp/prog.out" 2>"$tmp/prog.err" \
       && diff -u test/ast/p87_parser/prog.expected.out "$tmp/prog.out" >"$tmp/diff.txt" 2>&1; then
        ok
    else
        bad "the fixture output differs: $(head -3 "$tmp/diff.txt" "$tmp/build.err" 2>/dev/null | tr '\n' ' ')"
    fi
fi

echo "p87parser: $pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then echo "OK p87parser"; fi
[ "$fail" -eq 0 ]
