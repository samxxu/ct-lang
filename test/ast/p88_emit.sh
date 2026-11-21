#!/usr/bin/env bash
# PH-88 S88a probe: the emitter's node-kind dispatch is rewritten as one
# function per kind, with the kind read once by the dispatcher.
#
# `emit_node` / `emit_expr` / `emit_type_decl` / `emit_inline` / `emit_field`
# used to be if-chains that re-read `nodes[n].kind` at every arm. PH-88 moves
# each arm into a free function (`em_node_*`, `em_expr_*`, ...), reads the kind
# once, and passes it in; a kind without a slice is a visible hole. This probe:
#   1) inventories the slice set and the covered kinds per dispatcher;
#   2) proves the inventory catches a missing slice (it deletes one dispatch
#      line in a temporary copy and requires the same check to fail);
#   3) proves the rewrite is byte-identical for the test corpus (D-017 A1
#      layer 1): the frozen 66-file manifest must still match.
#
# Usage: bash test/ast/p88_emit.sh <ct-ast>
set -u
CT=${1:?usage: p88_emit.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p88emit.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p88emit: $1" >&2; }

src=selfhost/ct-ast/backend/emit/Emitter.h.ct
if [ ! -f "$src" ]; then
    echo "FAIL p88emit: $src is missing" >&2
    exit 1
fi

cat >"$tmp/check.py" <<'PY'
import re, sys

path = sys.argv[1]
src = open(path, encoding="utf-8").read()

EXPECT = {
    "emit_expr": {
        "calls": ["em_expr_addr", "em_expr_adtctor", "em_expr_arrow",
                  "em_expr_assign", "em_expr_bin", "em_expr_bin_comma",
                  "em_expr_box", "em_expr_call", "em_expr_cast",
                  "em_expr_compound", "em_expr_deref", "em_expr_fnum",
                  "em_expr_index", "em_expr_into", "em_expr_into_self",
                  "em_expr_mcall", "em_expr_member", "em_expr_newobj",
                  "em_expr_num", "em_expr_offsetof", "em_expr_opt",
                  "em_expr_post", "em_expr_pre", "em_expr_raw",
                  "em_expr_sizeof", "em_expr_slice_get", "em_expr_slice_index",
                  "em_expr_slice_range", "em_expr_str", "em_expr_tern",
                  "em_expr_try", "em_expr_unary", "em_expr_vaarg",
                  "em_expr_var"],
        "kinds": ["N_ADDR", "N_ADTCTOR", "N_ARROW", "N_ASSIGN", "N_BIN",
                  "N_BOX", "N_CALL", "N_CAST", "N_COMPOUND", "N_DEREF",
                  "N_FNUM", "N_INDEX", "N_INTO", "N_INTO_SELF", "N_MCALL",
                  "N_MEMBER", "N_NEWOBJ", "N_NUM", "N_OFFSETOF", "N_OPT",
                  "N_POST", "N_PRE", "N_RAW", "N_SIZEOF", "N_SLICE_GET",
                  "N_SLICE_INDEX", "N_SLICE_RANGE", "N_STR", "N_TERN",
                  "N_TRY", "N_UNARY", "N_VAARG", "N_VAR"],
    },
    "emit_node": {
        "calls": ["em_node_block", "em_node_break", "em_node_case",
                  "em_node_cont", "em_node_decl", "em_node_decls",
                  "em_node_defer", "em_node_defer_run", "em_node_delete",
                  "em_node_dowhile", "em_node_empty", "em_node_expr_matseq",
                  "em_node_expression_statement", "em_node_for",
                  "em_node_foreach", "em_node_func", "em_node_goto",
                  "em_node_if", "em_node_label", "em_node_loop",
                  "em_node_match", "em_node_matseq", "em_node_ret",
                  "em_node_sassert", "em_node_switch", "em_node_while"],
        "kinds": ["N_ASSIGN", "N_BIN", "N_BLOCK", "N_BREAK", "N_CASE",
                  "N_CONT", "N_DECL", "N_DECLS", "N_DEFER", "N_DEFER_RUN",
                  "N_DELETE", "N_DOWHILE", "N_EMPTY", "N_EXPR", "N_FOR",
                  "N_FOREACH", "N_FUNC", "N_GOTO", "N_IF", "N_LABEL",
                  "N_LOOP", "N_MATCH", "N_MATSEQ", "N_POST", "N_RET",
                  "N_SASSERT", "N_SWITCH", "N_WHILE"],
    },
    "emit_type_decl": {
        "calls": ["em_decl_enum", "em_decl_enum_adt", "em_decl_global",
                  "em_decl_struct", "em_decl_typedef", "em_decl_union"],
        "kinds": ["N_ENUM", "N_GLOBAL", "N_STRUCT", "N_TYPEDEF", "N_UNION"],
    },
    "emit_inline": {
        "calls": ["em_inline_assign", "em_inline_bin_comma",
                  "em_inline_decl_field", "em_inline_decls",
                  "em_inline_expr", "em_inline_field_bitfield",
                  "em_inline_post", "em_inline_try"],
        "kinds": ["N_ASSIGN", "N_BIN", "N_DECL", "N_DECLS", "N_EXPR",
                  "N_FIELD", "N_POST", "N_TRY"],
    },
    "emit_field": {
        "calls": ["em_field_field_union", "em_field_fields"],
        "kinds": ["N_FIELD", "N_FIELDS"],
    },
}


def skip(s, i):
    if s.startswith('/*', i):
        e = s.find('*/', i + 2)
        return len(s) if e < 0 else e + 2
    if s.startswith('//', i):
        e = s.find('\n', i + 2)
        return len(s) if e < 0 else e
    if s[i] in '"\'':
        q = s[i]
        j = i + 1
        while j < len(s):
            if s[j] == '\\':
                j += 2
                continue
            if s[j] == q:
                return j + 1
            j += 1
        return len(s)
    return i


def match_brace(s, i):
    d = 0
    j = i
    while j < len(s):
        if s.startswith('/*', j) or s.startswith('//', j) or s[j] in '"\'':
            j = skip(s, j)
            continue
        if s[j] == '{':
            d += 1
        elif s[j] == '}':
            d -= 1
            if d == 0:
                return j
        j += 1
    raise SystemExit('unbalanced braces')


problems = []
total_slices = 0
for fn, want in EXPECT.items():
    m = re.search(r'^    int ' + fn + r'\(', src, re.M)
    if not m:
        problems.append('%s: the dispatcher is missing' % fn)
        continue
    j = src.index('{', m.end())
    body = src[j:match_brace(src, j)]
    if body.count('self->arena->nodes[n].kind') != 1:
        problems.append('%s: the dispatcher must read nodes[n].kind exactly once, found %d'
                        % (fn, body.count('self->arena->nodes[n].kind')))
    if 'switch (' in body:
        problems.append('%s: a switch is still in the dispatcher' % fn)
    if re.search(r'\bcase N_', body):
        problems.append('%s: a case label is still in the dispatcher' % fn)
    calls = sorted(set(re.findall(r'(?:^|\s)(em_[a-z0-9_]+)\(self', body)))
    if calls != sorted(want['calls']):
        problems.append('%s: slice calls drifted: %s' % (fn, ','.join(calls)))
    kinds = sorted(set(re.findall(r'\b(N_[A-Z0-9_]+)\b', body)))
    if kinds != sorted(want['kinds']):
        problems.append('%s: covered kinds drifted: %s' % (fn, ','.join(kinds)))
    for name in calls:
        m2 = re.search(r'^static int ' + re.escape(name) + r'\(', src, re.M)
        if not m2:
            problems.append('%s: slice %s is called but not defined' % (fn, name))
            continue
        j2 = src.index('{', m2.end())
        sbody = src[j2:match_brace(src, j2)]
        if 'self->arena->nodes[n].kind' in sbody:
            problems.append('%s: slice %s still reads nodes[n].kind' % (fn, name))
        if 'int nk' not in src[m2.start():j2]:
            problems.append('%s: slice %s does not take the read kind' % (fn, name))
        total_slices += 1

if total_slices != 76:
    problems.append('slice total is %d, expected 76' % total_slices)

if problems:
    for p in problems:
        print(p, file=sys.stderr)
    sys.exit(1)
print('slices=%d' % total_slices)
PY

# 1) the slice inventory
if out=$(python3 "$tmp/check.py" "$src" 2>"$tmp/check.err"); then
    ok; echo "  p88emit: $out"
else
    bad "$(head -3 "$tmp/check.err" | tr '\n' ' ')"
fi

# 2) the inventory must be able to fail: drop one dispatch line in a copy
if python3 - "$src" "$tmp/mutated.h.ct" <<'PY'
import sys
src = open(sys.argv[1], encoding="utf-8").read()
needle = "        if (nk == N_NUM) return em_expr_num(self, n, nk);\n"
assert needle in src, "the N_NUM dispatch line is missing"
open(sys.argv[2], "w", encoding="utf-8").write(src.replace(needle, "", 1))
PY
then
    if python3 "$tmp/check.py" "$tmp/mutated.h.ct" >/dev/null 2>&1; then
        bad "the inventory did not notice a missing dispatch line"
    else
        ok; echo "  p88emit: missing-arm negative is red"
    fi
else
    bad "could not build the missing-arm mutant"
fi

# 3) byte-identical corpus (D-017 A1 layer 1). The manifest normalises the
# `Generated by ct v<X.Y.Z>` banner; every other byte must match.
if python3 tools/p85_inventory.py --root . corpus-manifest --ct "$CT" \
        >"$tmp/manifest.tsv" 2>"$tmp/manifest.err" \
   && diff "$tmp/manifest.tsv" test/probes/p85_corpus_sha.tsv >"$tmp/manifest.diff" 2>&1; then
    ok; echo "  p88emit: 66 corpus files are byte-identical"
else
    bad "the test corpus changed: $(head -3 "$tmp/manifest.diff" "$tmp/manifest.err" 2>/dev/null | tr '\n' ' ')"
fi

echo "p88emit: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
