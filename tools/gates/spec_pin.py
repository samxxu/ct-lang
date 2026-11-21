#!/usr/bin/env python3
"""G9 spec anchoring: AGENTS.md's spec pin must match the master spec, or the
in-repo full copy when the master spec is absent (11.5 L-5).

Usage: spec_pin.py <repo-root>
Exit: 0 pinned, 1 drift, 2 usage.
"""
import hashlib
import os
import re
import sys


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    if len(sys.argv) != 2:
        print("usage: spec_pin.py <repo-root>", file=sys.stderr)
        return 2
    root = sys.argv[1]
    agents = os.path.join(root, "AGENTS.md")
    try:
        text = open(agents, encoding="utf-8").read()
    except OSError as exc:
        print(f"g9: FAIL: cannot read AGENTS.md ({exc})", file=sys.stderr)
        return 1
    m = re.search(r"<!-- spec:begin version=([^ ]+) sha256=([0-9a-f]{64}) -->", text)
    if not m:
        print("g9: FAIL: AGENTS.md spec block header missing", file=sys.stderr)
        return 1
    version, pinned = m.group(1), m.group(2)
    master = os.path.expanduser("~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md")
    source = "master spec"
    path = master
    if not os.path.isfile(master):
        path = os.path.join(root, "docs/spec/ai-coding-workflow.md")
        source = "in-repo full copy"
        if not os.path.isfile(path):
            print(f"g9: SKIP (master spec absent and {path} missing)")
            return 0
    actual = sha256(path)
    if actual != pinned:
        print(f"g9: FAIL: AGENTS.md pins {pinned} but {source} is {actual}", file=sys.stderr)
        return 1
    if source == "master spec":
        head = open(path, encoding="utf-8").read(4096)
        hm = re.search(r"\| spec-version \| `?([^`|]+?)`? \|", head)
        if hm and hm.group(1).strip() != version:
            print(f"g9: FAIL: AGENTS.md pins {version} but master spec declares {hm.group(1).strip()}", file=sys.stderr)
            return 1
    print(f"g9: OK (spec {version}, sha256 {pinned[:12]}…, {source})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
