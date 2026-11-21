#!/usr/bin/env bash
# PH-86 S86c probe: error exits are unchanged, and the ?/errdefer scope is on
# the record.
#
# E86-4 / D-017 B4: the token-view migration must not change a single
# diagnostic. The probe re-runs every negative fixture under test/ast/errors/
# and test/ast/p86_errors/ and compares (exit status, stderr bytes) with the
# manifest frozen at baseline 1e2c30f7, then compares the lexer-boundary
# fixtures line by line. It also checks that the S86c scope decision is
# written down with its bootstrap evidence: the card asks for ?/errdefer, but
# the L2 bootstrap neither implements nor lowers them, so using either in
# ct-ast source breaks the chain (see docs/design/p86_errors.md).
#
# Usage: bash test/ast/p86_errors.sh <ct-ast>
set -u
CT=${1:?usage: p86_errors.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/p86err.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p86errors: $1" >&2; }

# ---- 1) the whole negative corpus still reports the same bytes ------------
python3 - "$CT" "$work" >"$work/manifest.out" 2>&1 <<'PY'
import hashlib, os, subprocess, sys
ct, work = sys.argv[1], sys.argv[2]
bad = []
n = 0
for line in open("test/probes/p86_error_diags.tsv", encoding="utf-8"):
    if not line.strip() or line.startswith("#"):
        continue
    path, want_exit, want_sha = line.rstrip("\n").split("\t")
    out = os.path.join(work, "e.c")
    p = subprocess.run([ct, path, "-o", out], capture_output=True)
    got_sha = hashlib.sha256(p.stderr).hexdigest()
    n += 1
    if str(p.returncode) != want_exit or got_sha != want_sha:
        bad.append("%s (exit %s/%s)" % (path, p.returncode, want_exit))
print("checked %d diagnostics, %d differ" % (n, len(bad)))
for b in bad[:10]:
    print("  DIFF", b)
sys.exit(1 if bad else 0)
PY
if [ $? -eq 0 ]; then ok; else bad "$(head -12 "$work/manifest.out" | tr '\n' ' ')"; fi

# ---- 2) the lexer-boundary fixtures keep their exact text ----------------
for f in test/ast/p86_errors/*.ct; do
    b=$(basename "$f" .ct)
    "$CT" "$f" -o "$work/$b.c" >"$work/$b.out" 2>"$work/$b.err"
    if cmp -s "$work/$b.err" "test/ast/p86_errors/$b.expected.err"; then
        ok
    else
        bad "$b: stderr changed: $(diff "test/ast/p86_errors/$b.expected.err" "$work/$b.err" | head -4 | tr '\n' ' ')"
    fi
done

# ---- 3) the stale integer-token diagnostic is intentional ----------------
if grep -qF "expected a type (tok 2 '(')" test/ast/p86_errors/stale_num_diag.expected.err; then
    ok
else
    bad "stale_num_diag no longer pins the old integer-token text"
fi

# ---- 4) the S86c scope decision and its evidence are on disk -------------
need() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok; else bad "$1 is missing '$2'"; fi; }
audit=docs/design/p86_errors.md
evidence=test/probes/p86_bootstrap_evidence.txt
need "$audit" "## 2 错误出口清单（token 路径）"
need "$audit" "## 3 \`?\` / \`errdefer\` 的范围裁定"
need "$audit" "L2"
need "$audit" "不适用"
need "$audit" "identifier is too long"
need "$audit" "stale_num_diag.ct"
need "$audit" "PH-87/88"
need "$evidence" "pass-through"
need "$evidence" "errdefer"
need "$evidence" "cc exit=1"
need "$evidence" "?;"
if [ -f battle/p86-errorpath/question.md ] && [ -f battle/p86-errorpath/verdict.md ]; then
    ok
else
    bad "battle/p86-errorpath question/verdict is missing"
fi
if grep -qF "test/probes/p86_error_diags.tsv" "$audit"; then ok; else bad "audit does not name the manifest"; fi

echo "p86errors: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
