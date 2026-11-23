#!/usr/bin/env python3
"""
check-docs.py - documentation gate (Phase 17.4).

Standard library only. It asserts seventeen invariants:

  1. every relative link in docs/**/*.md and README.md resolves;
     the only exemption is a historical snapshot under docs/history/reports/**
     that links into the since-deleted selfhost/ast/** or selfhost/src/**.
     Every `#fragment` in any Markdown link in the repository is resolved too
     (DOC-89): section anchors are checked against the target's headings using
     GitHub's slug rules, line anchors (`#L10` / `#L10-L20`) against the target
     file's length. `docs/history/**` is a frozen snapshot and is skipped; a
     few exact (source, target) pairs quoted in historical issues/battles are
     exempted in FRAGMENT_EXEMPT because they record the line numbers of their
     own date;
  2. the version token written in README.md and docs/README.md equals
     CTC_VERSION in selfhost/l0/ctc.c (and all compiler layers agree);
  3. the hard-gate count stated in README.md, docs/README.md and
     docs/glossary.md equals the number of run_gate calls in
     selfhost/check-all.sh; issues/README.md carries the same count in a
     machine-readable `<!-- gates:N -->` marker (its dated records quote
     historical counts, so prose scanning is not usable there); ci.yml job
     step labels may not name a stale count;
  4. the status line of every docs/design/phase*.md matches the Chinese phase
     table in docs/roadmap.md (done -> check, in progress -> half, planned ->
     white); the English table was removed by the docs-language policy;
  5. an "适用版本" header under docs/*.md names the compiler line, never a
     fixed version: the number goes stale at the next bump (DOC-63);
  6. G9: AGENTS.md pins the methodology's `spec-version` and `spec-sha256`
     (CI-8); a missing spec file is an explicit skip, a mismatch is red;
  7. docs/design/ keeps the newest DESIGN_WINDOW phases, older phase docs live
     in docs/history/design/ and may not be duplicated (DOC-66);
  8. every battle question's `superseded-by:` pointer and the ADR's
     `superseded-battles:` list agree in both directions;
  9. T-8 (AGENTS §0.7): an "实施中" phase card and every ADR dated on or
     after SIGNOFF_FROM carry a `签收:` line by a non-author role;
 10. DOC-85: every numbered claim in the briefing appendix of docs/idioms.md
     cites a `§N` section that exists in docs/language-spec.md. The rule is
     inactive until idioms.md lands, then it switches on with the file;
 11. SH-104: docs/planning/j6-evidence/ledger.md carries every P-1…P-6 row
     (P-3.7/3.8, P-4.6, P-5.7 included), each with a status from the fixed
     four, a non-empty 最小可判证据, and a reason on every `阻塞` row;
 12. DOC-79: the 分档清单 in docs/stable-subset.md has five cells per row,
     a legal tier, non-empty 授权 and 版本/截止, and at least one row in each
     of the three tiers;
 13. DOC-76: README.md, docs/language-spec.md and docs/roadmap.md carry the
     same ct-compat marker (claim and spec section), all state 不再自称 C 超集,
     and the spec= value resolves to a real heading;
 14. DOC-77: docs/capabilities.tsv lists every capability once with a legal
     status and a spec section that resolves (for `implemented` rows), and
     README §3 carries exactly one `<!-- cap:id -->` marker per row.
  15. DOC-94: active prose writes the language name as `Ct`, never bare `CT`.
      Fenced blocks, inline code, the generated spec block in AGENTS.md, and
      the historical/exempt trees are out of scope. `--selftest` runs the
      positive and negative fixtures for this assertion.
  16. DOC-88: docs/language-spec.md opens with a `## 目录` outline that lists
      every H2 (except the outline itself) and every H3 once; every outline
      entry resolves to a real heading. A missing outline, a missing heading,
      a duplicate entry or a dead entry is red.
  17. DOC-88: a new `docs/language-spec.md#L...` reference is red. The existing
      line anchors are frozen in test/docs/line-anchors.txt as
      `<path>#L<a>[-L<b>]  <batch>`; an entry with no reference left is a
      zombie and red, and the batch names the earliest pending batch.
      `--selftest` runs the positive/negative fixtures for both assertions.

Exit code 0 when all seventeen hold, 1 otherwise.
"""

import hashlib
import os
import re
import subprocess
import sys
import tempfile
import unicodedata
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SPEC = os.path.expanduser("~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md")
DESIGN_WINDOW = 12
SIGNOFF_FROM = "2026-11-20"

LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE = re.compile(r"`[^`\n]*`")
BRIEFING_ITEM = re.compile(r"^(\d+)\.\s+(.*)$")
SECTION_HEAD = re.compile(r"^#{3,4}\s+(\d+(?:\.\d+)*)\.?\s", re.M)
SPEC_REF = re.compile(r"§(\d+(?:\.\d+)*)")
J6_ROW = re.compile(
    r"^\|\s*(P-\d+\.\d+)\b[^|]*\|([^|]*)\|([^|]*)\|([^|]*)\|([^|]*)\|", re.M
)
J6_IDS = (
    {"P-1.%d" % i for i in (1, 2, 3, 4)}
    | {"P-2.%d" % i for i in range(1, 6)}
    | {"P-3.%d" % i for i in range(1, 9)}
    | {"P-4.%d" % i for i in range(1, 7)}
    | {"P-5.%d" % i for i in range(1, 8)}
    | {"P-6.%d" % i for i in (1, 2, 3, 4)}
)
J6_STATES = {"已过", "部分", "缺失", "阻塞"}
J6_COUNTS = re.compile(
    r"<!--\s*j6:counts\s+([^>]*)-->")
J6_COUNT_KEYS = (("passed", "已过"), ("partial", "部分"),
                 ("missing", "缺失"), ("blocked", "阻塞"))
STABLE_TIERS = ("已冻结", "冻结中", "1.0 前可改")
COMPAT_MARKER = re.compile(r"<!--\s*ct-compat:\s*([^>]*)-->")
CAP_MARKER = re.compile(r"<!--\s*cap:([a-z0-9-]+)\s*-->")
CAP_STATUS = {"implemented", "planned"}

# DOC-88: the spec outline and the frozen line-anchor ledger. The ledger keys
# on the referenced path plus the line fragment (the profile is global; the
# source file is only used to compute the earliest pending batch).
SPEC_DOC = "docs/language-spec.md"
TOC_HEADING = "目录"
LINE_ANCHOR_LEDGER = "test/docs/line-anchors.txt"
LINE_BATCHES = ("B0", "B1", "B2", "B3", "HIST")
LINE_BATCH_ORDER = {name: index for index, name in enumerate(LINE_BATCHES)}
LINE_LEDGER_ENTRY = re.compile(
    r"^(docs/language-spec\.md#L\d+(?:-L\d+)?)\s+(\S+)\s*$"
)
SPEC_LINE_ANCHOR = re.compile(r"^L(\d+)(?:-L(\d+))?$")

# DOC-89: exact exemptions for dead *line* anchors quoted by historical records.
# These documents cite the line numbers that were true on their own date; they
# are records, not live navigation, so rewriting the numbers would falsify them.
# The exemption is per (source file, raw target), never per directory or rule:
# a new dead anchor in the same file still fails.
FRAGMENT_EXEMPT = {
    "battle/langcap-1/verdict.md": {
        "../../issues/packages/pkg-2-ct-install-package-root-import.md#L100-L118",
    },
    "docs/review/builtin-layer-vs-std-package-name-check.md": {
        "../../README.md#L468",
    },
    "docs/reviews/2026-11-17-pkg-index-audit.md": {
        "../../README.md#L450",
    },
    "docs/proposals/ct-pure-type-alias-proposal.md": {
        "../../test/ast/153_into_type_host/lib/ops.m.ct#L9-L15",
    },
    "issues/README.md": {"../docs/roadmap.md#L265"},
    "issues/docs/doc22-batch2-stale-statements.md": {
        "../../test/bindings/README.md#L192",
    },
    "issues/docs/doc25-include-roots-asymmetry.md": {"../../README.md#L507"},
    "issues/docs/doc34-grammar-assertion-count.md": {"../../README.md#L294"},
    "issues/docs/doc26-stale-counts-and-tag-layout.md": {
        "../../README.md#L293",
        "../../README.md#L554",
        "../../README.md#L818",
        "../../docs/roadmap.md#L904",
        "../../docs/roadmap.md#L945",
        "../../docs/roadmap.md#L1001",
    },
    "issues/docs/doc27-test-readme-stale.md": {
        "../../test/README.md#L44",
    },
    "issues/docs/doc30-version-register-drift.md": {"../../docs/glossary.md#L298"},
    "issues/docs/doc35-test-readme-probe-counts.md": {
        "../../test/README.md#L45",
    },
    "issues/docs/doc36-bindings-cross-unit-interface.md": {
        "../../test/bindings/README.md#L253-L271",
    },
    "issues/docs/doc37-selfhost-readme-ct-ast-layout.md": {
        "../../selfhost/README.md#L81-L83",
    },
    "issues/docs/doc38-readme-gitignore-claim.md": {
        "../../README.md#L333",
        "../../README.md#L865",
    },
    "issues/docs/doc39-glossary-arena-module.md": {"../../docs/glossary.md#L354"},
    "issues/docs/doc40-roadmap-check-ast-count.md": {
        "../../docs/roadmap.md#L953",
        "../../docs/roadmap.md#L1009",
    },
    "issues/docs/doc41-glossary-capability-patch-list.md": {
        "../../docs/glossary.md#L400",
    },
    "issues/docs/doc42-readme-ast-errors-assertion.md": {
        "../../README.md#L779-L780",
    },
    "issues/docs/doc46-readme-transform-table-stale.md": {
        "../../README.md#L603",
        "../../README.md#L604",
        "../../README.md#L655",
    },
    "issues/docs/doc48-borrow-design-stale-status.md": {
        "../../docs/history/design/borrow.md#L357-L366",
    },
    "issues/docs/doc47-memory-guide-stale.md": {
        "../../docs/memory-guide.md#L646-L652",
        "../../docs/memory-guide.md#L692",
        "../../docs/memory-guide.md#L1048",
    },
    "issues/docs/doc61-roadmap-phase18-english.md": {
        "../../docs/roadmap.md#L975",
    },
    "issues/docs/doc68-vscode-generic-jump-index.md": {
        "../../editors/vscode/extension.js#L373-L390",
    },
    "issues/docs/readme-passthrough-scope.md": {"../../README.md#L513"},
    "issues/docs/readme-quickstart-branch.md": {"../../README.md#L477-L486"},
    "issues/selfhost/ct-ast-parse-diag-format.md": {"../../README.md#L509"},
    "issues/docs/language-spec-struct-array-field-stale.md": {
        "../../docs/roadmap.md#L743",
    },
    "issues/docs/roadmap-stale-todo.md": {"../../docs/roadmap.md#L680-L682"},
}

# DOC-94: the language name is "Ct" in active prose. The check skips code
# (fenced blocks and inline spans), the generated spec block, and the trees
# whose contents are historical records or byte-for-byte upstream copies.
CT_EXEMPT_DIRS = (
    "docs/history",
    "docs/reviews",
    "docs/review",
    "docs/proposals",
    "docs/decisions",
    "docs/design",
    "docs/spec",
    "battle",
    "issues",
)
CT_ACTIVE_ROOTS = ("test", "examples", "editors", "selfhost")
BARE_CT = re.compile(r"\bCT\b")
FENCE_LINE = re.compile(r"^\s*(```|~~~)")
SPEC_BEGIN_LINE = re.compile(r"^\s*<!--\s*spec:begin\b.*-->\s*$")
SPEC_END_LINE = re.compile(r"^\s*<!--\s*spec:end\b.*-->\s*$")

STATUS_MAP = {
    "完成": "\u2705",
    "实施中": "\U0001f7e8",
    "规划中": "\u2b1c",
}
STATUS_EN = {
    "done": "\u2705",
    "in progress": "\U0001f7e8",
    "planned": "\u2b1c",
}


def read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def strip_code(text):
    text = FENCE.sub("", text)
    return INLINE.sub("", text)


def md_files():
    out = [os.path.join(ROOT, "README.md")]
    for base, _, names in os.walk(os.path.join(ROOT, "docs")):
        for name in sorted(names):
            if name.endswith(".md"):
                out.append(os.path.join(base, name))
    return out


def check_links(errors):
    checked = 0
    scanned = 0
    for path in md_files():
        rel = os.path.relpath(path, ROOT)
        text = strip_code(read(path))
        scanned += 1
        for match in LINK.finditer(text):
            target = match.group(1).strip()
            if not target or target.startswith("#"):
                continue
            if re.match(r"^(https?:|mailto:|file:)", target):
                continue
            target = target.split()[0]
            dest = target.split("#", 1)[0]
            if not dest:
                continue
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), dest))
            checked += 1
            if os.path.exists(resolved):
                continue
            if rel.startswith("docs/history/reports/") and (
                "/selfhost/ast/" in resolved or "/selfhost/src/" in resolved
            ):
                continue
            errors.append(f"{rel}: dead link -> {target}")
    return checked, scanned


def md_all_files():
    """Every Markdown file in the repository (DOC-89 scans the whole tree)."""
    out = []
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = sorted(d for d in dirs if d not in (".git", ".temp", "node_modules"))
        for name in sorted(names):
            if name.endswith(".md"):
                out.append(os.path.join(base, name))
    return out


def slugify(heading):
    """GitHub's heading slug: lower-case, drop punctuation, spaces -> hyphens."""
    text = re.sub(r"<[^>]*>", "", heading.strip()).lower()
    text = urllib.parse.unquote(text)
    out = []
    for char in text:
        if char in "- ":
            out.append(char)
        elif char.isspace():
            out.append(" ")
        elif (
            char.isalnum()
            or unicodedata.category(char).startswith("M")
            or unicodedata.category(char) == "Pc"
        ):
            out.append(char)
    return "".join(out).strip().replace(" ", "-")


def spec_headings(path):
    """(line, level, text, slug) for every heading outside a fence, in order."""
    return headings_from_text(read(path))


def headings_from_text(text):
    """Same shape as spec_headings, for files that are already in memory."""
    out = []
    seen = {}
    in_fence = False
    for number, line in enumerate(text.splitlines(), 1):
        if FENCE_LINE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        match = re.match(r"^(#{1,6})\s+(.*?)(?:\s+#+)?\s*$", line)
        if not match:
            continue
        base = slugify(match.group(2))
        if not base:
            continue
        if base in seen:
            seen[base] += 1
            candidate = f"{base}-{seen[base]}"
            while any(item[3] == candidate for item in out):
                seen[base] += 1
                candidate = f"{base}-{seen[base]}"
        else:
            seen[base] = 0
            candidate = base
        out.append((number, len(match.group(1)), match.group(2), candidate))
    return out


def heading_slugs(path):
    """The set of anchor slugs the target Markdown file exposes."""
    return {item[3] for item in spec_headings(path)}


def file_line_count(path):
    with open(path, "rb") as handle:
        data = handle.read()
    return data.count(b"\n") + (0 if not data or data.endswith(b"\n") else 1)


def resolve_fragment(path, fragment):
    """Return (ok, reason) for one `#fragment` pointing at `path` (DOC-89)."""
    fragment = urllib.parse.unquote(fragment)
    if not fragment:
        return True, None
    line = re.match(r"^L(\d+)(?:-L(\d+))?$", fragment)
    if line:
        start = int(line.group(1))
        end = int(line.group(2)) if line.group(2) else start
        count = file_line_count(path)
        if 1 <= start <= end <= count:
            return True, None
        return False, f"line anchor L{start}-L{end} outside 1..{count}"
    if not path.endswith(".md"):
        return True, None  # non-Markdown targets have no heading anchors
    slugs = heading_slugs(path)
    if fragment in slugs:
        return True, None
    import difflib

    close = difflib.get_close_matches(fragment, list(slugs), n=1, cutoff=0.6)
    hint = close[0] if close else "(no similar heading)"
    return False, f"no such heading; closest candidate: {hint}"


def fragment_issues(path, text):
    """Check every `#fragment` in one file's Markdown text."""
    rel = os.path.relpath(path, ROOT)
    checked = 0
    issues = []
    for match in LINK.finditer(text):
        target = match.group(1).strip()
        parts = target.split()
        if not parts:
            continue
        target = parts[0]
        if re.match(r"^(https?:|mailto:|file:)", target):
            continue
        if "#" not in target:
            continue
        dest, fragment = target.split("#", 1)
        if not dest:
            resolved = path
        else:
            resolved = os.path.normpath(os.path.join(os.path.dirname(path), dest))
        if not os.path.exists(resolved):
            continue  # path checking owns the missing-file case
        if target in FRAGMENT_EXEMPT.get(rel.replace(os.sep, "/"), ()):
            continue
        checked += 1
        ok, reason = resolve_fragment(resolved, fragment)
        if not ok:
            issues.append(f"{rel}: dead anchor -> {target} ({reason})")
    return checked, issues


def check_fragments(errors):
    """DOC-89: generic `#fragment` validation over every Markdown link."""
    checked = 0
    scanned = 0
    for path in md_all_files():
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        if rel.startswith("docs/history/"):
            continue  # frozen snapshot; its anchors are historical records
        count, issues = fragment_issues(path, strip_code(read(path)))
        checked += count
        scanned += 1
        errors.extend(issues)
    return checked, scanned


def split_toc(text):
    """Return (found, toc_line, [fragment, ...]) for the first `## 目录` section."""
    lines = text.splitlines()
    in_fence = False
    start = None
    for index, line in enumerate(lines, 1):
        if FENCE_LINE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"^##\s+" + TOC_HEADING + r"\s*$", line):
            start = index
            break
    if start is None:
        return False, None, []
    entries = []
    in_fence = False
    for line in lines[start:]:
        if FENCE_LINE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if re.match(r"^#{1,2}\s+", line) and not re.match(
            r"^##\s+" + TOC_HEADING + r"\s*$", line
        ):
            break
        for match in LINK.finditer(line):
            target = match.group(1).strip().split()
            if target and target[0].startswith("#"):
                fragment = target[0][1:]
                if fragment:
                    entries.append(fragment)
    return True, start, entries


def check_spec_toc_text(text, rel=SPEC_DOC):
    """DOC-88: every H2/H3 in the outline exactly once, every entry resolves."""
    errors = []
    heads = headings_from_text(text)
    by_slug = {item[3]: item for item in heads}
    required = [
        item
        for item in heads
        if (item[1] == 2 and item[2] != TOC_HEADING) or item[1] == 3
    ]
    found, toc_line, entries = split_toc(text)
    if not found:
        return [f"{rel}: missing `## {TOC_HEADING}` outline (DOC-88)"], 0, len(required)
    first_other_h2 = next(
        (item[0] for item in heads if item[1] == 2 and item[2] != TOC_HEADING),
        None,
    )
    if first_other_h2 is not None and toc_line > first_other_h2:
        errors.append(
            f"{rel}: `## {TOC_HEADING}` must come before the first H2 "
            f"(line {first_other_h2}; DOC-88)"
        )
    counts = {}
    for fragment in entries:
        counts[fragment] = counts.get(fragment, 0) + 1
        if fragment not in by_slug:
            errors.append(
                f"{rel}: outline dead item -> #{fragment} "
                "(no such heading; DOC-88)"
            )
    for item in required:
        count = counts.get(item[3], 0)
        if count == 0:
            errors.append(
                f"{rel}: outline misses heading `{item[2]}` "
                f"(#{item[3]}; DOC-88)"
            )
        elif count > 1:
            errors.append(
                f"{rel}: outline lists `{item[2]}` {count} times (DOC-88)"
            )
    return errors, len(entries), len(required)


def check_spec_toc(errors):
    path = os.path.join(ROOT, SPEC_DOC)
    if not os.path.exists(path):
        errors.append(f"{SPEC_DOC}: missing (DOC-88 outline)")
        return 0, 0
    issues, entries, required = check_spec_toc_text(read(path))
    errors.extend(issues)
    return entries, required


def source_batch(rel):
    """DOC-88 batch of a Markdown file: B0 facade, B1 issues, B2 battle, B3 rest."""
    if rel.startswith("docs/history/"):
        return "HIST"
    if rel.startswith("README") or rel == "AGENTS.md" or rel.startswith("docs/"):
        return "B0"
    if rel.startswith("issues/"):
        return "B1"
    if rel.startswith("battle/"):
        return "B2"
    return "B3"


def spec_line_anchor_refs():
    """[(source_rel, `docs/language-spec.md#L...`)] for every Markdown link."""
    refs = []
    target = os.path.normpath(os.path.join(ROOT, SPEC_DOC))
    for path in md_all_files():
        rel = os.path.relpath(path, ROOT).replace(os.sep, "/")
        text = strip_code(read(path))
        for match in LINK.finditer(text):
            parts = match.group(1).strip().split()
            if not parts:
                continue
            link = parts[0]
            if re.match(r"^(https?:|mailto:|file:)", link) or "#" not in link:
                continue
            dest, fragment = link.split("#", 1)
            if not SPEC_LINE_ANCHOR.match(fragment):
                continue
            resolved = (
                os.path.normpath(os.path.join(os.path.dirname(path), dest))
                if dest
                else path
            )
            if os.path.normpath(resolved) != target:
                continue
            refs.append((rel, f"{SPEC_DOC}#{fragment}"))
    return refs


def parse_line_anchor_ledger(text):
    allowed = {}
    errors = []
    for number, line in enumerate(text.splitlines(), 1):
        entry = line.strip()
        if not entry or entry.startswith("#"):
            continue
        match = LINE_LEDGER_ENTRY.match(entry)
        if not match:
            errors.append(
                f"{LINE_ANCHOR_LEDGER}:{number}: bad entry `{entry}` "
                "(want `<path>#L<a>[-L<b>]  <batch>`; DOC-88)"
            )
            continue
        key, batch = match.groups()
        if batch not in LINE_BATCH_ORDER:
            errors.append(
                f"{LINE_ANCHOR_LEDGER}:{number}: unknown batch `{batch}` "
                f"(want one of {', '.join(LINE_BATCHES)}; DOC-88)"
            )
        if key in allowed:
            errors.append(
                f"{LINE_ANCHOR_LEDGER}:{number}: duplicate entry {key} (DOC-88)"
            )
        allowed[key] = batch
    return allowed, errors


def check_line_anchors_text(refs, ledger_text):
    """DOC-88: frozen line anchors; new refs and zombie/relabelled entries are red."""
    allowed, errors = parse_line_anchor_ledger(ledger_text)
    actual = {}
    for rel, key in refs:
        actual.setdefault(key, []).append(rel)
    for key, sources in actual.items():
        if key not in allowed:
            errors.append(
                f"{sources[0]}: new language-spec line anchor -> {key} "
                "(DOC-88: use a section anchor; new `#L` refs are frozen out)"
            )
    for key, batch in allowed.items():
        if key not in actual:
            errors.append(
                f"{LINE_ANCHOR_LEDGER}: zombie entry {key} {batch} "
                "(no reference left; delete it; DOC-88)"
            )
            continue
        expected = min(
            (source_batch(rel) for rel in actual[key]),
            key=lambda name: LINE_BATCH_ORDER[name],
        )
        if batch != expected:
            errors.append(
                f"{LINE_ANCHOR_LEDGER}: {key} is tagged {batch} but its "
                f"earliest remaining reference is {expected} (DOC-88)"
            )
    return errors, len(actual), len(allowed)


def check_line_anchors(errors):
    ledger = os.path.join(ROOT, LINE_ANCHOR_LEDGER)
    refs = spec_line_anchor_refs()
    if not os.path.exists(ledger):
        errors.append(
            f"{LINE_ANCHOR_LEDGER}: missing (freeze the existing "
            "language-spec line anchors; DOC-88)"
        )
        return len({key for _, key in refs}), 0
    issues, actual, allowed = check_line_anchors_text(refs, read(ledger))
    errors.extend(issues)
    return actual, allowed


def check_version(errors):
    ctc = read(os.path.join(ROOT, "selfhost/l0/ctc.c"))
    found = re.search(r'#define\s+CTC_VERSION\s+"([0-9.]+)"', ctc)
    if not found:
        errors.append("selfhost/l0/ctc.c: CTC_VERSION not found")
        return None
    version = found.group(1)
    for other in ("selfhost/l1/ctc.ct", "selfhost/l2/core.ct", "selfhost/ct-ast/main.ct"):
        text = read(os.path.join(ROOT, other))
        other_version = re.search(r'#define\s+CTC_VERSION\s+"([0-9.]+)"', text)
        if not other_version or other_version.group(1) != version:
            errors.append(f"{other}: CTC_VERSION differs from selfhost/l0/ctc.c ({version})")
    for doc in ("README.md", "docs/README.md"):
        for token in re.findall(r"v(\d+\.\d+\.\d+)", read(os.path.join(ROOT, doc))):
            if token != version:
                errors.append(f"{doc}: version token v{token} != current v{version}")
    return version


GATE_CLAIM = re.compile(
    r"(\d+)\s*(?:道硬门禁|个硬门禁|个条目|关(?:卡)?|hard\s+gates|gates)"
)


def check_gate_count(errors):
    script = read(os.path.join(ROOT, "selfhost/check-all.sh"))
    actual = len(re.findall(r'^run_gate\s+"', script, re.M))
    if actual == 0:
        errors.append("selfhost/check-all.sh: no run_gate calls found")
    for doc in ("README.md", "docs/README.md", "docs/glossary.md"):
        claims = [int(n) for n in GATE_CLAIM.findall(read(os.path.join(ROOT, doc)))]
        if not claims:
            errors.append(f"{doc}: no hard-gate count found")
        for claim in claims:
            if claim != actual:
                errors.append(f"{doc}: states {claim} hard gates, check-all.sh runs {actual}")
    issue = read(os.path.join(ROOT, "issues/README.md"))
    marker = re.search(r"<!--\s*gates:(\d+)\s*-->", issue)
    if not marker:
        errors.append("issues/README.md: no <!-- gates:N --> marker")
    elif int(marker.group(1)) != actual:
        errors.append(
            f"issues/README.md: marker says {marker.group(1)} hard gates, "
            f"check-all.sh runs {actual}"
        )
    workflow = read(os.path.join(ROOT, ".github/workflows/ci.yml"))
    spelled = {"nine": 9, "ten": 10, "eleven": 11, "twelve": 12}
    for source in (".github/workflows/ci.yml", "Makefile"):
        text = workflow if source.endswith("ci.yml") else read(os.path.join(ROOT, source))
        for match in re.finditer(r"(\d+|nine|ten|eleven|twelve)\s+hard gates", text, re.I):
            token = match.group(1).lower()
            claim = int(token) if token.isdigit() else spelled[token]
            if claim != actual:
                errors.append(f"{source}: states {claim} hard gates, check-all.sh runs {actual}")
    return actual


def check_phase_status(errors):
    roadmap = read(os.path.join(ROOT, "docs/roadmap.md"))
    phases = 0
    for name in sorted(os.listdir(os.path.join(ROOT, "docs/design"))):
        match = re.fullmatch(r"phase(\d+)\.md", name)
        if not match:
            continue
        phases += 1
        number = match.group(1)
        head = "\n".join(read(os.path.join(ROOT, "docs/design", name)).splitlines()[:25])
        status = re.search(r"\*\*状态：\s*(完成|实施中|规划中)", head)
        if not status:
            status = re.search(r"\*\*Status:\s*(done|in progress|planned)", head, re.I)
        if not status:
            errors.append(f"docs/design/{name}: no status line in the first 25 lines")
            continue
        word = status.group(1).lower()
        emoji = STATUS_MAP.get(word) or STATUS_EN.get(word)
        if not emoji:
            errors.append(f"docs/design/{name}: unknown status '{status.group(1)}'")
            continue
        row = re.search(r"^\|\s*Phase\s+" + number + r"\s*\|.*$", roadmap, re.M)
        if not row:
            errors.append(f"docs/design/{name}: no Phase {number} row in docs/roadmap.md")
            continue
        if emoji not in row.group(0):
            errors.append(
                f"docs/design/{name}: status '{status.group(1)}' disagrees with the roadmap row "
                f"(expected {emoji})"
            )
        if f"design/phase{number}.md" not in row.group(0):
            errors.append(f"docs/design/{name}: roadmap row does not link design/phase{number}.md")
        english = re.search(r"^\|\s*" + number + r"\s*\|.*$", roadmap, re.M)
        if english and emoji not in english.group(0):
            errors.append(
                f"docs/design/{name}: the English roadmap row disagrees with status "
                f"'{status.group(1)}' (expected {emoji})"
            )
    return phases


def check_applies_to(errors):
    """The "适用版本" headers name the line, never a version number (DOC-63).

    A pinned number is wrong the moment the version is bumped, and nobody
    notices: the tutorial said v0.16.0 while the tree shipped v0.19.1. The
    reader can always run `ct -v`, so the header points there instead.
    """
    checked = 0
    for name in sorted(os.listdir(os.path.join(ROOT, "docs"))):
        if not name.endswith(".md"):
            continue
        path = os.path.join(ROOT, "docs", name)
        for number, line in enumerate(read(path).splitlines(), 1):
            if "适用版本" not in line:
                continue
            checked += 1
            if re.search(r"\bv\d+\.\d+\.\d+", line):
                errors.append(
                    f"docs/{name}:{number}: the 适用版本 header pins a version "
                    f"(use `ct -v` instead)"
                )
    return checked


def version_tuple(text):
    return tuple(int(part) for part in text.split(".") if part.isdigit())


def published_spec():
    """Return the spec bytes of the external repo's published revision.

    The checkout may carry uncommitted edits, so hashing the worktree would
    only prove that the pin agrees with a dirty tree. Read the committed HEAD
    instead and fall back to the worktree only when the external repo or git
    is unavailable.
    """
    repo = os.path.dirname(os.path.dirname(SPEC))
    try:
        relative = os.path.relpath(SPEC, repo)
        return subprocess.check_output(
            ["git", "-C", repo, "show", f"HEAD:{relative}"],
            stderr=subprocess.DEVNULL,
        )
    except (OSError, subprocess.CalledProcessError):
        print("spec pin: git unavailable, hashing the worktree instead", file=sys.stderr)
        return open(SPEC, "rb").read()


def check_spec_pin(errors):
    """G9 (CI-8): AGENTS.md pins the methodology it was written against.

    The spec lives outside this repository, so an absent file is a skip rather
    than a failure (CI has no ~/trae-ws checkout); when it is present, both the
    digest and the "not behind" version rule are enforced.
    """
    agents = read(os.path.join(ROOT, "AGENTS.md"))
    version = re.search(r"^[\s>]*\|[ \t]*`?spec-version`?[ \t]*\|[ \t]*`?([0-9.]+)`?", agents, re.M)
    digest = re.search(r"^[\s>]*\|[ \t]*`?spec-sha256`?[ \t]*\|[ \t]*`?([0-9a-f]{64})`?", agents, re.M)
    if not version or not digest:
        errors.append("AGENTS.md: the G9 pin needs both `spec-version` and `spec-sha256` rows")
        return "missing"
    if not os.path.exists(SPEC):
        return "skipped (spec not found)"
    spec_head = published_spec().decode(errors="replace")[:2000]
    # A draft master spec is not adopted by any project yet; enforcing its
    # digest here would force every project to pin an unreleased draft.
    if re.search(r"^\|\s*状态\s*\|\s*草稿", spec_head, re.M) or "未落入任何项目" in spec_head:
        m = re.search(r"^\|\s*spec-version\s*\|\s*`?([0-9.]+)`?", spec_head, re.M)
        return f"skipped (master spec draft {m.group(1) if m else '?'})"
    status = "ok"
    actual = hashlib.sha256(published_spec()).hexdigest()
    if actual != digest.group(1):
        status = "mismatch"
        errors.append(
            f"AGENTS.md: spec-sha256 {digest.group(1)[:12]}... != {actual[:12]}... ({SPEC})"
        )
    spec_version = re.search(r"^\|\s*spec-version\s*\|\s*`?([0-9.]+)`?", spec_head, re.M)
    if spec_version and version_tuple(version.group(1)) < version_tuple(spec_version.group(1)):
        status = "stale" if status == "ok" else status + ", stale"
        errors.append(
            f"AGENTS.md: spec-version {version.group(1)} is behind the methodology's "
            f"{spec_version.group(1)}"
        )
    return f"{status} ({version.group(1)}, {digest.group(1)[:8]})"


def check_design_window(errors):
    """DOC-66: docs/design/ keeps the newest DESIGN_WINDOW phases.

    Older designs are retired to docs/history/design/; the gate only checks the
    upper bound and forbids duplicates, so a phase cannot appear twice.
    """
    design = os.path.join(ROOT, "docs/design")
    retired = os.path.join(ROOT, "docs/history/design")
    kept = {}
    for name in sorted(os.listdir(design)):
        match = re.fullmatch(r"phase(\d+)\.md", name)
        if match:
            kept[int(match.group(1))] = name
    if not kept:
        errors.append("docs/design: no phase*.md files found")
        return 0, DESIGN_WINDOW
    floor = max(kept) - DESIGN_WINDOW + 1
    for number, name in sorted(kept.items()):
        if number < floor:
            errors.append(
                f"docs/design/{name}: phase {number} is outside the {DESIGN_WINDOW}-phase "
                f"window (oldest kept: {floor}); move it to docs/history/design/"
            )
    for name in sorted(os.listdir(retired)):
        match = re.fullmatch(r"phase(\d+)\.md", name)
        if match and int(match.group(1)) in kept:
            errors.append(f"phase{match.group(1)}.md exists in both docs/design/ and docs/history/design/")
    readme = read(os.path.join(ROOT, "docs/README.md"))
    if f"最近 {DESIGN_WINDOW} 个" not in readme:
        errors.append(
            f"docs/README.md: the archive policy must state 最近 {DESIGN_WINDOW} 个已完成阶段"
        )
    return len(kept), DESIGN_WINDOW


def check_superseded_links(errors):
    """Every battle's `superseded-by` and the ADR's `superseded-battles` agree.

    The battle card keeps the historical verdict; the ADR is the current
    ruling. A one-way pointer is not enough: readers must be able to walk from
    either side. Missing either half is red, and a battle pointing at an ADR
    that does not list it back is red too.
    """
    battle_root = os.path.join(ROOT, "battle")
    adr_root = os.path.join(ROOT, "docs", "decisions")
    pointers = {}
    listed = {}
    if os.path.isdir(battle_root):
        for name in sorted(os.listdir(battle_root)):
            q = os.path.join(battle_root, name, "question.md")
            if not os.path.isfile(q):
                continue
            match = re.search(r"(?m)^superseded-by:\s*(D-\d+)\s*$", read(q))
            if match:
                pointers[name] = match.group(1)
    if os.path.isdir(adr_root):
        for name in sorted(os.listdir(adr_root)):
            if not re.fullmatch(r"D-\d+.*\.md", name):
                continue
            match = re.search(
                r"(?m)^\s*[-*]?\s*superseded-battles:\s*(.+)$",
                read(os.path.join(adr_root, name)),
            )
            if not match:
                continue
            ids = [part for part in re.split(r"[,\s]+", match.group(1).strip()) if part]
            listed[name.rsplit(".", 1)[0]] = ids
    for battle, adr in pointers.items():
        if adr not in listed:
            errors.append(
                f"battle/{battle}: superseded-by {adr} has no matching ADR file"
            )
        elif battle not in listed[adr]:
            errors.append(
                f"battle/{battle}: superseded-by {adr} is not listed in {adr}'s superseded-battles"
            )
    for adr, battles in listed.items():
        for battle in battles:
            if battle not in pointers:
                errors.append(
                    f"docs/decisions/{adr}.md: superseded-battles names '{battle}' "
                    f"but battle/{battle}/question.md has no superseded-by"
                )
            elif pointers[battle] != adr:
                errors.append(
                    f"docs/decisions/{adr}.md: superseded-battles names '{battle}' "
                    f"but its question.md points at {pointers[battle]}"
                )
    return len(pointers) + sum(len(v) for v in listed.values())


def check_signoffs(errors):
    """T-8 (AGENTS §0.7): new artifacts carry a non-author signoff.

    Phase cards are authored by REQ, so their `签收:` must name EDITOR,
    REVIEW or USER. ADRs are authored by EDITOR (verdict section), so their
    signoff must name REQ, REVIEW or USER. Only "实施中" cards and ADRs dated
    on/after SIGNOFF_FROM are checked, so closed phases and older ADRs are not
    retroactively red.
    """
    checked = 0
    design = os.path.join(ROOT, "docs", "design")
    for name in sorted(os.listdir(design)):
        if not re.fullmatch(r"phase\d+\.md", name):
            continue
        text = read(os.path.join(design, name))
        head = "\n".join(text.splitlines()[:25])
        if not re.search(r"\*\*状态：\s*实施中", head):
            continue
        dates = re.findall(r"20\d\d-\d\d-\d\d", head)
        if not dates or max(dates) < SIGNOFF_FROM:
            continue
        checked += 1
        m = re.search(r"(?m)^>\s*.*签收\s*[:：]\s*(EDITOR|REVIEW|REQ|USER)\b", head)
        if not m:
            errors.append(
                f"docs/design/{name}: no 签收 line (T-8; expected EDITOR/REVIEW/USER)"
            )
        elif m.group(1) == "REQ":
            errors.append(
                f"docs/design/{name}: REQ authors the card; 签收 must be EDITOR/REVIEW/USER (T-8)"
            )

    adr = os.path.join(ROOT, "docs", "decisions")
    for name in sorted(os.listdir(adr)):
        if not re.fullmatch(r"D-\d+.*\.md", name):
            continue
        text = read(os.path.join(adr, name))
        head = "\n".join(text.splitlines()[:25])
        dates = re.findall(r"20\d\d-\d\d-\d\d", head)
        if not dates or max(dates) < SIGNOFF_FROM:
            continue
        checked += 1
        m = re.search(r"(?m)^\s*[-*]?\s*签收\s*[:：]\s*(EDITOR|REVIEW|REQ|USER)\b", head)
        if not m:
            errors.append(
                f"docs/decisions/{name}: no 签收 line (T-8; expected REQ/REVIEW/USER)"
            )
        elif m.group(1) == "EDITOR":
            errors.append(
                f"docs/decisions/{name}: EDITOR authors the verdict; 签收 must be REQ/REVIEW/USER (T-8)"
            )
    return checked


def check_idiom_briefing(errors):
    """DOC-85: every numbered claim in the briefing appendix of docs/idioms.md
    cites a language-spec section that exists. Inactive while the file is
    absent; the gate switches on with the file."""
    path = os.path.join(ROOT, "docs/idioms.md")
    if not os.path.exists(path):
        return 0
    text = read(path)
    heading = re.search(r"^#{1,6}[^\n]*briefing[^\n]*$", text, re.M | re.I)
    if not heading:
        errors.append("docs/idioms.md: no briefing appendix heading (DOC-85)")
        return 0
    tail = text[heading.end():]
    nxt = re.search(r"^#{1,6}\s", tail, re.M)
    body = tail[: nxt.start()] if nxt else tail
    block = re.search(r"```[a-zA-Z]*\n(.*?)```", body, re.S)
    body = block.group(1) if block else body
    spec = read(os.path.join(ROOT, "docs/language-spec.md"))
    sections = set(SECTION_HEAD.findall(spec))
    checked = 0
    for line in body.splitlines():
        item = BRIEFING_ITEM.match(line)
        if not item:
            continue
        checked += 1
        refs = SPEC_REF.findall(item.group(2))
        if not refs:
            errors.append(
                f"docs/idioms.md: briefing item {item.group(1)} cites no §spec section (DOC-85)"
            )
            continue
        for ref in refs:
            if ref not in sections:
                errors.append(
                    f"docs/idioms.md: briefing item {item.group(1)} cites §{ref}, "
                    "absent from docs/language-spec.md"
                )
    return checked


def j6_check_text(text, errors):
    """Validate one J-6 ledger text and return the number of rows seen."""
    seen = {}
    counts = {state: 0 for state in J6_STATES}
    for m in J6_ROW.finditer(text):
        rid = m.group(1)
        cri, ev, state, owner = (m.group(2).strip(), m.group(3).strip(),
                                 m.group(4).strip(), m.group(5).strip())
        seen[rid] = state
        if state not in J6_STATES:
            errors.append(f"j6-ledger: {rid} has status '{state}' (expected 已过/部分/缺失/阻塞)")
            continue
        counts[state] += 1
        if not cri or cri in ("—", "-"):
            errors.append(f"j6-ledger: {rid} has no 最小可判证据")
        if not owner or owner in ("—", "-"):
            errors.append(f"j6-ledger: {rid} has no 负责人")
        if state == "阻塞" and "阻塞" not in ev:
            errors.append(f"j6-ledger: {rid} is 阻塞 without a reason in 现有证据")
        if state == "已过" and not re.search(r"(test/|docs/|battle/|见下|下方)", ev):
            errors.append(f"j6-ledger: {rid} is 已过 without a path/pointer in 现有证据")
        if state in ("部分", "缺失") and "承接" not in ev:
            errors.append(f"j6-ledger: {rid} is {state} without a 承接 item "
                          "(owner + next step)")
    for rid in sorted(J6_IDS - set(seen)):
        errors.append(f"j6-ledger: {rid} row is missing (SH-104)")

    marker = J6_COUNTS.search(text)
    if not marker:
        errors.append("j6-ledger: missing `<!-- j6:counts passed=… partial=… missing=… blocked=… -->`")
    else:
        fields = {}
        for part in marker.group(1).split():
            if "=" in part:
                k, v = part.split("=", 1)
                fields[k.strip()] = v.strip()
        for key, state in J6_COUNT_KEYS:
            raw = fields.get(key)
            try:
                want = int(raw)
            except (TypeError, ValueError):
                errors.append(f"j6-ledger: counts marker has no integer {key}= (got {raw!r})")
                continue
            if want != counts[state]:
                errors.append(f"j6-ledger: counts marker says {key}={want}, "
                              f"rows say {state}={counts[state]}")
    return len(seen)


def check_j6_ledger(errors):
    """SH-104: the J-6 evidence ledger must carry every P-1…P-6 row with a
    legal state, a non-empty minimal criterion, a reason on 阻塞 rows, a
    承接 item on 部分/缺失 rows, and a header count that matches the rows."""
    path = os.path.join(ROOT, "docs/planning/j6-evidence/ledger.md")
    if not os.path.exists(path):
        errors.append("docs/planning/j6-evidence/ledger.md: missing (SH-104)")
        return 0
    return j6_check_text(read(path), errors)


def check_stable_subset(errors):
    """DOC-79: the tier table in docs/stable-subset.md is well formed and every
    tier has at least one row."""
    path = os.path.join(ROOT, "docs/stable-subset.md")
    if not os.path.exists(path):
        errors.append("docs/stable-subset.md: missing (DOC-79)")
        return 0
    text = read(path)
    head = re.search(r"^##\s*2\.\s*分档清单\s*$", text, re.M)
    if not head:
        errors.append("docs/stable-subset.md: no '## 2. 分档清单' section (DOC-79)")
        return 0
    tail = text[head.end():]
    nxt = re.search(r"^##\s", tail, re.M)
    body = tail[: nxt.start()] if nxt else tail
    tiers = {}
    rows = 0
    for line in body.splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 5:
            errors.append(f"stable-subset: row has {len(cells)} cells (expected 5): {line[:60]}")
            continue
        if cells[0] == "能力面" or not cells[0].strip("-: "):
            continue
        rows += 1
        tier = cells[1]
        if tier not in STABLE_TIERS:
            errors.append(f"stable-subset: illegal tier '{tier}' in row: {cells[0][:40]}")
        tiers[tier] = tiers.get(tier, 0) + 1
        if not cells[2] or cells[2] in ("—", "-"):
            errors.append(f"stable-subset: empty 授权 in row: {cells[0][:40]}")
        if not cells[3] or cells[3] in ("—", "-"):
            errors.append(f"stable-subset: empty 版本/截止 in row: {cells[0][:40]}")
    for tier in STABLE_TIERS:
        if not tiers.get(tier):
            errors.append(f"stable-subset: no row in tier '{tier}' (DOC-79)")
    return rows


def check_compat_claim(errors):
    """DOC-76: the 'no longer a C superset' claim is identical in README, the
    spec and the roadmap, and its spec= pointer resolves to a heading."""
    files = ("README.md", "docs/language-spec.md", "docs/roadmap.md")
    claims, specs, seen = set(), set(), 0
    for rel in files:
        text = read(os.path.join(ROOT, rel))
        m = COMPAT_MARKER.search(text)
        if not m:
            errors.append(f"{rel}: missing ct-compat marker (DOC-76)")
            continue
        kv = dict(re.findall(r"(\w+)=([^\s]+)", m.group(1)))
        if kv.get("claim") != "v1.0-not-c-superset":
            errors.append(f"{rel}: ct-compat claim '{kv.get('claim')}' (expected v1.0-not-c-superset)")
        if not kv.get("spec"):
            errors.append(f"{rel}: ct-compat marker has no spec= section")
        if "不再自称 C 超集" not in text:
            errors.append(f"{rel}: missing phrase '不再自称 C 超集' (DOC-76)")
        claims.add(kv.get("claim"))
        specs.add(kv.get("spec"))
        seen += 1
    if len(claims) > 1:
        errors.append(f"ct-compat: claim differs across files: {sorted(claims)}")
    if len(specs) > 1:
        errors.append(f"ct-compat: spec= differs across files: {sorted(specs)}")
    elif specs:
        spec_no = next(iter(specs))
        if spec_no:
            spec_text = read(os.path.join(ROOT, "docs/language-spec.md"))
            if not re.search(r"^#{3,4}\s+" + re.escape(spec_no) + r"(?:\.|\s|$)", spec_text, re.M):
                errors.append(f"ct-compat: spec={spec_no} is not a heading in docs/language-spec.md")
    return seen


def check_capability_map(errors):
    """DOC-77: docs/capabilities.tsv and the README cap markers agree, and every
    implemented capability points at a real spec section."""
    path = os.path.join(ROOT, "docs/capabilities.tsv")
    if not os.path.exists(path):
        errors.append("docs/capabilities.tsv: missing (DOC-77)")
        return 0
    spec = read(os.path.join(ROOT, "docs/language-spec.md"))
    heads = set(re.findall(r"^#{2,4}\s+(\d+(?:\.\d+)*)\.?\s", spec, re.M))
    rows = {}
    for n, line in enumerate(read(path).splitlines(), 1):
        s = line.strip()
        if not s or s.startswith("#"):
            continue
        parts = [p.strip() for p in s.split("\t")]
        if len(parts) != 6:
            errors.append(f"capabilities.tsv:{n}: expected 6 tab-separated columns")
            continue
        cid, name, secs, status, first, issues = parts
        if not re.fullmatch(r"[a-z0-9-]+", cid):
            errors.append(f"capabilities.tsv:{n}: illegal id '{cid}'")
        if cid in rows:
            errors.append(f"capabilities.tsv:{n}: duplicate id '{cid}'")
        if status not in CAP_STATUS:
            errors.append(f"capabilities.tsv:{n}: status '{status}' (expected implemented/planned)")
        if first != "—" and not re.fullmatch(r"v\d+\.\d+(?:\.\d+)?", first):
            errors.append(f"capabilities.tsv:{n}: 首版 '{first}' (expected vX.Y or —)")
        if issues != "—":
            for iid in [x.strip() for x in issues.split(",") if x.strip()]:
                if not re.fullmatch(r"[A-Z]+-\d+", iid):
                    errors.append(f"capabilities.tsv:{n}: 关联卡 '{iid}' (expected CARD-N or —)")
        sl = [x.strip() for x in secs.split(",") if x.strip()]
        if not sl:
            errors.append(f"capabilities.tsv:{n}: no spec section for '{cid}'")
        if status == "implemented":
            for sec in sl:
                if sec not in heads:
                    errors.append(f"capabilities.tsv:{n}: section {sec} not a heading in docs/language-spec.md")
        rows[cid] = status
    counts = {}
    for m in CAP_MARKER.finditer(read(os.path.join(ROOT, "README.md"))):
        cid = m.group(1)
        counts[cid] = counts.get(cid, 0) + 1
    for cid, count in counts.items():
        if cid not in rows:
            errors.append(f"README.md: cap marker '{cid}' is not in docs/capabilities.tsv")
        elif count > 1:
            errors.append(f"README.md: cap marker '{cid}' appears {count} times (expected 1)")
    for cid in rows:
        if cid not in counts:
            errors.append(f"README.md: missing cap marker for '{cid}'")
    return len(rows)


def ct_is_active(rel):
    """True when a repo-relative path is active prose for DOC-94.

    The English mirror is out of scope by project policy, and the exempt trees
    hold historical records, review snapshots or the verbatim upstream spec.
    """
    rel = rel.replace(os.sep, "/")
    if rel == "README.en.md" or not rel.endswith(".md"):
        return False
    if rel in ("README.md", "AGENTS.md"):
        return True
    head = rel.split("/")[0]
    if head == "docs":
        for exempt in CT_EXEMPT_DIRS:
            if rel == exempt + ".md" or rel.startswith(exempt + "/"):
                return False
        return True
    return head in CT_ACTIVE_ROOTS


def ct_active_paths():
    out = []
    for base, dirs, names in os.walk(ROOT):
        dirs[:] = sorted(
            d for d in dirs if d not in (".git", ".temp", "node_modules")
        )
        for name in sorted(names):
            rel = os.path.relpath(os.path.join(base, name), ROOT)
            if ct_is_active(rel):
                out.append(os.path.join(base, name))
    return out


def ct_hits(text):
    """Return (line, column, snippet) for bare CT in active prose.

    The scan is line-oriented so the reported line number matches the file.
    Inline code is stripped before matching; fenced blocks and the generated
    spec block in AGENTS.md are skipped entirely.
    """
    hits = []
    in_fence = False
    in_spec_block = False
    for number, line in enumerate(text.splitlines(), 1):
        if SPEC_BEGIN_LINE.match(line):
            in_spec_block = True
            continue
        if SPEC_END_LINE.match(line):
            in_spec_block = False
            continue
        if in_spec_block:
            continue
        if FENCE_LINE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        for match in BARE_CT.finditer(INLINE.sub("", line)):
            hits.append((number, match.start() + 1, line.strip()))
    return hits


def check_ct_spelling(errors):
    """DOC-94: bare `CT` in active prose must be written `Ct`."""
    files = ct_active_paths()
    hits = 0
    for path in files:
        rel = os.path.relpath(path, ROOT)
        for number, column, snippet in ct_hits(read(path)):
            hits += 1
            errors.append(
                f"{rel}:{number}:{column}: bare 'CT' in active prose "
                f"(write 'Ct'; DOC-94): {snippet[:70]}"
            )
    return hits, len(files)


def j6_selftest():
    """Positive/negative fixtures for the SH-104 ledger assertions."""
    ids = sorted(J6_IDS, key=lambda s: tuple(int(x) for x in s[2:].split(".")))

    def ledger(rows, counts="passed=34 partial=0 missing=0 blocked=0"):
        return "<!-- j6:counts " + counts + " -->\n| 判据 | 最小可判证据 | 现有证据 | 状态 | 负责人 |\n" + \
            "| --- | --- | --- | --- | --- |\n" + "\n".join(rows) + "\n"

    def row(rid, state="已过", ev="test/x", owner="DEV"):
        return f"| {rid} | criterion | {ev} | {state} | {owner} |"

    valid = ledger([row(rid) for rid in ids])
    cases = [
        ("valid", valid, 0),
        ("illegal-state", ledger([row(ids[0], state="完成")] + [row(r) for r in ids[1:]]), 1),
        ("missing-row", ledger([row(r) for r in ids[1:]]), 1),
        ("blocked-no-reason", ledger([row(ids[0], state="阻塞", ev="test/x")] +
                                     [row(r) for r in ids[1:]]), 1),
        ("partial-no-承接", ledger([row(ids[0], state="部分")] +
                                   [row(r) for r in ids[1:]]), 1),
        ("count-mismatch", ledger([row(r) for r in ids], "passed=33 partial=0 missing=0 blocked=0"), 1),
    ]
    failed = 0
    for name, text, want in cases:
        errors = []
        j6_check_text(text, errors)
        ok = (len(errors) == 0) if want == 0 else (len(errors) >= want)
        print(f"j6-ledger selftest: {name}: {len(errors)} error(s), "
              f"expected {'0' if want == 0 else '>=1'} -> {'OK' if ok else 'FAIL'}")
        failed += 0 if ok else 1
    if failed:
        print(f"j6-ledger selftest: FAIL ({failed} case(s))")
        return 1
    print(f"j6-ledger selftest: OK ({len(cases)} cases)")
    return 0


def ct_selftest():
    """DOC-94 fixtures: prose is red, code/exempt contexts are green."""
    cases = (
        ("prose", "这是 CT 语言。", 1),
        ("heading", "# CT 入门教程", 1),
        ("adjacent text", "C 与 CT 之间", 1),
        ("inline code", "`CT` / `CT_HOME` / `CT=/path`", 0),
        ("fenced block", "```\nCT=/path/to/ct\n```", 0),
        ("spec block", "<!-- spec:begin version=1 -->\nCT 包\n<!-- spec:end -->", 0),
    )
    paths = (
        ("docs/glossary.md", True),
        ("AGENTS.md", True),
        ("docs/history/phase-log.md", False),
        ("docs/reviews/x.md", False),
        ("docs/spec/ai-coding-workflow.md", False),
        ("README.en.md", False),
        ("issues/README.md", False),
        ("battle/x/verdict.md", False),
    )
    failed = 0
    for name, text, want in cases:
        got = len(ct_hits(text))
        ok = got == want
        failed += 0 if ok else 1
        print(f"ct-ratchet selftest: {name}: {got} hit(s), expected {want} -> {'OK' if ok else 'FAIL'}")
    for rel, want in paths:
        got = ct_is_active(rel)
        ok = got == want
        failed += 0 if ok else 1
        print(f"ct-ratchet selftest: path {rel}: active={got}, expected {want} -> {'OK' if ok else 'FAIL'}")
    if failed:
        print(f"ct-ratchet selftest: FAIL ({failed} case(s))")
        return 1
    print(f"ct-ratchet selftest: OK ({len(cases) + len(paths)} cases)")
    return 0


def anchor_selftest():
    """DOC-89 fixtures: positive anchors pass, missing/out-of-range are red."""
    target_text = (
        "# Top\n\n"
        "## 4.53 可选类型检查 `ct check --types`（Phase 32）\n\n"
        "## 重复标题\n\n"
        "## 重复标题\n\n"
        "## 全角标点：测试（一）\n"
    )
    cases = (
        ("inline code in heading", "453-可选类型检查-ct-check---typesphase-32", True),
        ("duplicate heading", "重复标题", True),
        ("duplicate heading suffix", "重复标题-1", True),
        ("CJK punctuation", "全角标点测试一", True),
        ("percent-encoded", "%E9%87%8D%E5%A4%8D%E6%A0%87%E9%A2%98", True),
        ("line range", "L1-L3", True),
        ("missing heading", "no-such-heading", False),
        ("line out of range", "L99", False),
    )
    with tempfile.TemporaryDirectory(
        prefix="check-docs-anchor-", dir=os.environ.get("TMPDIR") or None
    ) as work:
        target = os.path.join(work, "target.md")
        with open(target, "w", encoding="utf-8") as handle:
            handle.write(target_text)
        failed = 0
        for name, fragment, want in cases:
            got, _ = resolve_fragment(target, fragment)
            ok = got == want
            failed += 0 if ok else 1
            print(
                f"fragment-ratchet selftest: {name}: "
                f"{'resolved' if got else 'rejected'} -> {'OK' if ok else 'FAIL'}"
            )
        positive = (
            "[a](target.md#453-可选类型检查-ct-check---typesphase-32)\n"
            "[b](target.md#重复标题-1)\n"
            "[c](target.md#%E9%87%8D%E5%A4%8D%E6%A0%87%E9%A2%98)\n"
            "[d](target.md#L2-L4)\n"
        )
        count, issues = fragment_issues(target, positive)
        ok = count == 4 and not issues
        failed += 0 if ok else 1
        print(
            f"fragment-ratchet selftest: positive links: "
            f"{count} checked, {len(issues)} issue(s) -> {'OK' if ok else 'FAIL'}"
        )
        negative = positive + "[bad](target.md#does-not-exist)\n"
        count, issues = fragment_issues(target, negative)
        ok = count == 5 and len(issues) == 1 and "does-not-exist" in issues[0]
        failed += 0 if ok else 1
        print(
            f"fragment-ratchet selftest: negative link: "
            f"{len(issues)} issue(s) -> {'OK' if ok else 'FAIL'}"
        )
        self_path = os.path.join(work, "self.md")
        with open(self_path, "w", encoding="utf-8") as handle:
            handle.write("# Self\n\n[me](#self)\n[bad](#missing)\n")
        count, issues = fragment_issues(self_path, read(self_path))
        ok = count == 2 and len(issues) == 1
        failed += 0 if ok else 1
        print(
            f"fragment-ratchet selftest: same-file fragments: "
            f"{len(issues)} issue(s) -> {'OK' if ok else 'FAIL'}"
        )
    if failed:
        print(f"fragment-ratchet selftest: FAIL ({failed} case(s))")
        return 1
    print(f"fragment-ratchet selftest: OK ({len(cases) + 3} cases)")
    return 0


def toc_selftest():
    """DOC-88 fixtures: outline completeness and dead-item rejection."""
    valid = (
        "# T\n\n"
        "## 目录\n\n"
        "- [A](#a)\n"
        "- [B](#b)\n"
        "- [4.1 C](#41-c)\n\n"
        "## A\n\n"
        "### B\n\n"
        "### 4.1 C\n"
    )
    cases = (
        ("valid", valid, 0),
        ("missing heading", valid.replace("- [B](#b)\n", ""), 1),
        ("duplicate entry", valid.replace("- [B](#b)\n", "- [B](#b)\n- [B](#b)\n"), 1),
        ("dead entry", valid.replace("- [B](#b)\n", "- [B](#b)\n- [X](#missing)\n"), 1),
        ("no outline", "# T\n\n## A\n\n### B\n", 1),
        (
            "outline not at top",
            "# T\n\n## A\n\n## 目录\n\n- [A](#a)\n\n### B\n",
            1,
        ),
    )
    failed = 0
    for name, text, want in cases:
        errors, _, _ = check_spec_toc_text(text, "fixture.md")
        ok = (len(errors) == 0) if want == 0 else (len(errors) >= 1)
        failed += 0 if ok else 1
        print(
            f"outline-ratchet selftest: {name}: {len(errors)} error(s), "
            f"expected {'0' if want == 0 else '>=1'} -> {'OK' if ok else 'FAIL'}"
        )
    if failed:
        print(f"outline-ratchet selftest: FAIL ({failed} case(s))")
        return 1
    print(f"outline-ratchet selftest: OK ({len(cases)} cases)")
    return 0


def line_anchor_selftest():
    """DOC-88 fixtures: new anchor, zombie entry, bad batch, relabelled entry."""
    refs = [
        ("docs/a.md", "docs/language-spec.md#L10"),
        ("battle/b.md", "docs/language-spec.md#L20"),
    ]
    valid = (
        "docs/language-spec.md#L10  B0\n"
        "docs/language-spec.md#L20  B2\n"
    )
    cases = (
        ("valid", refs, valid, 0),
        (
            "new anchor",
            refs + [("issues/c.md", "docs/language-spec.md#L30")],
            valid,
            1,
        ),
        (
            "zombie entry",
            refs,
            valid + "docs/language-spec.md#L40  B3\n",
            1,
        ),
        (
            "bad batch",
            refs,
            "docs/language-spec.md#L10  B9\n"
            "docs/language-spec.md#L20  B2\n",
            1,
        ),
        (
            "duplicate entry",
            refs,
            valid + "docs/language-spec.md#L10  B0\n",
            1,
        ),
        (
            "batch relabel",
            [("issues/c.md", "docs/language-spec.md#L10")],
            "docs/language-spec.md#L10  B0\n",
            1,
        ),
        (
            "history entry",
            [("docs/history/x.md", "docs/language-spec.md#L50")],
            "docs/language-spec.md#L50  HIST\n",
            0,
        ),
    )
    failed = 0
    for name, case_refs, ledger, want in cases:
        errors, _, _ = check_line_anchors_text(case_refs, ledger)
        ok = (len(errors) == 0) if want == 0 else (len(errors) >= 1)
        failed += 0 if ok else 1
        print(
            f"line-anchor-ratchet selftest: {name}: {len(errors)} error(s), "
            f"expected {'0' if want == 0 else '>=1'} -> {'OK' if ok else 'FAIL'}"
        )
    if failed:
        print(f"line-anchor-ratchet selftest: FAIL ({failed} case(s))")
        return 1
    print(f"line-anchor-ratchet selftest: OK ({len(cases)} cases)")
    return 0


def main():
    if "--selftest" in sys.argv[1:]:
        rc = ct_selftest()
        rc = j6_selftest() or rc
        rc = anchor_selftest() or rc
        rc = toc_selftest() or rc
        rc = line_anchor_selftest() or rc
        return rc
    errors = []
    links, scanned = check_links(errors)
    fragments, fragment_files = check_fragments(errors)
    toc_entries, toc_required = check_spec_toc(errors)
    line_refs, line_entries = check_line_anchors(errors)
    version = check_version(errors)
    gates = check_gate_count(errors)
    phases = check_phase_status(errors)
    applies = check_applies_to(errors)
    spec = check_spec_pin(errors)
    design, window = check_design_window(errors)
    superseded = check_superseded_links(errors)
    signoffs = check_signoffs(errors)
    briefing = check_idiom_briefing(errors)
    j6 = check_j6_ledger(errors)
    stable = check_stable_subset(errors)
    compat = check_compat_claim(errors)
    caps = check_capability_map(errors)
    ct, ct_files = check_ct_spelling(errors)
    for error in errors:
        print(f"FAIL: {error}")
    # The two status lines print on both paths: on a red run the first one names
    # the actual pin state (`mismatch` / `stale`), so the last line is not a
    # vague "FAIL" that hides which half of G9 broke.
    print(f"spec pin: {spec}")
    if errors:
        print(f"check-docs: FAIL ({len(errors)} problem(s))")
        return 1
    print(
        f"check-docs: OK ({links} relative links in {scanned} files, "
        f"{fragments} fragment(s) in {fragment_files} Markdown files, "
        f"v{version}, {gates} hard gates, {phases} phase status, "
        f"{applies} 适用版本 header(s), {superseded} superseded link(s), "
        f"{signoffs} signoff(s), {briefing} briefing item(s), {j6} J-6 row(s), "
        f"{stable} stability row(s), {compat} compat marker(s), "
        f"{caps} capability row(s), {ct} bare CT in {ct_files} active file(s), "
        f"{toc_entries}/{toc_required} outline entr(ies), "
        f"{line_refs} spec line anchor(s) in {line_entries} ledger entr(ies))"
    )
    print(f"design window: ok ({design}/{window})")  # non-zero/duplicate is fatal above
    return 0


if __name__ == "__main__":
    sys.exit(main())
