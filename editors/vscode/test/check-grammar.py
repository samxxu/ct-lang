#!/usr/bin/env python3
"""Smoke test for syntaxes/ct.tmLanguage.json.

Approximates TextMate's scanning order with Python's `re` to prove two things:

  1. the CT rules fire on the constructs they are meant to fire on, and
  2. they do NOT fire inside comments/strings/chars -- the same guarantee the
     compiler makes ("never rewrite inside a string, char or comment").

This is a smoke test, not a substitute for opening VS Code: Python's `re` is not
Oniguruma, and the real engine also runs VS Code's built-in `source.c` grammar,
which this script delegates to as the terminal pseudo-rule "C".

    python3 editors/vscode/test/check-grammar.py
"""

import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
EXT = os.path.dirname(HERE)                              # editors/vscode
ROOT = os.path.dirname(os.path.dirname(EXT))             # repository root
GRAMMAR = os.path.join(EXT, "syntaxes", "ct.tmLanguage.json")

CT_CASES = (
    "examples/01_greeter/greeter.ct",
    "examples/02_market/market.ct",
    "test/cases/02_multi_trait.ct",
    "test/cases/06_name_collision.ct",
    # namespace / multi-file / Drop fixtures live under test/archive since Phase 0.3
    # moved those features out of the compiler; the grammar still highlights them
    # (the syntax decisions are frozen), so they stay in this sample list.
    "test/archive/cases/19_namespace.ct",
    "test/archive/multifile/calc.ct",
    "test/archive/import/app.ct",
    "test/archive/cases/22_drop.ct",
    # Phase 5 AutoDrop (`own`) lives on the CT line only, so its fixture is under
    # test/modules rather than test/cases.
    "test/modules/autodrop/prog.ct",
)
TRICKY = "\n".join([
    "// use self here",
    'char *s = "use self here";',
    'printf("self->name\\n");',
    "int use_it = 1;",
    "selfish = 1;",
    "/* use self",
    "   self->x */",
])


def resolve(patterns, repo, out):
    """Flatten the grammar's patterns, keeping TextMate's top-to-bottom order."""
    for p in patterns:
        if "include" in p:
            name = p["include"]
            if name.startswith("#"):
                key = name[1:]
                if key in ("comments", "strings"):
                    resolve(repo[key]["patterns"], repo, out)
                else:
                    out.append((key, repo[key]))
            else:
                out.append((name, None))     # source.c -> delegate to the C grammar
        else:
            out.append((p.get("name", "<anon>"), p))
    return out


def scan_line(line, rules, in_block):
    """Yield (rule_name, matched_text) in scan order; "C" means delegated."""
    hits = []
    i = 0
    while i < len(line):
        if in_block:
            m = re.compile(r"\*/").search(line, i)
            if m:
                hits.append(("comment-block", line[i:m.end()]))
                i = m.end()
                in_block = False
            else:
                hits.append(("comment-block", line[i:]))
                break
            continue
        for name, rule in rules:
            if rule is None:
                # `source.c` is a whole grammar we do not emulate. Skip it here so
                # that positions the CT rules do not claim still get tested --
                # the real engine hands those to the C grammar one token at a time.
                continue
            if "begin" in rule:
                m = re.compile(rule["begin"]).match(line, i)
                if m:
                    e = re.compile(rule["end"]).search(line, m.end())
                    if e:
                        hits.append((name, line[m.start():e.end()]))
                        i = e.end()
                    else:
                        hits.append((name, line[m.start():]))
                        if name == "comment-block":
                            in_block = True
                        i = len(line)
                    break
            else:
                m = re.compile(rule["match"]).match(line, i)
                if m and m.end() > m.start():
                    hits.append((name, m.group(0)))
                    i = m.end()
                    break
        else:
            hits.append(("C", line[i]))      # no rule matched here: advance one char
            i += 1
    return hits, in_block


def scan(text, rules):
    rows = []
    in_block = False
    for n, line in enumerate(text.split("\n"), 1):
        hits, in_block = scan_line(line, rules, in_block)
        rows.append((n, line, hits))
    return rows


def flat_hits(rows):
    return [h for _, _, hits in rows for h in hits]


def main():
    with open(GRAMMAR) as fh:
        grammar = json.load(fh)
    rules = resolve(grammar["patterns"], grammar["repository"], [])
    print("scopeName : %s" % grammar["scopeName"])
    print("scan order: %s" % ", ".join(n for n, _ in rules))
    print()

    failures = []
    checks = 0

    def check(desc, cond, detail=""):
        nonlocal checks
        checks += 1
        if cond:
            print("  ok    %s" % desc)
        else:
            print("  FAIL  %s   %s" % (desc, detail))
            failures.append(desc)

    for rel in CT_CASES:
        print("%s:" % rel)
        path = os.path.join(ROOT, rel)
        with open(path) as fh:
            rows = scan(fh.read(), rules)
        for n, line, hits in rows:
            interesting = [h for h in hits if h[0] != "C"]
            if interesting:
                print("    %3d: %-22s %s"
                      % (n, ", ".join(h[0] for h in interesting), line.strip()[:58]))
        all_hits = flat_hits(rows)

        if "01_greeter" in rel:
            trait = [h for _, l, hs in rows if l.strip().startswith("trait ") for h in hs]
            check("trait declaration -> ct-trait", trait and trait[0][0] == "ct-trait", str(trait))
            check("`} use Greeter;` -> ct-use",
                  any(h[0] == "ct-use" for _, l, hs in rows if "use Greeter" in l for h in hs))
            check("`impl Greeter for Person {` -> ct-impl",
                  any(h[0] == "ct-impl" for _, l, hs in rows if "impl " in l for h in hs))
            check("`self->...` -> ct-self",
                  any("" != t for t in [t for n2, t in all_hits if n2 == "ct-self"]))
        if "02_market" in rel:
            use_lines = [l for _, l, _ in rows if re.search(r"\buse\b", l)]
            hits = [t for n2, t in all_hits if n2 == "ct-use"]
            check("every `use` clause -> ct-use", use_lines and len(hits) == len(use_lines),
                  "%d use lines, %d hits" % (len(use_lines), len(hits)))
        if "02_multi_trait" in rel:
            check("`use Greeter, Counter;` -> ct-use (comma list)",
                  any("use Greeter, Counter;" in t for t in
                      [t for n2, t in all_hits if n2 == "ct-use"]))
        if "06_name_collision" in rel:
            check("`} use Alpha, Beta;` -> ct-use",
                  any("use Alpha, Beta;" in t for t in
                      [t for n2, t in all_hits if n2 == "ct-use"]))
        if "19_namespace" in rel:
            check("`namespace Shop {` -> ct-namespace",
                  any(h[0] == "ct-namespace" for _, l, hs in rows
                      if l.strip().startswith("namespace ") for h in hs))
            check("`Shop::Person` -> ct-path",
                  any(h[0] == "ct-path" for _, l, hs in rows if "Shop::" in l for h in hs))
        if "multifile/calc" in rel:
            check("`pub int add(...)` -> ct-pub",
                  any(h[0] == "ct-pub" for _, l, hs in rows
                      if l.strip().startswith("pub ") for h in hs))
        if "import/app" in rel:
            check("`import shapes;` -> ct-import",
                  any(h[0] == "ct-import" for _, l, hs in rows
                      if l.strip().startswith("import ") for h in hs))
        if "22_drop" in rel:
            check("`impl Drop for Inner` -> ct-impl",
                  any(h[0] == "ct-impl" for _, l, hs in rows
                      if l.strip().startswith("impl ") for h in hs))
            check("`use Drop;` -> ct-use",
                  any(h[0] == "ct-use" for _, l, hs in rows if "use Drop" in l for h in hs))
        if "modules/autodrop" in rel:
            check("`own Box *b` -> ct-own",
                  any(h[0] == "ct-own" for _, l, hs in rows
                      if l.strip().startswith("own ") for h in hs))
        print()

    print("synthetic -- these must stay comments / strings / plain identifiers:")
    rows = scan(TRICKY, rules)
    for n, line, hits in rows:
        print("    %3d: %s" % (n, ", ".join("%s=%r" % h for h in hits)))
    by_line = {n: hits for n, _, hits in rows}
    check("`// use self here` yields no ct-use / ct-self",
          not any(h[0] in ("ct-use", "ct-self") for h in by_line[1]), str(by_line[1]))
    check("line 2: the string is one token with no CT rule inside",
          [h for h in by_line[2] if h[0] != "C"] ==
          [("string-double", '"use self here"')], str(by_line[2]))
    check("line 3: the string is one token with no CT rule inside",
          [h for h in by_line[3] if h[0] != "C"] ==
          [("string-double", '"self->name\\n"')], str(by_line[3]))
    check("`use_it` is not the `use` keyword",
          not any(h[0] == "ct-use" for h in by_line[4]), str(by_line[4]))
    check("`selfish` is not `self`",
          not any(h[0] == "ct-self" for h in by_line[5]), str(by_line[5]))
    check("block comment spans lines without leaking CT rules",
          all(h[0] == "comment-block" for h in by_line[6] + by_line[7]),
          str(by_line[6] + by_line[7]))

    print()
    print("== %d checks, %d failed ==" % (checks, len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
