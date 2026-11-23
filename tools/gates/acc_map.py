#!/usr/bin/env python3
"""G2 design-acceptable: every interface/protocol promise maps to an ACC-* row.

CI-16 replaces the old `g2` SKIP with a mechanical check.  The scope is
explicit: `docs/design/acc-scope.tsv` lists the design documents that carry
interface/protocol promises, the promise family, and the minimum number of
ACC rows that document must own.  A document joins the scope by its row and
carries the marker `<!-- g2:interface -->`; both directions are checked so a
document cannot silently gain a marker without being registered.

Each scoped document carries a `## ACC 映射` section with a four-column table:

    | ACC-id | 承诺 | 章节 | 判据/证据 |

- `ACC-<n>` is globally unique (at least two digits);
- 承诺 non-empty;
- 章节 names the section/anchor the promise comes from;
- 判据/证据 names a test, gate, source file or spec section that can be
  re-run or read.

Usage: acc_map.py <repo-root> [--scope FILE] [--quiet]
Exit: 0 mapped, 1 violations, 2 usage.
"""
import os
import re
import sys

MARKER = "<!-- g2:interface -->"
SECTION = "## ACC 映射"
ID_RE = re.compile(r"^ACC-(\d{2,})$")
EVIDENCE_RE = re.compile(
    r"(test/|tools/|selfhost/|docs/|examples/|battle/|\bcheck[_-]|§[0-9]|\.sh\b|:[0-9]+)")


def read(path):
    return open(path, encoding="utf-8", errors="replace").read()


def parse_scope(path):
    rows, errors = [], []
    if not os.path.exists(path):
        return rows, [f"{path}: missing (CI-16 scope registry)"]
    for lineno, line in enumerate(read(path).splitlines(), 1):
        if not line.strip() or line.startswith("#"):
            continue
        if line.startswith("doc\t"):
            continue
        cells = [c.strip() for c in line.split("\t")]
        if len(cells) != 3:
            errors.append(f"{path}:{lineno}: scope row must be doc<TAB>protocol<TAB>min, "
                          f"got {len(cells)} column(s)")
            continue
        doc, protocol, minimum = cells
        if not doc or not protocol:
            errors.append(f"{path}:{lineno}: scope row has an empty doc or protocol")
            continue
        try:
            minimum = int(minimum)
        except ValueError:
            errors.append(f"{path}:{lineno}: min ACC count {minimum!r} is not an integer")
            continue
        rows.append({"doc": doc, "protocol": protocol, "min": minimum, "line": lineno})
    if not rows and not errors:
        errors.append(f"{path}: scope registry is empty")
    return rows, errors


def mapping_rows(text):
    """Return (rows, error) for the `## ACC 映射` section, or (None, None)."""
    lines = text.splitlines()
    start = None
    for i, line in enumerate(lines):
        if line.strip() == SECTION:
            start = i + 1
            break
    if start is None:
        return None, None
    end = len(lines)
    for j in range(start, len(lines)):
        if re.match(r"^##\s", lines[j]):
            end = j
            break
    rows, errors = [], []
    for lineno in range(start, end):
        line = lines[lineno].strip()
        if not line.startswith("|"):
            continue
        cells = [c.strip() for c in line.strip("|").split("|")]
        if all(set(c) <= set("-: ") for c in cells):
            continue
        if cells and cells[0] == "ACC-id":
            continue
        rows.append((lineno + 1, cells))
    return rows, errors


def check_doc(root, doc, minimum):
    path = os.path.join(root, "docs/design", doc)
    errors = []
    if not os.path.exists(path):
        return [f"docs/design/{doc}: scope doc is missing"], []
    text = read(path)
    if MARKER not in text:
        errors.append(f"docs/design/{doc}: scope doc is missing the `{MARKER}` marker")
    rows, _ = mapping_rows(text)
    if rows is None:
        errors.append(f"docs/design/{doc}: scope doc has no `{SECTION}` section")
        return errors, []
    if len(rows) < minimum:
        errors.append(f"docs/design/{doc}: `{SECTION}` has {len(rows)} ACC row(s), "
                      f"scope requires at least {minimum}")
    for lineno, cells in rows:
        if len(cells) < 4:
            errors.append(f"docs/design/{doc}:{lineno}: ACC row needs 4 columns "
                          "(ACC-id / 承诺 / 章节 / 判据证据), got "
                          f"{len(cells)}: {' | '.join(cells)}")
            continue
        acc, promise, section, witness = cells[0], cells[1], cells[2], cells[3]
        if not ID_RE.match(acc):
            errors.append(f"docs/design/{doc}:{lineno}: bad ACC id {acc!r} "
                          "(expected ACC-<two or more digits>)")
        if not promise:
            errors.append(f"docs/design/{doc}:{lineno}: ACC {acc} has no 承诺")
        if not section:
            errors.append(f"docs/design/{doc}:{lineno}: ACC {acc} has no 章节")
        if not witness or not EVIDENCE_RE.search(witness):
            errors.append(f"docs/design/{doc}:{lineno}: ACC {acc} has no runnable/readable "
                          "判据证据 (test/gate path, source file or §spec)")
    return errors, rows


def main():
    args = sys.argv[1:]
    if not args or args[0].startswith("-"):
        print("usage: acc_map.py <repo-root> [--scope FILE] [--quiet]", file=sys.stderr)
        return 2
    root = args[0]
    scope = os.path.join(root, "docs/design/acc-scope.tsv")
    quiet = False
    i = 1
    while i < len(args):
        if args[i] == "--scope" and i + 1 < len(args):
            scope = args[i + 1]
            i += 2
        elif args[i] == "--quiet":
            quiet = True
            i += 1
        else:
            print("usage: acc_map.py <repo-root> [--scope FILE] [--quiet]", file=sys.stderr)
            return 2

    rows, errors = parse_scope(scope)
    scope_docs = set()
    seen_ids = {}
    total_rows = 0
    for row in rows:
        if row["doc"] in scope_docs:
            errors.append(f"docs/design/acc-scope.tsv:{row['line']}: duplicate scope row "
                          f"for {row['doc']}")
            continue
        scope_docs.add(row["doc"])
        doc_errors, doc_rows = check_doc(root, row["doc"], row["min"])
        errors.extend(doc_errors)
        for lineno, cells in doc_rows or []:
            if not cells:
                continue
            acc = cells[0]
            if acc in seen_ids:
                errors.append(f"docs/design/{row['doc']}:{lineno}: duplicate ACC id {acc} "
                              f"(first at {seen_ids[acc]})")
            else:
                seen_ids[acc] = f"docs/design/{row['doc']}:{lineno}"
            total_rows += 1

    # A marker without a scope row is an unregistered interface document.
    for name in sorted(os.listdir(os.path.join(root, "docs/design"))):
        if not name.endswith(".md"):
            continue
        path = os.path.join(root, "docs/design", name)
        if not os.path.isfile(path):
            continue
        text = read(path)
        if MARKER in text and name not in scope_docs:
            errors.append(f"docs/design/{name}: has `{MARKER}` but is not in "
                          "docs/design/acc-scope.tsv")
        if SECTION in text and MARKER not in text:
            errors.append(f"docs/design/{name}: has `{SECTION}` but no `{MARKER}` marker")

    if errors:
        for e in errors:
            print("g2: FAIL: " + e, file=sys.stderr)
        print(f"g2: FAIL ({len(errors)} violation(s))", file=sys.stderr)
        return 1
    if not quiet:
        print(f"g2: OK ({len(scope_docs)} interface doc(s), {total_rows} ACC row(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
