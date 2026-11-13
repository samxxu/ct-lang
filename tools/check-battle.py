#!/usr/bin/env python3
"""check-battle.py - validate one battle case against ai-coding-workflow §7.

Usage:
    python3 tools/check-battle.py <battle-id> [--strict] [--rerun] [--json]

The checker is read-only: it never edits claims, verdicts or source.  It
validates the machine-checkable parts of §7:

  * question.md fields, H-1 (opposition present and != proposer) and
    H-2 (judge == EDITOR, proposer != EDITOR);
  * at least one criterion, each with a non-placeholder pass condition;
  * claim.md / counter.md with E1-E5 sections (§7.7), and any r2..r3 rounds
    carrying a new E1 or E2 (§7.8 T3);
  * at most 3 rounds (§7.11 H-4);
  * verify.json: environment, evidence (command/exit/output/reproduced),
    anchors that resolve to real file:line, and a non-empty checks matrix
    when verdict.md exists (§7.8 T4);
  * optional --rerun re-executes each evidence command once (60 s timeout)
    and compares the exit code; --strict turns anchor warnings into errors.

Exit code 0 = no errors, 1 = at least one error.
"""

import json
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path.cwd()
BATTLES = ROOT / "battle"
ANCHOR_RE = re.compile(r"([A-Za-z0-9_./-]+\.(?:md|ct|c|h|py|sh|json)):(\d+)")
E_HEAD_RE = re.compile(r"(?m)^#{1,4}\s*.*?\bE([1-5])\b")
ROUND_RE = re.compile(r"^(claim|counter)-r(\d+)\.md$")
PLACEHOLDERS = ("<待填", "（空）", "TBD", "TODO")

ERR = []
WARN = []


def err(msg):
    ERR.append(msg)


def warn(msg):
    WARN.append(msg)


def read(path):
    try:
        return path.read_text(encoding="utf-8")
    except OSError as exc:
        err(f"cannot read {path}: {exc}")
        return ""


def parse_front_matter(text):
    """Simple key: value front matter; no nesting (the format is a flat map)."""
    out = {}
    lines = text.splitlines()
    if not lines or lines[0].strip() != "---":
        return out
    for line in lines[1:]:
        if line.strip() == "---":
            break
        if ":" not in line:
            continue
        k, v = line.split(":", 1)
        out[k.strip()] = v.strip()
    return out


def parse_table_fields(text):
    """Fallback for the hand-written question.md tables (`| key | value |`)."""
    out = {}
    alias = {
        "当前 HEAD": "head",
        "触发理由": "trigger",
        "相关 Issue/CR": "issue",
        "禁止触碰": "forbidden",
    }
    for line in text.splitlines():
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        key = alias.get(cells[0], cells[0])
        if key.lower() in ("proposer", "opposition", "judge", "head", "trigger", "forbidden"):
            key = key.lower()
        if key in ("head", "trigger", "proposer", "opposition", "judge", "forbidden"):
            if set(cells[1]) <= set("-: "):
                continue
            out.setdefault(key, cells[1])
    return out


def parse_question(path):
    text = read(path)
    data = parse_front_matter(text)
    for k, v in parse_table_fields(text).items():
        data.setdefault(k, v)
    return data, text


def parse_criteria(text):
    """Criteria rows: J-1, ACC-3 ... inside the 逐条判据 section."""
    rows = []
    in_sec = False
    for line in text.splitlines():
        if re.match(r"^#{2,4}\s*.*判据", line):
            in_sec = True
            continue
        if in_sec and re.match(r"^#{2,4}\s", line):
            break
        if not in_sec or not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 2:
            continue
        if not re.match(r"^(J|ACC)-\d+$", cells[0]):
            continue
        rows.append(cells)
    return rows


def section_body(text, letter):
    """Body of the first heading containing E<letter>, until the next heading."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if re.match(r"^#{1,4}\s", line) and re.search(rf"\bE{letter}\b", line):
            start = i + 1
            break
    if start is None:
        return None
    body = []
    for line in lines[start:]:
        if re.match(r"^#{1,4}\s", line) and re.search(r"\bE[1-5]\b", line):
            if not re.search(rf"\bE{letter}\b", line):
                break
        body.append(line)
    return "\n".join(body).strip()


def resolve_anchor(raw):
    """Resolve a path written against the repo, docs/ or a fixture label."""
    p = Path(raw)
    if p.is_absolute():
        return p if p.exists() else None
    candidates = [ROOT / raw]
    for prefix in ("docs/design", "docs", "selfhost/ct-ast", "selfhost", "test", "lib/std"):
        candidates.append(ROOT / prefix / raw)
    for cand in candidates:
        if cand.exists():
            return cand
    if "/" not in raw:
        hits = list(ROOT.rglob(raw))
        if len(hits) == 1:
            return hits[0]
    return None


def check_anchor(raw, line, strict, where):
    path = resolve_anchor(raw)
    if path is None:
        (err if strict else warn)(f"{where}: anchor file not found: {raw}")
        return
    try:
        total = len(path.read_text(encoding="utf-8", errors="replace").splitlines())
    except OSError as exc:
        err(f"{where}: cannot read anchor {raw}: {exc}")
        return
    if line < 1 or line > total:
        (err if strict else warn)(f"{where}: anchor line out of range: {raw}:{line} (file has {total})")


def check_rounds(bdir):
    rounds = set()
    for path in bdir.iterdir():
        m = ROUND_RE.match(path.name)
        if m:
            n = int(m.group(2))
            rounds.add(n)
            if n > 3:
                err(f"{path.name}: round {n} exceeds the 3-round cap (H-4)")
    for side in ("claim", "counter"):
        have = {int(ROUND_RE.match(p.name).group(2))
                for p in bdir.iterdir() if ROUND_RE.match(p.name) and p.name.startswith(side)}
        for n in sorted(have):
            if n > 2 and (n - 1) not in have:
                warn(f"{side}-r{n}.md exists without {side}-r{n-1}.md")
    return max(rounds) if rounds else 1


def check_side(bdir, side):
    path = bdir / f"{side}.md"
    if not path.exists():
        err(f"{side}.md missing")
        return
    text = read(path)
    found = set()
    for m in re.finditer(r"(?m)^#{1,4}\s*.*?\bE([1-5])\b", text):
        found.add(int(m.group(1)))
    for n in range(1, 6):
        if n not in found:
            err(f"{side}.md: E{n} section missing")
    e1 = section_body(text, "1") or ""
    if not (re.search(r"```", e1) or re.search(r"(?m)^\s*\$ ", e1)):
        err(f"{side}.md: E1 has no command block")
    e2 = section_body(text, "2") or ""
    anchors = ANCHOR_RE.findall(e2)
    if not anchors:
        err(f"{side}.md: E2 has no file:line anchor")
    for n in (3, 4, 5):
        body = section_body(text, str(n)) or ""
        if not body:
            err(f"{side}.md: E{n} section is empty")
    if not re.search(r"不利于", e2):
        warn(f"{side}.md: E2 has no anchor marked 不利于己方")
    for m in ANCHOR_RE.finditer(text):
        check_anchor(m.group(1), int(m.group(2)), False, f"{side}.md")


def check_round_files(bdir):
    for path in sorted(bdir.iterdir()):
        m = ROUND_RE.match(path.name)
        if not m or int(m.group(2)) == 1:
            continue
        text = read(path)
        if not re.search(r"\bE1\b|\bE2\b", text):
            err(f"{path.name}: new round carries neither E1 nor E2")


def check_verify(bdir, verdict_present, strict, rerun):
    path = bdir / "verify.json"
    if not path.exists():
        if verdict_present:
            err("verify.json missing but verdict.md exists (§7.8 T4)")
        else:
            warn("verify.json not written yet (required before verdict)")
        return
    try:
        data = json.loads(read(path))
    except json.JSONDecodeError as exc:
        err(f"verify.json: invalid JSON: {exc}")
        return
    if not isinstance(data.get("environment"), dict) or not data["environment"]:
        err("verify.json: environment is empty")
    ev = data.get("evidence")
    if not isinstance(ev, list) or not ev:
        err("verify.json: evidence list is empty")
    else:
        for item in ev:
            if not isinstance(item, dict):
                err("verify.json: evidence item is not an object")
                continue
            for key in ("id", "command", "output", "exit"):
                if key not in item or item[key] in ("", None):
                    err(f"verify.json: evidence {item.get('id', '?')} missing '{key}'")
            if "reproduced" not in item:
                err(f"verify.json: evidence {item.get('id', '?')} missing 'reproduced'")
            if rerun and item.get("command"):
                _rerun(item)
    anchors = data.get("anchors") or []
    for a in anchors:
        if not isinstance(a, dict) or "file" not in a or "line" not in a:
            err("verify.json: malformed anchor entry")
            continue
        check_anchor(str(a["file"]), int(a["line"]), strict, "verify.json")
    checks = data.get("checks") or []
    if verdict_present and not checks:
        err("verify.json: checks matrix is empty but verdict.md exists")


def _rerun(item):
    cmd = str(item["command"])
    if re.search(r"rm\s+-rf\s+/|git\s+(push|commit)|sudo\b", cmd):
        warn(f"verify.json: evidence {item.get('id', '?')} command not re-run (write/privileged)")
        return
    try:
        proc = subprocess.run(["bash", "-lc", cmd], cwd=ROOT, capture_output=True,
                              text=True, timeout=60)
    except subprocess.TimeoutExpired:
        err(f"verify.json: evidence {item.get('id', '?')} command timed out")
        return
    if proc.returncode != item.get("exit"):
        err(f"verify.json: evidence {item.get('id', '?')} exit {proc.returncode} != recorded {item.get('exit')}")


def main(argv):
    if len(argv) < 2:
        print("usage: check-battle.py <battle-id> [--strict] [--rerun] [--json]", file=sys.stderr)
        return 2
    battle_id = argv[1]
    strict = "--strict" in argv[2:]
    rerun = "--rerun" in argv[2:]
    as_json = "--json" in argv[2:]
    bdir = BATTLES / battle_id
    if not bdir.is_dir():
        print(f"check-battle: no such battle: {bdir}", file=sys.stderr)
        return 1

    question_path = bdir / "question.md"
    if not question_path.exists():
        err("question.md missing")
        data = {}
    else:
        data, qtext = parse_question(question_path)
        for key in ("head", "trigger", "proposer", "opposition", "judge", "forbidden"):
            if not data.get(key):
                err(f"question.md: field '{key}' is empty")
        if data.get("id") and data["id"] != battle_id:
            err(f"question.md: id '{data['id']}' != directory '{battle_id}'")
        proposer = data.get("proposer", "")
        opposition = data.get("opposition", "")
        judge = data.get("judge", "")
        if not opposition or opposition == proposer:
            err(f"H-1: opposition must exist and differ from proposer (both '{proposer}')")
        if judge != "EDITOR":
            err(f"H-2: judge must be EDITOR (got '{judge}')")
        if proposer == "EDITOR":
            err("H-2: proposer must not be EDITOR")
        crit = parse_criteria(qtext)
        if not crit:
            err("question.md: no criteria rows (J-*/ACC-*) - not a battle case (§7.1)")
        for row in crit:
            if len(row) < 3 or any(not c or any(p in c for p in PLACEHOLDERS) for c in row[:3]):
                err(f"question.md: criterion '{row[0]}' has a placeholder or empty cell")

    rounds = check_rounds(bdir)
    check_side(bdir, "claim")
    check_side(bdir, "counter")
    check_round_files(bdir)
    verdict_present = (bdir / "verdict.md").exists()
    check_verify(bdir, verdict_present, strict, rerun)

    if as_json:
        print(json.dumps({"battle": battle_id, "rounds": rounds, "errors": ERR,
                          "warnings": WARN}, ensure_ascii=False, indent=2))
    else:
        print(f"check-battle: {battle_id}")
        print(f"  rounds: {rounds}/3")
        for e in ERR:
            print(f"  FAIL  {e}")
        for w in WARN:
            print(f"  warn  {w}")
        print(f"  {'PASS' if not ERR else 'FAIL'} ({len(ERR)} errors, {len(WARN)} warnings)")
    return 0 if not ERR else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
