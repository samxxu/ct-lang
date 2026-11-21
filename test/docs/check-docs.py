#!/usr/bin/env python3
"""
check-docs.py - documentation gate (Phase 17.4).

Standard library only. It asserts eleven invariants:

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
     four, a non-empty 最小可判证据, and a reason on every `阻塞` row.

Exit code 0 when all eleven hold, 1 otherwise.
"""

import hashlib
import os
import re
import subprocess
import sys

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


def check_j6_ledger(errors):
    """SH-104: the J-6 evidence ledger must carry every P-1…P-6 row with a
    legal state, a non-empty minimal criterion, and a reason on 阻塞 rows."""
    path = os.path.join(ROOT, "docs/planning/j6-evidence/ledger.md")
    if not os.path.exists(path):
        errors.append("docs/planning/j6-evidence/ledger.md: missing (SH-104)")
        return 0
    text = read(path)
    seen = {}
    for m in J6_ROW.finditer(text):
        rid = m.group(1)
        cri, ev, state, owner = (m.group(2).strip(), m.group(3).strip(),
                                 m.group(4).strip(), m.group(5).strip())
        seen[rid] = state
        if state not in J6_STATES:
            errors.append(f"j6-ledger: {rid} has status '{state}' (expected 已过/部分/缺失/阻塞)")
        if not cri or cri in ("—", "-"):
            errors.append(f"j6-ledger: {rid} has no 最小可判证据")
        if not owner or owner in ("—", "-"):
            errors.append(f"j6-ledger: {rid} has no 负责人")
        if state == "阻塞" and "阻塞" not in ev:
            errors.append(f"j6-ledger: {rid} is 阻塞 without a reason in 现有证据")
        if state == "已过" and (not ev or ev in ("—", "-")):
            errors.append(f"j6-ledger: {rid} is 已过 without an evidence pointer")
    for rid in sorted(J6_IDS - set(seen)):
        errors.append(f"j6-ledger: {rid} row is missing (SH-104)")
    return len(seen)


def main():
    errors = []
    links, scanned = check_links(errors)
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
        f"{applies} 适用版本 header(s), {superseded} superseded link(s), "
        f"{signoffs} signoff(s), {briefing} briefing item(s), {j6} J-6 row(s))"
    )
    print(f"design window: ok ({design}/{window})")  # non-zero/duplicate is fatal above
    return 0


if __name__ == "__main__":
    sys.exit(main())
