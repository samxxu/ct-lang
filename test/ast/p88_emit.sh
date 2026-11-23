#!/usr/bin/env bash
# PH-88 S88a / v1-PH-0 S0.5a probe: the emitter's node-kind dispatch is one
# exhaustive `match` arm per kind, with the kind read once and passed to a
# single per-kind helper.
#
# v0-PH-88 moved each arm of `emit_node` / `emit_expr` / `emit_type_decl` /
# `emit_inline` / `emit_field` into a free function (`em_node_*`, `em_expr_*`,
# ...) and read the kind once. v1-PH-0 S0.5a replaces the if-chain with an
# exhaustive `match` over the `NodeKind` view (one arm per kind, no or
# patterns); this probe:
#   1) inventories the match arms and the 76 helper calls, and pins the
#      `NodeKind` variant list against the N_* kind numbers;
#   2) proves the inventory catches a missing arm: it deletes the N_NUM arm in
#      a temporary source copy and requires the compiler to reject it with
#      `match does not cover variant 'NodeKind.NK_NUM'`;
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
arena=selfhost/ct-ast/runtime/arena/Arena.h.ct
if [ ! -f "$src" ]; then
    echo "FAIL p88emit: $src is missing" >&2
    exit 1
fi
if [ ! -f "$arena" ]; then
    echo "FAIL p88emit: $arena is missing" >&2
    exit 1
fi

cat >"$tmp/check.py" <<'PY'
import glob, os, re, sys

root = sys.argv[1]
src = open(os.path.join(root, "selfhost/ct-ast/backend/emit/Emitter.h.ct"), encoding="utf-8").read()
arena = open(os.path.join(root, "selfhost/ct-ast/runtime/arena/Arena.h.ct"), encoding="utf-8").read()

# kind -> the helper its arm must call. The 76 entries are the 76 em_*
# slices v0-PH-88 introduced; each kind has exactly one arm.
EXPECT = {
    "emit_expr": {
        "N_ADDR": "em_expr_addr", "N_ADTCTOR": "em_expr_adtctor",
        "N_ARROW": "em_expr_arrow", "N_ASSIGN": "em_expr_assign",
        "N_BIN": "em_expr_bin", "N_BOX": "em_expr_box",
        "N_CALL": "em_expr_call", "N_CAST": "em_expr_cast",
        "N_COMPOUND": "em_expr_compound", "N_DEREF": "em_expr_deref",
        "N_FNUM": "em_expr_fnum", "N_INDEX": "em_expr_index",
        "N_INTO": "em_expr_into", "N_INTO_SELF": "em_expr_into_self",
        "N_MCALL": "em_expr_mcall", "N_MEMBER": "em_expr_member",
        "N_NEWOBJ": "em_expr_newobj", "N_NUM": "em_expr_num",
        "N_OFFSETOF": "em_expr_offsetof", "N_OPT": "em_expr_opt",
        "N_POST": "em_expr_post", "N_PRE": "em_expr_pre",
        "N_RAW": "em_expr_raw", "N_SIZEOF": "em_expr_sizeof",
        "N_SLICE_GET": "em_expr_slice_get", "N_SLICE_INDEX": "em_expr_slice_index",
        "N_SLICE_RANGE": "em_expr_slice_range", "N_STR": "em_expr_str",
        "N_TERN": "em_expr_tern", "N_TRY": "em_expr_try",
        "N_UNARY": "em_expr_unary", "N_VAARG": "em_expr_vaarg",
        "N_VAR": "em_expr_var",
    },
    "emit_node": {
        "N_ASSIGN": "em_node_expression_statement",
        "N_BIN": "em_node_expression_statement",
        "N_BLOCK": "em_node_block", "N_BREAK": "em_node_break",
        "N_CASE": "em_node_case", "N_CONT": "em_node_cont",
        "N_DECL": "em_node_decl", "N_DECLS": "em_node_decls",
        "N_DEFER": "em_node_defer", "N_DEFER_RUN": "em_node_defer_run",
        "N_DELETE": "em_node_delete", "N_DOWHILE": "em_node_dowhile",
        "N_EMPTY": "em_node_empty", "N_EXPR": "em_node_expr_matseq",
        "N_FOR": "em_node_for", "N_FOREACH": "em_node_foreach",
        "N_FUNC": "em_node_func", "N_GOTO": "em_node_goto",
        "N_IF": "em_node_if", "N_LABEL": "em_node_label",
        "N_LOOP": "em_node_loop", "N_MATCH": "em_node_match",
        "N_MATSEQ": "em_node_matseq", "N_POST": "em_node_expression_statement",
        "N_RET": "em_node_ret", "N_SASSERT": "em_node_sassert",
        "N_SWITCH": "em_node_switch", "N_WHILE": "em_node_while",
    },
    "emit_type_decl": {
        "N_ENUM": "em_decl_enum", "N_GLOBAL": "em_decl_global",
        "N_STRUCT": "em_decl_struct", "N_TYPEDEF": "em_decl_typedef",
        "N_UNION": "em_decl_union",
    },
    "emit_inline": {
        "N_ASSIGN": "em_inline_assign", "N_BIN": "em_inline_bin_comma",
        "N_DECL": "em_inline_decl_field", "N_DECLS": "em_inline_decls",
        "N_EXPR": "em_inline_expr", "N_FIELD": "em_inline_decl_field",
        "N_POST": "em_inline_post", "N_TRY": "em_inline_try",
    },
    "emit_field": {
        "N_FIELD": "em_field_field_union", "N_FIELDS": "em_field_fields",
    },
}

# N_ENUM has two helpers (plain enum / ADT enum), selected by aux & 2.
EXTRA_HELPERS = {"emit_type_decl": {"N_ENUM": ["em_decl_enum_adt"]}}

def skip(s, i):
    if s.startswith("/*", i):
        e = s.find("*/", i + 2)
        return len(s) if e < 0 else e + 2
    if s.startswith("//", i):
        e = s.find("\n", i + 2)
        return len(s) if e < 0 else e
    if s[i] in "\"'":
        q = s[i]
        j = i + 1
        while j < len(s):
            if s[j] == "\\":
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
        if s.startswith("/*", j) or s.startswith("//", j) or s[j] in "\"'":
            j = skip(s, j)
            continue
        if s[j] == "{":
            d += 1
        elif s[j] == "}":
            d -= 1
            if d == 0:
                return j
        j += 1
    raise SystemExit("unbalanced braces")

def body_of(fn):
    m = re.search(r"^    int " + fn + r"\(", src, re.M)
    if not m:
        return None
    j = src.index("{", m.end())
    return src[j:match_brace(src, j) + 1]

def arms_of(body):
    starts = [m.start() for m in re.finditer(r"NodeKind\.NK_([A-Z0-9_]+)\(\) => \{", body)]
    names = []
    for i, p in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(body)
        m = re.match(r"NodeKind\.NK_([A-Z0-9_]+)\(\) => \{", body[p:])
        names.append((m.group(1), body[p:end]))
    return names

problems = []
total_slices = 0
seen_helpers = set()

# The NodeKind view must list exactly one variant per kind value, in order.
m = re.search(r"^pub enum NodeKind \{(.*?)^\}", arena, re.S | re.M)
if not m:
    problems.append("Arena.h.ct: the NodeKind enum is missing")
    node_variants = []
else:
    node_variants = re.findall(r"^\s+NK_([A-Z0-9_]+)\(\),", m.group(1), re.M)

kind_nums = {}
for f in glob.glob(os.path.join(root, "selfhost/ct-ast/**/*.ct"), recursive=True):
    for line in open(f, encoding="utf-8"):
        mm = re.match(r"#define\s+(N_[A-Z0-9_]+)\s+(\d+)\s*$", line)
        if mm:
            kind_nums.setdefault(int(mm.group(2)), set()).add(mm.group(1)[2:])
expected_variants = []
for v in range(max(kind_nums) + 1 if kind_nums else 0):
    names = kind_nums.get(v)
    if not names:
        expected_variants.append("UNUSED%d" % v)
    elif len(names) > 1:
        problems.append("kind %d has conflicting macros: %s" % (v, ",".join(sorted(names))))
    else:
        expected_variants.append(next(iter(names)))
if node_variants != expected_variants:
    problems.append("NodeKind variants drifted from the N_* numbering: %s"
                    % ",".join(expected_variants))

for fn, want in EXPECT.items():
    body = body_of(fn)
    if body is None:
        problems.append("%s: the dispatcher is missing" % fn)
        continue
    if body.count("nodes[n].kind") != 1:
        problems.append("%s: the dispatcher must read nodes[n].kind exactly once, found %d"
                        % (fn, body.count("nodes[n].kind")))
    if "match ((NodeKind){ .tag = nk })" not in body:
        problems.append("%s: the dispatcher is not a match over the NodeKind view" % fn)
    if "switch (" in body:
        problems.append("%s: a switch is still in the dispatcher" % fn)
    if re.search(r"\bcase N_", body):
        problems.append("%s: a case label is still in the dispatcher" % fn)
    if "||" in body:
        problems.append("%s: an or-pattern is not allowed" % fn)
    arms = arms_of(body)
    got = sorted(n for n, _ in arms)
    if got != sorted(node_variants):
        problems.append("%s: match arms drifted from the NodeKind variants" % fn)
    for kind, text in arms:
        called = set(re.findall(r"\b(em_[a-z0-9_]+)\(self", text))
        if called:
            seen_helpers |= called
            want_kind = kind if kind in want else None
            # emit_node N_DECL and N_ENUM have two helpers; the primary is enough
            if want_kind and want[want_kind] not in called:
                problems.append("%s: %s arm does not call %s" % (fn, kind, want[want_kind]))
    # each expected kind has exactly one arm that calls its helper
    for kind, helper in want.items():
        arm = [t for n, t in arms if n == kind[2:]]
        if len(arm) != 1:
            problems.append("%s: expected exactly one %s arm, found %d" % (fn, kind, len(arm)))
            continue
        if helper + "(self" not in arm[0]:
            problems.append("%s: %s arm does not call %s" % (fn, kind, helper))
        for extra in EXTRA_HELPERS.get(fn, {}).get(kind, []):
            if extra + "(self" not in arm[0]:
                problems.append("%s: %s arm does not call %s" % (fn, kind, extra))

for name in sorted(seen_helpers):
    m2 = re.search(r"^static int " + re.escape(name) + r"\(", src, re.M)
    if not m2:
        problems.append("slice %s is called but not defined" % name)
        continue
    j2 = src.index("{", m2.end())
    sbody = src[j2:match_brace(src, j2) + 1]
    if "self->arena->nodes[n].kind" in sbody:
        problems.append("slice %s still reads nodes[n].kind" % name)
    if "int nk" not in src[m2.start():j2]:
        problems.append("slice %s does not take the read kind" % name)
    total_slices += 1

if total_slices != 76:
    problems.append("slice total is %d, expected 76" % total_slices)
if len(seen_helpers) != 76:
    problems.append("helper calls cover %d names, expected 76" % len(seen_helpers))

if problems:
    for p in problems:
        print(p, file=sys.stderr)
    sys.exit(1)
print("slices=%d arms=%d variants=%d" % (total_slices, sum(len(arms_of(body_of(f))) for f in EXPECT), len(node_variants)))
PY

# 1) the match-arm inventory
if out=$(python3 "$tmp/check.py" "$root" 2>"$tmp/check.err"); then
    ok; echo "  p88emit: $out"
else
    bad "$(head -3 "$tmp/check.err" | tr '\n' ' ')"
fi

# 2) the inventory must be able to fail: delete the N_NUM arm in a source copy
#    and require the compiler to reject it at the match (not a silent fallback).
if python3 - "$src" "$tmp/mut/Emitter.h.ct" <<'PY'
import re, sys, os
src = open(sys.argv[1], encoding="utf-8").read()
pat = re.compile(r"            NodeKind\.NK_NUM\(\) => \{\n"
                 r"                return em_expr_num\(self, n, N_NUM\);\n"
                 r"            \}\n")
if not pat.search(src):
    raise SystemExit("the N_NUM arm is missing")
os.makedirs(os.path.dirname(sys.argv[2]), exist_ok=True)
open(sys.argv[2], "w", encoding="utf-8").write(pat.sub("", src, count=1))
PY
then
    rm -rf "$tmp/mut/tree" "$tmp/mut/out"
    cp -R selfhost/ct-ast "$tmp/mut/tree"
    cp "$tmp/mut/Emitter.h.ct" "$tmp/mut/tree/backend/emit/Emitter.h.ct"
    mkdir -p "$tmp/mut/out"
    if CT_C_BOUNDARY=allow "$CT" build --emit-c -I "$tmp/mut/tree" \
            "$tmp/mut/tree/main.ct" -o "$tmp/mut/out" \
            >"$tmp/mut/build.out" 2>"$tmp/mut/build.err"; then
        bad "the missing-arm source compiled"
    elif grep -q "match does not cover variant 'NodeKind.NK_NUM'" "$tmp/mut/build.err"; then
        ok; echo "  p88emit: missing-arm negative is red (match does not cover variant)"
    else
        bad "the missing-arm build failed for another reason: $(head -2 "$tmp/mut/build.err" | tr '\n' ' ')"
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
