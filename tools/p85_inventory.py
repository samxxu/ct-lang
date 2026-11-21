#!/usr/bin/env python3
"""p85_inventory.py - ct-ast source inventory, import graph and M0 move check.

Phase 85 (S85a / S85c). The compiler tree is a set of `.h.ct` units, each of
which declares one type or trait named after its file (the unit-name lint in
`selfhost/check-ast.sh`). This tool re-derives the facts the inventory document
states so the document can be spot-checked:

  * per unit: subsystem, lines, imports, declared types/traits, file-scope
    state (globals), free functions, trait methods and their body hashes;
  * the import graph and its cycles (J4: M0 must not add a cycle);
  * helper clusters (free functions + globals closed under use) that M0 can
    move without touching a body;
  * the M0 move check: body-hash set containment against a frozen baseline,
    the expected product set and the old->new map.

Subcommands:
  scan [--root R] [--json]      print the inventory (JSON with --json)
  doc  [--root R]               print the markdown tables the document quotes
  cycles [--root R]             print the import cycles, one per line
  groups [--root R]             print the movable helper clusters, one per line
  check [--root R] [--doc P]    verify the document against the tree
  m0 [--root R]                 verify the M0 move against its baseline
  m0-baseline [--root R]        write the M0 baseline JSON to stdout

Exit codes: 0 ok, 1 a check failed, 2 usage / environment error.
"""

import argparse
import hashlib
import json
import os
import re
import sys

CT_AST = "selfhost/ct-ast"


# --------------------------------------------------------------------------
# lexing helpers: blank comments and literals while keeping offsets/newlines
# --------------------------------------------------------------------------
def blank(src):
    """Return `src` with comments and string/char literals replaced by spaces.

    Offsets are preserved so the raw text can still be sliced by positions the
    scanner finds in the blanked copy."""
    out = list(src)
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            for k in range(i, j):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        elif c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i + 2)
            j = n if j < 0 else j
            for k in range(i, j):
                out[k] = " "
            i = j
        elif c in "\"'":
            q = c
            j = i + 1
            while j < n:
                if src[j] == "\\":
                    j += 2
                    continue
                if src[j] == q:
                    j += 1
                    break
                j += 1
            for k in range(i, min(j, n)):
                if out[k] != "\n":
                    out[k] = " "
            i = j
        else:
            i += 1
    return "".join(out)


def line_of(src, pos):
    return src.count("\n", 0, pos) + 1


CTRL = ("if", "for", "while", "switch", "match", "else", "do")


def match_braces(code):
    """Map each `{` offset to its matching `}` offset (in the blanked copy)."""
    open_at = []
    pairs = {}
    for i, c in enumerate(code):
        if c == "{":
            open_at.append(i)
        elif c == "}":
            if open_at:
                pairs[open_at.pop()] = i
    return pairs


def split_header(code, brace):
    """Text before `brace` back to the previous top-level `;`, `{` or `}`."""
    j = brace - 1
    while j >= 0 and code[j] not in ";{}":
        j -= 1
    return code[j + 1:brace].strip()


def brace_info(code):
    """depth and parent of every `{`, in one pass."""
    depth = {}
    parent = {}
    stack = []
    for i, c in enumerate(code):
        if c == "{":
            depth[i] = len(stack)
            parent[i] = stack[-1] if stack else None
            stack.append(i)
        elif c == "}" and stack:
            stack.pop()
    return depth, parent


def find_functions(src, code, pairs):
    """Yield function records from the blanked source."""
    funcs = []
    depth, parent = brace_info(code)
    for brace in sorted(pairs):
        close = pairs[brace]
        header = split_header(code, brace)
        if not header or "=" in header:
            continue
        if not header.rstrip().endswith(")"):
            continue
        # a block whose header starts with a control keyword is not a function
        # (`if (!foo(x)) {`); nested calls put the callee before the last `(`.
        if re.match(r"^(if|for|while|switch|match|else|do|return|case)\b", header):
            continue
        # the name is the identifier just before the last '('
        lp = header.rfind("(")
        m = re.search(r"([A-Za-z_][A-Za-z0-9_]*)\s*$", header[:lp])
        if not m:
            continue
        name = m.group(1)
        if name in CTRL:
            continue
        # a declaration puts a type word before the name (`int f(`, `char *f(`);
        # a call used as a condition (`if (strcmp(a, b) > 0) {`) or one that
        # follows a `for` head has `(`, `::` or an operator before it instead.
        pre = header[:m.start()].rstrip().rstrip("*").rstrip()
        if not pre or not re.search(r"[A-Za-z0-9_]$", pre):
            continue
        owner = None
        trait = None
        kind = "free"
        par = parent.get(brace)
        if par is not None:
            ehead = split_header(code, par)
            em = re.match(r"impl\s+(?:(\w+)\s+for\s+)?(\w+)", ehead)
            if em:
                kind = "method"
                trait = em.group(1)
                owner = em.group(2)
        funcs.append({
            "name": name,
            "kind": kind,
            "owner": owner,
            "trait": trait,
            "line": line_of(src, brace),
            "hdr_line": line_of(src, brace - len(header)),
            "body": src[brace:close + 1],
        })
    return funcs


def find_top_blocks(code, pairs):
    """Top-level `struct` / `trait` / `impl` blocks: (kind, name, trait)."""
    out = []
    depth, parent = brace_info(code)
    for brace in sorted(pairs):
        if depth[brace] != 0:
            continue
        head = split_header(code, brace)
        m = re.match(r"(?:pub\s+)?(struct|union|enum|trait)\s+(\w+)", head)
        if m:
            out.append((m.group(1), m.group(2), head))
            continue
        m = re.match(r"impl\s+(?:(\w+)\s+for\s+)?(\w+)", head)
        if m:
            out.append(("impl", m.group(2), m.group(1) or ""))
    return out


def find_imports(src):
    return re.findall(r"^\s*import\s+([A-Za-z0-9_:]+)\s*(?:as\s+(\w+))?\s*;",
                      src, re.MULTILINE)


def find_globals(src, code):
    """File-scope variables: statements with no `(` and an identifier before
    `[` / `=` / `;`."""
    globs = []
    for m in re.finditer(r"(?m)^(?:static\s+|pub\s+)*([A-Za-z_][\w ]*?[\w*])\s+"
                         r"(\*?\s*[A-Za-z_]\w*)\s*(\[[^;]*\])?\s*(=[^;]*)?;", src):
        decl = m.group(0)
        if "(" in code[m.start():m.start() + len(decl)]:
            continue
        if re.match(r"\s*(import|namespace|#|typedef|using|return)\b", decl):
            continue
        if re.search(r"\b(struct|union|enum|trait)\s+\w+\s*$", m.group(1)):
            pass
        globs.append({"name": m.group(2).strip().lstrip("*").strip(),
                      "line": line_of(src, m.start()),
                      "text": decl.strip()})
    return globs


def sha(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def parse_unit(root, path):
    full = os.path.join(root, path)
    with open(full, encoding="utf-8") as fh:
        src = fh.read()
    code = blank(src)
    pairs = match_braces(code)
    blocks = find_top_blocks(code, pairs)
    funcs = find_functions(src, code, pairs)
    globs = find_globals(src, code)
    names = {f["name"] for f in funcs if f["kind"] == "free"}
    gnames = {g["name"] for g in globs}
    # body hashes on the raw text with trailing spaces normalised per line
    for f in funcs:
        body = "\n".join(line.rstrip() for line in f["body"].splitlines())
        f["sha"] = sha(body)
        refs_free = set()
        refs_glob = set()
        for ident in re.findall(r"\b([A-Za-z_]\w*)\s*\(", blank(f["body"])):
            if ident in names:
                refs_free.add(ident)
        for ident in re.findall(r"\b([A-Za-z_]\w*)\b", blank(f["body"])):
            if ident in gnames:
                refs_glob.add(ident)
        f["refs_free"] = sorted(refs_free)
        f["refs_glob"] = sorted(refs_glob)
    types = [b[1] for b in blocks if b[0] in ("struct", "union", "enum")]
    traits = [b[1] for b in blocks if b[0] == "trait"]
    impls = [(b[2], b[1]) for b in blocks if b[0] == "impl"]
    return {
        "path": path,
        "lines": src.count("\n") + (0 if src.endswith("\n") else 1),
        "imports": [{"path": a, "alias": b} for a, b in find_imports(src)],
        "types": types,
        "traits": traits,
        "impls": impls,
        "globals": globs,
        "functions": funcs,
        "file_sha": sha(src),
    }


def scan(root):
    base = os.path.join(root, CT_AST)
    units = []
    for dirpath, dirnames, filenames in os.walk(base):
        dirnames.sort()
        for name in sorted(filenames):
            if not name.endswith((".h.ct", ".m.ct")):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name),
                                  os.path.join(root, CT_AST))
            units.append(rel)
    units.sort()
    # the entry is not a `.h.ct` unit (it declares no type of its own), but it
    # is part of the program and its imports close the product set
    out = [parse_unit(root, os.path.join(CT_AST, "main.ct"))]
    out.extend(parse_unit(root, os.path.join(CT_AST, rel)) for rel in units)
    return out


def subsystem_of(path):
    """`backend::emit`, `frontend::parse`, `tool::pkg`, ... -- the unit's own
    namespace directory, not the tree name."""
    rel = path.split("selfhost/ct-ast/")[-1]
    parts = rel.split("/")
    if len(parts) >= 3:
        return parts[0] + "::" + parts[1]
    if len(parts) == 2:
        return parts[0]
    return "entry"


def import_edges(units):
    """Unit path (without the ct-ast prefix) -> imported unit paths.

    A by-name import `a::b::C::D` names unit `a::b::C`; a unit import names the
    unit itself. The mapping is by the directory + file stem, which is exactly
    how the module layer resolves a path."""
    known = {u["path"]: u for u in units}
    edges = {}
    for u in units:
        targets = []
        for imp in u["imports"]:
            segs = imp["path"].split("::")
            for cut in (len(segs), len(segs) - 1):
                if cut <= 0:
                    continue
                cand = os.path.join(CT_AST, "/".join(segs[:cut]) + ".h.ct")
                if cand in known and cand != u["path"]:
                    targets.append(cand)
                    break
        edges[u["path"]] = sorted(set(targets))
    return edges


def cycles_of(edges):
    """Elementary cycles, canonicalised to start at their smallest node.

    Tarjan's SCC first: a DAG (the current tree) answers in O(V+E) instead of
    enumerating paths, and the DFS below only runs inside a real cycle."""
    index = {}
    low = {}
    onstack = {}
    stack = []
    sccs = []
    counter = [0]

    def strongconnect(v):
        index[v] = low[v] = counter[0]
        counter[0] += 1
        stack.append(v)
        onstack[v] = True
        for w in edges.get(v, ()):
            if w not in index:
                strongconnect(w)
                low[v] = min(low[v], low[w])
            elif onstack.get(w):
                low[v] = min(low[v], index[w])
        if low[v] == index[v]:
            comp = []
            while True:
                w = stack.pop()
                onstack[w] = False
                comp.append(w)
                if w == v:
                    break
            sccs.append(comp)

    for v in sorted(edges):
        if v not in index:
            strongconnect(v)
    cyclic = [c for c in sccs
              if len(c) > 1 or (len(c) == 1 and c[0] in edges.get(c[0], ()))]
    if not cyclic:
        return []
    order = {v: i for i, v in enumerate(sorted(edges))}
    found = set()

    def walk(start, node, path, seen):
        for nxt in edges.get(node, ()):
            if len(found) >= 200:
                return
            if nxt == start and len(path) > 1:
                cyc = path[:]
                k = cyc.index(min(cyc, key=lambda x: order.get(x, 0)))
                cyc = cyc[k:] + cyc[:k]
                found.add(tuple(cyc))
            elif nxt not in seen:
                seen.add(nxt)
                walk(start, nxt, path + [nxt], seen)
                seen.discard(nxt)

    for comp in cyclic:
        for start in comp:
            walk(start, start, [start], {start})
    return sorted(found)


def helper_groups(unit):
    """Closed clusters of free functions + globals, with the methods that use
    them. A cluster is movable when nothing outside it refers to its free
    functions or globals."""
    free = {f["name"]: f for f in unit["functions"] if f["kind"] == "free"}
    glob = {g["name"]: g for g in unit["globals"]}
    nodes = set(free) | set(glob)
    parent = {n: n for n in nodes}

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[rb] = ra

    users = {n: set() for n in nodes}
    for f in unit["functions"]:
        refs = [r for r in f["refs_free"] + f["refs_glob"] if r in nodes]
        for r in refs:
            users[r].add(f["name"])
        for a in refs:
            for b in refs:
                union(a, b)
    comps = {}
    for n in nodes:
        comps.setdefault(find(n), []).append(n)
    # a method belongs to every component it touches; if it touches several,
    # those components must travel together
    by_func = {}
    for f in unit["functions"]:
        refs = [r for r in f["refs_free"] + f["refs_glob"] if r in nodes]
        by_func[f["name"]] = sorted({find(r) for r in refs})
    merged = {}
    for c in comps:
        merged[c] = {c}
    changed = True
    while changed:
        changed = False
        for groups in by_func.values():
            for a in groups:
                for b in groups:
                    if a in merged and b in merged and merged[a] is not merged[b]:
                        keep, drop = merged[a], merged[b]
                        keep |= drop
                        for k, v in list(merged.items()):
                            if v is drop:
                                merged[k] = keep
                        changed = True
    out = {}
    for c, names in comps.items():
        key = id(merged[c])
        out.setdefault(key, {"free": set(), "globals": set(), "methods": set()})
        out[key]["free"] |= {n for n in names if n in free}
        out[key]["globals"] |= {n for n in names if n in glob}
    for f in unit["functions"]:
        for c in by_func.get(f["name"], []):
            key = id(merged[c])
            if key in out and f["name"] not in out[key]["free"]:
                out[key]["methods"].add(f["name"])
    res = []
    for g in out.values():
        if not g["free"] and not g["globals"]:
            continue
        g["free"] = sorted(g["free"])
        g["globals"] = sorted(g["globals"])
        g["methods"] = sorted(g["methods"])
        res.append(g)
    res.sort(key=lambda g: (-len(g["free"]) - len(g["globals"]), g["free"][:1]))
    return res


def load_doc(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def cmd_scan(args):
    units = scan(args.root)
    for u in units:
        u["subsystem"] = subsystem_of(u["path"])
    data = {"root": os.path.abspath(args.root), "units": units}
    if args.json:
        print(json.dumps(data, indent=2, sort_keys=False))
    else:
        for u in units:
            print("%-52s %5d  %2d fn  %2d glob  %s"
                  % (u["path"], u["lines"], len(u["functions"]),
                     len(u["globals"]), ",".join(u["traits"] + u["types"])))
    return 0


def cmd_doc(args):
    units = scan(args.root)
    total = sum(u["lines"] for u in units)
    print("units: %d, lines: %d" % (len(units), total))
    print()
    print("| 单元 | 子系统 | 行数 | 类型/trait | 自由函数 | trait 方法 | 文件级状态 | import |")
    print("| --- | --- | --- | --- | --- | --- | --- | --- |")
    for u in units:
        nfree = sum(1 for f in u["functions"] if f["kind"] == "free")
        nmeth = sum(1 for f in u["functions"] if f["kind"] == "method")
        decl = ", ".join(u["traits"] + u["types"]) or "-"
        globs = ", ".join(g["name"] for g in u["globals"]) or "-"
        print("| %s | %s | %d | %s | %d | %d | %s | %d |"
              % (u["path"], subsystem_of(u["path"]), u["lines"], decl,
                 nfree, nmeth, globs, len(u["imports"])))
    print()
    edges = import_edges(units)
    print("import edges: %d, cycles: %d" % (sum(len(v) for v in edges.values()),
                                            len(cycles_of(edges))))
    for c in cycles_of(edges):
        print("cycle: " + " -> ".join(c + [c[0]]))
    return 0


def cmd_cycles(args):
    units = scan(args.root)
    cyc = cycles_of(import_edges(units))
    for c in cyc:
        print(" -> ".join(c + [c[0]]))
    print("cycles: %d" % len(cyc))
    return 0


def cmd_groups(args):
    units = scan(args.root)
    for u in units:
        gs = helper_groups(u)
        if not gs:
            continue
        print("== %s (%d clusters)" % (u["path"], len(gs)))
        for g in gs:
            print("  free=%s" % ",".join(g["free"]))
            print("  glob=%s" % ",".join(g["globals"]))
            print("  meth=%s" % ",".join(g["methods"]))
            print()
    return 0


def cmd_check(args):
    units = scan(args.root)
    doc_path = args.doc or os.path.join(args.root, "docs/design/p85_inventory.md")
    if not os.path.exists(doc_path):
        print("check: missing %s" % doc_path, file=sys.stderr)
        return 1
    doc = load_doc(doc_path)
    bad = 0
    total_lines = 0
    total_fns = 0
    for u in units:
        nfree = sum(1 for f in u["functions"] if f["kind"] == "free")
        nmeth = sum(1 for f in u["functions"] if f["kind"] == "method")
        total_lines += u["lines"]
        total_fns += len(u["functions"])
        row = re.compile(r"^\|\s*`?" + re.escape(u["path"]) + r"`?\s*\|([^\n]*)\|\s*$",
                         re.MULTILINE)
        m = row.search(doc)
        if not m:
            print("check: no row for %s" % u["path"])
            bad += 1
            continue
        cols = [c.strip().strip("`") for c in m.group(1).split("|")]
        # subsystem | lines | types | free | methods | state | imports
        try:
            lines_n, free_n, meth_n, import_n = (int(cols[1]), int(cols[3]),
                                                 int(cols[4]), int(cols[6]))
        except (IndexError, ValueError):
            print("check: unreadable row for %s: %s" % (u["path"], cols))
            bad += 1
            continue
        for name, want, got in (("lines", lines_n, u["lines"]),
                                ("free", free_n, nfree),
                                ("methods", meth_n, nmeth),
                                ("imports", import_n, len(u["imports"]))):
            if want != got:
                print("check: %s %s: document %d, tree %d"
                      % (u["path"], name, want, got))
                bad += 1
        subsystem = cols[0]
        if subsystem != subsystem_of(u["path"]):
            print("check: %s subsystem: document %s, tree %s"
                  % (u["path"], subsystem, subsystem_of(u["path"])))
            bad += 1
        globs = ", ".join(g["name"] for g in u["globals"]) or "-"
        if globs not in doc:
            print("check: file-level state not listed for %s" % u["path"])
            bad += 1
    cyc = cycles_of(import_edges(units))
    for c in cyc:
        text = " -> ".join(c + [c[0]])
        if text not in doc:
            print("check: the import cycle is not listed: %s" % text)
            bad += 1
    if "cycles: 0" not in doc and not cyc:
        print("check: the document does not state the cycle count")
        bad += 1
    summary = "%d units, %d lines, %d functions" % (len(units), total_lines,
                                                    total_fns)
    if summary not in doc:
        print("check: the document does not pin '%s'" % summary)
        bad += 1
    if bad:
        print("p85_inventory: %d finding(s)" % bad, file=sys.stderr)
        return 1
    print("p85_inventory: %s, %d import cycles, every row matches the tree"
          % (summary, len(cyc)))
    return 0


def m0_snapshot(units):
    """Everything J1 / J4 / A2 pin: body hash multiset, unit set, products."""
    counts = {}
    for u in units:
        for f in u["functions"]:
            key = u["path"] + "::" + (f["owner"] + "." if f["owner"] else "") + f["name"]
            counts.setdefault(f["sha"], []).append(key)
    return {
        "units": [u["path"] for u in units],
        "lines": sum(u["lines"] for u in units),
        "functions": sum(len(u["functions"]) for u in units),
        "body_hashes": counts,
    }


def products_for(root):
    """The build's product set (`<base>.c` per reachable `.h.ct` unit)."""
    units = scan(root)
    by_path = {u["path"]: u for u in units}
    edges = import_edges(units)
    seen = set()
    stack = ["selfhost/ct-ast/main.ct"]
    while stack:
        cur = stack.pop()
        if cur in seen or cur not in by_path:
            continue
        seen.add(cur)
        stack.extend(edges.get(cur, ()))
    return sorted(os.path.splitext(os.path.basename(p))[0] for p in seen
                  if p.endswith(".h.ct"))


def cmd_m0_baseline(args):
    units = scan(args.root)
    snap = m0_snapshot(units)
    snap["products"] = products_for(args.root)
    snap["cycles"] = [" -> ".join(c + [c[0]])
                      for c in cycles_of(import_edges(units))]
    print(json.dumps(snap, indent=2, sort_keys=True))
    return 0


def read_mapping(path):
    rows = []
    with open(path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            parts = line.split("\t")
            if len(parts) != 2:
                raise SystemExit("m0: bad mapping row: %r" % line)
            rows.append(parts)
    return rows


def cmd_m0(args):
    base_path = os.path.join(args.root, "test/probes/p85_m0_baseline.json")
    map_path = os.path.join(args.root, "test/probes/p85_m0_mapping.tsv")
    edits_path = os.path.join(args.root, "test/probes/p85_m0_s85d_edits.tsv")
    for p in (base_path, map_path, edits_path):
        if not os.path.exists(p):
            print("m0: missing %s" % p, file=sys.stderr)
            return 2
    with open(base_path, encoding="utf-8") as fh:
        base = json.load(fh)
    units = scan(args.root)
    now = m0_snapshot(units)
    rows = read_mapping(map_path)
    modified = set()
    added = set()
    with open(edits_path, encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line or line.startswith("#"):
                continue
            kind, key = line.split("\t")
            (modified if kind == "modified" else added).add(key)
    bad = 0
    # J1: every baseline body is still there, byte for byte; a missing hash is
    # only allowed for a body a later task (S85d) declares it changed.
    for h, keys in base["body_hashes"].items():
        if h in now["body_hashes"]:
            continue
        for key in keys:
            if key not in modified:
                print("m0: body changed or vanished: %s" % key)
                bad += 1
    # and a hash that was not in the baseline may only be one of the declared
    # post-M0 bodies
    for h, keys in now["body_hashes"].items():
        if h in base["body_hashes"]:
            continue
        for key in keys:
            if key not in modified and key not in added:
                print("m0: new function body: %s" % key)
                bad += 1
    if now["functions"] != base["functions"] + len(added):
        print("m0: function count %d != baseline %d + %d"
              % (now["functions"], base["functions"], len(added)))
        bad += 1
    # the pure-move invariant: every function of a mapped unit is byte-identical
    # to a body that existed before M0
    for _, new in rows:
        unit = next((u for u in units if u["path"] == new), None)
        if unit is None:
            print("m0: mapping target is missing: %s" % new)
            bad += 1
            continue
        for f in unit["functions"]:
            if f["sha"] not in base["body_hashes"]:
                key = new + "::" + (f["owner"] + "." if f["owner"] else "") + f["name"]
                print("m0: a moved body is not the baseline body: %s" % key)
                bad += 1
    # A2: the product set grows by exactly the mapped units
    expected = sorted(base["products"] + [os.path.splitext(os.path.basename(n))[0]
                                          for _, n in rows])
    products = products_for(args.root)
    if products != expected:
        print("m0: product set mismatch: missing=%s extra=%s"
              % (sorted(set(expected) - set(products)),
                 sorted(set(products) - set(expected))))
        bad += 1
    # J4: no import cycle may be added (the baseline has none)
    cyc = cycles_of(import_edges(units))
    if [c for c in cyc if " -> ".join(c + [c[0]]) not in base["cycles"]]:
        print("m0: new import cycle: %s"
              % [" -> ".join(c + [c[0]]) for c in cyc])
        bad += 1
    present = set(now["units"])
    for old, new in rows:
        if old not in present:
            print("m0: mapping host is missing: %s" % old)
            bad += 1
        if new not in present:
            print("m0: mapping target is missing: %s" % new)
            bad += 1
    if bad:
        print("p85_m0: %d finding(s)" % bad, file=sys.stderr)
        return 1
    print("p85_m0: body hashes preserved (%d bodies, %d functions, %d moved "
          "units, %d declared S85d edits), %d products, %d cycles"
          % (len(base["body_hashes"]), now["functions"], len(rows),
             len(modified) + len(added), len(products), len(cyc)))
    return 0


def cmd_corpus_manifest(args):
    """sha256 of `<ct-ast> <file>` emission for the pinned corpus. The probe
    compares the current compiler against this pre-M0 manifest, which is the
    level-1 (test corpus byte-identical) criterion of E85-6."""
    import subprocess
    import tempfile
    cc = args.ct
    files = []
    for pattern in ("test/cases/*.ct", "examples/*/*.ct"):
        import glob as g
        files.extend(sorted(g.glob(os.path.join(args.root, pattern))))
    files = [f for f in files
             if "07_dialect" not in f and "ct-dialects" not in f]
    tmp = tempfile.mkdtemp(prefix="p85corpus.")
    for f in files:
        rel = os.path.relpath(f, args.root)
        out = os.path.join(tmp, "out.c")
        env = dict(os.environ, CT_C_BOUNDARY="allow")
        try:
            subprocess.run([cc, f, "-o", out], check=False, env=env,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except OSError:
            continue
        if os.path.exists(out):
            with open(out, encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            # The banner carries the compiler version; a version bump is an
            # intended change (the task bumps five CTC_VERSION sites and the
            # goldens' banner), so the manifest pins the emission *below* the
            # version token: byte-identical modulo the intended banner bump.
            text = re.sub(r"Generated by ct v[0-9]+\.[0-9]+\.[0-9]+",
                          "Generated by ct v<VERSION>", text)
            h = hashlib.sha256(text.encode("utf-8")).hexdigest()
            print("%s\t%s" % (rel, h))
            os.unlink(out)
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", default=".")
    sub = ap.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("scan")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_scan)
    p = sub.add_parser("doc")
    p.set_defaults(func=cmd_doc)
    p = sub.add_parser("cycles")
    p.set_defaults(func=cmd_cycles)
    p = sub.add_parser("groups")
    p.set_defaults(func=cmd_groups)
    p = sub.add_parser("check")
    p.add_argument("--doc")
    p.set_defaults(func=cmd_check)
    p = sub.add_parser("m0")
    p.set_defaults(func=cmd_m0)
    p = sub.add_parser("m0-baseline")
    p.set_defaults(func=cmd_m0_baseline)
    p = sub.add_parser("corpus-manifest")
    p.add_argument("--ct", required=True)
    p.set_defaults(func=cmd_corpus_manifest)
    args = ap.parse_args(argv)
    try:
        return args.func(args)
    except FileNotFoundError as exc:
        print("p85_inventory: %s" % exc, file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
