#!/usr/bin/env python3
"""PN-1/2/3/6/7/8 phase-ID gate (G1 extension).

The project's historical cards were named `PH-<n>` and lived in
`docs/design/` / `docs/history/design/`.  DOC-74 / DOC-83 moved every card to
`docs/phases/v<M>-PH-<n>/card.md` and recorded the mapping in
`docs/planning/phase-id-ledger.md`; this gate is the mechanical judge of that
state:

  * `window:` (ledger header) is W0/W1/W2/W3 and selects the accepted ID form;
    in W2/W3 a bare `PH-<n>` directory or card head is red (PN-8);
  * every card directory/card-head ID matches `v<M>-PH-<n>` (PN-1), the number
    is unique per MAJOR (PN-3) and `version-minor == n` (PN-2);
  * a revoked number is never reused (PN-7);
  * the ledger has one `migrated` row per live card, every row's status is one
    of migrated/revoked/planned, and the mapped new path exists while the old
    path is gone (PN-6);
  * in W2/W3 no legacy card is left in `docs/design/` / `docs/history/design/`
    (PN-4/PN-6).

Usage:
  phase_id.py <repo-root>
  phase_id.py <repo-root> --dir <phases-dir> --window W2
  phase_id.py selftest
Exit: 0 pass, 1 violation, 2 usage.
"""
from __future__ import annotations

import argparse
import os
import re
import shutil
import sys
import tempfile

ID_RE = re.compile(r"^v(0|[1-9][0-9]*)-PH-(0|[1-9][0-9]*)$")
BARE_RE = re.compile(r"^PH-0*([0-9]+)$")
LEDGER_REL = "docs/planning/phase-id-ledger.md"
WINDOWS = ("W0", "W1", "W2", "W3")
LEDGER_STATUS = {"migrated", "revoked", "planned"}
LEGACY_DIRS = ("docs/design", "docs/history/design")
LEGACY_CARD_RE = re.compile(r"^phase[0-9]+\.md$")


def read(path):
    with open(path, encoding="utf-8", errors="replace") as fh:
        return fh.read()


def top_fields(text):
    fields = {}
    for line in text.splitlines():
        if re.match(r"^##\s+", line):
            break
        s = line.strip().lstrip("-*+ ").strip()
        m = re.match(r"^([A-Za-z\u4e00-\u9fff][A-Za-z0-9_\-\u4e00-\u9fff]*)\s*[：:]\s*(.*?)\s*$", s)
        if m and m.group(1) not in fields:
            fields[m.group(1)] = m.group(2)
    return fields


def card_field(text, key):
    fields = top_fields(text)
    if key in fields and fields[key]:
        return fields[key].strip().strip("`* ")
    for line in text.splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip().strip("*` ") for c in line.strip().strip("|").split("|")]
        if len(cells) >= 2 and cells[0] == key:
            return cells[1]
    return ""


def ledger_window(root, override=None):
    if override:
        return override
    path = os.path.join(root, LEDGER_REL)
    if not os.path.isfile(path):
        return ""
    fields = top_fields(read(path))
    return fields.get("window", "")


def parse_phase(pid, window):
    m = ID_RE.match(pid)
    if m:
        if window == "W0":
            raise ValueError(f"{pid} 在 W0 不被接受（W0 只认裸 PH-<n>，PN-8）")
        return int(m.group(1)), int(m.group(2))
    m = BARE_RE.match(pid)
    if m:
        if window in ("W0", "W1"):
            return 0, int(m.group(1))
        raise ValueError(f"裸 {pid} 在 window={window} 不被接受（PN-8）")
    raise ValueError(f"{pid!r} 不符合 PN-1 语法（期望 v<M>-PH-<n>）")


def ledger_rows(root):
    path = os.path.join(root, LEDGER_REL)
    if not os.path.isfile(path):
        return []
    rows = []
    for line in read(path).splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 6 or cells[0].lower().startswith("旧"):
            continue
        if all(set(c) <= set("-: ") for c in cells):
            continue
        rows.append(dict(zip(("old", "new", "oldpath", "newpath", "version", "status"), cells)))
    return rows


def load_cards(phases_dir):
    cards = []
    if not os.path.isdir(phases_dir):
        return cards
    for name in sorted(os.listdir(phases_dir)):
        path = os.path.join(phases_dir, name, "card.md")
        if os.path.isfile(path):
            cards.append((name, path))
    return cards


def check(root, phases_dir=None, window_override=None):
    errors = []
    window = ledger_window(root, window_override)
    if window not in WINDOWS:
        return [f"{LEDGER_REL}: window 缺失或不合法（只允许 W0/W1/W2/W3，PN-8）"]

    phases_dir = phases_dir or os.path.join(root, "docs/phases")
    cards = load_cards(phases_dir)
    if not cards:
        return [f"{os.path.relpath(phases_dir, root)}: 没有 phase 卡（PN-6）"]

    seen = {}
    for dirname, path in cards:
        label = os.path.relpath(path, root)
        text = read(path)
        pid = card_field(text, "phase-id")
        if not pid:
            pid = card_field(text, "编号")
        m = re.search(r"(?:v[0-9]+-)?PH-[0-9]+", pid)
        if m:
            pid = m.group(0)
        if not pid:
            errors.append(f"{label}: 缺 phase-id（PN-1）")
            continue
        try:
            major, n = parse_phase(pid, window)
        except ValueError as exc:
            errors.append(f"{label}: {exc}")
            continue
        if dirname != pid:
            errors.append(f"{label}: 目录名 {dirname} 与卡头 phase-id {pid} 不一致（PN-1）")
        try:
            minor = int(card_field(text, "version-minor"))
        except ValueError:
            errors.append(f"{label}: version-minor 缺失或不是整数（PN-2）")
            minor = None
        if minor is not None and minor != n:
            errors.append(f"{label}: version-minor={minor} 不等于 n={n}（PN-2）")
        key = (major, n)
        if key in seen:
            errors.append(f"{label}: phase 号 {pid} 与 {seen[key]} 重复（PN-3）")
        seen[key] = label

    rows = ledger_rows(root)
    revoked = {row["new"] for row in rows if row["status"] == "revoked"}
    for key, label in seen.items():
        pass
    migrated = [row for row in rows if row["status"] == "migrated"]
    by_new = {}
    for row in rows:
        if row["status"] not in LEDGER_STATUS:
            errors.append(f"{LEDGER_REL}: 状态 {row['status']!r} 不在 migrated/revoked/planned（PN-6）")
        by_new.setdefault(row["new"], []).append(row)
    card_ids = set()
    for dirname, _ in cards:
        card_ids.add(dirname)
        hits = [row for row in by_new.get(dirname, []) if row["status"] == "migrated"]
        if not hits:
            errors.append(f"{LEDGER_REL}: {dirname} 缺 migrated 行（PN-6）")
        if dirname in revoked:
            errors.append(f"{LEDGER_REL}: {dirname} 已被撤销，禁止复用（PN-7）")
        for row in hits:
            if window in ("W2", "W3"):
                if not os.path.exists(os.path.join(root, row["newpath"])):
                    errors.append(f"{LEDGER_REL}: 新路径不存在 {row['newpath']}（PN-6）")
                if os.path.exists(os.path.join(root, row["oldpath"])):
                    errors.append(f"{LEDGER_REL}: 旧路径仍存在 {row['oldpath']}（PN-6）")
    if len(migrated) != len(cards):
        errors.append(f"{LEDGER_REL}: migrated 行数 {len(migrated)} != 卡片数 {len(cards)}（PN-6）")

    if window in ("W2", "W3"):
        for base in LEGACY_DIRS:
            full = os.path.join(root, base)
            if not os.path.isdir(full):
                continue
            for name in sorted(os.listdir(full)):
                if LEGACY_CARD_RE.match(name):
                    errors.append(f"{base}/{name}: W2/W3 下仍存在 legacy 卡（PN-4/PN-6）")
    return errors


def write_case(tmp, window, cards, rows):
    os.makedirs(os.path.join(tmp, "docs/planning"), exist_ok=True)
    ledger = ["# ledger", "", f"window: {window}", "", "| 旧 ID | 新 ID | 旧路径 | 新路径 | 版本 | 状态 |",
              "| --- | --- | --- | --- | --- | --- |"]
    ledger.extend(rows)
    with open(os.path.join(tmp, LEDGER_REL), "w", encoding="utf-8") as fh:
        fh.write("\n".join(ledger) + "\n")
    for dirname, pid, minor in cards:
        d = os.path.join(tmp, "docs/phases", dirname)
        os.makedirs(d, exist_ok=True)
        with open(os.path.join(d, "card.md"), "w", encoding="utf-8") as fh:
            fh.write(f"---\nphase-id: {pid}\nversion-minor: {minor}\n---\n\n# card\n")


def row(old, new):
    return f"| {old} | {new} | docs/design/phase{old.split('-')[-1]}.md | docs/phases/{new}/card.md | v0.9.0 | migrated |"


def selftest():
    cases = []
    base = tempfile.mkdtemp(prefix="phaseid.")
    try:
        def make(name):
            path = os.path.join(base, name)
            os.makedirs(path, exist_ok=True)
            return path

        # 1: W2, new ID, coherent ledger.
        p = make("good")
        write_case(p, "W2", [("v0-PH-9", "v0-PH-9", 9)],
                   [row("PH-9", "v0-PH-9")])
        cases.append(("W2 good v0-PH-9", p, None, True))

        # 2: W2, bare PH-<n> directory/card head -> red (the W2 negative).
        p = make("bare")
        write_case(p, "W2", [("PH-9", "PH-9", 9)], [row("PH-9", "PH-9")])
        cases.append(("W2 bare PH-9", p, None, False))

        # 3: W1, bare PH-<n> is still legal (dual-recognition window).
        p = make("w1")
        write_case(p, "W1", [("PH-9", "PH-9", 9)], [row("PH-9", "PH-9")])
        cases.append(("W1 bare PH-9", p, None, True))

        # 4: card head disagrees with its directory.
        p = make("mismatch")
        write_case(p, "W2", [("v0-PH-9", "v0-PH-8", 9)],
                   [row("PH-9", "v0-PH-9")])
        cases.append(("dir/card mismatch", p, None, False))

        # 5: version-minor != n.
        p = make("minor")
        write_case(p, "W2", [("v0-PH-9", "v0-PH-9", 8)],
                   [row("PH-9", "v0-PH-9")])
        cases.append(("version-minor drift", p, None, False))

        # 6: W2 with a legacy card still in docs/design.
        p = make("legacy")
        write_case(p, "W2", [("v0-PH-9", "v0-PH-9", 9)],
                   [row("PH-9", "v0-PH-9")])
        os.makedirs(os.path.join(p, "docs/design"), exist_ok=True)
        open(os.path.join(p, "docs/design/phase9.md"), "w").close()
        cases.append(("W2 legacy card left", p, None, False))

        # 7: ledger misses the card row.
        p = make("norow")
        write_case(p, "W2", [("v0-PH-9", "v0-PH-9", 9)], [])
        cases.append(("ledger without row", p, None, False))

        failed = 0
        for name, path, override, want_ok in cases:
            errors = check(path, window_override=override)
            ok = not errors
            if ok != want_ok:
                failed += 1
                print(f"phase-id selftest: {name}: {'OK' if ok else 'RED'} "
                      f"(expected {'OK' if want_ok else 'RED'})", file=sys.stderr)
                for err in errors:
                    print("  " + err, file=sys.stderr)
            else:
                print(f"phase-id selftest: {name}: {'OK' if ok else 'RED'} -> OK")
        if failed:
            print(f"phase-id selftest: FAIL ({failed} case(s))", file=sys.stderr)
            return 1
        print(f"phase-id selftest: OK ({len(cases)} cases, W2 bare PH-<n> is red)")
        return 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


def main():
    args = sys.argv[1:]
    if args[:1] == ["selftest"]:
        return selftest()
    ap = argparse.ArgumentParser(description="PN-1/2/3/6/7/8 phase-ID gate")
    ap.add_argument("root", nargs="?")
    ap.add_argument("--dir", default=None, help="override docs/phases")
    ap.add_argument("--window", default=None, help="override the ledger window")
    ns = ap.parse_args(args)
    if not ns.root:
        ap.print_usage(sys.stderr)
        return 2
    root = os.path.abspath(ns.root)
    phases = os.path.abspath(ns.dir) if ns.dir else None
    errors = check(root, phases, ns.window)
    for err in errors:
        print("g1: FAIL: " + err, file=sys.stderr)
    if errors:
        return 1
    window = ledger_window(root, ns.window)
    print(f"g1: OK (phase IDs all v<M>-PH-<n>, window {window}; "
          f"{len(load_cards(phases or os.path.join(root, 'docs/phases')))} card(s), "
          f"{len(ledger_rows(root))} ledger row(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
