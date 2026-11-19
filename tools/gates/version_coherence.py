#!/usr/bin/env python3
"""PN-2 version coherence (G8): every phase tag's MINOR equals its phase
number, and every phase card's `version-minor` equals it too. Published tags
listed in docs/planning/version-legacy-offsets.tsv are a frozen exception; a
mismatch outside that ledger fails.

Usage: version_coherence.py <repo-root>
Exit: 0 coherent, 1 drift, 2 usage.
"""
import glob
import re
import subprocess
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: version_coherence.py <repo-root>", file=sys.stderr)
        return 2
    root = sys.argv[1]
    ledger = {}
    try:
        for line in open(root + "/docs/planning/version-legacy-offsets.tsv",
                         encoding="utf-8", errors="replace"):
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            cols = line.split("\t")
            if len(cols) >= 2:
                ledger[int(cols[0])] = cols[1]
    except FileNotFoundError:
        pass

    fails, warns = [], []
    tags = subprocess.run(["git", "tag", "-l", "v*"], cwd=root,
                          capture_output=True).stdout.decode("utf-8", "replace").split()
    for tag in tags:
        if not re.fullmatch(r"v\d+\.\d+\.\d+", tag):
            continue
        msg = subprocess.run(["git", "tag", "-l", "--format=%(contents:subject)", tag],
                             cwd=root, capture_output=True).stdout.decode("utf-8", "replace")
        m = re.search(r"PH-(\d+) closeout", msg)
        if not m:
            continue
        n = int(m.group(1))
        minor = int(tag.split(".")[1])
        if minor == n:
            continue
        if ledger.get(n) == tag:
            warns.append(f"{tag} PH-{n}: legacy offset MINOR={minor} (ledger)")
        else:
            fails.append(f"{tag} PH-{n}: MINOR={minor} != {n} and not in the legacy ledger")

    for card in sorted(glob.glob(root + "/docs/design/phase[0-9]*.md")):
        mm = re.search(r"phase(\d+)\.md$", card)
        if not mm:
            continue
        n = int(mm.group(1))
        txt = open(card, encoding="utf-8", errors="replace").read()
        vm = re.search(r"^\| version-minor \| (\d+)", txt, re.M)
        if not vm:
            if "状态：完成" in txt:
                fails.append(f"phase{n}: closed card has no version-minor")
            continue
        minor = int(vm.group(1))
        if minor != n and n not in ledger:
            fails.append(f"phase{n}: card version-minor={minor} != {n} (PN-2)")

    for w in warns:
        print("g8: warn: " + w, file=sys.stderr)
    if fails:
        for f in fails:
            print("g8: FAIL: " + f, file=sys.stderr)
        return 1
    print(f"g8: OK (PN-2 version coherence; {len(warns)} legacy offsets)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
