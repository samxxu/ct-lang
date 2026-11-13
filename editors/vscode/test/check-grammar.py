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
import shutil
import subprocess
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
    "test/modules/alias/src/main.ct",
    "test/archive/cases/22_drop.ct",
    # Phase 5 AutoDrop (`own`) lives on the CT line only, so its fixture is under
    # test/modules rather than test/cases.
    "test/modules/autodrop/prog.ct",
    # Phase 11.1 `map`: a CT-line-only construct (ct-ast).
    "test/ast/13_map_instance/prog.ct",
    # Batch 36 trait default methods: a body may live in the trait itself.
    "test/ast/57_trait_default/prog.ct",
    # Phase 4.40 `borrow` / `Handback`: a contextual keyword in both its
    # statement-initial and parameter-annotation forms.
    "test/ast/62_borrow_handback/prog.ct",
    # Phase 17.3 raw passthrough: the marker pair, with a macro and a C
    # function inside that must not be read as a CT construct.
    "test/ast/65_raw/prog.ct",
    # Batch 38 zero-cost static mapping: `.m.ct` units with `for type` and
    # `for namespace` hosts, plus the call sites that consume them.
    "test/modules/map_unit/libc/libc.m.ct",
    "test/modules/map_unit/main.ct",
    "test/modules/map_unit_type/ctypes/ctypes.m.ct",
    # Phase 24 range initializer: the `$` index is a token of its own in the
    # expression, and `0..13` must not be mistaken for anything else.
    "test/ast/109_range_init_basic/prog.ct",
    # Phase 20 type alias: `type` / `pub type` is contextual, not a C keyword.
    "test/ast/67_type_alias/lib/lib.m.ct",
    # Phase 21 closures: `=>` is the closure arrow.
    "test/ast/70_closure_basic/prog.ct",
    # Phase 22/23 `loop`: the keyword only exists in statement position.
    "test/ast/100_loop_contextual_label/prog.ct",
    "test/ast/102_loop_range_basic/prog.ct",
    # Phase 26 generics: declaration, call and the type-argument spellings.
    "test/ast/123_generic_identity/prog.ct",
    "test/ast/124_generic_struct/prog.ct",
    "test/ast/125_generic_type_positions/prog.ct",
    "test/ast/128_generic_type_operands/prog.ct",
    # Phase 29: `foreach`, the built-in `Vec` / `Map` protocol, generic
    # structs with their `impl<T>` blocks, trait-constrained generics and the
    # range initializer on a `Vec` as well as on an array.
    "examples/21_generic_bound/generic_bound.ct",
    "examples/22_foreach_map/foreach_map.ct",
    "examples/23_generic_stack/generic_stack.ct",
    "examples/24_vec_ops/vec_ops.ct",
    "examples/26_range_vec/range_vec.ct",
    "test/ast/138_generic_struct/prog.ct",
    "test/ast/147_generic_impl/prog.ct",
    # Phase 30: the receiver-context block (`expr into { ... }`), including the
    # `->field` / `[i]` suffixes and the `int into = 1;` look-alike.
    "examples/29_into_block/into.ct",
    # C11 / GNU surfaces that the CT line accepts verbatim.
    "test/ast/42_static_assert/prog.ct",
    "test/ast/53_c11_align_generic/prog.ct",
    "test/ast/55_c_compat/prog.ct",
    "test/ast/56_header_compat/prog.ct",
    # 2b.3 qualified map host (`hal::uart1`) and its recipe body.
    "test/modules/map_ns/hal/uart.h.ct",
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
# Headers whose tokens are split by an inline comment: the strict one-line rules
# do not fire, the `*-open` fallbacks must.
EXTRA = "\n".join([
    "int pub = 1;",
    "pub int exported(void);",
    "impl Greeter /* note */ for Person {",
    "map trait Controller /* note */ for instance uart1 {",
])
# Phase 24: `$` is the range index. It must be highlighted in the initializer
# and must stay invisible inside a string or a comment -- the same guarantee
# that the compiler's lexer makes before the parser ever sees a `$`.
RANGE = "\n".join([
    "int odd[] = 0..13($ * 2 + 1);",
    'char *s = "$";',
    "// $ is not code here",
])
# Phase 26 generics: the declaration header is line-anchored, the call needs a
# closing `>` and an argument list, and `return` is not a return type.
GENERIC = "\n".join([
    "T id<T>(T x)",
    "{",
    "    return x;",
    "}",
    "int f(void)",
    "{",
    "    return id<int>(42);",
    "}",
    "int g(void)",
    "{",
    "    if (a < b) f();",
    "    return 0;",
    "}",
])
# Phase 22/23: `loop` is a keyword only as `loop(`; `..` excludes `...`.
LOOP = "\n".join([
    "    loop(2) {",
    "    int loop = 5;",
    "loop:",
    "    goto loop;",
    "    loop(2..5) {",
    "    case 0 ... 59:",
    "int f(int a, ...);",
])
# Phase 21: `=>` only, never `>=` or `->`.
CLOSURE = "\n".join([
    "    int (*add)(int x) = (int x) => x + 1;",
    "    if (a >= b) {",
    "    p->x = 1;",
])
# Phase 29: `foreach` is a keyword only as `foreach(`; the entry pair
# `item.key` / `item.value` is the Map protocol and nothing else is special.
FOREACH = "\n".join([
    "    foreach (nums) {",
    "        sum = sum + item;",
    "    }",
    "    int foreach = 3;",
    "foreach:",
    "    goto foreach;",
    "    foreach (ages) {",
    "        printf(\"%s is %d\", item.key, item.value);",
    "    }",
    "    p.item = 2;",
])
# Phase 30: `into` only when a `{` follows; a leading `.member` starts the
# block body and the inline spelling is the same construct.
INTO = "\n".join([
    "    cfg into {",
    "        .host = \"0.0.0.0\";",
    "        .port = 8080;",
    "        report($);",
    "    };",
    "    int into = 1;",
    "    if (into) {",
    "    int p2 = cfg into { .backlog = 64; } ->port;",
    "    x = mk() into { .x = 1; }.add(2);",
    "    Stage s = p into { .flag = 1; }[1];",
    "    p.host = 1;",
])
# Phase 29 generics: the type-instantiation position (a declarator, not a
# call), the static `Vec<T>::from` path, and the `impl<T>` header.
GENERIC29 = "\n".join([
    "    Vec<int> nums;",
    "    Map<char *, int> ages;",
    "    Vec<char *>::from(names, 3);",
    "    sq.len();",
    "    v.push(4);",
    "    Box<Box<int>> tight;",
    "    Pair<char *, Box<int>> mixed;",
    "    T max2<T: Ord>(T a, T b)",
    "    max2<int>(a, b);",
    "    struct Stack<T> {",
    "    pub struct Pair<T, U> {",
    "    impl<T> Stack<T> {",
    "    impl<T> Stack<T> use Show {",
    "    if (a < b) f();",
    "    return a < b;",
    "    t.each(fn, env);",
])
# Phase 20: `type` is contextual and anchored at line start.
ALIAS = "\n".join([
    "pub type Text  = char *;",
    "type Count = int;",
    "map trait TextOps for type Text {",
])
# `_Static_assert` and its C11 alias.
ASSERTS = "\n".join([
    '_Static_assert(sizeof(int) == 4, "four");',
    'static_assert(sizeof(char) == 1, "one");',
])
# C11 keywords accepted by the CT type parser.
C11 = "\n".join([
    "_Alignas(16) int g;",
    "_Alignof(int)",
    "_Alignof T",
    "alignof(T)",
    "_Atomic(int) c;",
    "_Generic(i, int: 1, default: 0)",
    "_Noreturn void stop(void);",
    "_Thread_local int t;",
    "_Bool b;",
    "_Complex double z;",
    "__attribute__((aligned(32))) int a;",
])
# Phase 40: errdefer and the err: marker.
P40 = "int f(void) { errdefer { } return err: 1; }"
# Phase 41: contextual atomic and the ct_atomic_* builtins.
P41 = "int f(void) { atomic int n = 0; ct_atomic_store(&n, 1); return ct_atomic_load(&n); }"
# 2b.3 qualified instance host plus a recipe body; a plain C member call must
# not be read as a recipe.
MAP = "\n".join([
    "map trait Writer for instance hal::uart1 {",
    "    write(buf, len) -> uart_put;",
    "    dog_get()->hi();",
])
# New tokens inside a string / comment are not code, exactly like `$` above.
QUOTED = "\n".join([
    'char *s = "T id<T>(T x) loop(2..5) => _Static_assert '
    '_Alignof T _Generic __attribute__ pub type Text = '
    'foreach (x) { into { .host = 1; } } Vec<int> Box<int> '
    'impl<T> item.key v.push()";',
    "// T id<T>(T x) loop(2..5) => _Static_assert "
    "_Alignof T _Generic __attribute__ type Text = "
    "foreach (x) { into { .host = 1; } } Vec<int> Box<int> "
    "impl<T> item.key v.push()",
])
NEW_RULES = {
    "ct-type-alias", "ct-generic-decl", "ct-generic-call", "ct-loop",
    "ct-range-dots", "ct-closure-arrow", "ct-static-assert", "ct-alignas",
    "ct-alignof", "ct-alignof-type", "ct-atomic", "ct-generic-select",
    "ct-noreturn", "ct-thread-local", "ct-c11-builtin-types", "ct-attribute",
    "ct-recipe", "ct-generic-struct", "ct-generic-impl", "ct-generic-type",
    "ct-generic-static-call", "ct-foreach", "ct-into", "ct-into-field",
    "ct-into-method", "ct-into-inline-field", "ct-into-inline-method",
    "ct-foreach-entry", "ct-container-method",
}


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
        if "modules/alias" in rel:
            imports = [t for n2, t in all_hits if n2 == "ct-import"]
            check("every `import` line -> ct-import",
                  len(imports) == len([l for _, l, _ in rows if l.strip().startswith("import ")]),
                  str(imports))
            check("`import app::model::Point as Point;` -> ct-import",
                  any(" as " in t for t in imports), str(imports))
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
        if "62_borrow_handback" in rel:
            check("line-start `borrow Conn *a` -> ct-borrow",
                  any(h[0] == "ct-borrow" for _, l, hs in rows
                      if l.strip().startswith("borrow ") for h in hs))
            check("`render(borrow struct Conn *c)` -> ct-borrow-param",
                  any(h[0] == "ct-borrow-param" for _, l, hs in rows
                      if "render(borrow " in l for h in hs))
        if "13_map_instance" in rel:
            check("`map trait T for instance x {` -> ct-map",
                  any(h[0] == "ct-map" for _, l, hs in rows
                      if l.strip().startswith("map ") for h in hs))
        if "libc.m.ct" in rel:
            check("`map trait T for type char * {` -> ct-map-type",
                  any(h[0] == "ct-map-type" for _, l, hs in rows
                      if l.strip().startswith("map ") and " for type " in l for h in hs))
            check("`map trait T for namespace n {` -> ct-map-namespace",
                  any(h[0] == "ct-map-namespace" for _, l, hs in rows
                      if l.strip().startswith("map ") and " for namespace " in l for h in hs))
            check("recipe `toInt(s) -> ...` -> ct-recipe",
                  any(h[0] == "ct-recipe" for _, l, hs in rows
                      if "->" in l and l.strip().endswith(";") for h in hs))
        if "57_trait_default" in rel:
            check("trait with default bodies -> ct-trait",
                  any(h[0] == "ct-trait" for _, l, hs in rows
                      if l.strip().startswith("trait ") for h in hs))
            check("`self->` inside a default body -> ct-self",
                  any(h[0] == "ct-self" for _, l, hs in rows if "self->" in l for h in hs))
        if "65_raw" in rel:
            check("`#ct-raw` at column 1 -> ct-raw",
                  any(h[0] == "ct-raw" for _, l, hs in rows
                      if l.strip() == "#ct-raw" for h in hs))
            check("`#ct-endraw` -> ct-raw-end",
                  any(h[0] == "ct-raw-end" for _, l, hs in rows
                      if l.strip() == "#ct-endraw" for h in hs))
            check("no CT keyword rule fires inside the raw block",
                  not any(h[0] in ("ct-use", "ct-self", "ct-trait", "ct-impl",
                                  "ct-own", "ct-borrow", "ct-pub")
                          for _, l, hs in rows if "TRIPLE" in l or "raw_helper" in l
                          for h in hs))
        if "109_range_init" in rel:
            check("`$` in the range initializer -> ct-range-index",
                  any(h[0] == "ct-range-index" for _, l, hs in rows
                      if "0..13(" in l for h in hs))
            check("`0..13` -> ct-range-dots",
                  any(h[0] == "ct-range-dots" for _, l, hs in rows
                      if "0..13(" in l for h in hs))
        if "67_type_alias" in rel:
            check("`pub type Text` -> ct-type-alias",
                  any(h[0] == "ct-type-alias" for _, l, hs in rows
                      if "pub type Text" in l for h in hs))
            check("`pub type Count` -> ct-type-alias",
                  any(h[0] == "ct-type-alias" for _, l, hs in rows
                      if "pub type Count" in l for h in hs))
            check("`map ... for type Text` is not a type alias",
                  not any(h[0] == "ct-type-alias" for _, l, hs in rows
                          if "for type Text" in l for h in hs))
        if "70_closure_basic" in rel:
            check("`(int x) => ...` -> ct-closure-arrow",
                  any(h[0] == "ct-closure-arrow" for _, l, hs in rows
                      if "=>" in l for h in hs))
        if "100_loop_contextual_label" in rel:
            check("statement `loop(2)` -> ct-loop",
                  any(h[0] == "ct-loop" for _, l, hs in rows
                      if l.strip().startswith("loop(2)") for h in hs))
            check("`int loop = 5;` is not ct-loop",
                  not any(h[0] == "ct-loop" for _, l, hs in rows
                          if "int loop = 5" in l for h in hs))
            check("label `loop:` is not ct-loop",
                  not any(h[0] == "ct-loop" for _, l, hs in rows
                          if l.strip() == "loop:" for h in hs))
            check("`goto loop;` is not ct-loop",
                  not any(h[0] == "ct-loop" for _, l, hs in rows
                          if "goto loop" in l for h in hs))
        if "102_loop_range_basic" in rel:
            check("`loop(2..5)` -> ct-loop + ct-range-dots",
                  any(h[0] == "ct-loop" for _, l, hs in rows
                      if "loop(2..5)" in l for h in hs)
                  and any(h[0] == "ct-range-dots" for _, l, hs in rows
                          if "loop(2..5)" in l for h in hs))
        if "123_generic_identity" in rel:
            check("`T id<T>(T x)` -> ct-generic-decl",
                  any(h[0] == "ct-generic-decl" for _, l, hs in rows
                      if l.strip().startswith("T id<T>") for h in hs))
            check("`id<int>(42)` -> ct-generic-call",
                  any(h[0] == "ct-generic-call" for _, l, hs in rows
                      if "id<int>" in l for h in hs))
            check("`id<char *>(p)` -> ct-generic-call",
                  any(h[0] == "ct-generic-call" for _, l, hs in rows
                      if "id<char *>" in l for h in hs))
        if "124_generic_struct" in rel:
            check("`pass<struct Point>(a)` -> ct-generic-call",
                  any(h[0] == "ct-generic-call" for _, l, hs in rows
                      if "pass<struct Point>" in l for h in hs))
        if "125_generic_type_positions" in rel:
            check("`pick<int>(...)` -> ct-generic-call",
                  any(h[0] == "ct-generic-call" for _, l, hs in rows
                      if "pick<int>" in l for h in hs))
            check("`offY<struct Pair>(...)` -> ct-generic-call",
                  any(h[0] == "ct-generic-call" for _, l, hs in rows
                      if "offY<struct Pair>" in l for h in hs))
            check("`_Alignof(T)` -> ct-alignof",
                  any(h[0] == "ct-alignof" for _, l, hs in rows
                      if "_Alignof(T)" in l for h in hs))
        if "128_generic_type_operands" in rel:
            check("`_Alignof T` (no parens) -> ct-alignof-type",
                  any(h[0] == "ct-alignof-type" for _, l, hs in rows
                      if "_Alignof T" in l for h in hs))
            check("`alignof(T)` -> ct-alignof",
                  any(h[0] == "ct-alignof" for _, l, hs in rows
                      if "alignof(T)" in l for h in hs))
            check("`alignof(T)` is not ct-alignof-type",
                  not any(h[0] == "ct-alignof-type" for _, l, hs in rows
                          if "alignof(T)" in l for h in hs))
        if "21_generic_bound" in rel:
            check("`void sort<T: Compare>(...)` -> ct-generic-decl",
                  any(h[0] == "ct-generic-decl" for _, l, hs in rows
                      if "sort<T: Compare>" in l for h in hs))
            check("`sort<struct Num>(...)` -> ct-generic-call",
                  any(h[0] == "ct-generic-call" for _, l, hs in rows
                      if "sort<struct Num>" in l for h in hs))
        if "22_foreach_map" in rel:
            check("`foreach (nums) {` -> ct-foreach",
                  any(h[0] == "ct-foreach" for _, l, hs in rows
                      if l.strip().startswith("foreach (nums)") for h in hs))
            check("`item.key` / `item.value` -> ct-foreach-entry",
                  any(h[0] == "ct-foreach-entry" for _, l, hs in rows
                      if "item.key" in l for h in hs))
            check("`nums.push(...)` -> ct-container-method",
                  any(h[0] == "ct-container-method" for _, l, hs in rows
                      if "nums.push(" in l for h in hs))
            check("`nums.get(0)` -> ct-container-method",
                  any(h[0] == "ct-container-method" for _, l, hs in rows
                      if "nums.get(0)" in l for h in hs))
        if "23_generic_stack" in rel:
            check("`struct Stack<T> {` -> ct-generic-struct",
                  any(h[0] == "ct-generic-struct" for _, l, hs in rows
                      if l.strip().startswith("struct Stack<T>") for h in hs))
            check("`impl<T> Stack<T> {` -> ct-generic-impl",
                  any(h[0] == "ct-generic-impl" for _, l, hs in rows
                      if l.strip().startswith("impl<T> Stack<T>") for h in hs))
            check("`Stack<int> a;` -> ct-generic-type",
                  any(h[0] == "ct-generic-type" for _, l, hs in rows
                      if l.strip().startswith("Stack<int>") for h in hs))
            check("`pa->push(12)` -> ct-container-method",
                  any(h[0] == "ct-container-method" for _, l, hs in rows
                      if "pa->push(" in l for h in hs))
        if "24_vec_ops" in rel:
            check("`v.push(...)` -> ct-container-method",
                  any(h[0] == "ct-container-method" for _, l, hs in rows
                      if "v.push(" in l for h in hs))
            check("`v.len()` -> ct-container-method",
                  any(h[0] == "ct-container-method" for _, l, hs in rows
                      if "v.len()" in l for h in hs))
            check("`foreach (v) {` -> ct-foreach",
                  any(h[0] == "ct-foreach" for _, l, hs in rows
                      if l.strip().startswith("foreach (v)") for h in hs))
        if "26_range_vec" in rel:
            check("`Vec<int> sq = 4..8 {` -> ct-generic-type",
                  any(h[0] == "ct-generic-type" for _, l, hs in rows
                      if "Vec<int> sq" in l for h in hs))
            check("`4..8` -> ct-range-dots",
                  any(h[0] == "ct-range-dots" for _, l, hs in rows
                      if "4..8" in l for h in hs))
            check("`$ * $` -> ct-range-index",
                  any(h[0] == "ct-range-index" for _, l, hs in rows
                      if "4..8" in l for h in hs))
        if "138_generic_struct" in rel:
            check("`struct Pair<T, U> {` -> ct-generic-struct",
                  any(h[0] == "ct-generic-struct" for _, l, hs in rows
                      if l.strip().startswith("struct Pair<T, U>") for h in hs))
            check("`Pair<int, char *> p;` -> ct-generic-type",
                  any(h[0] == "ct-generic-type" for _, l, hs in rows
                      if l.strip().startswith("Pair<int, char *>") for h in hs))
        if "147_generic_impl" in rel:
            check("`impl<T> Pair<T, int> {` -> ct-generic-impl",
                  any(h[0] == "ct-generic-impl" for _, l, hs in rows
                      if l.strip().startswith("impl<T> Pair<T, int>") for h in hs))
            check("`impl<T> Stack<T> use Show {` -> ct-generic-impl",
                  any(h[0] == "ct-generic-impl" for _, l, hs in rows
                      if l.strip().startswith("impl<T> Stack<T> use Show") for h in hs))
        if "29_into_block" in rel:
            check("`cfg into {` -> ct-into",
                  any(h[0] == "ct-into" for _, l, hs in rows
                      if "cfg into {" in l for h in hs))
            check("leading `.host = ...` -> ct-into-field",
                  any(h[0] == "ct-into-field" for _, l, hs in rows
                      if l.strip().startswith(".host") for h in hs))
            check("`report($)` -> ct-range-index",
                  any(h[0] == "ct-range-index" for _, l, hs in rows
                      if "report($)" in l for h in hs))
            check("`int into = 1;` is not ct-into",
                  not any(h[0] == "ct-into" for _, l, hs in rows
                          if "int into = 1" in l for h in hs))
            check("`live.host` is not ct-into-field",
                  not any(h[0] == "ct-into-field" for _, l, hs in rows
                          if "live.host" in l for h in hs))
        if "42_static_assert" in rel:
            check("`_Static_assert` -> ct-static-assert",
                  any(h[0] == "ct-static-assert" for _, l, hs in rows
                      if "_Static_assert" in l for h in hs))
        if "53_c11_align_generic" in rel:
            check("`_Alignas` -> ct-alignas",
                  any(h[0] == "ct-alignas" for _, l, hs in rows
                      if "_Alignas" in l for h in hs))
            check("`_Alignof(int)` -> ct-alignof",
                  any(h[0] == "ct-alignof" for _, l, hs in rows
                      if "_Alignof(int)" in l for h in hs))
            check("`_Alignof(int)` is not ct-alignof-type",
                  not any(h[0] == "ct-alignof-type" for _, l, hs in rows
                          if "_Alignof(int)" in l for h in hs))
            check("`_Generic` -> ct-generic-select",
                  any(h[0] == "ct-generic-select" for _, l, hs in rows
                      if "_Generic" in l for h in hs))
        if "55_c_compat" in rel:
            check("`static_assert` -> ct-static-assert",
                  any(h[0] == "ct-static-assert" for _, l, hs in rows
                      if "static_assert" in l and "_Static_assert" not in l
                      for h in hs))
            check("`_Noreturn` -> ct-noreturn",
                  any(h[0] == "ct-noreturn" for _, l, hs in rows
                      if "_Noreturn" in l for h in hs))
        if "56_header_compat" in rel:
            check("`_Atomic` -> ct-atomic",
                  any(h[0] == "ct-atomic" for _, l, hs in rows
                      if "_Atomic" in l for h in hs))
            check("`__attribute__` -> ct-attribute",
                  any(h[0] == "ct-attribute" for _, l, hs in rows
                      if "__attribute__" in l for h in hs))
        if "map_ns/hal/uart.h.ct" in rel:
            map_hits = [t for n2, t in all_hits if n2 == "ct-map"]
            check("qualified map host `hal::uart1` -> ct-map",
                  bool(map_hits) and "hal::uart1" in map_hits[0], str(map_hits))
            check("recipe `write(buf, len) -> ...` -> ct-recipe",
                  any(h[0] == "ct-recipe" for _, l, hs in rows
                      if "write(buf, len)" in l for h in hs))
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
    print("synthetic headers -- tokens split by comments:")
    rows = scan(EXTRA, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`int pub = 1;` does not fire ct-pub", "ct-pub" not in by_line[1], str(by_line[1]))
    check("line-start `pub int` -> ct-pub", "ct-pub" in by_line[2], str(by_line[2]))
    check("`impl ... /* */ ... for` -> ct-impl-open",
          "ct-impl-open" in by_line[3], str(by_line[3]))
    check("`map trait ... /* */ ...` -> ct-map-open",
          "ct-map-open" in by_line[4], str(by_line[4]))

    print()
    print("synthetic range index -- `$` is code only where the compiler says so:")
    rows = scan(RANGE, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`0..13($ * 2 + 1)` -> ct-range-index",
          "ct-range-index" in by_line[1], str(by_line[1]))
    check("`$` inside a string stays a string",
          "ct-range-index" not in by_line[2], str(by_line[2]))
    check("`$` inside a comment stays a comment",
          "ct-range-index" not in by_line[3], str(by_line[3]))

    print()
    print("synthetic generics -- declaration header vs call:")
    rows = scan(GENERIC, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`T id<T>(T x)` -> ct-generic-decl",
          "ct-generic-decl" in by_line[1], str(by_line[1]))
    check("`return id<int>(42);` -> ct-generic-call",
          "ct-generic-call" in by_line[7], str(by_line[7]))
    check("`return id<int>(42);` is not ct-generic-decl",
          "ct-generic-decl" not in by_line[7], str(by_line[7]))
    check("`if (a < b) f();` is not ct-generic-call",
          "ct-generic-call" not in by_line[11], str(by_line[11]))

    print()
    print("synthetic foreach -- statement form and the Map entry protocol:")
    rows = scan(FOREACH, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`foreach (nums) {` -> ct-foreach", "ct-foreach" in by_line[1], str(by_line[1]))
    check("bare `item` in the body is a plain identifier",
          "ct-foreach-entry" not in by_line[2] and "ct-foreach" not in by_line[2],
          str(by_line[2]))
    check("`int foreach = 3;` is not ct-foreach", "ct-foreach" not in by_line[4], str(by_line[4]))
    check("label `foreach:` is not ct-foreach", "ct-foreach" not in by_line[5], str(by_line[5]))
    check("`goto foreach;` is not ct-foreach", "ct-foreach" not in by_line[6], str(by_line[6]))
    check("`foreach (ages) {` -> ct-foreach", "ct-foreach" in by_line[7], str(by_line[7]))
    check("`item.key` / `item.value` -> ct-foreach-entry",
          "ct-foreach-entry" in by_line[8], str(by_line[8]))
    check("`p.item` is not ct-foreach-entry",
          "ct-foreach-entry" not in by_line[10], str(by_line[10]))

    print()
    print("synthetic into -- contextual keyword, block body and suffixes:")
    rows = scan(INTO, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`cfg into {` -> ct-into", "ct-into" in by_line[1], str(by_line[1]))
    check("leading `.host = ...` -> ct-into-field", "ct-into-field" in by_line[2], str(by_line[2]))
    check("leading `.port = ...` -> ct-into-field", "ct-into-field" in by_line[3], str(by_line[3]))
    check("`report($)` -> ct-range-index", "ct-range-index" in by_line[4], str(by_line[4]))
    check("`int into = 1;` is not ct-into", "ct-into" not in by_line[6], str(by_line[6]))
    check("`if (into) {` is not ct-into", "ct-into" not in by_line[7], str(by_line[7]))
    check("inline `{ .backlog = 64; }` -> ct-into-inline-field",
          "ct-into-inline-field" in by_line[8], str(by_line[8]))
    check("suffix `}.add(2);` stays outside the block",
          "ct-into-method" not in by_line[9] and "ct-into-inline-method" not in by_line[9],
          str(by_line[9]))
    check("suffix `}[1];` keeps the block highlights",
          "ct-into-inline-field" in by_line[10], str(by_line[10]))
    check("plain `p.host` is not ct-into-field",
          "ct-into-field" not in by_line[11], str(by_line[11]))

    print()
    print("synthetic generics 29 -- instantiation, static path and impl header:")
    rows = scan(GENERIC29, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`Vec<int> nums;` -> ct-generic-type",
          "ct-generic-type" in by_line[1], str(by_line[1]))
    check("`Map<char *, int> ages;` -> ct-generic-type",
          "ct-generic-type" in by_line[2], str(by_line[2]))
    check("`Vec<char *>::from(...)` -> ct-generic-static-call",
          "ct-generic-static-call" in by_line[3], str(by_line[3]))
    check("`sq.len()` -> ct-container-method",
          "ct-container-method" in by_line[4], str(by_line[4]))
    check("`v.push(4)` -> ct-container-method",
          "ct-container-method" in by_line[5], str(by_line[5]))
    check("`Box<Box<int>> tight;` -> ct-generic-type",
          "ct-generic-type" in by_line[6], str(by_line[6]))
    check("`Pair<char *, Box<int>> mixed;` -> ct-generic-type",
          "ct-generic-type" in by_line[7], str(by_line[7]))
    check("`T max2<T: Ord>(...)` -> ct-generic-decl",
          "ct-generic-decl" in by_line[8], str(by_line[8]))
    check("`max2<int>(...)` -> ct-generic-call",
          "ct-generic-call" in by_line[9], str(by_line[9]))
    check("`struct Stack<T> {` -> ct-generic-struct",
          "ct-generic-struct" in by_line[10], str(by_line[10]))
    check("`pub struct Pair<T, U> {` -> ct-generic-struct",
          "ct-generic-struct" in by_line[11], str(by_line[11]))
    check("`impl<T> Stack<T> {` -> ct-generic-impl",
          "ct-generic-impl" in by_line[12], str(by_line[12]))
    check("`impl<T> Stack<T> use Show {` -> ct-generic-impl",
          "ct-generic-impl" in by_line[13], str(by_line[13]))
    check("`if (a < b) f();` is not ct-generic-type",
          "ct-generic-type" not in by_line[14], str(by_line[14]))
    check("`return a < b;` is not ct-generic-type",
          "ct-generic-type" not in by_line[15], str(by_line[15]))
    check("`t.each(fn, env)` leaves `each` an ordinary method",
          "ct-foreach" not in by_line[16] and "ct-container-method" not in by_line[16],
          str(by_line[16]))

    print()
    print("synthetic loop / range -- statement position and `...` exclusion:")
    rows = scan(LOOP, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("statement `loop(2)` -> ct-loop", "ct-loop" in by_line[1], str(by_line[1]))
    check("`int loop = 5;` is not ct-loop", "ct-loop" not in by_line[2], str(by_line[2]))
    check("label `loop:` is not ct-loop", "ct-loop" not in by_line[3], str(by_line[3]))
    check("`goto loop;` is not ct-loop", "ct-loop" not in by_line[4], str(by_line[4]))
    check("`loop(2..5)` -> ct-loop + ct-range-dots",
          "ct-loop" in by_line[5] and "ct-range-dots" in by_line[5], str(by_line[5]))
    check("`...` in a case range is not ct-range-dots",
          "ct-range-dots" not in by_line[6], str(by_line[6]))
    check("`...` in a prototype is not ct-range-dots",
          "ct-range-dots" not in by_line[7], str(by_line[7]))

    print()
    print("synthetic closure arrow -- `=>` only:")
    rows = scan(CLOSURE, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`=>` -> ct-closure-arrow", "ct-closure-arrow" in by_line[1], str(by_line[1]))
    check("`>=` is not ct-closure-arrow", "ct-closure-arrow" not in by_line[2], str(by_line[2]))
    check("`->` is not ct-closure-arrow", "ct-closure-arrow" not in by_line[3], str(by_line[3]))

    print()
    print("synthetic type alias -- contextual and line-anchored:")
    rows = scan(ALIAS, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`pub type` -> ct-type-alias", "ct-type-alias" in by_line[1], str(by_line[1]))
    check("`type` -> ct-type-alias", "ct-type-alias" in by_line[2], str(by_line[2]))
    check("`map ... for type` is not ct-type-alias",
          "ct-type-alias" not in by_line[3], str(by_line[3]))

    print()
    print("synthetic static assert -- `_Static_assert` and its alias:")
    rows = scan(ASSERTS, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`_Static_assert` -> ct-static-assert",
          "ct-static-assert" in by_line[1], str(by_line[1]))
    check("`static_assert` -> ct-static-assert",
          "ct-static-assert" in by_line[2], str(by_line[2]))

    print()
    print("synthetic C11 keywords:")
    rows = scan(C11, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`_Alignas` -> ct-alignas", "ct-alignas" in by_line[1], str(by_line[1]))
    check("`_Alignof(int)` -> ct-alignof", "ct-alignof" in by_line[2], str(by_line[2]))
    check("`_Alignof(int)` is not ct-alignof-type",
          "ct-alignof-type" not in by_line[2], str(by_line[2]))
    check("`_Alignof T` -> ct-alignof-type",
          "ct-alignof-type" in by_line[3], str(by_line[3]))
    check("`alignof(T)` -> ct-alignof", "ct-alignof" in by_line[4], str(by_line[4]))
    check("`alignof(T)` is not ct-alignof-type",
          "ct-alignof-type" not in by_line[4], str(by_line[4]))
    check("`_Atomic` -> ct-atomic", "ct-atomic" in by_line[5], str(by_line[5]))
    check("`_Generic` -> ct-generic-select",
          "ct-generic-select" in by_line[6], str(by_line[6]))
    check("`_Noreturn` -> ct-noreturn", "ct-noreturn" in by_line[7], str(by_line[7]))
    check("`_Thread_local` -> ct-thread-local",
          "ct-thread-local" in by_line[8], str(by_line[8]))
    check("`_Bool` / `_Complex` -> ct-c11-builtin-types",
          "ct-c11-builtin-types" in by_line[9]
          and "ct-c11-builtin-types" in by_line[10],
          str([by_line[9], by_line[10]]))
    check("`__attribute__` -> ct-attribute",
          "ct-attribute" in by_line[11], str(by_line[11]))

    print()
    print("synthetic Phase 40 -- errdefer and err: marker:")
    rows = scan(P40, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`errdefer` / `err:` -> ct-errdefer + ct-err-colon",
          "ct-errdefer" in by_line[1] and "ct-err-colon" in by_line[1],
          str(by_line[1]))

    print()
    print("synthetic Phase 41 -- atomic modifier and ct_atomic_*:")
    rows = scan(P41, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("`atomic` / `ct_atomic_*` -> ct-atomic + ct-atomic-op",
          "ct-atomic" in by_line[1] and "ct-atomic-op" in by_line[1],
          str(by_line[1]))

    print()
    print("synthetic map host / recipe -- qualified path and `->` heuristic:")
    rows = scan(MAP, rules)
    by_line = {n: [h[0] for h in hs] for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    map_hits = [t for _, _, hs in rows for n2, t in hs if n2 == "ct-map"]
    check("qualified map host `hal::uart1` -> ct-map",
          bool(map_hits) and "hal::uart1" in map_hits[0], str(map_hits))
    check("recipe `write(buf, len) -> ...` -> ct-recipe",
          "ct-recipe" in by_line[2], str(by_line[2]))
    check("`dog_get()->hi();` is not ct-recipe",
          "ct-recipe" not in by_line[3], str(by_line[3]))

    print()
    print("synthetic quoted new tokens -- strings and comments stay opaque:")
    rows = scan(QUOTED, rules)
    by_line = {n: hs for n, _, hs in rows}
    for n, line, hits in rows:
        print("    %3d: %-22s %s" % (n, ", ".join(h[0] for h in hits), line.strip()))
    check("new tokens inside a string do not fire CT rules",
          not any(h[0] in NEW_RULES for h in by_line[1]), str(by_line[1]))
    check("new tokens inside a comment do not fire CT rules",
          not any(h[0] in NEW_RULES for h in by_line[2]), str(by_line[2]))

    # v0.26.4 / DOC-68: the go-to-definition scanner lives in ../indexer.js and
    # is asserted by a plain Node script. Node is not a prerequisite of the
    # compiler gates, so a missing runtime is a reported skip (the same
    # convention as the BSD-only probes in AGENTS.md), never a silent pass.
    print()
    print("== index checks ==")
    node = shutil.which("node")
    if node:
        index_test = os.path.join(HERE, "check-index.js")
        proc = subprocess.run([node, index_test], capture_output=True, text=True)
        out = (proc.stdout + proc.stderr).strip()
        print("    " + out.replace("\n", "\n    "))
        check("the indexer assertions pass", proc.returncode == 0,
              "exit %d" % proc.returncode)
    else:
        print("    skip (node not found)")

    print("== %d checks, %d failed ==" % (checks, len(failures)))
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
