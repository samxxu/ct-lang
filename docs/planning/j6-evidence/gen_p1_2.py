#!/usr/bin/env python3
"""Generate p1_2.csv (SH-104 / J-6 P-1.2).

One row per `.ct` file under examples/, test/ and lib/ (sorted by path),
with six boolean columns:

    path, literal, char_ptr_param, array_param, array_init, ref_out, new

- `literal`          any double-quoted string literal (includes `#include "..."`);
- `char_ptr_param`   `char *name` in a parameter list;
- `array_param`      `T name[]` in a parameter list;
- `array_init`       `T name[] = {` (or any `[] =`);
- `ref_out`          `ref`/`out` used as a parameter annotation;
- `new`              the `new` keyword as a word.

The regexes are deliberately textual: this is a corpus measuring table, not a
parser.  Regenerate with:

    python3 docs/planning/j6-evidence/gen_p1_2.py > docs/planning/j6-evidence/p1_2.csv
"""
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ROOTS = ("examples", "test", "lib")

LITERAL = re.compile(r'"[^"\n]*"')
CHAR_PTR_PARAM = re.compile(r"char\s*\*\s*[A-Za-z_]\w*\s*[,)]")
ARRAY_PARAM = re.compile(r"[A-Za-z_]\w*(?:\s*<[^>]*>)?\s+[A-Za-z_]\w*\s*\[\s*\]\s*[,)]")
ARRAY_INIT = re.compile(r"\[\s*\]\s*=")
REF_OUT = re.compile(r"\b(?:ref|out)\s+[A-Za-z_]\w*")
NEW = re.compile(r"\bnew\b")


def scan(path):
    text = open(path, encoding="utf-8", errors="replace").read()
    return (
        bool(LITERAL.search(text)),
        bool(CHAR_PTR_PARAM.search(text)),
        bool(ARRAY_PARAM.search(text)),
        bool(ARRAY_INIT.search(text)),
        bool(REF_OUT.search(text)),
        bool(NEW.search(text)),
    )


def main():
    files = []
    for top in ROOTS:
        for dirpath, dirnames, filenames in os.walk(os.path.join(ROOT, top)):
            dirnames.sort()
            for name in sorted(filenames):
                if name.endswith(".ct"):
                    files.append(os.path.relpath(os.path.join(dirpath, name), ROOT))
    files.sort()
    out = sys.stdout
    out.write("path,literal,char_ptr_param,array_param,array_init,ref_out,new\n")
    for rel in files:
        flags = scan(os.path.join(ROOT, rel))
        out.write(rel + "," + ",".join("1" if f else "0" for f in flags) + "\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
