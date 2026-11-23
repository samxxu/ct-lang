#!/usr/bin/env python3
"""G1 phase-card completeness and G5 criterion<->test minimal subset.

DOC-74 / DOC-83 moved every card to `docs/phases/v<M>-PH-<n>/card.md`; the
legacy flat `docs/design/phase<n>.md` form stays readable for fixtures and for
the W0/W1 dual-recognition window.

G1 (`phase_card.py <root> g1`): the active v0 window (the newest `DESIGN_WINDOW`
  cards; historical cards are frozen by DOC-66) has a title, a status line, a
  non-empty task list, non-empty exit criteria with at least one `E<n>-<k>`
  definition, and `version-minor == n`.

G5 (`phase_card.py <root> g5`): every criterion `E<n>-<k>` owned by an active
  card is referenced at least twice in the card (definition + acceptance/
  verification row) or appears in the test/gate scripts.  A criterion defined
  once and never referenced is a criterion with no case.

Usage: phase_card.py <repo-root> g1|g5 [--dir DIR]
Exit: 0 pass, 1 violation, 2 usage.
"""
import glob
import os
import re
import sys

DESIGN_WINDOW = 12
DIR_ID_RE = re.compile(r"^v(0|[1-9][0-9]*)-PH-(0|[1-9][0-9]*)$")
FLAT_RE = re.compile(r"phase(\d+)\.md$")


def cards(card_dir):
    """Return [(n, path, major)]; new directory layout plus the legacy flat form."""
    out = []
    if os.path.isdir(card_dir):
        for name in sorted(os.listdir(card_dir)):
            m = DIR_ID_RE.match(name)
            path = os.path.join(card_dir, name, "card.md")
            if m and os.path.isfile(path):
                out.append((int(m.group(2)), path, int(m.group(1))))
        for path in sorted(glob.glob(os.path.join(card_dir, "phase[0-9]*.md"))):
            m = FLAT_RE.search(path)
            if m:
                out.append((int(m.group(1)), path, 0))
    return sorted(out)


def active(card_list):
    """The newest DESIGN_WINDOW v0 cards; older cards are frozen (DOC-66)."""
    v0 = [(n, p, m) for n, p, m in card_list if m == 0]
    if not v0:
        return card_list
    floor = max(n for n, _, _ in v0) - DESIGN_WINDOW + 1
    return [(n, p, m) for n, p, m in card_list if m == 0 and n >= floor]


def read(path):
    return open(path, encoding="utf-8", errors="replace").read()


def check_g1(card_dir):
    fails = []
    n_cards = 0
    for n, path, _major in active(cards(card_dir)):
        rel = os.path.relpath(path, card_dir)
        n_cards += 1
        text = read(path)
        m = re.search(r"^# (?:Phase |v[0-9]+-PH-)(\d+)\b(.+)$", text, re.M)
        if not m:
            fails.append(f"{rel}: missing `# Phase <n>` title")
        elif int(m.group(1)) != n:
            fails.append(f"{rel}: title phase {m.group(1)} != directory phase {n}")
        if "状态：" not in text:
            fails.append(f"{rel}: missing status line (`状态：`)")
        task = re.search(r"^\| 任务清单 \| (.+?) \|$", text, re.M)
        if not task or not task.group(1).strip():
            fails.append(f"{rel}: missing/empty `| 任务清单 |` field")
        elif not re.search(r"^\| S\d+[a-z]?", text, re.M):
            fails.append(f"{rel}: task list names no `S<n>` row")
        exit_row = re.search(r"^\| 退出判据 \| (.+?) \|$", text, re.M)
        if not exit_row or not exit_row.group(1).strip():
            fails.append(f"{rel}: missing/empty `| 退出判据 |` field")
        elif not re.search(rf"^\| E{n}-\d+ \|", text, re.M):
            fails.append(f"{rel}: no `E{n}-<k>` definition row")
        vm = re.search(
            r"^(?:\|\s*version-minor\s*\|\s*|version-minor\s*:\s*)(\d+)", text, re.M
        )
        if not vm:
            fails.append(f"{rel}: missing `version-minor` field")
        elif int(vm.group(1)) != n:
            fails.append(f"{rel}: version-minor={vm.group(1)} != {n}")
    if n_cards == 0:
        fails.append(f"no phase cards found under {card_dir}")
    for f in fails:
        print("g1: FAIL: " + f, file=sys.stderr)
    if fails:
        return 1
    print(f"g1: OK ({n_cards} active phase cards: title/status/tasks/exit-criteria/version-minor)")
    return 0


def check_g5(card_dir, root):
    fails = []
    n_ids = 0
    ext = ""
    for base in ("test", "selfhost"):
        for dp, _, fns in os.walk(os.path.join(root, base)):
            for fn in fns:
                if fn.endswith((".sh", ".ct", ".py", ".c")) or fn.startswith("check-"):
                    try:
                        ext += read(os.path.join(dp, fn))
                    except OSError:
                        pass
    for n, path, _major in active(cards(card_dir)):
        rel = os.path.relpath(path, card_dir)
        text = read(path)
        ids = sorted(set(int(x) for x in re.findall(rf"E{n}-(\d+)", text)))
        if not ids:
            fails.append(f"{rel}: no `E{n}-<k>` criterion found")
            continue
        for k in ids:
            n_ids += 1
            tag = f"E{n}-{k}"
            count = len(re.findall(re.escape(tag) + r"(?![0-9])", text))
            if count < 2 and tag not in ext:
                fails.append(f"{rel}: {tag} defined but never referenced (no acceptance row, no test case)")
    for f in fails:
        print("g5: FAIL: " + f, file=sys.stderr)
    if fails:
        return 1
    print(f"g5: OK ({n_ids} criteria: each has a definition + acceptance/test reference)")
    return 0


def main():
    if len(sys.argv) < 3 or sys.argv[2] not in ("g1", "g5"):
        print("usage: phase_card.py <repo-root> g1|g5 [--dir DIR]", file=sys.stderr)
        return 2
    root = sys.argv[1]
    gate = sys.argv[2]
    card_dir = os.path.join(root, "docs/phases")
    if len(sys.argv) >= 5 and sys.argv[3] == "--dir":
        card_dir = sys.argv[4]
    if gate == "g1":
        return check_g1(card_dir)
    return check_g5(card_dir, root)


if __name__ == "__main__":
    sys.exit(main())
