#!/usr/bin/env python3
"""G6 issue-ledger closure (AGENTS 5.4, CI-11, CI-13).

Every `issues/**/*.md` entry must carry a status from the closed set

    open | verified | reopened | rejected | deferred | wontfix | superseded

in either its front-matter `status:` or its `| 状态 |` table row (when both
exist they must agree).  `fixed` is a DEV claim that belongs in the body's
disposal section, never in a status field.  Each entry must name at least one
status source.  `verified` entries must also carry evidence in the body
(commit sha, raw command output, or a test/gate reference with a review), so a
bare "verified" cannot close an issue without a trace.

Strict mode (the default) judges the whole ledger and is what `tools/check.sh
g6` runs.  CI-13's ratchet is opt-in:

    --ratchet         judge against issues/.g6-baseline.tsv: a violation that
                      matches a baseline row is "known" and reported, any
                      other violation is new debt and fails; a baseline row
                      with no matching violation is a zombie (the issue was
                      normalized, renamed or deleted) and fails.
    --write-baseline  rewrite the baseline from the current ledger.  This is
                      the only way to add or remove rows; never edit the TSV
                      by hand.  The baseline must carry a `# tracking:` issue
                      with a `退出条件` section (CI-14 today).

Baseline format (tab separated, `#` comments):

    # g6-baseline v1
    # tracking: CI-14
    path<TAB>现状<TAB>归一键<TAB>类别

Usage: issue_ledger.py <repo-root> [--issues DIR] [--quiet]
                       [--ratchet] [--write-baseline]
                       [--baseline FILE] [--tracking ID]
Exit: 0 closed, 1 violations, 2 usage.
"""
import os
import re
import sys
import glob

CLOSED = ("open", "verified", "reopened", "rejected", "deferred", "wontfix", "superseded")
BANNED = "fixed"
SHA_RE = re.compile(r"(?<![0-9a-zA-Z])[0-9a-f]{7,40}(?![0-9a-zA-Z])")
OUTPUT_RE = re.compile(r"(\$ |\bok\b|\bOK\b|PASS|FAIL|green|全绿|通过|exit=0|\d+ ok)")
TEST_RE = re.compile(r"(test/[A-Za-z0-9_./-]+|check-[A-Za-z0-9_./-]+)")
REVIEW_RE = re.compile(r"(复核|验证|复测)")

BASELINE_HEADER = "# g6-baseline v1"
BASELINE_COLUMNS = "path\t现状\t归一键\t类别"


def strip_fences(text):
    out, in_fence = [], False
    for line in text.splitlines():
        if line.lstrip().startswith("```"):
            in_fence = not in_fence
            out.append("")
            continue
        out.append("" if in_fence else line)
    return "\n".join(out)


def evidence(text):
    body = strip_fences(text)
    if SHA_RE.search(body):
        return "sha"
    for m in re.finditer(r"```[^\n]*\n(.*?)```", body, re.S):
        if OUTPUT_RE.search(m.group(1)):
            return "output"
    if TEST_RE.search(body) and re.search(r"(复核|验证|复测|通过|全绿|断言|assert|回归)", body):
        return "test"
    if REVIEW_RE.search(body) and re.search(r"(通过|全绿|无误|一致|0 失败|0 failed)", body):
        return "review"
    return ""


def statuses(text):
    """Return (front_matter_status|None, table_status|None)."""
    plain = strip_fences(text)
    fm = re.search(r"^status:\s*(.*)$", plain, re.M)
    fmv = fm.group(1).strip().strip("\"'") if fm else None
    row = re.search(r"^\|\s*(\*\*)?状态(\*\*)?\s*\|(.*)$", plain, re.M)
    rowv = None
    if row:
        rowv = row.group(3).strip().rstrip("|").strip()
        rowv = re.sub(r"^\*\*|\*\*$", "", rowv).strip()
    return fmv, rowv


def normalize_status(value):
    """Map a legacy status spelling to the AGENTS 5.4 closed set (CI-13 §1)."""
    core = (value or "").strip().strip("*").strip().lower()
    if core in CLOSED:
        return core
    if re.search(r"已修|修复|完成|fixed", core):
        return "verified"
    if re.search(r"不采纳|rejected|已关闭（不采纳）", core):
        return "rejected"
    if re.search(r"wontfix|永不修", core):
        return "wontfix"
    if re.search(r"superseded|被取代|取代", core):
        return "superseded"
    if re.search(r"deferred|延后", core):
        return "deferred"
    if re.search(r"reopened|复开", core):
        return "reopened"
    # Everything else is in-progress: CI-13 §1 says "无法归一先归 open".
    return "open"


def category_of(value):
    normalized = normalize_status(value)
    if normalized in ("open", "reopened"):
        return "在办类"
    if normalized == "deferred":
        return "延后类"
    return "核销类"


def violation(path, token, normalized, detail):
    return {
        "path": path,
        "token": token,
        "normalized": normalized,
        "category": category_of(normalized),
        "detail": detail,
    }


def collect(root, issues_dir):
    """Return (files, violations) for the whole ledger in strict mode."""
    files = sorted(p for p in glob.glob(os.path.join(issues_dir, "**", "*.md"), recursive=True)
                   if os.path.basename(p) != "README.md")
    violations = []
    for path in files:
        rel = os.path.relpath(path, root)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError as exc:
            violations.append(violation(rel, "unreadable", "open", f"cannot read ({exc})"))
            continue
        fmv, rowv = statuses(text)
        if fmv is None and rowv is None:
            violations.append(violation(
                rel, "missing-status", "open",
                "missing status (no front-matter `status:` and no `| 状态 |` row)"))
            continue
        bad = False
        for label, value in (("front-matter", fmv), ("row", rowv)):
            if value is None:
                continue
            if value == BANNED:
                violations.append(violation(
                    rel, "fixed-status", "verified",
                    f"`fixed` must not be a status ({label}); write it only in the body disposal section"))
                bad = True
            elif value not in CLOSED:
                normalized = normalize_status(value)
                violations.append(violation(
                    rel, "illegal-status:" + value, normalized,
                    f"illegal status {value!r} ({label}); allowed: {' | '.join(CLOSED)}; "
                    f"normalize to {normalized!r} (CI-13 §1)"))
                bad = True
        if fmv is not None and rowv is not None and fmv != rowv:
            violations.append(violation(
                rel, "status-mismatch", normalize_status(fmv),
                f"front-matter status {fmv!r} != table status {rowv!r}"))
            continue
        value = fmv if fmv is not None else rowv
        if bad:
            continue
        if value == "verified" and not evidence(text):
            violations.append(violation(
                rel, "verified-no-evidence", "verified",
                "`verified` without evidence (need a commit sha, raw output, or test/gate reference)"))
        if value == "rejected" and not re.search(r"(理由|不采纳|不受理|裁定|有意限制|D[0-9]+|用户|REQ)", text):
            violations.append(violation(
                rel, "rejected-no-reason", "rejected",
                "`rejected` without a reason in the body"))
        if value == "superseded" and not re.search(r"(superseded|并入|REQ-|SH-|CI-|取代)", text):
            violations.append(violation(
                rel, "superseded-no-id", "superseded",
                "`superseded` without the replacing id"))
        if value == "deferred" and not re.search(r"(deferred|延后|v1\.|v2\.|触发|日期|冻结|1\.0 后)", text):
            violations.append(violation(
                rel, "deferred-no-trigger", "deferred",
                "`deferred` without a trigger/date"))
        if value == "wontfix" and not re.search(r"(理由|不修|永不|裁定)", text):
            violations.append(violation(
                rel, "wontfix-no-reason", "wontfix",
                "`wontfix` without a reason"))
        if value == "open":
            body = strip_fences(text)
            if len(body.strip()) < 80:
                violations.append(violation(
                    rel, "open-thin-body", "open",
                    "`open` without a repro/file:line description"))
    return files, violations


def read_baseline(path):
    """Return (meta, rows, errors). rows are dicts with path/token/normalized/category."""
    meta, rows, errors = {}, [], []
    if not os.path.exists(path):
        return meta, rows, errors
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        return meta, rows, [f"cannot read baseline ({exc})"]
    seen_header = False
    for lineno, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        if line.startswith("#"):
            m = re.match(r"#\s*([A-Za-z_-]+)\s*:\s*(.*)$", line)
            if m:
                meta[m.group(1).lower()] = m.group(2).strip()
            continue
        if line.startswith("path\t"):
            seen_header = True
            continue
        cells = line.split("\t")
        if len(cells) != 4:
            errors.append(f"{path}:{lineno}: baseline row must have 4 tab-separated columns "
                          f"(path/现状/归一键/类别), got {len(cells)}")
            continue
        rel, token, normalized, category = (c.strip() for c in cells)
        if not rel or not token:
            errors.append(f"{path}:{lineno}: baseline row has an empty path or violation key")
            continue
        rows.append({"path": rel, "token": token, "normalized": normalized,
                     "category": category, "line": lineno})
    if rows and not seen_header:
        errors.append(f"{path}: baseline is missing the `{BASELINE_COLUMNS}` column header")
    return meta, rows, errors


def find_issue(root, issues_dir, ident):
    """Locate the tracking issue by front-matter id or filename prefix."""
    want = ident.strip().lower()
    for path in glob.glob(os.path.join(issues_dir, "**", "*.md"), recursive=True):
        if os.path.basename(path) == "README.md":
            continue
        stem = os.path.basename(path).lower()
        if stem.startswith(want + "-") or stem.startswith(want + "."):
            return path
        try:
            head = open(path, encoding="utf-8", errors="replace").read(4096)
        except OSError:
            continue
        m = re.search(r"^id:\s*(.*)$", head, re.M)
        if m and m.group(1).strip().strip("\"'").lower() == want:
            return path
    return None


def check_tracking(root, issues_dir, meta):
    """A baseline is an exemption, so it must hang on a live tracking issue with
    exit conditions (CI-13 §2).  Returns a list of failures."""
    ident = meta.get("tracking", "").strip()
    if not ident:
        return ["baseline has no `# tracking: <issue-id>` line "
                "(CI-13 §2: a whitelist must hang on a tracking issue)"]
    path = find_issue(root, issues_dir, ident)
    if path is None:
        return [f"baseline tracking issue {ident!r} not found under issues/"]
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError as exc:
        return [f"cannot read tracking issue {ident!r}: {exc}"]
    errors = []
    if "退出条件" not in text:
        errors.append(f"baseline tracking issue {ident!r} has no `退出条件` section")
    if "g6" not in text:
        errors.append(f"baseline tracking issue {ident!r} does not mention the g6 gate")
    return errors


def baseline_key(v):
    """The baseline's `现状` column records the raw status spelling."""
    token = v["token"]
    prefix = "illegal-status:"
    return token[len(prefix):] if token.startswith(prefix) else token


def write_baseline(path, violations, meta):
    lines = [BASELINE_HEADER,
             "# tracking: " + meta["tracking"],
             "# owner: " + meta.get("owner", "REV"),
             "# exit: " + meta.get("exit", "基线清空、g6 严格模式绿、遗留项各有去向"),
             BASELINE_COLUMNS]
    for v in violations:
        lines.append("\t".join((v["path"], baseline_key(v), v["normalized"], v["category"])))
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as out:
        out.write("\n".join(lines) + "\n")


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print("usage: issue_ledger.py <repo-root> [--issues DIR] [--quiet] "
              "[--ratchet] [--write-baseline] [--baseline FILE] [--tracking ID]",
              file=sys.stderr)
        return 2
    root = args[0]
    issues_dir = os.path.join(root, "issues")
    quiet = False
    ratchet = False
    write = False
    baseline_path = None
    tracking = "CI-14"
    i = 1
    while i < len(args):
        if args[i] == "--issues" and i + 1 < len(args):
            issues_dir = args[i + 1]
            i += 2
        elif args[i] == "--quiet":
            quiet = True
            i += 1
        elif args[i] == "--ratchet":
            ratchet = True
            i += 1
        elif args[i] == "--write-baseline":
            write = True
            i += 1
        elif args[i] == "--baseline" and i + 1 < len(args):
            baseline_path = args[i + 1]
            i += 2
        elif args[i] == "--tracking" and i + 1 < len(args):
            tracking = args[i + 1]
            i += 2
        else:
            print("usage: issue_ledger.py <repo-root> [--issues DIR] [--quiet] "
                  "[--ratchet] [--write-baseline] [--baseline FILE] [--tracking ID]",
                  file=sys.stderr)
            return 2
    if not os.path.isdir(issues_dir):
        print(f"g6: FAIL: issues directory not found: {issues_dir}", file=sys.stderr)
        return 1
    if baseline_path is None:
        baseline_path = os.path.join(issues_dir, ".g6-baseline.tsv")

    files, violations = collect(root, issues_dir)

    if write:
        meta = {"tracking": tracking}
        errors = check_tracking(root, issues_dir, meta)
        # A brand-new baseline may point at a tracking issue whose file is not
        # there yet only when the ledger is clean; CI-14 exists today, so keep
        # the check strict in both directions.
        if errors:
            for e in errors:
                print("g6: FAIL: " + e, file=sys.stderr)
            print("g6: FAIL (baseline not written)", file=sys.stderr)
            return 1
        write_baseline(baseline_path, violations, meta)
        if not quiet:
            print(f"g6: baseline written ({len(violations)} row(s), tracking {tracking})")
        return 0

    if not ratchet:
        if violations:
            for v in violations:
                print(f"g6: FAIL: {v['path']}: {v['detail']}", file=sys.stderr)
            print(f"g6: FAIL ({len(violations)} violation(s) across {len(files)} issues)",
                  file=sys.stderr)
            return 1
        if not quiet:
            counts = {w: 0 for w in CLOSED}
            for path in files:
                text = open(path, encoding="utf-8", errors="replace").read()
                fmv, rowv = statuses(text)
                value = fmv if fmv is not None else rowv
                if value in counts:
                    counts[value] += 1
            summary = " ".join(f"{k}={v}" for k, v in counts.items() if v)
            print(f"g6: OK ({len(files)} issues; {summary})")
        return 0

    # ---- ratchet mode -------------------------------------------------
    meta, known_rows, errors = read_baseline(baseline_path)
    if not os.path.exists(baseline_path):
        # No baseline is exactly strict mode; the point of --ratchet is to be
        # usable before and after the whitelist is deleted (CI-14 exit 1).
        if violations:
            for v in violations:
                print(f"g6: FAIL: {v['path']}: {v['detail']}", file=sys.stderr)
            print(f"g6: FAIL ({len(violations)} violation(s) across {len(files)} issues; "
                  "no baseline -> strict)", file=sys.stderr)
            return 1
        if not quiet:
            print(f"g6: OK ({len(files)} issues; ratchet: no baseline -> strict; "
                  "known=0 new=0")
        return 0
    errors.extend(check_tracking(root, issues_dir, meta))
    if errors:
        for e in errors:
            print("g6: FAIL: " + e, file=sys.stderr)
        print("g6: FAIL (baseline is not usable)", file=sys.stderr)
        return 1

    known_map = {(r["path"], r["token"]): r for r in known_rows}
    new, known = [], 0
    for v in violations:
        key = (v["path"], baseline_key(v))
        if key in known_map:
            known += 1
            known_map.pop(key)
        else:
            new.append(v)
    zombie = list(known_map.values())

    for v in new:
        print(f"g6: FAIL: {v['path']}: new debt not in the baseline: {v['detail']}",
              file=sys.stderr)
    for r in zombie:
        print(f"g6: FAIL: {r['path']}: zombie baseline row {r['token']!r} "
              "(fixed, renamed or deleted -> run --write-baseline and drop the row)",
              file=sys.stderr)
    if new or zombie:
        print(f"g6: FAIL (ratchet: {len(new)} new violation(s), {len(zombie)} zombie "
              f"baseline row(s); known={known}, baseline={len(known_rows)})", file=sys.stderr)
        return 1
    if not quiet:
        print(f"g6: OK ({len(files)} issues; ratchet: known={known} new=0 "
              f"zombie=0 baseline={len(known_rows)})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
