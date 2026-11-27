#!/usr/bin/env python3
"""check-feature-matrix.py - S8c matrix consistency assertion.

The language-feature matrix (docs/planning/feature-examples-matrix.md) is the
single index of "feature -> example -> test -> doc -> status".  This gate keeps
it from rotting: every row must name an existing example and test, a non-empty
doc cell and a status of `有` / `薄` (a `缺` / `待实现` cell is a missing row).

Usage:
    python3 tools/check-feature-matrix.py [--warn|--strict] [--selftest] [--root DIR]

Default is `--warn`: findings are printed but the exit code is 0, so S8c can
land while the matrix catches up.  `--strict` turns findings into exit 1; use it
at phase closeout.  `--selftest` runs the positive/negative fixtures.

The check is std-lib only, like the other gates under tools/.
"""

import argparse
import os
import re
import sys

MATRIX = "docs/planning/feature-examples-matrix.md"
SECTION = "## 1 矩阵"
LINK = re.compile(r"\[[^\]]*\]\(([^)]+)\)")
STATUSES = {"有", "薄"}
MISSING = ("缺", "待实现", "missing", "MISSING")
NEW_FEATURES = ("S2", "S3", "S4", "S5", "S6")


def split_cells(line):
    """Split a Markdown table row on unescaped pipes, keeping link pipes."""
    cells = []
    buf = []
    depth = 0
    for ch in line.strip():
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth = max(0, depth - 1)
        if ch == "|" and depth == 0:
            cells.append("".join(buf).strip())
            buf = []
        else:
            buf.append(ch)
    cells.append("".join(buf).strip())
    # A row starts and ends with '|'; the edge cells are empty.
    if cells and cells[0] == "":
        cells = cells[1:]
    if cells and cells[-1] == "":
        cells = cells[:-1]
    return cells


def matrix_rows(text):
    lines = text.splitlines()
    try:
        start = lines.index(SECTION)
    except ValueError:
        return None, "matrix section '%s' not found" % SECTION
    rows = []
    for lineno, line in enumerate(lines[start + 1 :], start + 2):
        if line.startswith("## "):
            break
        if not line.startswith("|"):
            continue
        cells = split_cells(line)
        if not cells or cells[0] in ("", "---", "#"):
            continue
        if cells[0] == "#" or set(cells[0]) <= {"-", ":"}:
            continue
        rows.append((lineno, cells))
    return rows, None


def link_targets(cell):
    return [m.group(1).split("#", 1)[0] for m in LINK.finditer(cell)]


def check_matrix(text, root):
    errors = []
    rows, err = matrix_rows(text)
    if err:
        return [err]
    if not rows:
        return ["matrix has no feature rows"]

    seen = set()
    new_feature_examples = {key: 0 for key in NEW_FEATURES}
    for lineno, cells in rows:
        where = "line %d" % lineno
        if len(cells) != 6:
            errors.append("%s: expected 6 columns (feature/example/test/doc/status), got %d"
                          % (where, len(cells)))
            continue
        num, feature, example, test, doc, status = cells
        if not feature:
            errors.append("%s: empty feature cell" % where)
        if not example or "[" not in example:
            errors.append("%s: feature '%s' has no example link" % (where, feature))
        if not test or "[" not in test:
            errors.append("%s: feature '%s' has no test link" % (where, feature))
        if not doc:
            errors.append("%s: feature '%s' has an empty doc cell" % (where, feature))
        if status not in STATUSES:
            errors.append("%s: feature '%s' status '%s' is not one of %s"
                          % (where, feature, status, "/".join(sorted(STATUSES))))
        for cell_name, cell in (("example", example), ("test", test)):
            for target in link_targets(cell):
                path = os.path.normpath(os.path.join(root, "docs", "planning", target))
                if not os.path.exists(path):
                    errors.append("%s: feature '%s' %s path does not exist: %s"
                                  % (where, feature, cell_name, target))
                elif cell_name == "example" and os.path.isdir(path):
                    has_ct = False
                    for dirpath, _dirnames, filenames in os.walk(path):
                        if any(name.endswith(".ct") for name in filenames):
                            has_ct = True
                            break
                    if not has_ct:
                        errors.append("%s: feature '%s' example dir has no .ct: %s"
                                      % (where, feature, target))
        for cell in cells:
            for token in MISSING:
                if token in cell:
                    errors.append("%s: feature '%s' still says '%s'"
                                  % (where, feature, token))
        seen.add(num)
        for key in NEW_FEATURES:
            if ("（%s" % key) in feature or ("%s）" % key) in feature:
                new_feature_examples[key] += 1
    for key, count in new_feature_examples.items():
        if count == 0:
            errors.append("new feature %s has no example row" % key)
    return errors


def selftest():
    """DOC-style positive/negative fixtures; no filesystem writes."""
    good = (
        "## 1 矩阵\n\n"
        "| # | 特性 | example | test | doc | 状态 |\n"
        "| --- | --- | --- | --- | --- | --- |\n"
        "| 1 | 泛型 ADT（S6） | [e](examples/e) | [t](test/ast/t) | spec §4.73 | 薄 |\n"
        "| 2 | 字面量（S4） | [e](examples/e) | [t](test/ast/t) | spec §4.73 | 薄 |\n"
        "| 3 | or（S5） | [e](examples/e) | [t](test/ast/t) | spec §4.73 | 薄 |\n"
        "| 4 | 下标（S2） | [e](examples/e) | [t](test/ast/t) | spec §4.64 | 薄 |\n"
        "| 5 | 函子（S3） | [e](examples/e) | [t](test/ast/t) | spec §4.77 | 薄 |\n"
    )
    missing = good.replace("| 1 | 泛型 ADT（S6） | [e](examples/e)",
                           "| 1 | 泛型 ADT（S6） |")
    bad_status = good.replace("| 薄 |\n| 2", "| 缺 |\n| 2")
    bad_path = good.replace("[e](examples/e)", "[e](examples/nope)")
    cases = [
        ("good", good, 0),
        ("missing-example", missing, 1),
        ("missing-status", bad_status, 1),
        ("dead-path", bad_path, 1),
    ]
    failed = 0
    for name, text, want in cases:
        errors = check_matrix(text, os.getcwd())
        # The fixture links do not exist on disk; shape cases ignore those
        # findings, the dead-path case is exactly about one of them.
        shape_only = [e for e in errors if "does not exist" not in e
                      and "no .ct" not in e]
        if name == "dead-path":
            got = 1 if any("examples/nope" in e for e in errors) else 0
        else:
            got = 1 if shape_only else 0
        if got != want:
            failed += 1
            print("matrix selftest: FAIL %s (want %d, got %d)" % (name, want, got))
            for err in shape_only:
                print("  " + err)
        else:
            print("matrix selftest: ok %s" % name)
    if failed:
        print("matrix selftest: FAIL (%d case(s))" % failed)
        return 1
    print("matrix selftest: OK (%d cases)" % len(cases))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--warn", action="store_true", help="findings exit 0 (default)")
    mode.add_argument("--strict", action="store_true", help="findings exit 1")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    path = os.path.join(args.root, MATRIX)
    if not os.path.isfile(path):
        print("matrix: FAIL: %s missing" % MATRIX, file=sys.stderr)
        return 1
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    errors = check_matrix(text, args.root)
    if not errors:
        print("matrix: OK (every feature row has example/test/doc/status)")
        return 0
    for err in errors:
        print("matrix: %s" % err, file=sys.stderr)
    if args.strict:
        print("matrix: FAIL (%d finding(s), strict)" % len(errors), file=sys.stderr)
        return 1
    print("matrix: warn (%d finding(s); pass --strict at closeout)" % len(errors),
          file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
