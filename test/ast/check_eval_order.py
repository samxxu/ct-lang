#!/usr/bin/env python3
"""Flag fixtures that depend on C's unspecified argument evaluation order.

test/ast/241_map_str_key used to print `printf("remove=%d len=%d\\n",
m.remove(b), m.len())`: GCC/x86-64 evaluates right to left, Apple clang/arm64
left to right, so the same program printed `len=2` on CI and `len=1` locally
(TEST-19). The rule below is deliberately narrow -- a mutating call and a call
that reads the same container in one argument list -- so it has no false
positives on the corpus and stays useful as a gate.

Usage:
    python3 test/ast/check_eval_order.py            # scan the tree
    python3 test/ast/check_eval_order.py --self-test
"""
import glob
import re
import sys

MUTATING = re.compile(
    r"\.(remove|put|clear|release|at|insert|push|append|set|drop)\s*\(")
READING = re.compile(r"\.(len|get|has|entry|count|size)\s*\(")
PRINT = re.compile(r"\b(printf|fprintf|sprintf|snprintf)\s*\(")

SCAN = (
    glob.glob("test/**/*.ct", recursive=True)
    + glob.glob("examples/**/*.ct", recursive=True)
    + glob.glob("lib/core/*.ct")
)


def offences(text):
    """Return the 1-based line numbers of order-dependent print calls."""
    hits = []
    for i, line in enumerate(text.splitlines(), 1):
        if not PRINT.search(line):
            continue
        if MUTATING.search(line) and READING.search(line):
            hits.append(i)
    return hits


def scan(paths):
    bad = []
    for path in paths:
        try:
            with open(path, encoding="utf-8", errors="replace") as f:
                text = f.read()
        except OSError as e:
            print(f"cannot read {path}: {e}", file=sys.stderr)
            continue
        for line in offences(text):
            bad.append(f"{path}:{line}")
    return bad


def self_test():
    dirty = 'printf("remove=%d len=%d\\n", m.remove(b), m.len());\n'
    clean = (
        'int removed = m.remove(b);\n'
        'printf("remove=%d len=%d\\n", removed, m.len());\n'
        'printf("len=%d\\n", m.len());\n'
        'printf("v=%d\\n", m.put(a, 1));\n'
    )
    ok = True
    if not offences(dirty):
        print("self-test: the order-dependent line was not reported", file=sys.stderr)
        ok = False
    if offences(clean):
        print("self-test: a clean line was reported", file=sys.stderr)
        ok = False
    return 0 if ok else 1


def main(argv):
    if "--self-test" in argv:
        return self_test()
    bad = scan(SCAN)
    for b in bad:
        print(b)
    if bad:
        print(
            "error: these print calls mix a mutating call with a read of the same "
            "container; split them into statements (C argument order is unspecified)",
            file=sys.stderr,
        )
        return 1
    print(f"eval-order: {len(SCAN)} sources, 0 order-dependent print calls")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
