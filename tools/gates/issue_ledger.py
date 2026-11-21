#!/usr/bin/env python3
"""G6 issue-ledger closure (AGENTS 5.4, CI-11).

Every `issues/**/*.md` entry must carry a status from the closed set

    open | verified | reopened | rejected | deferred | wontfix | superseded

in either its front-matter `status:` or its `| 状态 |` table row (when both
exist they must agree).  `fixed` is a DEV claim that belongs in the body's
disposal section, never in a status field.  Each entry must name at least one
status source.  `verified` entries must also carry evidence in the body
(commit sha, raw command output, or a test/gate reference with a review), so a
bare "verified" cannot close an issue without a trace.

Usage: issue_ledger.py <repo-root> [--issues DIR] [--quiet]
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


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print("usage: issue_ledger.py <repo-root> [--issues DIR] [--quiet]", file=sys.stderr)
        return 2
    root = args[0]
    issues_dir = os.path.join(root, "issues")
    quiet = False
    i = 1
    while i < len(args):
        if args[i] == "--issues" and i + 1 < len(args):
            issues_dir = args[i + 1]
            i += 2
        elif args[i] == "--quiet":
            quiet = True
            i += 1
        else:
            print("usage: issue_ledger.py <repo-root> [--issues DIR] [--quiet]", file=sys.stderr)
            return 2
    if not os.path.isdir(issues_dir):
        print(f"g6: FAIL: issues directory not found: {issues_dir}", file=sys.stderr)
        return 1

    files = sorted(p for p in glob.glob(os.path.join(issues_dir, "**", "*.md"), recursive=True)
                   if os.path.basename(p) != "README.md")
    fails = []
    counts = {w: 0 for w in CLOSED}
    for path in files:
        rel = os.path.relpath(path, root)
        try:
            text = open(path, encoding="utf-8", errors="replace").read()
        except OSError as exc:
            fails.append(f"{rel}: cannot read ({exc})")
            continue
        fmv, rowv = statuses(text)
        if fmv is None and rowv is None:
            fails.append(f"{rel}: missing status (no front-matter `status:` and no `| 状态 |` row)")
            continue
        for label, value in (("front-matter", fmv), ("row", rowv)):
            if value is None:
                continue
            if value == BANNED:
                fails.append(f"{rel}: `fixed` must not be a status ({label}); write it only in the body disposal section")
            elif value not in CLOSED:
                fails.append(f"{rel}: illegal status {value!r} ({label}); allowed: {' | '.join(CLOSED)}")
        if fmv is not None and rowv is not None and fmv != rowv:
            fails.append(f"{rel}: front-matter status {fmv!r} != table status {rowv!r}")
            continue
        value = fmv if fmv is not None else rowv
        if value in counts:
            counts[value] += 1
        if value == "verified" and not evidence(text):
            fails.append(f"{rel}: `verified` without evidence (need a commit sha, raw output, or test/gate reference)")
        if value == "rejected" and not re.search(r"(理由|不采纳|不受理|裁定|有意限制|D[0-9]+|用户|REQ)", text):
            fails.append(f"{rel}: `rejected` without a reason in the body")
        if value == "superseded" and not re.search(r"(superseded|并入|REQ-|SH-|CI-|取代)", text):
            fails.append(f"{rel}: `superseded` without the replacing id")
        if value == "deferred" and not re.search(r"(deferred|延后|v1\.|v2\.|触发|日期|冻结|1\.0 后)", text):
            fails.append(f"{rel}: `deferred` without a trigger/date")
        if value == "wontfix" and not re.search(r"(理由|不修|永不|裁定)", text):
            fails.append(f"{rel}: `wontfix` without a reason")
        if value == "open":
            body = strip_fences(text)
            if len(body.strip()) < 80:
                fails.append(f"{rel}: `open` without a repro/file:line description")

    if fails:
        for f in fails:
            print("g6: FAIL: " + f, file=sys.stderr)
        print(f"g6: FAIL ({len(fails)} violation(s) across {len(files)} issues)", file=sys.stderr)
        return 1
    if not quiet:
        summary = " ".join(f"{k}={v}" for k, v in counts.items() if v)
        print(f"g6: OK ({len(files)} issues; {summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
