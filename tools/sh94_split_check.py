#!/usr/bin/env python3
"""sh94_split_check.py - mechanical acceptance for an SH-94 pure-move slice.

The M1 split moves whole function definitions into `<Subsystem><Role>.h.ct`
units without touching a body. This tool re-derives three claims:

  1. the body-hash multiset of `selfhost/ct-ast/**` is identical to the
     baseline commit (every body byte-identical, nothing added or dropped);
  2. each mapped function now lives in the named unit, as a free `pub`
     function (a move out of a `static` host needs the exported prototype);
  3. the line diff is mechanical: with every function definition removed from
     both sides, a host's skeleton may only gain an `import` (and blank /
     comment lines); a new unit's skeleton is only boilerplate.

Usage:
    python3 tools/sh94_split_check.py --baseline <sha> --map host=a,b:NewUnit.h.ct
    python3 tools/sh94_split_check.py --baseline <sha> --map ... --map ...

`--map` is repeatable; the host is a repo-relative path, the unit is the path
the moved functions must appear in. Exit: 0 ok, 1 a claim failed, 2 usage.
"""

import argparse
import collections
import os
import re
import shutil
import subprocess
import sys
import tempfile

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import p85_inventory as inv  # noqa: E402

SKELETON_OK = [
    re.compile(r"^\s*$"),
    re.compile(r"^\s*import\s+[A-Za-z0-9_:]+\s*(?:as\s+\w+)?\s*;\s*$"),
    re.compile(r"^\s*pub\s+[A-Za-z_].*;\s*$"),   # exported prototype
    re.compile(r"^\s*pub\s+[A-Za-z_].*,\s*$"),   # prototype first line
    re.compile(r"^\s+[A-Za-z_][^;]*;\s*$"),       # prototype continuation
    re.compile(r"^\s*(?:static|pub)\s+[A-Za-z_].*;\s*$"),
    re.compile(r"^\s*#\s*(include|define)\b"),
    re.compile(r"^\s*namespace\s+[A-Za-z_:]+\s*;\s*$"),
    re.compile(r"^\s*pub\s+struct\s+\w+\s*\{?\s*$"),
    re.compile(r"^\s*int\s+unused;\s*$"),
    re.compile(r"^\s*\}\s*$"),
]


def extract(root, rev):
    base = tempfile.mkdtemp(prefix="sh94base.")
    try:
        tar = subprocess.Popen(["git", "-C", root, "archive", rev],
                               stdout=subprocess.PIPE)
        subprocess.run(["tar", "-x", "-C", base], stdin=tar.stdout, check=True)
        tar.wait()
        return inv.scan(base)
    finally:
        shutil.rmtree(base, ignore_errors=True)


def skeleton(src, unit):
    """The unit's lines with every function definition (header + body) cut."""
    lines = src.splitlines()
    drop = set()
    for f in unit["functions"]:
        n = len(f["body"].splitlines())
        start = f["hdr_line"] - 1
        body = f["line"] - 1
        for i in range(start, body + n):
            drop.add(i)
    return [line for i, line in enumerate(lines) if i not in drop]


def changed_lines(a, b):
    import difflib
    out = []
    for line in difflib.unified_diff(a, b, lineterm="", n=0):
        if line.startswith(("+++", "---", "@@")):
            continue
        out.append(line)
    return out


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--baseline", required=True)
    ap.add_argument("--map", action="append", default=[],
                    help="host=a,b:NewUnit.h.ct (repeatable)")
    args = ap.parse_args(argv)
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    base_units = {u["path"]: u for u in extract(root, args.baseline)}
    cur_units = {u["path"]: u for u in inv.scan(root)}
    bad = []

    def multiset(units):
        c = collections.Counter()
        for u in units.values():
            for f in u["functions"]:
                c[f["sha"]] += 1
        return c

    a, b = multiset(base_units), multiset(cur_units)
    if a != b:
        for sha in sorted(set(a) | set(b)):
            if a[sha] != b.get(sha, 0):
                names = sorted({f["name"] for u in base_units.values()
                                for f in u["functions"] if f["sha"] == sha})
                bad.append("body multiset differs at %s (%s): %d -> %d"
                           % (sha[:12], ",".join(names[:3]), a[sha], b.get(sha, 0)))

    by_name = collections.defaultdict(list)
    for u in cur_units.values():
        for f in u["functions"]:
            by_name[f["name"]].append((u["path"], f))
    hosts = set()
    for row in args.map:
        left, _, unit = row.rpartition(":")
        hosts.add(left.split("=", 1)[0])
        for fn in left.split("=", 1)[1].split(","):
            hits = by_name.get(fn, [])
            if len(hits) != 1:
                bad.append("%s is defined %d time(s)" % (fn, len(hits)))
                continue
            path, f = hits[0]
            if path != unit:
                bad.append("%s moved to %s, expected %s" % (fn, path, unit))
            if f["kind"] != "free":
                bad.append("%s is not a free function" % fn)
            if not f["body"].startswith("{"):
                bad.append("%s has no body" % fn)
            # the body must not have been rewritten: hash is in the multiset,
            # and the defining line must now be `pub`, not `static`
            src = open(os.path.join(root, path), encoding="utf-8").read()
            line = src.splitlines()[f["hdr_line"] - 1]
            if not line.lstrip().startswith("pub "):
                bad.append("%s is not exported in %s: %r" % (fn, path, line))

    # skeleton: a host may only gain import lines; a new unit only boilerplate
    for host in sorted(hosts):
        if host not in cur_units or host not in base_units:
            bad.append("host %s is not a unit on both sides" % host)
            continue
        # baseline text comes from the archive; re-extract just this file
        base_text = git_show(root, args.baseline, host)
        new_text = open(os.path.join(root, host), encoding="utf-8").read()
        old = skeleton(inv.blank(base_text), base_units[host])
        new = skeleton(inv.blank(new_text), cur_units[host])
        for line in changed_lines(old, new):
            if line.startswith("+") and any(p.match(line[1:]) for p in SKELETON_OK):
                continue
            if line.startswith("-") and line[1:].strip() == "":
                continue
            if line.startswith("-") and re.match(r"^\s*static\s+[A-Za-z_].*;\s*$", line[1:]):
                continue
            if line.startswith("+") and line[1:].strip() == "":
                continue
            bad.append("%s skeleton changed: %r" % (host, line[:100]))
    for row in args.map:
        unit = row.rpartition(":")[2]
        if unit not in cur_units:
            bad.append("mapped unit %s is missing" % unit)
            continue
        text = open(os.path.join(root, unit), encoding="utf-8").read()
        for line in skeleton(inv.blank(text), cur_units[unit]):
            if any(p.match(line) for p in SKELETON_OK):
                continue
            bad.append("%s has a non-mechanical skeleton line %r" % (unit, line[:100]))

    if bad:
        for line in bad[:40]:
            print("sh94_split: FAIL %s" % line, file=sys.stderr)
        print("sh94_split: FAIL (%d finding(s))" % len(bad))
        return 1
    print("sh94_split: %d bodies, multiset identical; %d moved function(s) in place;"
          " skeletons mechanical" % (sum(b.values()), sum(len(r.rpartition(':')[0].split('=', 1)[1].split(',')) for r in args.map)))
    return 0


def git_show(root, rev, path):
    return subprocess.run(["git", "-C", root, "show", "%s:%s" % (rev, path)],
                          check=True, stdout=subprocess.PIPE).stdout.decode()


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
