#!/usr/bin/env python3
"""
check-docs.py - documentation gate (Phase 17.4).

Standard library only. It asserts seven invariants:

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
     in both the Chinese and the English table;
  5. an "适用版本" header under docs/*.md names the compiler line, never a
     fixed version: the number goes stale at the next bump (DOC-63);
  6. G9: AGENTS.md pins the methodology's `spec-version` and `spec-sha256`
     (CI-8); a missing spec file is an explicit skip, a mismatch is red;
  7. docs/design/ keeps the newest DESIGN_WINDOW phases, older phase docs live
     in docs/history/design/ and may not be duplicated (DOC-66).

Exit code 0 when all seven hold, 1 otherwise.
"""

import hashlib
import os
import re
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

SPEC = os.path.expanduser("~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md")
DESIGN_WINDOW = 12

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
    status = "ok"
    actual = hashlib.sha256(published_spec()).hexdigest()
    if actual != digest.group(1):
        status = "mismatch"
        errors.append(
            f"AGENTS.md: spec-sha256 {digest.group(1)[:12]}... != {actual[:12]}... ({SPEC})"
        )
    spec_head = published_spec().decode(errors="replace")[:2000]
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


def main():
    errors = []
    links, scanned = check_links(errors)
    version = check_version(errors)
    gates = check_gate_count(errors)
    phases = check_phase_status(errors)
    applies = check_applies_to(errors)
    spec = check_spec_pin(errors)
    design, window = check_design_window(errors)
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
        f"v{version}, {gates} hard gates, {phases} phase status, "
        f"{applies} 适用版本 header(s))"
    )
    print(f"design window: ok ({design}/{window})")  # non-zero/duplicate is fatal above
    return 0


if __name__ == "__main__":
    sys.exit(main())
