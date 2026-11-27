#!/usr/bin/env python3
"""migrate_lint.py - P-1.3 pointer-era migration lint (dry-run only).

Scans `.ct` files under `examples/`, `test/` and `lib/` for constructs that the
v1 pointer-free migration has to touch, and sorts every site into one of three
tiers:

    auto      可自动   the replacement is textual and provably local
    manual    需人工   the shape is known, but the edit needs a decision
                       (naming, ordering, surrounding statement)
    semantic  语义需确认 ownership / lifetime / ABI changes; a human must
                       confirm the behaviour before editing

Already-registered C-interop files (`test/c-boundary-allow.tsv`, `.m.ct` units,
`#ct-raw` blocks) are *not* migration targets.  Their pointer sites are reported
as a separate `keep` bucket and are excluded from the three-tier percentage, so
the automation rate describes code that is actually supposed to migrate.

The tool is a textual lint, not a parser: it strips comments and string literals
first, skips lines longer than 4000 bytes (long-identifier/error fixtures), and
reports the line that triggered each finding.  It never writes source files.

Usage:
    python3 tools/migrate_lint.py [--dry-run] [--list] [--format text|json|tsv]
    python3 tools/migrate_lint.py --files
    python3 tools/migrate_lint.py --selftest
    python3 tools/migrate_lint.py --root DIR --roots examples,test,lib

Exit code: 0 for a successful dry-run (findings are informational), 1 for a
usage/IO error, 2 for a failing selftest.
"""

import argparse
import json
import os
import re
import sys

ROOTS = ("examples", "test", "lib")
TIERS = ("auto", "manual", "semantic")
TIER_ZH = {"auto": "可自动", "manual": "需人工", "semantic": "语义需确认",
           "keep": "C 边界保留"}
MAX_LINE = 4000
BOUNDARY_TSV = os.path.join("test", "c-boundary-allow.tsv")

# --- patterns -------------------------------------------------------------
ARRAY_SUFFIX = re.compile(
    r"\b([A-Za-z_]\w*(?:\s*<[^>\n]{0,60}>)?)\s+([A-Za-z_]\w*)\s*\[\s*\]\s*(?=[,);=])")
CHAR_PTR = re.compile(r"\bchar\s*\*+")
ARROW = re.compile(r"->")
MALLOC = re.compile(r"\bmalloc\s*\(")
FREE = re.compile(r"\bfree\s*\(")
DELETE = re.compile(r"\bdelete\s+[A-Za-z_]\w*")
CSTR = re.compile(r"\.cstr\s*\(")
OWN_PTR = re.compile(r"\bown\s+[A-Za-z_]\w*\s*\*+")
MAP_CHAR = re.compile(r"\bMap\s*<\s*char\s*\*")
RESULT_CHAR = re.compile(r"\bResult\s*<[^>\n]*\bchar\s*\*")
GENERIC_PTR = re.compile(r"\b([A-Za-z_]\w*)\s*\*+\s*([A-Za-z_]\w*)")
PRINTF_S = re.compile(r"\bprintf\s*\(\s*\"%s")
AUTO_PRINTF = re.compile(
    r"\bprintf\s*\(\s*\"%s(\\n)?\"\s*,\s*([A-Za-z_]\w*(?:\.[A-Za-z_]\w*)*)"
    r"\.cstr\s*\(\s*\)\s*\)")
BOX_DECL = re.compile(r"\bBox\s*<\s*[^>\n]{1,60}>\s+([A-Za-z_]\w*)")
NOT_STRUCT_PTR = {"char", "void", "const", "unsigned", "signed", "short",
                  "long", "int", "float", "double", "size_t", "bool", "_Bool"}


class Finding(object):
    __slots__ = ("path", "line", "tier", "rule", "text", "suggestion", "reason")

    def __init__(self, path, line, tier, rule, text, suggestion, reason):
        self.path = path
        self.line = line
        self.tier = tier
        self.rule = rule
        self.text = text.strip()
        self.suggestion = suggestion
        self.reason = reason

    def as_dict(self):
        return {"path": self.path, "line": self.line, "tier": self.tier,
                "rule": self.rule, "text": self.text,
                "suggestion": self.suggestion, "reason": self.reason}


def strip_comments_and_strings(line, state):
    """Return (code_without_comments_or_strings, state).

    `state` carries an open block comment and an open string across lines.
    String and character literals become "" so their contents cannot match.
    """
    out = []
    i = 0
    n = len(line)
    in_block = state.get("block", False)
    quote = state.get("quote")
    while i < n:
        if in_block:
            end = line.find("*/", i)
            if end < 0:
                return "".join(out), {"block": True, "quote": None}
            i = end + 2
            in_block = False
            continue
        if quote:
            if line[i] == "\\":
                i += 2
                continue
            if line[i] == quote:
                quote = None
            i += 1
            continue
        if line.startswith("/*", i):
            in_block = True
            i += 2
            continue
        if line.startswith("//", i):
            break
        if line[i] in ("\"", "'"):
            quote = line[i]
            out.append('""')
            i += 1
            continue
        out.append(line[i])
        i += 1
    return "".join(out), {"block": False, "quote": quote}


def strip_comments(line, state):
    """Strip comments but keep string literals (for printf format detection)."""
    out = []
    i = 0
    n = len(line)
    in_block = state.get("block", False)
    quote = state.get("quote")
    while i < n:
        if in_block:
            end = line.find("*/", i)
            if end < 0:
                return "".join(out), {"block": True, "quote": None}
            i = end + 2
            in_block = False
            continue
        if quote:
            if line[i] == "\\":
                out.append(line[i:i + 2])
                i += 2
                continue
            if line[i] == quote:
                quote = None
            out.append(line[i])
            i += 1
            continue
        if line.startswith("/*", i):
            in_block = True
            i += 2
            continue
        if line.startswith("//", i):
            break
        if line[i] in ("\"", "'"):
            quote = line[i]
        out.append(line[i])
        i += 1
    return "".join(out), {"block": False, "quote": quote}


def read_boundary(root, rel):
    """True when this file is a registered C-interop unit."""
    if rel.endswith(".m.ct"):
        return True
    tsv = os.path.join(root, BOUNDARY_TSV)
    try:
        with open(tsv, encoding="utf-8") as handle:
            for raw in handle:
                if raw.startswith("#") or not raw.strip():
                    continue
                path = raw.split("\t", 1)[0].strip()
                if path and path == rel:
                    return True
    except OSError:
        pass
    return False


def has_raw_c(text):
    return "#ct-raw" in text


def boundary_dirs(root, roots):
    """Directories that own a `.m.ct`/`.shim.h` unit (their consumers are C interop)."""
    dirs = set()
    for top in roots:
        for dirpath, dirnames, filenames in os.walk(os.path.join(root, top)):
            if any(name.endswith((".m.ct", ".shim.h")) for name in filenames):
                dirs.add(os.path.relpath(dirpath, root))
    return dirs


def boundary_reason(root, rel, text, dirs):
    """Why this file is a keep (C interop/runtime) unit, or None."""
    parts = rel.split(os.sep)
    if rel.startswith("lib" + os.sep):
        return "builtin/runtime layer (implements the handles)"
    if ("errors" in parts or "archive" in parts
            or os.path.basename(rel).startswith("neg_")):
        return "negative/historical fixture (tests the old form on purpose)"
    if read_boundary(root, rel):
        return "registered C interop (test/c-boundary-allow.tsv)"
    parent = os.path.dirname(rel)
    for cand in (parent, os.path.dirname(parent)):
        if cand in dirs:
            return "consumer of a .m.ct/.shim unit"
    if any(token in rel for token in ("c-superset", "freestanding", "shim",
                                      "baremetal", "bindings")):
        return "C interop/board fixture"
    if has_raw_c(text):
        return "#ct-raw passthrough"
    if re.search(r"\bmap\s+trait\b", text):
        return "map-binding (C interop)"
    return None


def _inside(pos, spans):
    return any(start <= pos < end for start, end in spans)


def scan_text(text, rel, boundary=False, start_line=1):
    """Classify one file's migration sites.  Pure: no filesystem access."""
    findings = []
    box_vars = set(BOX_DECL.findall(text))
    state_code = {"block": False, "quote": None}
    state_raw = {"block": False, "quote": None}
    for offset, raw in enumerate(text.splitlines()):
        lineno = start_line + offset
        code, state_code = strip_comments_and_strings(raw, state_code)
        raw_code, state_raw = strip_comments(raw, state_raw)
        if len(raw) > MAX_LINE:
            continue
        if not code.strip():
            continue
        is_boundary = boundary

        def add(tier, rule, match, suggestion, reason):
            findings.append(Finding(rel, lineno, tier, rule, raw,
                                    suggestion, reason))

        # Type-argument char pointers are covered by their own rule; do not
        # count the same `char *` again as a standalone declaration.
        map_matches = list(MAP_CHAR.finditer(code))
        result_matches = list(RESULT_CHAR.finditer(code))
        masked = [m.span() for m in map_matches] + [m.span() for m in result_matches]

        # array suffix: T name[] -> T[] name (initializer-length arrays stay)
        for m in ARRAY_SUFFIX.finditer(code):
            rest = code[m.end():]
            if re.match(r"\s*=\s*\{", rest):
                continue
            if is_boundary:
                add("keep", "array-suffix", m,
                    "%s[] %s" % (m.group(1), m.group(2)),
                    "C 边界文件里的旧声明；语法迁移本身仍可自动")
            else:
                add("auto", "array-suffix", m,
                    "%s[] %s" % (m.group(1), m.group(2)),
                    "`T a[]` 后缀废弃；无初始化式时改为 `T[] a`")

        # Map<char *, V> key
        for m in map_matches:
            if is_boundary:
                add("keep", "map-char-key", m, "Map<char *, V>", "C 指针键，保留")
            else:
                add("semantic", "map-char-key", m, "Map<String, V>",
                    "键改为 owning String；调用点的字面量键需补 to_string()")

        # Result<..., char *> payload
        for m in result_matches:
            tier = "keep" if is_boundary else "semantic"
            add(tier, "result-char-ptr", m, "Result<..., String/Str>",
                "错误载荷改为 String/Str 需确认错误值的寿命")

        # auto printf of a cstr() (exact "%s" / "%s\n" shape)
        auto_printf = AUTO_PRINTF.search(raw_code)
        if auto_printf:
            nl = auto_printf.group(1)
            recv = auto_printf.group(2)
            add("auto", "printf-cstr", auto_printf,
                "%s.%s()" % (recv, "println" if nl else "print"),
                "`printf(\"%s\")` + `cstr()` 是 print API 的机械替代")

        # char * sites (type arguments excluded)
        for m in CHAR_PTR.finditer(code):
            if _inside(m.start(), masked):
                continue
            if is_boundary:
                add("keep", "char-ptr", m, "保留 char *",
                    "已登记的 C 互操作/ABI 边界")
            else:
                add("manual", "char-ptr", m, "String / Str",
                    "按“过这行还要活着”选 owner 或 view；字段/返回需先定寿命")

        # non-self arrow sites
        for m in ARROW.finditer(code):
            recv = code[:m.start()].rstrip()
            word = re.search(r"([A-Za-z_]\w*)$", recv)
            if word and word.group(1) in ("self", "_self"):
                continue  # Ct receiver syntax, not a user pointer
            in_box = bool(word and word.group(1) in box_vars)
            if is_boundary:
                add("keep", "arrow", m, "保留 ->", "C 结构体指针/映射单元语法")
            elif in_box:
                add("auto", "arrow", m, ".",
                    "接收者是 Box<T>；`b.f` 自动解引用")
            else:
                add("manual", "arrow", m, ".",
                    "普通结构体指针需先改 Box<T>/ref 形参")

        # malloc / free / delete / own
        own_matches = list(OWN_PTR.finditer(code))
        malloc_matches = list(MALLOC.finditer(code))
        for m in malloc_matches:
            if is_boundary:
                add("keep", "malloc", m, "保留 malloc", "C 堆互操作/生命周期夹具")
            elif own_matches:
                add("semantic", "own-malloc", m, "Box<T> + new（或保留 own 通道）",
                    "own T* 的所有权转移语义要逐条确认")
            else:
                add("semantic", "malloc", m, "Box<T> p = new T { ... }",
                    "单对象堆分配改 Box；字段初值需补全")
        if not malloc_matches:
            for m in own_matches:
                if is_boundary:
                    add("keep", "own-ptr", m, "保留 own T*", "C 生命周期夹具")
                else:
                    add("semantic", "own-ptr", m, "Box<T> + new",
                        "own 的自动释放时点与 Box 的显式 release 不同")
        for m in FREE.finditer(code):
            if is_boundary:
                add("keep", "free", m, "保留 free", "C 堆互操作/生命周期夹具")
            else:
                add("manual", "free", m, "p.release()",
                    "handle 协议取代手工 free")
        for m in DELETE.finditer(code):
            if is_boundary:
                add("keep", "delete", m, "保留 delete", "C 生命周期夹具")
            else:
                add("manual", "delete", m, "p.release()",
                    "Box/Vec/Map 用 release()")

        # cstr() outside the auto print shape
        if not auto_printf:
            for m in CSTR.finditer(code):
                if is_boundary:
                    add("keep", "cstr", m, "保留 cstr()", "C 字符串出口")
                else:
                    add("semantic", "cstr", m, "print()/println()",
                        "cstr() 分配并交给 C；改用 print 还是保留取决于接收方")

        # generic struct pointer declarations (non-char, non-own)
        for m in GENERIC_PTR.finditer(code):
            base = m.group(1)
            if base in NOT_STRUCT_PTR or base == "char":
                continue
            if own_matches or malloc_matches:
                continue
            if _inside(m.start(), masked):
                continue
            # Reduce multiplication false positives: require an explicit
            # `struct` keyword or a capitalised user type.
            before = code[:m.start()]
            explicit = bool(re.search(r"\bstruct\s+$", before))
            if not explicit and not base[:1].isupper():
                continue
            if is_boundary:
                add("keep", "struct-ptr", m, "保留 T *", "C 结构体指针")
            elif explicit:
                add("semantic", "struct-ptr", m, "Box<T> / ref T",
                    "显式 struct * 的布局/所有权要先确认")
            else:
                add("manual", "struct-ptr", m, "Box<T> / ref T",
                    "结构体指针改 owning 句柄或 ref 形参")

        # printf("%s") without the cstr auto shape
        if not auto_printf:
            for m in PRINTF_S.finditer(raw_code):
                tier = "keep" if is_boundary else "manual"
                add(tier, "printf-s", m, "x.print() / x.println()",
                    "非 C 边界时字符串输出走 print API")

    return findings


def iter_files(root, roots):
    for top in roots:
        base = os.path.join(root, top)
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames.sort()
            for name in sorted(filenames):
                if name.endswith(".ct"):
                    full = os.path.join(dirpath, name)
                    yield os.path.relpath(full, root), full


def summarize(findings):
    totals = {tier: 0 for tier in TIERS + ("keep",)}
    for finding in findings:
        totals[finding.tier] += 1
    migratable = totals["auto"] + totals["manual"] + totals["semantic"]
    pct = {tier: (100.0 * totals[tier] / migratable if migratable else 0.0)
           for tier in TIERS}
    return totals, migratable, pct


def print_text(findings, files_seen, roots, skipped, keep_reasons):
    totals, migratable, pct = summarize(findings)
    print("migration lint dry-run (P-1.3)")
    print("corpus: %s - %d .ct file(s)" % ("/".join(roots), files_seen))
    print()
    print("tier                sites    pct")
    print("-----------------  ------  -----")
    for tier in TIERS:
        label = "%s %s" % (tier, TIER_ZH[tier])
        print("%-17s  %6d  %5.1f%%" % (label, totals[tier], pct[tier]))
    print("%-17s  %6d" % ("migratable total", migratable))
    print("%-17s  %6d" % ("C boundary keep", totals["keep"]))
    for reason, count in sorted(keep_reasons.items(), key=lambda kv: -kv[1]):
        print("    keep: %-58s %5d file(s)" % (reason[:58], count))
    if skipped:
        print("%-17s  %6d" % ("long lines skipped", skipped))
    print()

    by_root = {}
    for finding in findings:
        if finding.tier == "keep":
            continue
        top = finding.path.split(os.sep, 1)[0]
        by_root.setdefault(top, {t: 0 for t in TIERS})[finding.tier] += 1
    if by_root:
        print("per root (migratable sites):")
        for top in roots:
            row = by_root.get(top, {t: 0 for t in TIERS})
            total = sum(row.values())
            if not total:
                print("  %-10s  %6d" % (top, 0))
                continue
            print("  %-10s  %6d  auto %d (%.1f%%)  manual %d (%.1f%%)  semantic %d (%.1f%%)"
                  % (top, total, row["auto"], 100.0 * row["auto"] / total,
                     row["manual"], 100.0 * row["manual"] / total,
                     row["semantic"], 100.0 * row["semantic"] / total))
        print()

    rules = {}
    for finding in findings:
        if finding.tier == "keep":
            continue
        key = (finding.tier, finding.rule)
        rules[key] = rules.get(key, 0) + 1
    if rules:
        print("top rules:")
        for (tier, rule), count in sorted(rules.items(), key=lambda kv: -kv[1])[:12]:
            print("  %-8s %-16s %6d" % (tier, rule, count))
        print()
    print("dry-run only: no file was modified.")


def print_json(findings, files_seen, roots, skipped):
    totals, migratable, pct = summarize(findings)
    payload = {
        "tool": "migrate_lint",
        "version": 1,
        "roots": list(roots),
        "files": files_seen,
        "skipped_long_lines": skipped,
        "totals": totals,
        "migratable": migratable,
        "percent": {tier: round(pct[tier], 2) for tier in TIERS},
        "findings": [f.as_dict() for f in findings],
    }
    json.dump(payload, sys.stdout, ensure_ascii=False, indent=2)
    sys.stdout.write("\n")


def print_tsv(findings):
    print("path\tline\ttier\trule\tsuggestion\tcode")
    for finding in findings:
        print("\t".join((
            finding.path, str(finding.line), finding.tier, finding.rule,
            finding.suggestion.replace("\t", " "),
            finding.text.replace("\t", " ")[:200])))


def print_files(findings, files_seen):
    """One row per file with findings (path, boundary, tier counts)."""
    rows = {}
    for finding in findings:
        row = rows.setdefault(finding.path, {"auto": 0, "manual": 0,
                                             "semantic": 0, "keep": 0})
        row[finding.tier] += 1
    print("path\tboundary\tauto\tmanual\tsemantic\tkeep\ttotal")
    for path in sorted(rows):
        row = rows[path]
        total = row["auto"] + row["manual"] + row["semantic"] + row["keep"]
        print("%s\t%s\t%d\t%d\t%d\t%d\t%d"
              % (path, "1" if row["keep"] else "0", row["auto"], row["manual"],
                 row["semantic"], row["keep"], total))


def selftest():
    """Positive/negative fixtures for the three tiers; no filesystem writes."""
    cases = []
    # 1. clean, already-migrated Ct: no findings at all.
    cases.append(("clean", "struct P { int x; }\nint main(void) { P p; p.x = 1; return p.x; }\n", 0, 0, 0, 0))
    # 2. array suffix is auto; initializer-length array is not a finding.
    cases.append(("array-auto", "void f(int a[]) { }\nint b[] = { 1, 2 };\n", 1, 0, 0, 0))
    # 3. char * and manual arrow are manual.
    cases.append(("manual", "char *s = \"x\";\nstruct P *p;\np->x = 1;\n", 0, 2, 1, 0))
    # 4. cstr() and own T* are semantic.
    cases.append(("semantic", "own P *q = malloc(sizeof(struct P));\nx.cstr();\nown P *r;\n", 0, 0, 3, 0))
    # 5. registered C boundary keeps its pointers out of the three tiers.
    cases.append(("boundary", "char *buf = malloc(8);\nu->x = 1;\n", 0, 0, 0, 3, True))
    # 6. comments and string literals never match; self-> is receiver syntax.
    cases.append(("decoy", "/* char *x; p->y; malloc(1) */\nprintf(\"p->y char *\");\nself->f = 1;\n", 0, 0, 0, 0))
    # 7. printf("%s", s.cstr()) is the one auto print shape.
    cases.append(("printf-auto", "printf(\"%s\\n\", msg.cstr());\n", 1, 0, 0, 0))
    # 8. Map<char *,V> is a manual key migration.
    cases.append(("map-key", "Map<char *, int> m;\n", 0, 0, 1, 0))

    failed = 0
    for case in cases:
        name, text = case[0], case[1]
        want = case[2:6]
        boundary = len(case) > 6 and case[6]
        findings = scan_text(text, "fixture.ct", boundary=boundary)
        totals = {tier: 0 for tier in TIERS + ("keep",)}
        for finding in findings:
            totals[finding.tier] += 1
        got = (totals["auto"], totals["manual"], totals["semantic"],
               totals["keep"])
        if got != tuple(want):
            failed += 1
            print("migration-lint selftest: FAIL %s (want %s, got %s)"
                  % (name, tuple(want), got))
            for finding in findings:
                print("  %s:%s %s %s" % (finding.path, finding.line,
                                         finding.tier, finding.rule))
        else:
            print("migration-lint selftest: ok %s" % name)
    # Corpus/corpus-boundary fixtures: `keep` decisions are what make the
    # three-tier percentage meaningful, so pin them too.
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    corpus_cases = [
        ("keep-lib", "lib/core/Vec.h.ct", "", set(), "builtin"),
        ("keep-negative", "test/errors/too_many_fields.ct", "", set(), "negative"),
        ("keep-allow-tsv", "docs/snippets/README/0.13_c_boundary.ct", "", set(), "registered"),
        ("keep-map", "examples/06_iface_field/iface_field.ct",
         "map trait X for instance y { }", set(), "map-binding"),
        ("not-keep", "examples/99_clean/prog.ct", "int main(void) { return 0; }",
         set(), None),
    ]
    for name, rel, text, dirs, want in corpus_cases:
        got = boundary_reason(root, rel, text, dirs)
        if want is None:
            ok = got is None
        else:
            ok = bool(got) and want in got
        if not ok:
            failed += 1
            print("migration-lint selftest: FAIL %s (want %r, got %r)"
                  % (name, want, got))
        else:
            print("migration-lint selftest: ok %s" % name)

    if failed:
        print("migration-lint selftest: FAIL (%d case(s))" % failed)
        return 2
    print("migration-lint selftest: OK (%d cases)" % (len(cases) + len(corpus_cases)))
    return 0


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true",
                        help="scan and report; never writes (default)")
    parser.add_argument("--list", action="store_true",
                        help="print one line per finding")
    parser.add_argument("--format", choices=("text", "json", "tsv"),
                        default="text")
    parser.add_argument("--files", action="store_true",
                        help="one TSV row per file (path/tier counts)")
    parser.add_argument("--selftest", action="store_true")
    parser.add_argument("--root", default=os.path.dirname(os.path.dirname(
        os.path.abspath(__file__))))
    parser.add_argument("--roots", default=",".join(ROOTS),
                        help="comma separated roots (default examples,test,lib)")
    args = parser.parse_args(argv)

    if args.selftest:
        return selftest()

    root = os.path.abspath(args.root)
    roots = tuple(x.strip() for x in args.roots.split(",") if x.strip())
    if not roots:
        print("migrate_lint: no roots", file=sys.stderr)
        return 1

    findings = []
    files_seen = 0
    skipped = 0
    dirs = boundary_dirs(root, roots)
    keep_reasons = {}
    for rel, full in iter_files(root, roots):
        files_seen += 1
        try:
            with open(full, encoding="utf-8", errors="replace") as handle:
                text = handle.read()
        except OSError as exc:
            print("migrate_lint: cannot read %s: %s" % (rel, exc), file=sys.stderr)
            return 1
        reason = boundary_reason(root, rel, text, dirs)
        boundary = reason is not None
        if boundary:
            keep_reasons[reason] = keep_reasons.get(reason, 0) + 1
            findings.extend(scan_text(text, rel, boundary=True))
        else:
            findings.extend(scan_text(text, rel, boundary=False))
        skipped += sum(1 for line in text.splitlines() if len(line) > MAX_LINE)

    findings.sort(key=lambda f: (f.path, f.line, f.tier, f.rule))
    if args.format == "json":
        print_json(findings, files_seen, roots, skipped)
    elif args.format == "tsv":
        print_tsv(findings)
    elif args.files:
        print_files(findings, files_seen)
    else:
        print_text(findings, files_seen, roots, skipped, keep_reasons)
        if args.list:
            print()
            for tier in TIERS:
                rows = [f for f in findings if f.tier == tier]
                if not rows:
                    continue
                print("== %s (%d) ==" % (tier, len(rows)))
                for finding in rows:
                    print("%s:%d  %-14s %s" % (finding.path, finding.line,
                                               finding.rule,
                                               finding.suggestion))
            keep = [f for f in findings if f.tier == "keep"]
            if keep:
                print("== keep / C boundary (%d; excluded) ==" % len(keep))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
