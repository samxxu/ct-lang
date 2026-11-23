#!/usr/bin/env python3
"""DOC-74 / DOC-83: one-shot phase-ID migration (PN-4…PN-8, D-019).

The script is the *only* thing that changes phase IDs.  It performs the whole
atomic migration in the order PN-6 requires:

  1. discover the live cards — `docs/design/phase<NN>.md`,
     `docs/history/design/phase<NN>.md` and `docs/design/v1-phase0.md`;
  2. rename every card to `docs/phases/v<M>-PH-<n>/card.md` (`git mv`, so the
     rename is recorded);
  3. add the top fields `phase-id:` / `version-minor:` (D-019 C) and retire the
     "legacy path blocked" note;
  4. rewrite every relative Markdown link (a moved card's base changes by one
     directory level) and every textual `docs/…/design/phase<NN>.md`;
  5. replace bare `PH-<n>` with `v0-PH-<n>` outside the PN-5/PN-6 exemptions;
  6. write `docs/planning/phase-id-ledger.md` with `window: W2`;
  7. run the five PN-6 set assertions plus diff / tag / scope guards; any
     failure rolls the whole worktree back to HEAD.

Exemptions (PN-5): `battle/**`, historical tags and commit messages, source
code and test strings, and the pinned spec copy `docs/spec/**` are never
touched.

Usage:
  python3 tools/migrate-phase-ids.py --dry-run   # print the plan, change nothing
  python3 tools/migrate-phase-ids.py --apply     # migrate, assert, rollback on failure
  python3 tools/migrate-phase-ids.py --verify    # assertions on the current tree
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
import unicodedata
import urllib.parse

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LEDGER = "docs/planning/phase-id-ledger.md"
PHASES = "docs/phases"
EXEMPT_DIRS = ("battle", "selfhost", "test", "tools", "editors", "examples", "lib", "bootstrap")
SCAN_ROOTS = ("docs", "issues")
SCAN_TOP = ("README.md", "AGENTS.md")
SPEC_BLOCK_BEGIN = "<!-- spec:begin"
SPEC_BLOCK_END = "<!-- spec:end -->"
CARD_RE = re.compile(r"^phase(\d+)\.md$")
NEW_DIR_RE = re.compile(r"^v(0|[1-9][0-9]*)-PH-(0|[1-9][0-9]*)$")
BARE_RE = re.compile(r"(?<![A-Za-z0-9_-])PH-(\d+)\b")
LINK_RE = re.compile(r"(!?\[[^\]]*\]\()([^)\s]+)(\))")
ROADMAP_ROW_RE = re.compile(r"^\|\s*Phase\s+\d+\s*\|", re.M)

PATH_SUBS = (
    (re.compile(r"docs/history/design/phase(\d+)\.md"), r"docs/phases/v0-PH-\1/card.md"),
    (re.compile(r"docs/design/phase(\d+)\.md"), r"docs/phases/v0-PH-\1/card.md"),
    (re.compile(r"(?<!docs/)(?<!history/)history/design/phase(\d+)\.md"),
     r"phases/v0-PH-\1/card.md"),
    (re.compile(r"(?<!docs/)(?<!history/)(?<!\.\./)design/phase(\d+)\.md"),
     r"phases/v0-PH-\1/card.md"),
)


def sh(args, check=True, cwd=ROOT):
    return subprocess.run(args, cwd=cwd, capture_output=True, text=True, check=check)


def git(*args, check=True):
    return sh(["git", *args], check=check)


def read(path):
    with open(os.path.join(ROOT, path), encoding="utf-8") as fh:
        return fh.read()


def write(path, text):
    full = os.path.join(ROOT, path)
    os.makedirs(os.path.dirname(full), exist_ok=True)
    with open(full, "w", encoding="utf-8") as fh:
        fh.write(text)


def exists(path):
    return os.path.exists(os.path.join(ROOT, path))


def repo_clean():
    out = git("status", "--porcelain", "--untracked-files=all").stdout
    dirty = [line for line in out.splitlines() if not line[3:].startswith(".temp/")]
    return dirty


def discover():
    """Return the pre-migration cards as dicts (old id/path, new id/path, n)."""
    cards = []
    for base in ("docs/design", "docs/history/design"):
        if not os.path.isdir(os.path.join(ROOT, base)):
            continue
        for name in sorted(os.listdir(os.path.join(ROOT, base))):
            m = CARD_RE.match(name)
            if not m:
                continue
            n = int(m.group(1))
            cards.append(card(n, f"{base}/{name}", 0, n))
    v1 = "docs/design/v1-phase0.md"
    if exists(v1):
        cards.append(card(0, v1, 1, 0))
    return cards


def card(n, old_path, major, minor):
    pid = f"v{major}-PH-{n}"
    return {
        "n": n,
        "major": major,
        "old_id": f"PH-{n}" if major == 0 else pid,
        "new_id": pid,
        "old_path": old_path,
        "new_path": f"{PHASES}/{pid}/card.md",
        "version": f"v{major}.{minor}.0",
    }


def window_of(text):
    for line in text.splitlines():
        if line.startswith("## "):
            break
        m = re.match(r"^window\s*:\s*(\S+)\s*$", line.strip())
        if m:
            return m.group(1)
    return ""


def add_top_fields(text, pid, minor):
    if re.search(r"^phase-id\s*:", text, re.M):
        return text
    head = f"---\nphase-id: {pid}\nversion-minor: {minor}\n---\n\n"
    return head + text


def retire_legacy_note(text, pid):
    text = re.sub(
        r"（legacy 文件 `phase\d+\.md`）",
        f"（`docs/phases/{pid}/card.md`）",
        text,
    )
    text = re.sub(
        r"^> \*\*布局说明\*\*：phase-ID 迁移仍被 blocker 挡住[^\n]*$",
        f"> **布局说明**：phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），"
        f"本卡位于 `docs/phases/{pid}/card.md`。",
        text,
        flags=re.M,
    )
    text = re.sub(
        r"phase-ID 迁移仍被 blocker 挡住，本卡用 `v1-phase0\.md` 路径。",
        "phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），"
        f"本卡位于 `docs/phases/{pid}/card.md`。",
        text,
    )
    return text


def slugify(heading):
    """GitHub heading slug, identical to test/docs/check-docs.py."""
    text = re.sub(r"<[^>]*>", "", heading.strip()).lower()
    text = urllib.parse.unquote(text)
    out = []
    for char in text:
        if char in "- ":
            out.append(char)
        elif char.isspace():
            out.append(" ")
        elif (char.isalnum() or unicodedata.category(char).startswith("M")
              or unicodedata.category(char) == "Pc"):
            out.append(char)
    return "".join(out).strip().replace(" ", "-")


def heading_slugs(text):
    """old slug -> new slug for headings whose text the migration changes."""
    changed = {}
    for line in text.splitlines():
        m = re.match(r"^(#{1,6})\s+(.*)$", line)
        if not m:
            continue
        old = m.group(2).strip()
        new = replace_ids(replace_paths(old))
        if old != new:
            changed[slugify(old)] = slugify(new)
    return changed


def rewrite_fragment_slugs(text, slug_map):
    if not slug_map:
        return text

    def repl(m):
        target = m.group(2)
        dest, sep, frag = target.partition("#")
        if not sep or not frag:
            return m.group(0)
        new = slug_map.get(frag)
        if not new:
            return m.group(0)
        return m.group(1) + dest + "#" + new + m.group(3)

    return LINK_RE.sub(repl, text)


def rewrite_links(text, old_dir, new_dir, card_map):
    def repl(m):
        target = m.group(2)
        if re.match(r"^(?:https?:|mailto:|file:|#|/)", target):
            return m.group(0)
        dest, sep, frag = target.partition("#")
        if not dest:
            return m.group(0)
        resolved = os.path.normpath(os.path.join(old_dir, dest))
        rel = os.path.relpath(resolved, ROOT)
        if rel in card_map:
            resolved = os.path.normpath(os.path.join(ROOT, card_map[rel]))
        elif old_dir == new_dir:
            return m.group(0)
        newrel = os.path.relpath(resolved, new_dir)
        return m.group(1) + newrel + (sep + frag if sep else "") + m.group(3)

    return LINK_RE.sub(repl, text)


def replace_paths(text):
    for pattern, repl in PATH_SUBS:
        text = pattern.sub(repl, text)
    return text


def replace_ids(text):
    return BARE_RE.sub(r"v0-PH-\1", text)


def split_agents(text):
    """Return [(chunk, editable)] so the generated spec block stays verbatim."""
    begin = text.find(SPEC_BLOCK_BEGIN)
    if begin < 0:
        return [(text, True)]
    end = text.find(SPEC_BLOCK_END, begin)
    if end < 0:
        return [(text, True)]
    end += len(SPEC_BLOCK_END)
    return [(text[:begin], True), (text[begin:end], False), (text[end:], True)]


def scan_files():
    files = []
    for name in SCAN_TOP:
        if exists(name):
            files.append(name)
    for base in SCAN_ROOTS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, base)):
            dirnames[:] = sorted(d for d in dirnames if d not in (".git", ".temp"))
            for name in sorted(filenames):
                if not name.endswith((".md", ".txt")):
                    continue
                rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
                if rel.startswith("docs/spec/"):
                    continue
                if rel == LEDGER:
                    continue
                files.append(rel)
    return sorted(set(files))


def rebuild_ledger(rows):
    lines = [
        "# phase-ID 编号账本（PN-6）",
        "",
        "window: W2",
        "",
        "> 迁移：DOC-74 / DOC-83，裁定 [D-019](../decisions/D-019.md)；"
        "脚本 `tools/migrate-phase-ids.py`。",
        "> 版本列是 PN-2 的规范化映射 `v<M>.<n>.0`；已收口的历史 tag 保留原偏移，"
        "见 [version-legacy-offsets.tsv](version-legacy-offsets.tsv)，迁移不改任何版本号。",
        "> `battle/**`、历史 tag、历史提交信息与代码/测试字符串为原始证据，"
        "不在迁移范围（PN-5/PN-6）。",
        "",
        "| 旧 ID | 新 ID | 旧路径 | 新路径 | 版本 | 状态 |",
        "| --- | --- | --- | --- | --- | --- |",
    ]
    for row in sorted(rows, key=lambda r: (r["major"], r["n"])):
        lines.append(
            f"| {row['old_id']} | {row['new_id']} | {row['old_path']} | "
            f"{row['new_path']} | {row['version']} | migrated |"
        )
    lines += [
        "",
        "## 窗口推进",
        "",
        "- **W0**（迁移前）：卡片位于 `docs/design/phaseNN.md` / "
        "`docs/history/design/phaseNN.md`，裸 `PH-<n>` 为唯一形态。",
        "- **W1**（脚本预检）：账本先建、迁移脚本以双认窗口 discover 旧卡；"
        "本仓与重命名同批落地，不单独提交 W1 中间态。",
        "- **W2**（本提交）：重命名落地，只认 `v<M>-PH-<n>`；"
        "裸 `PH-<n>` 负例见 `test/gates/phase_id_test.sh`（先红后绿）。",
        "- **W3**：`v1.0` 开卡后由 REQ 推进；W3→W2 不回溯。",
    ]
    return "\n".join(lines) + "\n"


def snapshot(rows):
    return {
        "head": git("rev-parse", "HEAD").stdout.strip(),
        "tags": sorted(git("tag", "-l").stdout.split()),
        "roadmap_rows": len(ROADMAP_ROW_RE.findall(read("docs/roadmap.md"))),
        "old_ids": sorted(row["old_id"] for row in rows),
    }


def apply_migration(rows, snap):
    card_map = {row["old_path"]: row["new_path"] for row in rows}
    # Every Markdown/text file is processed once; moved cards leave their old
    # location and are read from the new one (the base for relative links).
    file_map = {path: path for path in scan_files()}
    for row in rows:
        file_map.pop(row["old_path"], None)
        file_map[row["new_path"]] = row["new_path"]

    for row in rows:
        os.makedirs(os.path.join(ROOT, os.path.dirname(row["new_path"])), exist_ok=True)
        git("mv", row["old_path"], row["new_path"])

    slug_map = {}
    for current in file_map:
        slug_map.update(heading_slugs(read(current)))

    for current in sorted(file_map):
        old_path = current
        for row in rows:
            if row["new_path"] == current:
                old_path = row["old_path"]
                break
        text = read(current)
        chunks = split_agents(text) if current == "AGENTS.md" else [(text, True)]
        out = []
        for chunk, editable in chunks:
            if not editable:
                out.append(chunk)
                continue
            chunk = rewrite_links(
                chunk, os.path.dirname(old_path), os.path.dirname(current), card_map
            )
            chunk = replace_paths(chunk)
            chunk = replace_ids(chunk)
            chunk = rewrite_fragment_slugs(chunk, slug_map)
            out.append(chunk)
        text = "".join(out)
        if old_path != current:
            row = next(r for r in rows if r["new_path"] == current)
            text = add_top_fields(text, row["new_id"], row["n"])
            text = retire_legacy_note(text, row["new_id"])
        write(current, text)

    # docs TSVs carry references too (the G2 scope protocol cell); the
    # version-legacy-offsets ledger is historical data and stays verbatim.
    for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, "docs")):
        dirnames[:] = sorted(d for d in dirnames if d not in (".git", ".temp"))
        for name in sorted(filenames):
            if not name.endswith(".tsv"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), ROOT)
            if rel == "docs/planning/version-legacy-offsets.tsv":
                continue
            write(rel, replace_ids(read(rel)))

    # G2 scope registry: it names the cards relative to docs/design.
    scope = "docs/design/acc-scope.tsv"
    if exists(scope):
        text = read(scope)
        text = re.sub(r"^phase(\d+)\.md\t", r"../phases/v0-PH-\1/card.md\t", text, flags=re.M)
        write(scope, text)

    # docs/README archive policy: cards are consolidated under docs/phases.
    readme = "docs/README.md"
    text = read(readme)
    text = re.sub(
        r"> \*\*当前版本 v[0-9.]+。\*\* 本目录的 `design/` 保留\*\*最近 12 个已完成阶段\*\*的设计文档"
        r"（当前在研\n> 阶段计入），更早的 `design/phase\*\.md` 必须退役到 "
        r"\[history/design/\]\(history/design/\)；",
        "> **当前版本 v0.88.3。** 全部 phase 卡集中在 [phases/](phases/)，一卡一目录"
        "（`docs/phases/v<M>-PH-<n>/card.md`，PN-1）；`design/` 只保留计划、评审与映射等"
        "辅助记录，`history/design/` 为历史快照；",
        text,
    )
    write(readme, text)

    write(LEDGER, rebuild_ledger(rows))


def rel_exists(path):
    return os.path.exists(os.path.join(ROOT, path))


def migrated_cards():
    out = []
    base = os.path.join(ROOT, PHASES)
    if not os.path.isdir(base):
        return out
    for name in sorted(os.listdir(base)):
        m = NEW_DIR_RE.match(name)
        card = os.path.join(PHASES, name, "card.md")
        if m and rel_exists(card):
            out.append({"major": int(m.group(1)), "n": int(m.group(2)), "new_id": name,
                        "path": card})
    return out


def ledger_rows():
    if not rel_exists(LEDGER):
        return []
    rows = []
    for line in read(LEDGER).splitlines():
        if not line.strip().startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) != 6 or cells[0].lower().startswith("旧"):
            continue
        if all(set(c) <= set("-: ") for c in cells):
            continue
        rows.append(dict(zip(("old_id", "new_id", "old_path", "new_path", "version", "status"),
                             cells)))
    return rows


def check_assertions(rows, snap, expect_apply):
    ok = True
    out = []

    def emit(ok_case, text):
        nonlocal ok
        ok = ok and ok_case
        out.append(("PASS" if ok_case else "FAIL") + " " + text)

    old_ids = sorted(row["old_id"] for row in rows)
    new_ids = sorted(row["new_id"] for row in rows)
    shown = sorted(c["new_id"] for c in migrated_cards())
    emit(len(old_ids) == len(set(old_ids)) and len(new_ids) == len(set(new_ids))
         and sorted(shown) == new_ids,
         f"assertion 1/5 ID 集合一一对应：旧 ID {len(old_ids)} 个、新 ID {len(new_ids)} 个、"
         f"迁移后目录 {len(shown)} 个（无增减、无重复）")
    if expect_apply:
        emit(old_ids == snap["old_ids"],
             f"assertion 1/5 旧 ID 集合 = 迁移前卡片 ID 集合（{len(snap['old_ids'])} 个，"
             "见脚本 discover 输出）")

    missing_new = [row["new_path"] for row in rows if not rel_exists(row["new_path"])]
    still_old = [row["old_path"] for row in rows if rel_exists(row["old_path"])]
    emit(not missing_new and not still_old,
         f"assertion 2/5 路径映射：{len(rows)} 对旧→新；新路径缺失 {len(missing_new)}、"
         f"旧路径残留 {len(still_old)}")

    after = len(ROADMAP_ROW_RE.findall(read("docs/roadmap.md")))
    emit(after == snap["roadmap_rows"],
         f"assertion 3/5 roadmap phase 行数：迁移前 {snap['roadmap_rows']}、"
         f"迁移后 {after}（相等）")

    docs = sh([sys.executable, "test/docs/check-docs.py"], check=False)
    dead = [line for line in (docs.stdout + docs.stderr).splitlines() if "dead link" in line]
    lines = (docs.stdout + docs.stderr).strip().splitlines()
    summary = (lines or [""])[-1]
    emit(docs.returncode == 0 and not dead,
         f"assertion 4/5 check-docs：exit {docs.returncode}、dead link {len(dead)}；{summary}")
    if docs.returncode != 0:
        out.extend("  " + line for line in lines[:20])

    scanned, hits = scan_bare()
    emit(not hits,
         f"assertion 5/5 裸 PH-<n> 扫描：范围 {scanned} 个文件（docs/** 除 docs/spec 与账本、"
         f"issues/**、AGENTS.md 块外、README.md），命中 {len(hits)}")
    if hits:
        out.extend("  " + h for h in hits[:10])

    if expect_apply:
        diff = git("diff", "HEAD", "--name-status", "-M").stdout
        renames, modified = set(), []
        for line in diff.splitlines():
            parts = line.split("\t")
            if parts[0].startswith("R"):
                renames.add((parts[1], parts[2]))
            else:
                modified.append(parts[1])
        want = {(row["old_path"], row["new_path"]) for row in rows
                if row["old_path"] != row["new_path"]}
        emit(renames == want,
             f"assertion +  git diff --name-status -M 的改名集合 {len(renames)} 对 = "
             f"账本映射 {len(want)} 对；其余 {len(modified)} 个路径为文档引用修改")

        allowed = tuple(["docs/", "issues/", "AGENTS.md", "README.md"])
        touched = modified + [p for pair in renames for p in pair]
        bad = [p for p in touched if not p.startswith(allowed)]
        emit(not bad, f"assertion +  改动路径只落在 docs/、issues/、AGENTS.md、README.md"
                      f"（越界 {len(bad)}）")
        if bad:
            out.extend("  " + p for p in bad[:10])

        tags = sorted(git("tag", "-l").stdout.split())
        emit(tags == snap["tags"],
             f"assertion +  git tag 迁移前后逐字相同（{len(tags)} 个 tag）")

        battle = [p for p in touched if p.startswith("battle/")]
        emit(not battle, f"assertion +  battle/** 未被改动（命中 {len(battle)}）")
    else:
        # --verify mode: compare the ledger against the live tree.
        want = {(row["old_path"], row["new_path"]) for row in rows}
        emit(bool(rows), f"assertion +  账本存在且解析到 {len(rows)} 行")
        emit(not missing_new and shown and len(shown) == len(rows),
             f"assertion +  账本行数 {len(rows)} = docs/phases 卡片数 {len(shown)}")

    return ok, out


def scan_bare():
    files = scan_files()
    hits = []
    for rel in files:
        text = read(rel)
        if rel == "AGENTS.md":
            chunks = [chunk for chunk, editable in split_agents(text) if editable]
        else:
            chunks = [text]
        for chunk in chunks:
            for m in BARE_RE.finditer(chunk):
                line = chunk.count("\n", 0, m.start()) + 1
                hits.append(f"{rel}:{line}: {m.group(0)}")
    return len(files), hits


def dry_run(rows):
    print(f"migration plan: {len(rows)} cards")
    for row in rows:
        print(f"  {row['old_id']:>9}  {row['old_path']:44} -> {row['new_path']}  "
              f"({row['version']}, migrated)")
    print(f"ledger: {LEDGER} (window: W2)")
    status = repo_clean()
    print(f"worktree: {'clean' if not status else 'DIRTY'}")
    if status:
        for line in status[:20]:
            print("  " + line)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--dry-run", action="store_true")
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--verify", action="store_true")
    args = ap.parse_args()

    rows = discover()
    if args.verify:
        rows = rows or ledger_rows()
        if not rows:
            print("migrate-phase-ids: no cards and no ledger to verify", file=sys.stderr)
            return 1
        snap = snapshot(rows)
        ok, out = check_assertions(rows, snap, expect_apply=False)
        print("\n".join(out))
        return 0 if ok else 1

    if not rows:
        print("migrate-phase-ids: no old cards found (already migrated?)", file=sys.stderr)
        return 1

    if args.dry_run:
        dry_run(rows)
        return 0

    snap = snapshot(rows)

    dirty = repo_clean()
    if dirty:
        print("migrate-phase-ids: worktree is not clean; refusing to migrate", file=sys.stderr)
        for line in dirty[:20]:
            print("  " + line, file=sys.stderr)
        return 1
    if exists(LEDGER) and window_of(read(LEDGER)) == "W2":
        print("migrate-phase-ids: ledger already at W2; refusing to run twice", file=sys.stderr)
        return 1

    try:
        apply_migration(rows, snap)
        ok, out = check_assertions(rows, snap, expect_apply=True)
    except Exception as exc:  # noqa: BLE001 - any failure must roll back
        print(f"migrate-phase-ids: FAIL while applying: {exc}", file=sys.stderr)
        rollback(snap["head"])
        return 1

    print("\n".join(out))
    if not ok:
        print("migrate-phase-ids: FAIL; rolling back to " + snap["head"][:12], file=sys.stderr)
        rollback(snap["head"])
        return 1
    print(f"migrate-phase-ids: OK ({len(rows)} cards migrated, window: W2)")
    return 0


def rollback(head):
    git("reset", "--hard", head, check=False)
    sh(["git", "clean", "-fdq", PHASES], check=False)
    tracked = git("ls-files", "--error-unmatch", LEDGER, check=False).returncode == 0
    if not tracked and rel_exists(LEDGER):
        os.remove(os.path.join(ROOT, LEDGER))
    # Drop now-empty directories left by the rollback.
    base = os.path.join(ROOT, PHASES)
    if os.path.isdir(base):
        for dirpath, dirnames, filenames in os.walk(base, topdown=False):
            if not dirnames and not filenames:
                os.rmdir(dirpath)
    print("migrate-phase-ids: rolled back to " + head[:12], file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
