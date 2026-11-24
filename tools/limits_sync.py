#!/usr/bin/env python3
"""limits_sync.py - one authority for the ct-ast capacity caps (SH-94).

`selfhost/ct-ast/frontend/sym/Limits.h.ct` is the only place a `MAX_*` cap value
is chosen. The other `.h.ct` units still have to spell the macro themselves:
ct macros do not cross a translation unit (each `.h.ct` becomes its own `.c`,
and the generated header carries types only), so a cap used in N units needs N
`#define`s. Those defines are *mirrors* of the authority, maintained here:

  * `--check`   every `MAX_*` define under `selfhost/ct-ast` agrees with the
                authority, every authority cap is mirrored at least once, and
                no unit invents a `MAX_*` cap the authority does not list;
  * `--write`   rewrite a mirror's value in place, keeping the line's spelling
                (the emitted C is byte-identical when the value already agrees);
  * `--selftest` build a throwaway tree with one drifted mirror and require
                `--check` to fail and `--write` to repair it.

Exit codes: 0 ok, 1 a check failed, 2 usage / environment error.

Usage:
    python3 tools/limits_sync.py --check [--root R]
    python3 tools/limits_sync.py --write [--root R]
    python3 tools/limits_sync.py --selftest
"""

import argparse
import os
import re
import shutil
import sys
import tempfile

AUTHORITY = os.path.join("selfhost", "ct-ast", "frontend", "sym", "Limits.h.ct")
SCAN_ROOT = os.path.join("selfhost", "ct-ast")
CAP = re.compile(r"^#define\s+(MAX_[A-Z0-9_]+)\s+([0-9]+)\s*$")
CAP_LINE = re.compile(r"^(?P<pre>#define\s+(?P<name>MAX_[A-Z0-9_]+)\s+)(?P<val>[0-9]+)(?P<post>\s*)$")


def iter_units(root):
    base = os.path.join(root, SCAN_ROOT)
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            if name.endswith(".h.ct"):
                yield os.path.join(dirpath, name)


def read_authority(root):
    path = os.path.join(root, AUTHORITY)
    caps = {}
    with open(path, encoding="utf-8") as fh:
        for lineno, line in enumerate(fh, 1):
            m = CAP.match(line.rstrip("\n"))
            if not m:
                continue
            name, value = m.group(1), int(m.group(2))
            if name in caps and caps[name] != value:
                raise SystemExit(
                    "limits_sync: %s:%d declares %s twice (%d vs %d)"
                    % (AUTHORITY, lineno, name, caps[name], value))
            caps[name] = value
    if not caps:
        raise SystemExit("limits_sync: %s declares no MAX_* cap" % AUTHORITY)
    return caps


def scan_mirrors(root, authority_path):
    """Yield (path, lineno, name, value, line) for every mirror define."""
    out = []
    for path in iter_units(root):
        if os.path.abspath(path) == os.path.abspath(authority_path):
            continue
        with open(path, encoding="utf-8") as fh:
            for lineno, line in enumerate(fh, 1):
                m = CAP.match(line.rstrip("\n"))
                if m:
                    out.append((path, lineno, m.group(1), int(m.group(2)),
                                line.rstrip("\n")))
    return out


def check(root):
    authority_path = os.path.join(root, AUTHORITY)
    caps = read_authority(root)
    mirrors = scan_mirrors(root, authority_path)
    seen = {}
    errors = []
    for path, lineno, name, value, line in mirrors:
        rel = os.path.relpath(path, root)
        seen[name] = seen.get(name, 0) + 1
        if name not in caps:
            errors.append("%s:%d: %s is not declared in %s"
                          % (rel, lineno, name, AUTHORITY))
        elif value != caps[name]:
            errors.append("%s:%d: %s is %d, authority says %d"
                          % (rel, lineno, name, value, caps[name]))
    for name in sorted(caps):
        if name not in seen:
            errors.append("%s: %s is not mirrored by any unit"
                          % (AUTHORITY, name))
    if errors:
        for err in errors:
            print("limits_sync: %s" % err, file=sys.stderr)
        print("limits_sync: FAIL (%d cap(s), %d mirror(s), %d error(s))"
              % (len(caps), len(mirrors), len(errors)))
        return 1
    print("limits_sync: %d caps, %d mirrors, 0 drift" % (len(caps), len(mirrors)))
    return 0


def write(root):
    authority_path = os.path.join(root, AUTHORITY)
    caps = read_authority(root)
    mirrors = scan_mirrors(root, authority_path)
    changed = 0
    for path, lineno, name, value, line in mirrors:
        if name not in caps or value == caps[name]:
            continue
        new = CAP_LINE.sub(lambda m: "%s%d%s" % (m.group("pre"), caps[name],
                                                 m.group("post")), line)
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
        eol = "\n" if lines[lineno - 1].endswith("\n") else ""
        lines[lineno - 1] = new + eol
        with open(path, "w", encoding="utf-8") as fh:
            fh.writelines(lines)
        changed += 1
    print("limits_sync: rewrote %d mirror(s)" % changed)
    return 0


def selftest():
    root = tempfile.mkdtemp(prefix="limits-sync.")
    try:
        os.makedirs(os.path.join(root, os.path.dirname(AUTHORITY)))
        os.makedirs(os.path.join(root, SCAN_ROOT, "frontend", "parse"))
        auth = os.path.join(root, AUTHORITY)
        with open(auth, "w", encoding="utf-8") as fh:
            fh.write("#define MAX_TEST 16\n#define MAX_OTHER 64\n")
        unit = os.path.join(root, SCAN_ROOT, "frontend", "parse", "A.h.ct")
        with open(unit, "w", encoding="utf-8") as fh:
            fh.write("#define MAX_TEST    16\n#define MAX_OTHER   64\n")
        other = os.path.join(root, SCAN_ROOT, "frontend", "parse", "B.h.ct")
        with open(other, "w", encoding="utf-8") as fh:
            fh.write("#define MAX_TEST   16\n")
        if check(root) != 0:
            print("limits_sync: selftest FAIL (clean tree rejected)", file=sys.stderr)
            return 1
        # drift one mirror: --check must reject, --write must repair it
        with open(other, "w", encoding="utf-8") as fh:
            fh.write("#define MAX_TEST   8\n")
        if check(root) == 0:
            print("limits_sync: selftest FAIL (drift accepted)", file=sys.stderr)
            return 1
        if write(root) != 0 or check(root) != 0:
            print("limits_sync: selftest FAIL (write did not repair)", file=sys.stderr)
            return 1
        with open(other, encoding="utf-8") as fh:
            if fh.read() != "#define MAX_TEST   16\n":
                print("limits_sync: selftest FAIL (write changed the spelling)",
                      file=sys.stderr)
                return 1
        # an unlisted cap must be rejected: the authority is the closed set
        with open(other, "w", encoding="utf-8") as fh:
            fh.write("#define MAX_TEST   16\n#define MAX_ROGUE  1\n")
        if check(root) == 0:
            print("limits_sync: selftest FAIL (rogue cap accepted)", file=sys.stderr)
            return 1
        print("limits_sync: selftest OK (clean, drift, rogue, repair)")
        return 0
    finally:
        shutil.rmtree(root, ignore_errors=True)


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    mode = ap.add_mutually_exclusive_group(required=True)
    mode.add_argument("--check", action="store_true")
    mode.add_argument("--write", action="store_true")
    mode.add_argument("--selftest", action="store_true")
    ap.add_argument("--root", default=None)
    args = ap.parse_args(argv)
    if args.selftest:
        return selftest()
    root = args.root or os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    if not os.path.isdir(os.path.join(root, SCAN_ROOT)):
        print("limits_sync: %s is not a ct-lang tree" % root, file=sys.stderr)
        return 2
    return write(root) if args.write else check(root)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
