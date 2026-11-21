#!/usr/bin/env bash
# PH-84 S84e probe: the minimal documentation audit frozen by
# battle/doc-consistency-1 (verdict B).
#
# B's scope is a *minimal set*: the required sections of language-spec /
# tutorial / patterns stay the reference, and the entry/index documents get
# fact-and-link corrections only (no rewrite). This probe pins that set:
#
#   - spec §4.68 / §4.69 / §4.70 / §4.71 / §4.73 and tutorial §15 / §17 / §18,
#     patterns §5 / §6 all resolve;
#   - llm-guide's built-in-layer list names String / U16String and the borrowed
#     Str view, and no longer points at the removed `std::str`;
#   - glossary carries Str (borrowed), String, ADT, variant and `match` rows;
#   - architecture says the ct-ast-only features (incl. §4.73) are outside L0;
#   - README points at §4.73 / tutorial §18 / patterns §6.
#
# Usage: bash test/ast/p84_docs_audit.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fail=0

need() {   # need <file> <needle>
    if ! grep -qF -- "$2" "$root/$1"; then
        echo "FAIL p84audit: $1 does not mention '$2'" >&2
        fail=1
    fi
}

absent() { # absent <file> <needle>
    if grep -qF -- "$2" "$root/$1"; then
        echo "FAIL p84audit: $1 still mentions the stale '$2'" >&2
        fail=1
    fi
}

spec=docs/language-spec.md
tut=docs/tutorial.md
pat=docs/patterns.md

# ---- the required sections (J-2) -------------------------------------------
for sec in "^### 4\\.68 " "^### 4\\.69 " "^### 4\\.70 " "^### 4\\.71 " "^### 4\\.73 "; do
    if ! grep -qE "$sec" "$root/$spec"; then
        echo "FAIL p84audit: language-spec is missing $sec" >&2
        fail=1
    fi
done
for sec in "^## 15\\. " "^## 17\\. " "^## 18\\. "; do
    if ! grep -qE "$sec" "$root/$tut"; then
        echo "FAIL p84audit: tutorial is missing $sec" >&2
        fail=1
    fi
done
for sec in "^## 5 " "^## 6\\. "; do
    if ! grep -qE "$sec" "$root/$pat"; then
        echo "FAIL p84audit: patterns is missing $sec" >&2
        fail=1
    fi
done

# ---- llm-guide: the built-in layer list and the removed std::str -----------
need docs/llm-guide.md 'String'
need docs/llm-guide.md 'U16String'
need docs/llm-guide.md '借用视图'
absent docs/llm-guide.md 'std::str'

# ---- glossary: borrowed Str, owning String, ADT / variant / match ----------
need docs/glossary.md '借用字符串 Str'
need docs/glossary.md '拥有字符串 String'
need docs/glossary.md 'ADT / 和类型'
need docs/glossary.md '变体（variant）'
need docs/glossary.md '`match` |'

# ---- architecture: the ct-ast-only features are outside L0 -----------------
need docs/architecture.md 'ADT/`match`（§4.73）'
need docs/architecture.md 'ct-ast'

# ---- README: the pointers a new reader follows -----------------------------
need README.md 'ADT/`match` 见 §4.73'
need README.md 'ADT 见 §18'
need README.md '`kind` 判别改写见 §6'

[ "$fail" -eq 0 ] && echo "OK p84docs_audit"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
