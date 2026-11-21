#!/usr/bin/env python3
"""G7 secret scan (minimal): no credentials in tracked text files.

Usage: secret_scan.py <repo-root> [--dir DIR] [--quiet]
Exit: 0 clean, 1 hits, 2 usage.
"""
import os
import re
import subprocess
import sys

PATTERNS = [
    ("private-key", re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----")),
    ("aws-access-key", re.compile(r"AKIA[0-9A-Z]{16}")),
    ("github-token", re.compile(r"gh[pousr]_[A-Za-z0-9]{30,}")),
    ("slack-token", re.compile(r"xox[baprs]-[A-Za-z0-9-]{10,}")),
    ("openai-key", re.compile(r"sk-[A-Za-z0-9]{20,}")),
    ("google-api-key", re.compile(r"AIza[0-9A-Za-z_-]{35}")),
]
TEXT = (".md", ".txt", ".sh", ".py", ".c", ".h", ".ct", ".yml", ".yaml", ".json", ".toml", ".tpl", ".cfg", ".ini")


def tracked(root):
    try:
        out = subprocess.run(["git", "ls-files", "-z"], cwd=root, capture_output=True, check=True).stdout
        return [os.path.join(root, p.decode("utf-8", "replace")) for p in out.split(b"\0") if p]
    except (OSError, subprocess.CalledProcessError):
        files = []
        for dp, dns, fns in os.walk(root):
            dns[:] = [d for d in dns if d not in (".git", "node_modules", "dist")]
            files.extend(os.path.join(dp, f) for f in fns)
        return files


def main():
    args = sys.argv[1:]
    if not args:
        print("usage: secret_scan.py <repo-root> [--dir DIR] [--quiet]", file=sys.stderr)
        return 2
    root = args[0]
    directory = None
    quiet = False
    i = 1
    while i < len(args):
        if args[i] == "--dir" and i + 1 < len(args):
            directory = args[i + 1]
            i += 2
        elif args[i] == "--quiet":
            quiet = True
            i += 1
        else:
            print("usage: secret_scan.py <repo-root> [--dir DIR] [--quiet]", file=sys.stderr)
            return 2
    files = []
    if directory:
        for dp, _, fns in os.walk(directory):
            files.extend(os.path.join(dp, f) for f in fns)
    else:
        files = tracked(root)
    hits = 0
    for path in files:
        if directory is None and path.endswith((".png", ".jpg", ".gif", ".pdf", ".gz", ".zip", ".o", ".a")):
            continue
        if directory is None and not path.endswith(TEXT):
            continue
        try:
            if os.path.getsize(path) > 2 * 1024 * 1024:
                continue
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        rel = os.path.relpath(path, root)
        for name, pat in PATTERNS:
            for m in pat.finditer(text):
                line = text.count("\n", 0, m.start()) + 1
                print(f"g7: FAIL: {rel}:{line}: {name}", file=sys.stderr)
                hits += 1
    if hits:
        return 1
    if not quiet:
        print(f"g7: OK (secret scan: 0 hits in {len(files)} file(s))")
    return 0


if __name__ == "__main__":
    sys.exit(main())
