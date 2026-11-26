#!/usr/bin/env bash
# v1-PH-0 S0.5b probe: the remaining kind discriminators (`expr_ctype`,
# `maybe_box`, `chk_type`) are exhaustive `match` over the same NodeKind view
# as the emitter dispatchers.
#
# The probe:
#   1) inventories the matches and requires every one to cover all NodeKind
#      variants (no `_`, no or-patterns);
#   2) proves the inventory catches a missing arm: it deletes the `NK_STR` arm
#      from `chk_type` in a source copy and requires
#      `match does not cover variant 'NodeKind.NK_STR'`.
#
# Behaviour equivalence (the pinned corpus byte-identical, 345 diagnostics verbatim,
# 2-round self-hosting fixpoint) is covered by p88_emit / p86_errors and the
# check-ast fixpoint section.
#
# Usage: bash test/ast/p88_helpers.sh <ct-ast>
set -u
CT=${1:?usage: p88_helpers.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p88help.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p88helpers: $1" >&2; }

cat >"$tmp/check.py" <<'PY'
import os, re, sys

root = sys.argv[1]
arena = open(os.path.join(root, "selfhost/ct-ast/runtime/arena/Arena.h.ct"), encoding="utf-8").read()

def read(path):
    return open(os.path.join(root, path), encoding="utf-8").read()

# The three functions and the number of NodeKind matches each must carry.
TARGETS = [
    ("selfhost/ct-ast/frontend/type/TypeCheck.h.ct", "expr_ctype", 1),
    ("selfhost/ct-ast/frontend/type/TypeCheck.h.ct", "maybe_box", 3),
    ("selfhost/ct-ast/frontend/parse/ExprTypes.h.ct", "chk_type_text", 1),
]

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

def body_of(src, fn):
    m = re.search(r"^    (?:int\s+|const char \*)" + fn + r"\([^;\n]*\)\n    \{", src, re.M)
    if not m:
        return None
    j = src.index("{", m.end() - 1)
    return src[j:match_brace(src, j) + 1]

def match_blocks(body):
    out = []
    for m in re.finditer(r"match \(\(NodeKind\)\{ \.tag = [a-z][a-z0-9_]* \}\) \{", body):
        j = body.index("{", m.end() - 1)
        out.append(body[j:match_brace(body, j) + 1])
    return out

def arms_of(block):
    starts = [m.start() for m in re.finditer(r"NodeKind\.NK_([A-Z0-9_]+)\(\) => \{", block)]
    names = []
    for i, p in enumerate(starts):
        end = starts[i + 1] if i + 1 < len(starts) else len(block)
        m = re.match(r"NodeKind\.NK_([A-Z0-9_]+)\(\) => \{", block[p:])
        names.append((m.group(1), block[p:end]))
    return names

m = re.search(r"^pub enum NodeKind \{(.*?)^\}", arena, re.S | re.M)
if not m:
    print("Arena.h.ct: the NodeKind enum is missing", file=sys.stderr)
    sys.exit(1)
variants = re.findall(r"^\s+NK_([A-Z0-9_]+)\(\),", m.group(1), re.M)

problems = []
total_matches = 0
for path, fn, want_matches in TARGETS:
    src = read(path)
    body = body_of(src, fn)
    if body is None:
        problems.append("%s: %s is missing" % (path, fn))
        continue
    if body.count("nodes[n].kind") != 1:
        problems.append("%s: %s must read nodes[n].kind exactly once, found %d"
                        % (path, fn, body.count("nodes[n].kind")))
    if "switch (self->arena->nodes[n].kind)" in body:
        problems.append("%s: %s still has the old switch" % (path, fn))
    if re.search(r"\bcase N_", body):
        problems.append("%s: %s still has a case label" % (path, fn))
    blocks = match_blocks(body)
    if len(blocks) != want_matches:
        problems.append("%s: %s has %d NodeKind matches, expected %d"
                        % (path, fn, len(blocks), want_matches))
    for bi, block in enumerate(blocks):
        if re.search(r"NodeKind\.NK_[A-Z0-9_]+\(\)\s*\|\||\|\|\s*NodeKind\.NK_", block):
            problems.append("%s: %s match %d has an or-pattern" % (path, fn, bi + 1))
        arms = arms_of(block)
        got = sorted(n for n, _ in arms)
        if got != sorted(variants):
            problems.append("%s: %s match %d arms drifted from the NodeKind variants"
                            % (path, fn, bi + 1))
        total_matches += 1

if problems:
    for p in problems:
        print(p, file=sys.stderr)
    sys.exit(1)
print("helpers=%d matches=%d variants=%d" % (len(TARGETS), total_matches, len(variants)))
PY

if out=$(python3 "$tmp/check.py" "$root" 2>"$tmp/check.err"); then
    ok; echo "  p88helpers: $out"
else
    bad "$(head -3 "$tmp/check.err" | tr '\n' ' ')"
fi

# Missing-arm negative: delete the NK_STR arm from chk_type_text in a copy.
if python3 - "$root" "$tmp/mut/tree" <<'PY'
import os, re, shutil, sys
root, dest = sys.argv[1], sys.argv[2]
src = os.path.join(root, "selfhost/ct-ast/frontend/parse/ExprTypes.h.ct")
text = open(src, encoding="utf-8").read()
pat = re.compile(r"                NodeKind\.NK_STR\(\) => \{\n.*?\n                \}\n", re.S)
if not pat.search(text):
    raise SystemExit("the NK_STR arm is missing")
if os.path.isdir(dest):
    shutil.rmtree(dest)
shutil.copytree(os.path.join(root, "selfhost/ct-ast"), dest)
open(os.path.join(dest, "frontend/parse/ExprTypes.h.ct"), "w", encoding="utf-8").write(
    pat.sub("", text, count=1))
PY
then
    rm -rf "$tmp/mut/out"
    mkdir -p "$tmp/mut/out"
    if CT_C_BOUNDARY=allow "$CT" build --emit-c -I "$tmp/mut/tree" \
            "$tmp/mut/tree/main.ct" -o "$tmp/mut/out" \
            >"$tmp/mut/build.out" 2>"$tmp/mut/build.err"; then
        bad "the missing-arm source compiled"
    elif grep -q "match does not cover variant 'NodeKind.NK_STR'" "$tmp/mut/build.err"; then
        ok; echo "  p88helpers: missing-arm negative is red (match does not cover variant)"
    else
        bad "the missing-arm build failed for another reason: $(head -2 "$tmp/mut/build.err" | tr '\n' ' ')"
    fi
else
    bad "could not build the missing-arm mutant"
fi

echo "p88helpers: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
