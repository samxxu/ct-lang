#!/usr/bin/env python3
"""
check-docs.py - documentation gate (Phase 17.4).

Standard library only. It asserts four invariants:

  1. every relative link in docs/**/*.md and README.md resolves;
     the only exemption is a historical snapshot under docs/history/reports/**
     that links into the since-deleted selfhost/ast/** or selfhost/src/**;
  2. the version token written in README.md and docs/README.md equals
     CTC_VERSION in selfhost/l0/ctc.c (and all compiler layers agree);
  3. the hard-gate count stated in README.md, docs/README.md and
     docs/glossary.md equals the number of run_gate calls in
     selfhost/check-all.sh; issues/README.md carries the same count in a
     machine-readable `<!-- gates:N -->` marker (its dated records quote
     historical counts, so prose scanning is not usable there); ci.yml job
     step labels may not name a stale count;
  4. the status line of every docs/design/phase*.md matches the phase table
     in docs/roadmap.md (done -> check, in progress -> half, planned -> white),
     in both the Chinese and the English table.

Exit code 0 when all four hold, 1 otherwise.
"""

import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

LINK = re.compile(r"!?\[[^\]]*\]\(([^)]+)\)")
FENCE = re.compile(r"```.*?```", re.S)
INLINE = re.compile(r"`[^`\n]*`")

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
    for match in re.finditer(r"(\d+|nine|ten|eleven|twelve)\s+hard gates", workflow, re.I):
        token = match.group(1).lower()
        claim = int(token) if token.isdigit() else spelled[token]
        if claim != actual:
            errors.append(f".github/workflows/ci.yml: states {claim} hard gates, check-all.sh runs {actual}")
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


def main():
    errors = []
    links, scanned = check_links(errors)
    version = check_version(errors)
    gates = check_gate_count(errors)
    phases = check_phase_status(errors)
    for error in errors:
        print(f"FAIL: {error}")
    if errors:
        print(f"check-docs: FAIL ({len(errors)} problem(s))")
        return 1
    print(
        f"check-docs: OK ({links} relative links in {scanned} files, "
        f"v{version}, {gates} hard gates, {phases} phase status)"
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
