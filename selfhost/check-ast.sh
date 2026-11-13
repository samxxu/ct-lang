#!/bin/sh
#
# check-ast.sh - the AST compiler's behavioural gate (Phase 9.1-9.7, 10.x, 11.x, 12.1).
#
# Builds the bootstrap chain (L0 -> L1 -> L2), then builds the AST compiler
# (selfhost/ct-ast/main.ct, D30: a separate tree in parallel with the old
# pipeline), and runs every fixture under test/ast/*/:
#
#   prog.ct -> ct-ast -> <name>.c (+ <name>.h only for a .h.ct input)
#           -> cc (warning-free) -> run -> compare stdout with prog.expected.out
#
# D34 defines equivalence as exit status + a warning-free build + identical
# program output; diagnostics and warnings are not compared. The negative
# fixture under test/ast/errors/ must exit non-zero.
#
# 9.5a adds a module section: `ct-ast build` on test/modules fixtures (imports,
# `pub` routing, namespace + `--ns-root`, `-I` roots), compared on behaviour
# too, plus the two negative module cases.
#
# 9.5b adds the metadata section: `--emit-map` (stdout and file), `#line` in
# build mode (default on) and `--line` / `--no-line` in both modes.
#
# 9.6 adds the self-hosting section: the AST compiler compiles its own source,
# the result builds warning-free, and the rebuilt compiler reproduces the same
# output byte for byte (a fixpoint).
#
# 9.7 adds the corpus-equivalence section: every `test/cases/*.ct` and
# `examples/*/*.ct` is compiled by ct-ast, built and run, then compared with its
# `expected.out` (D34: exit status + build + output, not the generated text).
# A case without `expected.out` is judged compile-only; a dialect demo is first
# expanded by its `ct-dialects/` plugin, since the compiler never sees the DSL.
#
# 10.3 adds the memory section: AutoDrop (`own`) fixtures and the conservative
# leak warnings in text and JSON (compile and build mode), all byte-diffed
# against L2's diagnostics.
#
# 10.4 adds the recovery section: multi_error fixtures (compile and build) plus
# the MAX_ERRORS cap, byte-diffed against L2 and artifact-free.
#
# 10.5 adds the cache section: cold/warm builds, dependency invalidation and a
# missing artefact, with the keys byte-compared against L2's.
#
# 11.1 adds the map construct section: a `map` binding's wrapper + vtable, the
# `maps` field of the map JSON, and the MAX_MAPS cap.
#
# 11.2 wires a mapped global instance into dispatch: `test/ast/14_map_dispatch`
# uses it as a trait instance, and boxing it names the instance-level vtable.
#
# 11.3 hardens `map`: every trait method must be bound exactly once (an unbound
# slot is a null pointer, a duplicate binding redefines the wrapper), and a CALL
# argument may now be a bare visible name or a member path rooted at the
# instance (test/ast/15_map_args).
#
# 12.1 adds the bindings section: `test/bindings/mock-hal/` is a declarative binding
# to a fake HAL (pass-through include + mirrored trait / struct + a declared
# global instance + `map`), built end to end and compared with expected output.
# It also pins the fix that emits map wrappers in build mode.
#
# batch 3 adds the function-pointer forms: the typedef / array fixtures under
# test/ast/27_fnptr_forms, plus the two named diagnostics (a nested declarator
# and an array parameter).
#
# batch 7 adds `goto` and labels: test/ast/32_goto plus the four function-scoped
# diagnostics (an undefined target, a duplicate label, a declaration behind a
# label, and a label that guards nothing).
#
# batch 8 adds bit-fields: test/ast/33_bitfield plus four width/type diagnostics.
#
# batch 9 adds anonymous struct / union members: test/ast/34_anon_member plus
# the three promotion diagnostics.
#
# batch 10 adds `static` locals: test/ast/35_static_local plus the `own` and
# missing-declaration diagnostics.
#
# batch 11 adds compound literals: test/ast/36_compound_literal plus the
# pointer-type diagnostic.
#
# batch 12 adds the empty statement and `for`-init statics: test/ast/37_empty_stmt
# only (the batch adds no diagnostic).
#
# batch 13 adds variadic functions: test/ast/38_variadic plus the two rejected
# shapes (no named parameter, a variadic impl method).
#
# batch 14 aligns the built-in type words with L2 and accepts `inline`:
# test/ast/39_builtin_types plus the `inline` diagnostic.
#
# batch 15 adds floating-point literals: test/ast/40_float_literal plus the
# case-label diagnostic that now also covers floats.
#
# batch 16 adds `case` ranges: test/ast/41_case_range plus the constant check
# that now covers both ends of a range.
#
# batch 17 adds `_Static_assert`: test/ast/42_static_assert plus the condition
# and message diagnostics.
#
# batch 18 allows several declarators in one field declaration:
# test/ast/43_multi_field (the batch adds no diagnostic).
#
# batch 19 accepts expressions as array lengths: test/ast/44_array_length (no new
# diagnostic either).
#
# batch 20 adds prefix `++` / `--`: test/ast/45_pre_incr (no new diagnostic).
#
# batch 21 lifts the 160-byte cap on a captured initialiser list:
# test/ast/46_long_init (no new diagnostic; an over-long list still reports
# `initializer is too long` rather than truncating).
#
# batch 22 lets a function-pointer declarator carry a variadic tail:
# test/ast/47_vararg_fnptr plus the two rejected shapes (`(...)` with nothing in
# front, and `(void, ...)`).
#
# batch 23 accepts a comma list where a full expression is expected (an
# expression statement and a `for` init / step): test/ast/48_comma (no new
# diagnostic).
#
# batch 24 also accepts a parenthesised comma list in a value position:
# test/ast/49_comma_value (no new diagnostic).
#
# batch 25 accepts a type name that only a header declares (`time_t`): in a
# declaration position an unknown name followed by its declarator is taken as
# the type: test/ast/50_header_type (no new diagnostic).
#
# batch 26 extends that to casts and `sizeof` (`(time_t)raw`, `sizeof(time_t)`),
# where the name must also close the parenthesis: test/ast/51_cast_header_type
# (no new diagnostic).
#
# batch 27 keeps the batch probes as a gate: ct-ast compiles `selfhost/l0/ctc.c`
# itself, the generated C is built, and the resulting compiler runs an example.
#
# batch 28 accepts an assignment used as a value (`(c = f())`, and in a
# condition): test/ast/52_assign_value plus the rejected `own` target.
#
# batch 29 adds the C11 forms `_Alignas` / `_Alignof` / `_Generic`:
# test/ast/53_c11_align_generic plus the three shape diagnostics.
#
# batch 30 lands the `.h.ct` rule: only a `.h.ct` unit writes a `.h` (build and
# compile mode), and only it can be imported; test/modules/* was renamed
# accordingly, and the split case pins the artefact set.
#
# batch 31 accepts GNU `__attribute__((…))` as a trailing pass-through:
# test/ast/54_attribute plus the two shape diagnostics.
#
# batch 32 closes the C compatibility list: integer suffixes (`U` / `L` / `UL` /
# `LL` / `ULL`, normalized), the `static_assert` alias, `_Noreturn` kept from the
# first declaration and GNU `__restrict`: test/ast/55_c_compat plus the two
# malformed-suffix diagnostics.
#
# batch 33 accepts the header-order spellings: `_Atomic(type)`, `_Alignas(…)`
# before the storage class, and GNU attributes before the declarator (globals,
# functions, locals): test/ast/56_header_compat plus four shape diagnostics.
#
# batch 34 fixes L2's incremental build: a recompiled unit now pulls in the
# whole dependency closure, because the shared symbol table must hold every
# imported unit's exports (a clean dependency can sit after the first dirty
# unit). The cache section pins the shape with a three-unit project.
#
# batch 35 adds no language feature: six design patterns are written with the
# existing traits / interface values / composition and run as fixtures under
# test/patterns/**, so an OO gap surfaces as a failing pattern, not a new
# feature.
#
# batch 36 lets a trait method carry a default body: an impl writes only the
# abstract methods, and a trait whose methods are all default needs no `impl`
# at all (`use` is the adoption). test/ast/57_trait_default covers the mixed
# shape (with one override) and 58_trait_all_default the `use`-only shape; the
# cycle, the missing abstract method and the per-struct expansion failure are
# pinned negatives.
#
# batch 38 adds `.m.ct` mapping units: a mapping-only unit publishes no artefact, and
# every bound call is expanded at the consumer's call site into a plain C call
# (no wrapper, no `_iface` / `_vtbl`, no vtable). test/modules/map_unit covers a
# namespace host and a type host, map_unit_type the array decay / pointer
# argument / compound literal / unused-receiver forms, and map_unit_cross a
# mapping shared by a `.h.ct` and a `.ct` consumer. The whitelist of a `.m.ct`
# unit, the static-trait restrictions and the recipe rules are pinned negatives.
#
# batch 39 adds the sibling C shim of a `.m.ct`: `<base>.shim.h` is included by
# the consumer's generated C and its directory joins the printed `cc` line as an
# include root, while an existing `<base>.shim.c` joins that line as a source.
# test/modules/map_unit_shim pins the wiring, the cold/warm cache and the
# touching of the shim header; test/bindings/posix-socket is the real-library demo
# (a header-only shim over socketpair / write / read / errno). A shim source
# without its header is rejected by name, a shim header that is not a regular
# file is rejected too, a shim header under any other base name is never
# included (pinned negative), a static map's JSON carries the shim files, and
# two mapping units that share a base name are an error rather than a silent pick.
#
# batch 40 adds raw pass-through (17.3): `#ct-raw` at column 1 opens a block
# whose lines are copied verbatim into the generated C (never tokenised), and
# `#ct-endraw` closes it; the emitted text is re-anchored with a `#line` on the
# line after the block. test/ast/65_raw pins the verbatim copy and the anchor,
# and four negatives pin the column-1 rule, the unclosed block, the stray
# `#ct-endraw` and trailing text. The cap is 32768 bytes, and the compiler's
# own sources must stay free of raw blocks.
#
# batch 41 adds two things a static map can do that a real trait cannot: a
# method may end in `...` (the recipe forwards the actuals the named parameters
# left over, so `printf` and a reordering `snprintf` fit), and a namespace-host
# method may be called without its trait segment (`std::io::puts(...)` resolves
# to the one recipe bound on that host). test/modules/map_unit_varargs covers
# 0/1/3/6 forwarded actuals, the snprintf reorder and the bare call; the tail
# rules (last position, marker/signature agreement) and the ambiguous bare name
# are pinned negatives. A call with more actuals than a fixed recipe names is
# now an arity diagnostic instead of a silent drop.
#
# The unit-name lint keeps `selfhost/ct-ast/**` on the layout rule: a unit file
# is named after its main type, so every `.h.ct` declares a type or trait whose
# name matches its own basename (`main.ct` is the entry, not a unit).
#
# Usage:  bash selfhost/check-ast.sh
#         CC=gcc bash selfhost/check-ast.sh
#
# Exit code 0 means every assertion passed.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-ast-test.$$"

rm -rf "$work"
mkdir -p "$work" || exit 1

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

echo "cc: $CC"
echo
echo "== unit names (a unit file is named after its main type) =="
name_bad=""
for f in $(find selfhost/ct-ast -name '*.h.ct' | sort); do
    b="$(basename "$f" .h.ct)"
    if ! grep -qE "^(pub )?(struct|union|enum|trait) $b( |$)" "$f"; then
        name_bad="$name_bad $b"
    fi
done
if [ -z "$name_bad" ]; then
    ok "every .h.ct unit declares a type named after its file"
else
    bad "unit names" "$name_bad"
fi

echo
echo "== the AST compiler's own sources carry no raw blocks (17.3) =="
# ct-ast is built by L2, which does not know `#ct-raw`; a marker line here
# would break the bootstrap chain, so the marker is banned from this tree.
if grep -rq '^#ct-raw' selfhost/ct-ast; then
    bad "self-host guard" "selfhost/ct-ast must not use #ct-raw"
else
    ok "no #ct-raw in selfhost/ct-ast"
fi

echo
echo "== the compiler's own sources use no closure literals (21.7) =="
# Phase 21 S7 / M21-E2: until `v0.21.0` ships, `selfhost/**` source may *mention*
# the arrow token in comments or string literals (the lexer and parser have to),
# but it must not *use* it as a closure literal: L2 does not know the syntax and
# the bootstrap chain would stop building. Comments and string / character
# literals are stripped before counting, so a real use is the only thing that
# trips this. The test fixtures under `selfhost/check-semantics.sh` are inputs,
# not compiler source, and are not scanned here.
if [ -n "$(git tag -l v0.21.0 2>/dev/null)" ]; then
    ok "closure syntax in selfhost/** (allowed: v0.21.0 is tagged)"
elif ! cl_bad="$(python3 - selfhost <<'PY'
import os, sys

def strip(src):
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i + 2)
            i = n if j < 0 else j
            out.append(" ")
        elif c in "\"'":
            q = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == q:
                    i += 1
                    break
                i += 1
            out.append(" ")
        else:
            out.append(c)
            i += 1
    return "".join(out)

hits = []
for base, dirs, names in os.walk(sys.argv[1]):
    dirs.sort()
    for name in sorted(names):
        if not name.endswith((".ct", ".c", ".h")):
            continue
        path = os.path.join(base, name)
        with open(path, encoding="utf-8", errors="replace") as fh:
            if "=>" in strip(fh.read()):
                hits.append(path)
print(" ".join(hits))
PY
)"; then
    bad "self-host guard" "python3 could not scan selfhost/**"
elif [ -z "$cl_bad" ]; then
    ok "no closure literal in selfhost/** (the bootstrap uses pre-v0.21.0 syntax)"
else
    bad "self-host guard" "closure literal in: $cl_bad"
fi

echo
echo "== the compiler's own sources use no range initialisers (24.6) =="
# Phase 24: `int a[] = 0..n($ …)` is ct-ast syntax; L2, the driver that builds
# ct-ast, does not know it, so a range initialiser here would stop the bootstrap
# chain. Comments and string / character literals are stripped first, so the
# `"$"` the lexer compares against never counts. A bound is a literal, so the
# shape is anchored on `= <literal>..<literal>(` and `loop(0..n)` cannot match.
if [ -n "$(git tag -l v0.24.0 2>/dev/null)" ]; then
    ok "range initialisers in selfhost/** (allowed: v0.24.0 is tagged)"
elif ! ri_bad="$(python3 - selfhost <<'PY'
import os, re, sys

def strip(src):
    out = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == "/" and i + 1 < n and src[i + 1] == "*":
            j = src.find("*/", i + 2)
            i = n if j < 0 else j + 2
            out.append(" ")
        elif c == "/" and i + 1 < n and src[i + 1] == "/":
            j = src.find("\n", i + 2)
            i = n if j < 0 else j
            out.append(" ")
        elif c in "\"'":
            q = c
            i += 1
            while i < n:
                if src[i] == "\\":
                    i += 2
                    continue
                if src[i] == q:
                    i += 1
                    break
                i += 1
            out.append(" ")
        else:
            out.append(c)
            i += 1
    return "".join(out)

BOUND = r"-?\s*(?:0[xX][0-9a-fA-F]+|\d+)[uUlL]*"
PAT = re.compile(r"=" + BOUND + r"\s*\.\.\s*" + BOUND + r"\s*\(")

hits = []
for base, dirs, names in os.walk(sys.argv[1]):
    dirs.sort()
    for name in sorted(names):
        if not name.endswith((".ct", ".c", ".h")):
            continue
        path = os.path.join(base, name)
        with open(path, encoding="utf-8", errors="replace") as fh:
            if PAT.search(strip(fh.read())):
                hits.append(path)
print(" ".join(hits))
PY
)"; then
    bad "self-host guard" "python3 could not scan selfhost/**"
elif [ -z "$ri_bad" ]; then
    ok "no range initialiser in selfhost/** (the bootstrap predates Phase 24)"
else
    bad "self-host guard" "range initialiser in: $ri_bad"
fi

echo
echo "== build the bootstrap chain and the AST compiler =="
if ! "$CC" -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o "$work/ctc" 2>"$work/l0.log"; then
    echo "  compiler build failed:"; sed 's/^/    /' "$work/l0.log"; exit 1
fi
if ! "$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" 2>"$work/l1.log"; then
    echo "  L0 could not compile L1:"; sed 's/^/    /' "$work/l1.log"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "  L1 did not build:"; sed 's/^/    /' "$work/l1b.log"; exit 1
fi
mkdir -p "$work/l2src"
if ! "$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "  L1 could not build the split tree:"; sed 's/^/    /' "$work/l2.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "  L2 did not build:"; sed 's/^/    /' "$work/l2b.log"; exit 1
fi
mkdir -p "$work/astsrc"
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.out" 2>&1; then
    echo "  L2 could not build the AST compiler:"; sed 's/^/    /' "$work/ast.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
    echo "  the AST compiler did not build:"; sed 's/^/    /' "$work/astb.log"; exit 1
fi
ok "the chain builds (L0 -> L1 -> L2 -> ct-ast)"

# Phase 26 (SH-62 / SH-64): the systemic defence. A type parameter must be gone
# from an emitted instance -- an instance substitutes it -- so a residual `T`
# there is by definition an undeclared identifier that only `cc` would report.
# The scan is limited to the instance bodies (`<name>__ctN`), because a fixture
# may legitimately declare its own value named `T` outside a template; scanning
# the whole file would call that a leak (false positive). The only legal
# survivor inside an instance is a tag (`struct T` / `union T` / `enum T`).
# A build may pull generic declarations from imported `.h.ct` bodies, so every
# `.ct` file under the fixture contributes names -- not just the entry file.
# The scan also runs over every product of a build-mode fixture
# and every `.h` product is checked for instance bodies. `test/modules/p34_pub_*`
# products are scanned in the module section (P34 S3a); the remaining blind spots
# (`test/ast/errors/`, the corpus) are argued in docs/design/phase26.md §2.7.
fixture_sources() {
    find "$1" -name '*.ct' -type f | sort
}

# Usage: tparam_residue <product.c> <source.ct>...
tparam_residue() {
    product="$1"
    shift
    bodies=$(awk '/__ct[0-9]+\(.*\{/ { inb = 1 }
                  inb { print }
                  inb && /^\}/ { inb = 0 }' "$product")
    for tp in $(sed -n 's/^[A-Za-z_][A-Za-z0-9_ \t*]*<\([A-Za-z_][A-Za-z0-9_]*\)>[[:space:]]*(.*/\1/p' "$@" | sort -u); do
        total=$(printf '%s\n' "$bodies" | grep -oE "\b$tp\b" | wc -l | tr -d ' ')
        tags=$(printf '%s\n' "$bodies" | grep -oE "\b(struct|union|enum)[[:space:]]+$tp\b" | wc -l | tr -d ' ')
        if [ "$total" -gt "$tags" ]; then
            printf '%s(%s) ' "$tp" "$((total - tags))"
        fi
    done
}

# TEST-18: generic instances are `static` and belong to a `.c`
# product. An `<name>__ctN(...) {` inside a header can only be an emitter bug;
# a prototype (`...;`) is not an instance body and must not trip the check.
hdr_instances() {
    awk '/__ct[0-9]+\(/ { inb = 1 }
         inb && /\{/ { print; exit }
         inb && /;/ { inb = 0 }' "$1" 2>/dev/null
}

# TEST-18: a scanner that never fires is indistinguishable from a
# clean product, so feed it one dirty and one clean synthetic instance body.
# The generic lives in an imported unit, not in the entry file, so an
# entry-only scan stays silent: the pair is the red proof for `fixture_sources`.
selftest="$work/tparam-selftest"
rm -rf "$selftest"
mkdir -p "$selftest"
cat >"$selftest/src.ct" <<'CT'
int main(void)
{
    return 0;
}
CT
cat >"$selftest/lib.h.ct" <<'CT'
T twice<T>(T x)
{
    return x + x;
}
CT
cat >"$selftest/dirty.c" <<'C'
static int twice__ct1(int x) {
    T y = x;
    return y;
}
C
cat >"$selftest/clean.c" <<'C'
static int twice__ct1(int x) {
    return x + x;
}
C

echo
echo "== tparam_residue self-test (TEST-18) =="
if [ -n "$(tparam_residue "$selftest/dirty.c" "$selftest/src.ct" "$selftest/lib.h.ct")" ]; then
    ok "the scanner reports a leaked type parameter declared in another unit"
else
    bad "tparam_residue self-test" "the scanner stayed silent on a leaked type parameter"
fi
if [ -z "$(tparam_residue "$selftest/clean.c" "$selftest/src.ct" "$selftest/lib.h.ct")" ]; then
    ok "the scanner stays silent on a clean instance body"
else
    bad "tparam_residue self-test" "the scanner reported a clean instance body"
fi

echo
echo "== behavioural cases (compile -> cc -> run -> compare) =="
for d in test/ast/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    name="$(basename "$d")"
    # Phase 37: this fixture deliberately dispatches a null iface; the
    # dedicated p37 runtime probe runs it with --runtime-checks.
    case "$name" in 219_runtime_guard) continue;; esac
    src="$d/prog.ct"
    [ -f "$src" ] || continue
    out="$work/$name.c"
    exe="$work/$name.bin"

    # A fixture with more than one unit cannot use compile mode (`import` is a
    # build-mode feature), so a mapping unit or a header unit sends it through
    # `build`. A shim is found by base name, so every directory holding one is
    # an include root.
    if [ -n "$(find "$d" \( -name '*.m.ct' -o -name '*.h.ct' \) -print -quit)" ]; then
        md="$work/$name.mod"
        incs=""
        rm -rf "$md"
        mkdir -p "$md"
        for h in $(find "$d" -name '*.shim.h'); do incs="$incs -I $(dirname "$h")"; done
        if ! "$work/ct-ast" build --emit-c "$src" -o "$md" >"$work/$name.out" 2>"$work/$name.err"; then
            bad "$name" "ct-ast build failed: $(cat "$work/$name.err")"
            continue
        fi
        if [ -f "$md/prog.h" ]; then
            bad "$name" "a plain .ct unit must not emit a header"
            continue
        fi
        tp_bad=""
        for pc in "$md"/*.c; do
            [ -f "$pc" ] || continue
            tp="$(tparam_residue "$pc" $(fixture_sources "$d"))"
            [ -n "$tp" ] && tp_bad="$tp_bad $(basename "$pc"):$tp"
        done
        if [ -n "$tp_bad" ]; then
            bad "$name" "a build product still names a declared type parameter:$tp_bad"
            continue
        fi
        hdr_bad=""
        for ph in "$md"/*.h; do
            [ -f "$ph" ] || continue
            hd="$(hdr_instances "$ph")"
            [ -n "$hd" ] && hdr_bad="$hdr_bad $(basename "$ph"):$hd"
        done
        if [ -n "$hdr_bad" ]; then
            bad "$name" "a header product carries an instance body:$hdr_bad"
            continue
        fi
        if ! "$CC" -Wall -Wextra -std=c99 $incs -I "$md" "$md"/*.c \
                $(find "$d" -name '*.shim.c') -o "$exe" 2>"$work/$name.cc"; then
            bad "$name" "generated C did not build warning-free: $(cat "$work/$name.cc")"
            continue
        fi
        if ! "$exe" >"$work/$name.stdout" 2>&1; then
            bad "$name" "the program exited non-zero"
            continue
        fi
        if ! cmp -s "$work/$name.stdout" "$d/prog.expected.out"; then
            bad "$name" "program output differs: $(cat "$work/$name.stdout")"
            continue
        fi
        ok "$name (build mode: every product scanned for leaked type parameters)"
        continue
    fi

    if ! "$work/ct-ast" "$src" -o "$out" >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name" "ct-ast failed: $(cat "$work/$name.err")"
        continue
    fi
    tp_bad="$(tparam_residue "$out" $(fixture_sources "$d"))"
    if [ -n "$tp_bad" ]; then
        bad "$name" "the generated C still names a declared type parameter: $tp_bad"
        continue
    fi
    if [ -f "$work/$name.h" ]; then
        bad "$name" "a plain .ct unit must not emit a header"
        continue
    fi
    if ! grep -q "Generated by ct v" "$out"; then
        bad "$name" "the banner is missing"
        continue
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$out" -o "$exe" 2>"$work/$name.cc"; then
        bad "$name" "generated C did not build warning-free: $(cat "$work/$name.cc")"
        continue
    fi
    if ! "$exe" >"$work/$name.stdout" 2>&1; then
        bad "$name" "the program exited non-zero"
        continue
    fi
    if ! cmp -s "$work/$name.stdout" "$d/prog.expected.out"; then
        bad "$name" "program output differs: $(cat "$work/$name.stdout")"
        continue
    fi
    ok "$name"
done

# E34-8 (P34 S7): a boxed interface payload keeps the layer's product shape.
cat >"$work/p34_opt_iface.expected" <<'P34IFACE'
struct Option_Show__iface {
    int has;
    struct Show_iface value;
};
P34IFACE
sed -n '/^struct Option_Show__iface {$/,/^};$/p' "$work/217_option_iface.c" \
    >"$work/p34_opt_iface.actual" 2>/dev/null
if cmp -s "$work/p34_opt_iface.expected" "$work/p34_opt_iface.actual"; then
    ok "p34_option_iface_shape (struct Option_Show__iface carries the interface by value)"
else
    bad "p34_option_iface_shape" "$(head -5 "$work/p34_opt_iface.actual" 2>/dev/null)"
fi

# The member decay stops at one dimension: `char names[2][8]` decays to
# `char (*)[8]`, which no host spells, so the receiver type stays unknown
# instead of silently becoming `char *` (which would print `strlen(names)`).
rm -rf "$work/tdim"
mkdir -p "$work/tdim"
if "$work/ct-ast" build --emit-c test/ast/66_type_host_literals/two_dim.ct \
        -o "$work/tdim" >"$work/tdim.out" 2>"$work/tdim.err"; then
    bad "type host two-dimensional field" "expected a non-zero exit"
elif grep -qF 'cannot resolve the method trait (unknown receiver type)' "$work/tdim.err"; then
    ok "type host (a two-dimensional field decays to no host at all)"
else
    bad "type host two-dimensional field" "$(head -2 "$work/tdim.err")"
fi

echo
echo "== design patterns (OO coverage) =="
# Each pattern is written with the language as it stands -- traits, impl,
# interface values / arrays / fields, composition, namespaces and `map` -- and
# is compiled, built warning-free and run like a behavioural case. Nothing is
# added to the language for them: a pattern that could not be written would be
# reported as a gap instead of being patched into a new feature.
for d in test/patterns/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    name="$(basename "$d")"
    out="$work/pat_$name.c"
    exe="$work/pat_$name.bin"

    if ! "$work/ct-ast" "$d/prog.ct" -o "$out" >"$work/pat_$name.out" 2>"$work/pat_$name.err"; then
        bad "pattern/$name" "ct-ast failed: $(cat "$work/pat_$name.err")"
        continue
    fi
    if [ -f "$work/pat_$name.h" ]; then
        bad "pattern/$name" "a plain .ct unit must not emit a header"
        continue
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$out" -o "$exe" 2>"$work/pat_$name.cc"; then
        bad "pattern/$name" "generated C did not build warning-free: $(cat "$work/pat_$name.cc")"
        continue
    fi
    if ! "$exe" >"$work/pat_$name.stdout" 2>&1; then
        bad "pattern/$name" "the program exited non-zero"
        continue
    fi
    if ! cmp -s "$work/pat_$name.stdout" "$d/expected.out"; then
        bad "pattern/$name" "program output differs: $(cat "$work/pat_$name.stdout")"
        continue
    fi
    ok "pattern/$name"
done

echo
echo "== build-mode mirrors (compile / build parity) =="
# The compile path (`emit_program`) and the build path (`emit_unit` +
# `write_header`) are separate; these probes take an existing compile-mode
# fixture through `build` as a single unit and run it the same way, so a
# divergence in one path fails here.
for name in 28_switch 30_enum 31_union 33_bitfield 34_anon_member \
            35_static_local 36_compound_literal 54_attribute
do
    d="test/ast/$name"
    [ -f "$d/prog.ct" ] || continue
    mdir="$work/mirror-$name"
    rm -rf "$mdir"
    mkdir -p "$mdir"
    if ! "$work/ct-ast" build --emit-c "$d/prog.ct" -o "$mdir" >"$work/mirror-$name.out" \
            2>"$work/mirror-$name.err"; then
        bad "mirror/$name" "build failed: $(cat "$work/mirror-$name.err")"
        continue
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$mdir"/*.c -o "$work/mirror-$name.bin" \
            2>"$work/mirror-$name.cc"; then
        bad "mirror/$name" "generated C did not build warning-free: $(cat "$work/mirror-$name.cc")"
        continue
    fi
    if ! "$work/mirror-$name.bin" >"$work/mirror-$name.stdout" 2>&1; then
        bad "mirror/$name" "the program exited non-zero"
        continue
    fi
    if ! cmp -s "$work/mirror-$name.stdout" "$d/prog.expected.out"; then
        bad "mirror/$name" "program output differs: $(cat "$work/mirror-$name.stdout")"
        continue
    fi
    ok "mirror/$name"
done

echo
echo "== raw pass-through (17.3) =="
# A `#ct-raw` block is copied byte for byte -- the macro and the helper function
# below would not survive the parser/emitter pair -- and the text is re-anchored
# on the line after `#ct-endraw`. The plain behavioural loop above already runs
# the fixture; these probes pin the emitted text and the anchor.
rawd=test/ast/65_raw
if ! "$work/ct-ast" --line "$rawd/prog.ct" -o "$work/raw65.c" \
        >"$work/raw65.out" 2>"$work/raw65.err"; then
    bad "raw 65_raw" "ct-ast failed: $(cat "$work/raw65.err")"
elif ! grep -Fq '#define TRIPLE(x) ((x) * 3)' "$work/raw65.c"; then
    bad "raw 65_raw" "the macro was not copied verbatim"
elif ! grep -Fq 'static int raw_helper(int n)' "$work/raw65.c"; then
    bad "raw 65_raw" "the raw function was not copied verbatim"
elif ! grep -Fq '#line 12 "test/ast/65_raw/prog.ct"' "$work/raw65.c"; then
    bad "raw 65_raw" "the #line anchor after the block is missing"
else
    ok "raw (verbatim copy + #line anchor)"
fi

if ! "$work/ct-ast" --no-line "$rawd/prog.ct" -o "$work/raw65b.c" \
        >"$work/raw65b.out" 2>"$work/raw65b.err"; then
    bad "raw 65_raw (no-line)" "ct-ast failed: $(cat "$work/raw65b.err")"
elif ! grep -Fq '#define TRIPLE(x) ((x) * 3)' "$work/raw65b.c"; then
    bad "raw 65_raw (no-line)" "the macro was not copied verbatim"
elif grep -Fq '#line 12 "test/ast/65_raw/prog.ct"' "$work/raw65b.c"; then
    bad "raw 65_raw (no-line)" "--no-line still anchored the block"
else
    ok "raw (verbatim copy with --no-line)"
fi

rm -rf "$work/raw-build"
mkdir -p "$work/raw-build"
if ! "$work/ct-ast" build --emit-c "$rawd/prog.ct" -o "$work/raw-build" \
        >"$work/raw-build.out" 2>"$work/raw-build.err"; then
    bad "raw 65_raw (build)" "build failed: $(cat "$work/raw-build.err")"
elif ! grep -Fq '#define TRIPLE(x) ((x) * 3)' "$work/raw-build"/*.c; then
    bad "raw 65_raw (build)" "the macro was not copied verbatim"
elif ! grep -Fq '#line 12 "test/ast/65_raw/prog.ct"' "$work/raw-build"/*.c; then
    bad "raw 65_raw (build)" "the #line anchor after the block is missing"
else
    ok "raw (build mode mirrors the anchor)"
fi

# The cap is 32768 bytes for one block; one byte more is refused by name.
{
    printf '#include <stdio.h>\n\n#ct-raw\n'
    awk 'BEGIN { for (i = 0; i < 32769; i++) printf "x"; printf "\n" }'
    printf '#ct-endraw\n\nint main(void) { return 0; }\n'
} > "$work/raw-big.ct"
if "$work/ct-ast" "$work/raw-big.ct" -o "$work/raw-big.c" \
        >"$work/raw-big.out" 2>"$work/raw-big.err"; then
    bad "raw cap" "an over-long block was accepted"
elif grep -q "raw block exceeds 32768 bytes" "$work/raw-big.err"; then
    ok "raw (the 32768-byte cap)"
else
    bad "raw cap" "$(cat "$work/raw-big.err")"
fi

# The four raw diagnostics are pinned verbatim; the generic errors loop also
# sweeps them for the positioned shape.
for pair in \
    "raw_unclosed|unclosed #ct-raw (expected #ct-endraw)" \
    "raw_not_line_start|#ct-raw must start at column 1" \
    "raw_stray_endraw|#ct-endraw without #ct-raw" \
    "raw_end_trailing|unexpected text after #ct-endraw"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "raw: $cf" "expected a non-zero exit"
    elif grep -Fq "$cfmsg" "$work/$cf.err"; then
        ok "raw ($cf)"
    else
        bad "raw: $cf" "$(cat "$work/$cf.err")"
    fi
done

echo
echo "== bindings (Phase 12: the fake HAL demo) =="
# A binding is plain CT - a pass-through include, a mirrored trait / struct, a
# declared global instance and a `map` - so no language feature is involved.
# Build mode must emit the wrappers and the vtable into the unit that declares
# the map (12.1 fixed a gap where they were only emitted in compile mode).
bd=test/bindings/mock-hal
rm -rf "$work/bind"
mkdir -p "$work/bind"
if ! "$work/ct-ast" build --emit-c "$bd/demo.ct" -o "$work/bind" >"$work/bind.out" 2>"$work/bind.err"; then
    bad "test/bindings/mock-hal" "ct-ast failed: $(cat "$work/bind.err")"
elif ! grep -q "uart1_Controller_vtable" "$work/bind/uart.c"; then
    bad "test/bindings/mock-hal" "the map vtable was not emitted into the declaring unit"
elif ! "$CC" -Wall -Wextra -std=c99 -I "$bd" "$work/bind"/*.c "$bd/mock_hal_impl.c" \
        -o "$work/bind.bin" 2>"$work/bind.cc"; then
    bad "test/bindings/mock-hal" "generated C did not build warning-free: $(cat "$work/bind.cc")"
elif ! "$work/bind.bin" >"$work/bind.stdout" 2>&1; then
    bad "test/bindings/mock-hal" "the program exited non-zero"
elif ! cmp -s "$work/bind.stdout" "$bd/demo.expected.out"; then
    bad "test/bindings/mock-hal" "program output differs: $(cat "$work/bind.stdout")"
else
    ok "test/bindings/mock-hal"
fi

echo
echo "== corpus equivalence (9.7: test/cases + examples) =="
# D34: exit status + a warning-free build + identical program output. Golden
# `.c` / `.h` files are not compared; a case without `expected.out` is judged
# compile-only (`03_passthrough` / `04_signatures` have no `main`). A dialect
# demo is expanded by its plugins first: ct-ast, like ct, never sees the DSL.
# A file may mix several dialects, so every distinct marker is routed in
# first-appearance order (each plugin passes foreign blocks through).
#
# A plugin is an ordinary executable, not necessarily a shell script: the
# contract promises "any language", so the gate must not wrap it in `sh`. An
# executable file is run directly (the kernel applies its shebang); otherwise
# its shebang line names the interpreter; only a file with neither falls back
# to POSIX sh.
run_plugin() {
    _plugin=$1
    _input=$2
    if [ -x "$_plugin" ]; then
        "$_plugin" "$_input"
        return
    fi
    _interp=$(sed -n '1s/^#![[:space:]]*//p' "$_plugin")
    if [ -z "$_interp" ]; then
        _interp=sh
    fi
    # A shebang names an interpreter plus optional arguments (`/usr/bin/env
    # python3`), so splitting on whitespace is intended.
    # shellcheck disable=SC2086
    $_interp "$_plugin" "$_input"
}

ci=0
for ct in test/cases/*.ct examples/*/*.ct; do
    dir=$(dirname "$ct")
    name=$(basename "$ct" .ct)
    ci=$((ci + 1))
    label="$ct"
    src="$ct"
    exp_out="$dir/$name.expected.out"

    if [ -d "$dir/ct-dialects" ]; then
        dialects=$(sed -n 's|^//@ct-dialect:[[:space:]]*||p' "$ct" | tr -d ' ' | awk '!seen[$0]++')
        cp "$ct" "$work/corp-$ci.ct"
        src="$work/corp-$ci.ct"
        broken=0
        for dialect in $dialects; do
            base="$dir/ct-dialects/$(printf '%s' "$dialect" | tr / -)"
            plugin="$base.sh"
            if [ ! -f "$plugin" ]; then
                # `<name>.sh` stays the convention; any other `<name>.*` is
                # accepted so a plugin can carry its language's suffix.
                for cand in "$base".*; do
                    if [ -f "$cand" ]; then plugin=$cand; fi
                    break
                done
            fi
            if [ -z "$dialect" ] || [ ! -f "$plugin" ]; then
                bad "$label" "no plugin for dialect '$dialect' (expected $base.sh or $base.*)"
                broken=1
                break
            fi
            if ! run_plugin "$plugin" "$src" >"$work/corp-$ci.step.ct" 2>"$work/corp-$ci.err"; then
                bad "$label" "the expander for '$dialect' failed: $(cat "$work/corp-$ci.err")"
                broken=1
                break
            fi
            mv "$work/corp-$ci.step.ct" "$src"
        done
        if [ "$broken" -ne 0 ]; then continue; fi
    fi
    if ! "$work/ct-ast" "$src" -o "$work/corp-$ci.c" \
            >"$work/corp-$ci.out" 2>"$work/corp-$ci.err"; then
        bad "$label" "ct-ast failed: $(cat "$work/corp-$ci.err")"
        continue
    fi
    if ! "$CC" -Wall -Wextra -std=c99 -c "$work/corp-$ci.c" -o "$work/corp-$ci.o" \
            2>"$work/corp-$ci.cc"; then
        bad "$label" "the generated C does not compile: $(cat "$work/corp-$ci.cc")"
        continue
    fi
    if [ ! -f "$exp_out" ]; then
        ok "$label (compile only)"
        continue
    fi
    if ! "$CC" -Wall -Wextra -std=c99 "$work/corp-$ci.c" -o "$work/corp-$ci.bin" \
            2>"$work/corp-$ci.cc2"; then
        bad "$label" "the generated C does not link: $(cat "$work/corp-$ci.cc2")"
        continue
    fi
    if ! "$work/corp-$ci.bin" >"$work/corp-$ci.stdout" 2>&1; then
        bad "$label" "the program exited non-zero"
        continue
    fi
    if ! cmp -s "$work/corp-$ci.stdout" "$exp_out"; then
        bad "$label" "program output differs from $exp_out"
        continue
    fi
    ok "$label"
done

echo
echo "== module cases (build -> cc -> run -> compare) =="
mod="$work/mod"
rm -rf "$mod-split"
mkdir -p "$mod-split"
if "$work/ct-ast" build --emit-c test/modules/split/main.ct -o "$mod-split" \
        >"$work/msplit.out" 2>"$work/msplit.err" \
   && [ -f "$mod-split/shapes.h" ] && [ -f "$mod-split/impl_dog.h" ] \
   && [ ! -f "$mod-split/main.h" ] \
   && "$CC" -Wall -Wextra -std=c99 "$mod-split"/*.c -o "$work/msplit.bin" 2>"$work/msplit.cc" \
   && "$work/msplit.bin" >"$work/msplit.stdout" 2>&1 \
   && cmp -s "$work/msplit.stdout" test/modules/split/expected.out; then
    ok "split (import + pub routing + cross-unit dispatch; only .h.ct units write a header)"
else
    bad "split" "$(cat "$work/msplit.err" "$work/msplit.cc" "$work/msplit.stdout")"
fi

# E34-4 (P34 S5b): a `pub struct` with a non-generic inherent impl. The owner
# defines `Counter_get` once with external linkage; the consumer carries only
# an undefined reference and takes the prototype from the owner's header.
rm -rf "$mod-inh"
mkdir -p "$mod-inh"
if "$work/ct-ast" build --emit-c test/modules/p34_inherent/main.ct -o "$mod-inh" \
        >"$work/minh.out" 2>"$work/minh.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-inh"/*.c -o "$work/minh.bin" 2>"$work/minh.cc" \
   && "$work/minh.bin" >"$work/minh.stdout" 2>&1 \
   && cmp -s "$work/minh.stdout" test/modules/p34_inherent/expected.out; then
    ok "p34_inherent (cross-unit inherent methods run)"
else
    bad "p34_inherent" "$(cat "$work/minh.err" "$work/minh.cc" "$work/minh.stdout" 2>/dev/null)"
fi
if "$CC" -std=c99 -I "$mod-inh" -c "$mod-inh/lib.c" -o "$work/minh-lib.o" 2>"$work/minh-lib.cc" \
   && "$CC" -std=c99 -I "$mod-inh" -c "$mod-inh/main.c" -o "$work/minh-main.o" 2>>"$work/minh-lib.cc"; then
    n="$(nm "$work/minh-lib.o" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ T _?Counter_get$/ { c++ } END { print c + 0 }')"
    [ "$n" = 1 ] && ok "p34_inherent_nm_owner (Counter_get defined once, external)" \
        || bad "p34_inherent_nm_owner" "$(nm "$work/minh-lib.o" 2>/dev/null | grep -i counter | head -3)"
    n="$(nm "$work/minh-main.o" 2>/dev/null | awk '$0 ~ /^[[:space:]]+U _?Counter_get$/ { c++ } END { print c + 0 }')"
    [ "$n" = 1 ] && ok "p34_inherent_nm_consumer (the consumer calls by symbol)" \
        || bad "p34_inherent_nm_consumer" "$(nm "$work/minh-main.o" 2>/dev/null | grep -i counter | head -3)"
    n="$(grep -c '^int Counter_get(struct Counter \*);$' "$mod-inh/lib.h" 2>/dev/null)"
    [ "$n" = 1 ] && ok "p34_inherent_proto (the header spells struct Counter *)" \
        || bad "p34_inherent_proto" "$(grep 'Counter_get' "$mod-inh/lib.h" 2>/dev/null | head -2)"
else
    bad "p34_inherent_objects" "$(head -3 "$work/minh-lib.cc")"
fi

# E34-7 (P34 S8): `Point` lives in the consumer unit, so the `Option<Point>`
# layout and its methods move there too; the layer's header keeps a forward
# declaration only (the field would be incomplete there).
rm -rf "$mod-optp"
mkdir -p "$mod-optp"
if "$work/ct-ast" build --emit-c test/modules/p34_option_point/main.ct -o "$mod-optp" \
        >"$work/moptp.out" 2>"$work/moptp.err" \
   && "$CC" -Wall -Wextra -std=c99 -I "$mod-optp" "$mod-optp"/*.c -o "$work/moptp.bin" \
        2>"$work/moptp.cc" \
   && "$work/moptp.bin" >"$work/moptp.stdout" 2>&1 \
   && cmp -s "$work/moptp.stdout" test/modules/p34_option_point/expected.out; then
    ok "p34_option_point (Option<Point> cross-unit run)"
else
    bad "p34_option_point" "$(cat "$work/moptp.err" "$work/moptp.cc" "$work/moptp.stdout" 2>/dev/null)"
fi
n="$(grep -c '^struct Option_Point {$' "$mod-optp/main.c" 2>/dev/null)"
[ "$n" = 1 ] && ok "p34_option_point_product (struct Option_Point in the consumer)" \
    || bad "p34_option_point_product" "$(grep 'Option_Point' "$mod-optp"/*.c "$mod-optp"/*.h 2>/dev/null | head -3)"
n="$(grep -c '^struct Option_Point {$' "$mod-optp/Option.h" 2>/dev/null)"
[ "$n" = 0 ] && ok "p34_option_point_layer (the layer header keeps only the forward declaration)" \
    || bad "p34_option_point_layer" "the layer header defines the instance layout"

# E34-11 (P34 S6): the generated header carries types and declarations only, a
# generic instance is defined once per object, and the cache key is
# directional -- two clean builds of the same source agree byte for byte, while
# touching an imported header changes the consumer's key.
rm -rf "$work/cache-src" "$mod-cache-a" "$mod-cache-b"
mkdir -p "$work/cache-src" "$mod-cache-a" "$mod-cache-b"
cp test/modules/p34_inherent/main.ct test/modules/p34_inherent/lib.h.ct \
   test/modules/p34_inherent/expected.out "$work/cache-src/"
if "$work/ct-ast" build --emit-c "$work/cache-src/main.ct" -o "$mod-cache-a" \
        >"$work/mcache-a.out" 2>"$work/mcache-a.err" \
   && "$work/ct-ast" build --emit-c "$work/cache-src/main.ct" -o "$mod-cache-b" \
        >"$work/mcache-b.out" 2>"$work/mcache-b.err"; then
    if cmp -s "$mod-cache-a/.ctcache/main.c.key" "$mod-cache-b/.ctcache/main.c.key" \
       && cmp -s "$mod-cache-a/.ctcache/lib.c.key" "$mod-cache-b/.ctcache/lib.c.key"; then
        ok "p34_cache_same (two clean builds share every key)"
    else
        bad "p34_cache_same" "keys differ: $(diff "$mod-cache-a/.ctcache/main.c.key" "$mod-cache-b/.ctcache/main.c.key" 2>/dev/null | head -2)"
    fi
    hdr_bad="$(grep -nE '^[a-z][a-z ]*[a-z0-9_]+\(.*\) \{$' "$mod-cache-a/lib.h" 2>/dev/null | head -2)"
    if grep -q '^struct Counter {$' "$mod-cache-a/lib.h" 2>/dev/null && [ -z "$hdr_bad" ]; then
        ok "p34_cache_header (the header carries types and declarations only)"
    else
        bad "p34_cache_header" "$hdr_bad"
    fi
    before="$(stat -f %m "$work/cache-src/lib.h.ct")"
    touch -m -t 203001010000 "$work/cache-src/lib.h.ct"
    after="$(stat -f %m "$work/cache-src/lib.h.ct")"
    if [ "$before" != "$after" ]; then
        ok "p34_cache_mtime (touch moved the source stamp)"
    else
        bad "p34_cache_mtime" "$before"
    fi
    if "$work/ct-ast" build --emit-c "$work/cache-src/main.ct" -o "$mod-cache-b" \
            >"$work/mcache-b2.out" 2>"$work/mcache-b2.err"; then
        if ! cmp -s "$mod-cache-a/.ctcache/main.c.key" "$mod-cache-b/.ctcache/main.c.key"; then
            ok "p34_cache_dep (touching an imported header changes the consumer key)"
        else
            bad "p34_cache_dep" "$(cat "$mod-cache-a/.ctcache/main.c.key")"
        fi
        if cmp -s "$mod-cache-a/lib.c" "$mod-cache-b/lib.c"; then
            ok "p34_cache_stable (a re-keyed rebuild keeps the product bytes)"
        else
            bad "p34_cache_stable" "$(diff "$mod-cache-a/lib.c" "$mod-cache-b/lib.c" 2>/dev/null | head -3)"
        fi
    else
        bad "p34_cache_dep" "$(head -2 "$work/mcache-b2.err")"
    fi
else
    bad "p34_cache_same" "$(cat "$work/mcache-a.err" "$work/mcache-b.err" 2>/dev/null | head -2)"
fi
rm -rf "$mod-p34i-obj"
mkdir -p "$mod-p34i-obj"
if "$work/ct-ast" build --emit-c test/modules/p34_pub_generic/main.ct -o "$mod-p34i-obj" \
        >"$work/mp34i.out" 2>"$work/mp34i.err" \
   && "$CC" -std=c99 -I "$mod-p34i-obj" -c "$mod-p34i-obj/lib.c" -o "$work/mp34i-lib.o" \
        >"$work/mp34i.cc" 2>&1 \
   && "$CC" -std=c99 -I "$mod-p34i-obj" -c "$mod-p34i-obj/main.c" -o "$work/mp34i-main.o" \
        >>"$work/mp34i.cc" 2>&1; then
    n="$(nm "$work/mp34i-lib.o" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ t _?id__ct[0-9]+$/ { c++ } END { print c + 0 }')"
    [ "$n" = 1 ] && ok "p34_inst_once_lib (the owner defines one id instance)" \
        || bad "p34_inst_once_lib" "$(nm "$work/mp34i-lib.o" 2>/dev/null | grep 'id__ct' | head -3)"
    n="$(nm "$work/mp34i-main.o" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ t _?id__ct[0-9]+$/ { c++ } END { print c + 0 }')"
    [ "$n" = 1 ] && ok "p34_inst_once_main (the consumer defines one id instance)" \
        || bad "p34_inst_once_main" "$(nm "$work/mp34i-main.o" 2>/dev/null | grep 'id__ct' | head -3)"
else
    bad "p34_inst_once" "$(cat "$work/mp34i.err" "$work/mp34i.cc" 2>/dev/null | head -3)"
fi


# E34-2a / TEST-18 (P34 S3a): the `pub` generic templates now live in `.h.ct`
# headers and are instantiated by a consumer, so a leaked type parameter would
# land in a module product -- a blind spot before this slice. Each fixture gets
# its own output directory; an empty directory fails as loudly as a leak,
# otherwise the scan would pass over nothing.
rm -rf "$mod-p34g" "$mod-p34b"
mkdir -p "$mod-p34g" "$mod-p34b"
if "$work/ct-ast" build --emit-c test/modules/p34_pub_generic/main.ct -o "$mod-p34g" \
        >"$work/mp34g.out" 2>"$work/mp34g.err" \
   && "$work/ct-ast" build --emit-c test/modules/p34_pub_bound/main.ct -o "$mod-p34b" \
        >"$work/mp34b.out" 2>"$work/mp34b.err"; then
    d="$mod-p34g"
    if ( set -- "$d"/*.c && [ -f "$1" ] ); then
        tp="$(for f in "$d"/*.c; do tparam_residue "$f" $(fixture_sources test/modules/p34_pub_generic); done)"
        [ -z "$tp" ] || bad p34_pub_generic "$tp"
    else
        bad p34_pub_generic "no product"
    fi
    d="$mod-p34b"
    if ( set -- "$d"/*.c && [ -f "$1" ] ); then
        tp="$(for f in "$d"/*.c; do tparam_residue "$f" $(fixture_sources test/modules/p34_pub_bound); done)"
        [ -z "$tp" ] || bad p34_pub_bound "$tp"
    else
        bad p34_pub_bound "no product"
    fi
else
    bad p34_pub_generic "$(cat "$work/mp34g.err" "$work/mp34b.err" 2>/dev/null | head -2)"
fi

# The positive pair only fires when the scanner works; a silent scanner looks
# exactly like clean products. A hand-written dirty instance body keeps that
# failure mode red (E34-2a): the scan must report the leaked `T`, and the
# `*)` branch keeps an empty or unexpected string from passing by accident.
tp="$(tparam_residue test/probes/p34_residue_dirty.c $(fixture_sources test/modules/p34_pub_generic))"
if [ -z "$tp" ]; then
    bad p34_residue_dirty "the scanner stayed silent on a hand-written leak"
else
    case "$tp" in
        *"T(1)"*) ok "p34_residue_dirty (a hand-written module leak is reported)" ;;
        *) bad p34_residue_dirty "$tp" ;;
    esac
fi

rm -rf "$mod-ns"
mkdir -p "$mod-ns"
if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_dir/src \
        test/modules/ns_dir/src/main.ct test/modules/ns_dir/src/plain/extra.h.ct \
        -o "$mod-ns" >"$work/mns.out" 2>"$work/mns.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-ns"/*.c -o "$work/mns.bin" 2>"$work/mns.cc" \
   && "$work/mns.bin" >"$work/mns.stdout" 2>&1 \
   && cmp -s "$work/mns.stdout" test/modules/ns_dir/expected.out; then
    ok "ns_dir (namespace + --ns-root + import a::b)"
else
    bad "ns_dir" "$(cat "$work/mns.err" "$work/mns.cc" "$work/mns.stdout")"
fi

rm -rf "$mod-alias"
mkdir -p "$mod-alias"
if "$work/ct-ast" build --emit-c --ns-root test/modules/alias/src \
        test/modules/alias/src/main.ct -o "$mod-alias" \
        >"$work/malias.out" 2>"$work/malias.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-alias"/*.c -o "$work/malias.bin" 2>"$work/malias.cc" \
   && "$work/malias.bin" >"$work/malias.stdout" 2>&1 \
   && cmp -s "$work/malias.stdout" test/modules/alias/expected.out; then
    ok "alias (namespace A::B; + import a::b::C)"
else
    bad "alias" "$(cat "$work/malias.err" "$work/malias.cc" "$work/malias.stdout")"
fi

rm -rf "$work/mod-nsf"
mkdir -p "$work/mod-nsf"
if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_funcs/src \
        test/modules/ns_funcs/src/main.ct -o "$work/mod-nsf" \
        >"$work/mnsf.out" 2>"$work/mnsf.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/mod-nsf"/*.c -o "$work/mnsf.bin" 2>"$work/mnsf.cc" \
   && "$work/mnsf.bin" >"$work/mnsf.stdout" 2>&1 \
   && cmp -s "$work/mnsf.stdout" test/modules/ns_funcs/expected.out; then
    ok "ns_funcs (pub functions mangled by namespace; a::size and b::size coexist)"
else
    bad "ns_funcs" "$(cat "$work/mnsf.err" "$work/mnsf.cc" "$work/mnsf.stdout")"
fi

rm -rf "$work/mod-nsq"
mkdir -p "$work/mod-nsq"
if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_qual/src \
        test/modules/ns_qual/src/main.ct -o "$work/mod-nsq" \
        >"$work/mnsq.out" 2>"$work/mnsq.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/mod-nsq"/*.c -o "$work/mnsq.bin" 2>"$work/mnsq.cc" \
   && "$work/mnsq.bin" >"$work/mnsq.stdout" 2>&1 \
   && cmp -s "$work/mnsq.stdout" test/modules/ns_qual/expected.out; then
    ok "ns_qual (Point::size() and app::size() both reach app_size)"
else
    bad "ns_qual" "$(cat "$work/mnsq.err" "$work/mnsq.cc" "$work/mnsq.stdout")"
fi

rm -rf "$mod-inc"
mkdir -p "$mod-inc"
if "$work/ct-ast" build --emit-c test/modules/inc/main.ct -I test/modules/inc/extra \
        -o "$mod-inc" >"$work/minc.out" 2>"$work/minc.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-inc"/*.c -o "$work/minc.bin" 2>"$work/minc.cc" \
   && "$work/minc.bin" >"$work/minc.stdout" 2>&1 \
   && cmp -s "$work/minc.stdout" test/modules/inc/expected.out; then
    ok "inc (-I import root)"
else
    bad "inc" "$(cat "$work/minc.err" "$work/minc.cc" "$work/minc.stdout")"
fi

# P20-03: a type-host mapped call is checked against the binding it expands to,
# in every position -- including a bare statement call, which never reaches the
# type pass. `ok.ct` must stay warning-free; the negatives pin both counts.
rm -rf "$mod-hta"
mkdir -p "$mod-hta"
if "$work/ct-ast" build --emit-c -I test/modules/map_unit_type \
        test/modules/p20_type_host_arity/ok.ct -o "$mod-hta" \
        >"$work/mhta.out" 2>"$work/mhta.err" \
   && ! grep -qF "arity mismatch" "$work/mhta.err" \
   && "$CC" -Wall -Wextra -std=c99 -I test/modules/map_unit_type/ctypes \
        "$mod-hta"/*.c -o "$work/mhta.bin" 2>"$work/mhta.cc" \
   && "$work/mhta.bin" >"$work/mhta.stdout" 2>&1 \
   && cmp -s "$work/mhta.stdout" test/modules/p20_type_host_arity/ok.expected.out; then
    ok "p20_type_host_arity_ok (statement, initialiser, condition, nested)"
else
    bad "p20_type_host_arity_ok" "$(cat "$work/mhta.err" "$work/mhta.cc" "$work/mhta.stdout" 2>/dev/null | head -5)"
fi

rm -rf "$mod-htf"
mkdir -p "$mod-htf"
# A shortage is already fatal when the recipe is expanded ("a map call has
# fewer arguments than its binding"), and a failed build drops the recorded
# warnings, so the build case pins that message rather than the warning.
if "$work/ct-ast" build --emit-c -I test/modules/map_unit_type \
        test/modules/p20_type_host_arity/few.ct -o "$mod-htf" \
        >"$work/mhtf.out" 2>"$work/mhtf.err"; then
    bad "p20_type_host_arity_few" "expected a non-zero exit"
elif grep -qF "a map call has fewer arguments than its binding" "$work/mhtf.err"; then
    ok "p20_type_host_arity_few (a bare statement call one argument short)"
else
    bad "p20_type_host_arity_few" "$(head -2 "$work/mhtf.err")"
fi

rm -rf "$mod-htm"
mkdir -p "$mod-htm"
if "$work/ct-ast" build --emit-c -I test/modules/map_unit_type \
        test/modules/p20_type_host_arity/more.ct -o "$mod-htm" \
        >"$work/mhtm.out" 2>"$work/mhtm.err" \
   && grep -qF "warning: arity mismatch: 'toLong' takes 1 argument(s), 2 given" "$work/mhtm.err"; then
    ok "p20_type_host_arity_more (one argument too many, nested in a call)"
else
    bad "p20_type_host_arity_more" "$(cat "$work/mhtm.err" 2>/dev/null | head -5)"
fi

# A type-host recipe expands as a straight textual substitution and names its
# receiver once, so a call result in an argument position is legal and must not
# be materialised into `__ct_tmpN`: `hoist_scan` used to reject it as a temporary
# receiver, although only dynamic dispatch needs a temporary there.
rm -rf "$mod-htc"
mkdir -p "$mod-htc"
if "$work/ct-ast" build --emit-c -I test/modules/map_unit_type \
        test/modules/p20_type_host_call_arg/ok.ct -o "$mod-htc" \
        >"$work/mhtc.out" 2>"$work/mhtc.err" \
   && grep -qF "atoi((mkname()))" "$mod-htc"/*.c \
   && ! grep -qF "__ct_tmp" "$mod-htc"/*.c \
   && "$CC" -Wall -Wextra -std=c99 -I test/modules/map_unit_type/ctypes \
        "$mod-htc"/*.c -o "$work/mhtc.bin" 2>"$work/mhtc.cc" \
   && "$work/mhtc.bin" >"$work/mhtc.stdout" 2>&1 \
   && cmp -s "$work/mhtc.stdout" test/modules/p20_type_host_call_arg/ok.expected.out; then
    ok "p20_type_host_call_arg (a call result as receiver, no __ct_tmp)"
else
    bad "p20_type_host_call_arg" "$(cat "$work/mhtc.err" "$work/mhtc.cc" "$work/mhtc.stdout" 2>/dev/null | head -5)"
fi

# Phase 25.1 + SH-60: a static map's method signature is enforced at the call
# site in every form, not only by arity. `p25_static_argtype` binds one host per
# form -- `P` is a type host (`aux == 6` and `Trait::method(recv, ...)`), `Q` a
# namespace host (`ns::Trait.method` and `ns::method`). A compatible actual stays
# silent; a confident mismatch is a hard error (SH-60): the recipe splices the
# actual into the emitted call and `ct check` never sees an imported mapping
# unit, so a warning would let the bad call reach C or the runtime.
p25=test/modules/p25_static_argtype

rm -rf "$work/p25ok"
mkdir -p "$work/p25ok"
if "$work/ct-ast" build --emit-c -I "$p25" "$p25/ok.ct" -o "$work/p25ok" \
        >"$work/p25ok.out" 2>"$work/p25ok.err" \
   && ! grep -qF "type mismatch" "$work/p25ok.err"; then
    ok "p25_static_argtype_ok (all four forms, no false positive)"
else
    bad "p25_static_argtype_ok" "$(head -5 "$work/p25ok.err" 2>/dev/null)"
fi

# aux == 6: type-host dot call.
rm -rf "$work/p25a6"
mkdir -p "$work/p25a6"
if ! "$work/ct-ast" build --emit-c -I "$p25" "$p25/aux6.ct" -o "$work/p25a6" \
        >"$work/p25a6.out" 2>"$work/p25a6.err" \
   && grep -qF "error: type mismatch: 'find' argument 1: expected 'char *', got 'int'" \
        "$work/p25a6.err"; then
    ok "p25_static_argtype_aux6 (type-host dot call compares its actual)"
else
    bad "p25_static_argtype_aux6" "$(head -5 "$work/p25a6.err" 2>/dev/null)"
fi

# qf == 3: `ns::Trait.method(...)`.
rm -rf "$work/p25q3"
mkdir -p "$work/p25q3"
if ! "$work/ct-ast" build --emit-c -I "$p25" "$p25/q3.ct" -o "$work/p25q3" \
        >"$work/p25q3.out" 2>"$work/p25q3.err" \
   && grep -qF "error: type mismatch: 'g' argument 1: expected 'char *', got 'int'" \
        "$work/p25q3.err"; then
    ok "p25_static_argtype_q3 (ns::Trait.method compares its actual)"
else
    bad "p25_static_argtype_q3" "$(head -5 "$work/p25q3.err" 2>/dev/null)"
fi

# qf == 4: `ns::method(...)` with the trait segment elided.
rm -rf "$work/p25q4"
mkdir -p "$work/p25q4"
if ! "$work/ct-ast" build --emit-c -I "$p25" "$p25/q4.ct" -o "$work/p25q4" \
        >"$work/p25q4.out" 2>"$work/p25q4.err" \
   && grep -qF "error: type mismatch: 'f' argument 1: expected 'char *', got 'int'" \
        "$work/p25q4.err"; then
    ok "p25_static_argtype_q4 (ns::method compares its actual)"
else
    bad "p25_static_argtype_q4" "$(head -5 "$work/p25q4.err" 2>/dev/null)"
fi

# qf == 5: `Trait::method(recv, ...)`; the receiver stays out of the comparison.
rm -rf "$work/p25q5"
mkdir -p "$work/p25q5"
if ! "$work/ct-ast" build --emit-c -I "$p25" "$p25/q5.ct" -o "$work/p25q5" \
        >"$work/p25q5.out" 2>"$work/p25q5.err" \
   && grep -qF "error: type mismatch: 'find' argument 1: expected 'char *', got 'int'" \
        "$work/p25q5.err"; then
    ok "p25_static_argtype_q5 (Trait::method compares the tail, not the receiver)"
else
    bad "p25_static_argtype_q5" "$(head -5 "$work/p25q5.err" 2>/dev/null)"
fi

# L25-1: a closure actual may only fill a `(fn, env)` pair of the host method.
rm -rf "$work/p25cl"
mkdir -p "$work/p25cl"
if "$work/ct-ast" build --emit-c -I "$p25" "$p25/closure_slot.ct" -o "$work/p25cl" \
        >"$work/p25cl.out" 2>"$work/p25cl.err"; then
    bad "p25_static_closure_slot" "expected a non-zero exit"
elif grep -qF "a closure argument must fill a '(fn, env)' parameter pair (got 'char *')" \
        "$work/p25cl.err"; then
    ok "p25_static_closure_slot (L25-1 on a non-pair position)"
else
    bad "p25_static_closure_slot" "$(head -5 "$work/p25cl.err" 2>/dev/null)"
fi

# Phase 25.2 (SH-60 2b): a closure actual fills a static recipe's `(fn, env)`
# pair. The emitter used to count one slot per actual and failed with "a map
# call has fewer arguments than its binding"; now each form expands the pair in
# two slots. One fixture per call form, so a fix that only covers one path
# cannot pass: the generated call is asserted and then compiled and run.
p25c=test/modules/p25_static_closure
p25ci="$p25c/probe"

rm -rf "$work/p25c_a6"
mkdir -p "$work/p25c_a6"
if "$work/ct-ast" build --emit-c -I "$p25c" "$p25c/aux6.ct" -o "$work/p25c_a6" \
        >"$work/p25c_a6.out" 2>"$work/p25c_a6.err" \
   && ! grep -qF "fewer arguments" "$work/p25c_a6.err" \
   && grep -qF 'ct_probe_walk(("abc"), (__ct_cl_tramp_' "$work/p25c_a6"/*.c \
   && grep -qF '&(struct __ct_cl_env_' "$work/p25c_a6"/*.c \
   && "$CC" -Wall -Wextra -std=c99 -I "$p25ci" "$work/p25c_a6"/*.c \
        -o "$work/p25c_a6.bin" 2>"$work/p25c_a6.cc" \
   && [ "$("$work/p25c_a6.bin")" = "297" ]; then
    ok "p25_static_closure_aux6 (type-host dot call fills the pair)"
else
    bad "p25_static_closure_aux6" "$(cat "$work/p25c_a6.err" "$work/p25c_a6.cc" 2>/dev/null | head -5)"
fi

# qf == 5: `Trait::method(recv, ...)`; the receiver stays out of the tail.
rm -rf "$work/p25c_q5"
mkdir -p "$work/p25c_q5"
if "$work/ct-ast" build --emit-c -I "$p25c" "$p25c/q5.ct" -o "$work/p25c_q5" \
        >"$work/p25c_q5.out" 2>"$work/p25c_q5.err" \
   && ! grep -qF "fewer arguments" "$work/p25c_q5.err" \
   && grep -qF 'ct_probe_walk(("abc"), (__ct_cl_tramp_' "$work/p25c_q5"/*.c \
   && grep -qF '&(struct __ct_cl_env_' "$work/p25c_q5"/*.c \
   && "$CC" -Wall -Wextra -std=c99 -I "$p25ci" "$work/p25c_q5"/*.c \
        -o "$work/p25c_q5.bin" 2>"$work/p25c_q5.cc" \
   && [ "$("$work/p25c_q5.bin")" = "294" ]; then
    ok "p25_static_closure_q5 (Trait::method tail fills the pair)"
else
    bad "p25_static_closure_q5" "$(cat "$work/p25c_q5.err" "$work/p25c_q5.cc" 2>/dev/null | head -5)"
fi

# qf == 3: `ns::Trait.method(...)`.
rm -rf "$work/p25c_q3"
mkdir -p "$work/p25c_q3"
if "$work/ct-ast" build --emit-c -I "$p25c" "$p25c/q3.ct" -o "$work/p25c_q3" \
        >"$work/p25c_q3.out" 2>"$work/p25c_q3.err" \
   && ! grep -qF "fewer arguments" "$work/p25c_q3.err" \
   && grep -qF 'ct_probe_apply((3), (__ct_cl_tramp_' "$work/p25c_q3"/*.c \
   && grep -qF '&(struct __ct_cl_env_' "$work/p25c_q3"/*.c \
   && "$CC" -Wall -Wextra -std=c99 -I "$p25ci" "$work/p25c_q3"/*.c \
        -o "$work/p25c_q3.bin" 2>"$work/p25c_q3.cc" \
   && [ "$("$work/p25c_q3.bin")" = "6" ]; then
    ok "p25_static_closure_q3 (ns::Trait.method fills the pair)"
else
    bad "p25_static_closure_q3" "$(cat "$work/p25c_q3.err" "$work/p25c_q3.cc" 2>/dev/null | head -5)"
fi

# qf == 4: `ns::method(...)` with the trait segment elided.
rm -rf "$work/p25c_q4"
mkdir -p "$work/p25c_q4"
if "$work/ct-ast" build --emit-c -I "$p25c" "$p25c/q4.ct" -o "$work/p25c_q4" \
        >"$work/p25c_q4.out" 2>"$work/p25c_q4.err" \
   && ! grep -qF "fewer arguments" "$work/p25c_q4.err" \
   && grep -qF 'ct_probe_apply((3), (__ct_cl_tramp_' "$work/p25c_q4"/*.c \
   && grep -qF '&(struct __ct_cl_env_' "$work/p25c_q4"/*.c \
   && "$CC" -Wall -Wextra -std=c99 -I "$p25ci" "$work/p25c_q4"/*.c \
        -o "$work/p25c_q4.bin" 2>"$work/p25c_q4.cc" \
   && [ "$("$work/p25c_q4.bin")" = "18" ]; then
    ok "p25_static_closure_q4 (ns::method fills the pair)"
else
    bad "p25_static_closure_q4" "$(cat "$work/p25c_q4.err" "$work/p25c_q4.cc" 2>/dev/null | head -5)"
fi

# A declared binding: the second slot is the address of its own stack instance.
rm -rf "$work/p25c_var"
mkdir -p "$work/p25c_var"
if "$work/ct-ast" build --emit-c -I "$p25c" "$p25c/var.ct" -o "$work/p25c_var" \
        >"$work/p25c_var.out" 2>"$work/p25c_var.err" \
   && ! grep -qF "fewer arguments" "$work/p25c_var.err" \
   && grep -qF 'ct_probe_walk(("abc"), (__ct_cl_tramp_' "$work/p25c_var"/*.c \
   && grep -qF '(&__ct_cl_env_v_' "$work/p25c_var"/*.c \
   && "$CC" -Wall -Wextra -std=c99 -I "$p25ci" "$work/p25c_var"/*.c \
        -o "$work/p25c_var.bin" 2>"$work/p25c_var.cc" \
   && [ "$("$work/p25c_var.bin")" = "300" ]; then
    ok "p25_static_closure_var (a declared binding fills the pair)"
else
    bad "p25_static_closure_var" "$(cat "$work/p25c_var.err" "$work/p25c_var.cc" 2>/dev/null | head -5)"
fi

# Phase 25.4: the four diagnostics, each reached through its own recipe so one
# fix cannot make another pass. L25-1 (non-pair position) is asserted above on
# `p25_static_closure_slot`; the three below cover the repeat, the unpaired and
# the `...` tail.
p25neg=test/modules/p25_static_closure_neg

rm -rf "$work/p25n_twice"
mkdir -p "$work/p25n_twice"
if "$work/ct-ast" build --emit-c -I "$p25neg" "$p25neg/twice.ct" -o "$work/p25n_twice" \
        >"$work/p25n_twice.out" 2>"$work/p25n_twice.err"; then
    bad "p25_closure_twice" "expected a non-zero exit"
elif grep -qF "a map recipe must use a closure argument exactly once" "$work/p25n_twice.err"; then
    ok "p25_closure_twice (L25-2: a closure half is named once)"
else
    bad "p25_closure_twice" "$(head -5 "$work/p25n_twice.err" 2>/dev/null)"
fi

rm -rf "$work/p25n_unused"
mkdir -p "$work/p25n_unused"
if "$work/ct-ast" build --emit-c -I "$p25neg" "$p25neg/unused.ct" -o "$work/p25n_unused" \
        >"$work/p25n_unused.out" 2>"$work/p25n_unused.err"; then
    bad "p25_closure_unused" "expected a non-zero exit"
elif grep -qF "a map recipe must use both halves of a closure argument" "$work/p25n_unused.err"; then
    ok "p25_closure_unused (L25-4: both halves are named)"
else
    bad "p25_closure_unused" "$(head -5 "$work/p25n_unused.err" 2>/dev/null)"
fi

rm -rf "$work/p25n_vararg"
mkdir -p "$work/p25n_vararg"
if "$work/ct-ast" build --emit-c -I "$p25neg" "$p25neg/vararg.ct" -o "$work/p25n_vararg" \
        >"$work/p25n_vararg.out" 2>"$work/p25n_vararg.err"; then
    bad "p25_closure_vararg" "expected a non-zero exit"
elif grep -qF "a map recipe cannot pass a closure through '...'" "$work/p25n_vararg.err"; then
    ok "p25_closure_vararg (L25-3: no pair in the '...' tail)"
else
    bad "p25_closure_vararg" "$(head -5 "$work/p25n_vararg.err" 2>/dev/null)"
fi

# §6.3: 120's emitted call is byte-for-byte the hand-written one (indentation
# stripped), and 121 passes its declaration's instance rather than a literal.
p25pos=test/ast/120_map_each_closure
rm -rf "$work/p25p120"
mkdir -p "$work/p25p120"
if "$work/ct-ast" build --emit-c "$p25pos/prog.ct" -o "$work/p25p120" \
        >"$work/p25p120.out" 2>"$work/p25p120.err" \
   && [ "$(sed -n 's/^[[:space:]]*int r = \(.*\);$/\1/p' "$work/p25p120"/*.c)" \
        = 'ct_each_int((a), (4), (__ct_cl_tramp_0), (&(struct __ct_cl_env_0){ base }))' ]; then
    ok "p25_map_each_closure_120 (the pair is placed as if hand-written)"
else
    bad "p25_map_each_closure_120" "$(sed -n 's/^[[:space:]]*int r = \(.*\);$/\1/p' "$work/p25p120"/*.c 2>/dev/null | head -2)"
fi

rm -rf "$work/p25p121"
mkdir -p "$work/p25p121"
if "$work/ct-ast" build --emit-c "test/ast/121_map_each_closure_var/prog.ct" -o "$work/p25p121" \
        >"$work/p25p121.out" 2>"$work/p25p121.err" \
   && grep -qF '(&__ct_cl_env_v_' "$work/p25p121"/*.c \
   && ! grep -qF '&(struct __ct_cl_env_' "$work/p25p121"/*.c; then
    ok "p25_map_each_closure_121 (a declared binding passes its own instance)"
else
    bad "p25_map_each_closure_121" "$(cat "$work/p25p121.err" 2>/dev/null | head -5)"
fi

# Phase 26 (26.4): one template, two instances. The template itself is never a
# C symbol; each call site names a concrete instance, and both definitions are
# the same body with the type parameter replaced.
rm -rf "$work/p26g123"
mkdir -p "$work/p26g123"
if "$work/ct-ast" test/ast/123_generic_identity/prog.ct -o "$work/p26g123/prog.c" \
        >"$work/p26g123.out" 2>"$work/p26g123.err" \
   && cc -Wall -Wextra -std=c99 "$work/p26g123/prog.c" -o "$work/p26g123/prog" \
        >"$work/p26g123.cc" 2>&1 \
   && "$work/p26g123/prog" > "$work/p26g123.run" \
   && cmp -s "$work/p26g123.run" test/ast/123_generic_identity/prog.expected.out \
   && [ "$(grep -cE '^static .*__ct[0-9]+\(.*\);$' "$work/p26g123/prog.c")" -eq 2 ] \
   && ! grep -qE '\bT\b' "$work/p26g123/prog.c" \
   && grep -qF 'static int id__ct1(int);' "$work/p26g123/prog.c" \
   && grep -qF 'static char * id__ct2(char *);' "$work/p26g123/prog.c" \
   && grep -qF 'a = id__ct1(42);' "$work/p26g123/prog.c" \
   && grep -qF 'b = id__ct1(7);' "$work/p26g123/prog.c" \
   && [ "$(grep -cE '^static int id__ct1\(int x\) \{' "$work/p26g123/prog.c")" -eq 1 ] \
   && grep -qF 'q = id__ct2(p);' "$work/p26g123/prog.c" \
   && ! grep -qF 'id(' "$work/p26g123/prog.c"; then
    ok "p26_generic_identity (two instances, dedup, no template symbol, no residual T)"
else
    bad "p26_generic_identity" "$(cat "$work/p26g123.err" "$work/p26g123.cc" 2>/dev/null | head -5)"
fi

# §2.3: a struct spelling survives substitution intact (`struct Point` is one
# type word, not two).
rm -rf "$work/p26g124"
mkdir -p "$work/p26g124"
if "$work/ct-ast" test/ast/124_generic_struct/prog.ct -o "$work/p26g124/prog.c" \
        >"$work/p26g124.out" 2>"$work/p26g124.err" \
   && cc -Wall -Wextra -std=c99 "$work/p26g124/prog.c" -o "$work/p26g124/prog" \
        >"$work/p26g124.cc" 2>&1 \
   && "$work/p26g124/prog" > "$work/p26g124.run" \
   && cmp -s "$work/p26g124.run" test/ast/124_generic_struct/prog.expected.out \
   && grep -qF 'static struct Point pass__ct1(struct Point);' "$work/p26g124/prog.c" \
   && grep -qF 'b = pass__ct1(a);' "$work/p26g124/prog.c"; then
    ok "p26_generic_struct (a struct type argument is substituted)"
else
    bad "p26_generic_struct" "$(cat "$work/p26g124.err" "$work/p26g124.cc" 2>/dev/null | head -5)"
fi

# TEST-17: every type position inside a template body must be substituted.
# Before the SH-62 fix this fixture died at the cast; the emitted-C greps pin
# each form so a partially-substituted body cannot pass on runtime output alone.
rm -rf "$work/p26g125"
mkdir -p "$work/p26g125"
if "$work/ct-ast" test/ast/125_generic_type_positions/prog.ct -o "$work/p26g125/prog.c" \
        >"$work/p26g125.out" 2>"$work/p26g125.err" \
   && cc -Wall -Wextra -std=c99 "$work/p26g125/prog.c" -o "$work/p26g125/prog" \
        >"$work/p26g125.cc" 2>&1 \
   && "$work/p26g125/prog" > "$work/p26g125.run" \
   && cmp -s "$work/p26g125.run" test/ast/125_generic_type_positions/prog.expected.out \
   && grep -qF 'if (sizeof(int) > _Alignof(int)) {' "$work/p26g125/prog.c" \
   && grep -qF 'offsetof(struct Pair, y)' "$work/p26g125/prog.c" \
   && grep -qF 'va_arg(ap, int)' "$work/p26g125/prog.c" \
   && grep -qF 'v = (int)(a);' "$work/p26g125/prog.c" \
   && grep -qF 'int v;' "$work/p26g125/prog.c" \
   && [ "$(grep -cE '^static .*__ct[0-9]+\(.*\);$' "$work/p26g125/prog.c")" -eq 3 ] \
   && ! grep -qE '\bT\b' "$work/p26g125/prog.c"; then
    ok "p26_generic_type_positions (sizeof/_Alignof/offsetof/va_arg/cast/local/call arg)"
else
    bad "p26_generic_type_positions" "$(cat "$work/p26g125.err" "$work/p26g125.cc" 2>/dev/null | head -5)"
fi

# SH-63: a tag named like the type parameter stays a tag. On v0.26.0 this file
# exited 0 and emitted `static struct int getv__ct1(struct int *)`, which cc
# rejects; the generated grep plus the compile below make that red.
rm -rf "$work/p26g126"
mkdir -p "$work/p26g126"
if "$work/ct-ast" test/ast/126_generic_struct_tag/prog.ct -o "$work/p26g126/prog.c" \
        >"$work/p26g126.out" 2>"$work/p26g126.err" \
   && cc -Wall -Wextra -std=c99 "$work/p26g126/prog.c" -o "$work/p26g126/prog" \
        >"$work/p26g126.cc" 2>&1 \
   && "$work/p26g126/prog" > "$work/p26g126.run" \
   && cmp -s "$work/p26g126.run" test/ast/126_generic_struct_tag/prog.expected.out \
   && grep -qF 'static int getv__ct1(struct T *);' "$work/p26g126/prog.c" \
   && grep -qF '_Generic ( x , struct T : 1' "$work/p26g126/prog.c" \
   && ! grep -qF 'struct int' "$work/p26g126/prog.c"; then
    ok "p26_generic_struct_tag (tag T survives, bare T is the parameter)"
else
    bad "p26_generic_struct_tag" "$(cat "$work/p26g126.err" "$work/p26g126.cc" 2>/dev/null | head -5)"
fi

# R6: `id__ct1` is taken by a user function, so the instance must retry.
rm -rf "$work/p26g127"
mkdir -p "$work/p26g127"
if "$work/ct-ast" test/ast/127_generic_name_retry/prog.ct -o "$work/p26g127/prog.c" \
        >"$work/p26g127.out" 2>"$work/p26g127.err" \
   && cc -Wall -Wextra -std=c99 "$work/p26g127/prog.c" -o "$work/p26g127/prog" \
        >"$work/p26g127.cc" 2>&1 \
   && "$work/p26g127/prog" > "$work/p26g127.run" \
   && cmp -s "$work/p26g127.run" test/ast/127_generic_name_retry/prog.expected.out \
   && grep -qF 'static int id__ct1_1(int);' "$work/p26g127/prog.c" \
   && grep -qF 'id__ct1_1(2)' "$work/p26g127/prog.c"; then
    ok "p26_generic_name_retry (R6 collision falls back to id__ct1_1)"
else
    bad "p26_generic_name_retry" "$(cat "$work/p26g127.err" "$work/p26g127.cc" 2>/dev/null | head -5)"
fi

# SH-62 (reopened): a type operand needs no parentheses. v0.26.1 still parsed
# `sizeof T` as `sizeof` of an identifier and emitted `sizeof(T)`; `_Alignof T`
# failed outright. Each spelling is pinned in the generated C.
rm -rf "$work/p26g128"
mkdir -p "$work/p26g128"
if "$work/ct-ast" test/ast/128_generic_type_operands/prog.ct -o "$work/p26g128/prog.c" \
        >"$work/p26g128.out" 2>"$work/p26g128.err" \
   && cc -Wall -Wextra -std=c99 "$work/p26g128/prog.c" -o "$work/p26g128/prog" \
        >"$work/p26g128.cc" 2>&1 \
   && "$work/p26g128/prog" > "$work/p26g128.run" \
   && cmp -s "$work/p26g128.run" test/ast/128_generic_type_operands/prog.expected.out \
   && grep -qF 'sizeof(int)' "$work/p26g128/prog.c" \
   && grep -qF '_Alignof(int)' "$work/p26g128/prog.c" \
   && grep -qF 'alignof(int)' "$work/p26g128/prog.c" \
   && grep -qF 'sizeof(int)) * 2' "$work/p26g128/prog.c" \
   && grep -qF 'sizeof(int) + sizeof(int)' "$work/p26g128/prog.c"; then
    ok "p26_generic_type_operands (bare sizeof/_Alignof, alignof, sizeof T * 2)"
else
    bad "p26_generic_type_operands" "$(cat "$work/p26g128.err" "$work/p26g128.cc" 2>/dev/null | head -5)"
fi

# L26-1..L26-5: each diagnostic is pinned to its own line and column, so a
# message that drifts by one token is caught here rather than by prose.
p26_diag() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p26d.c" \
            >"$work/p26d.out" 2>"$work/p26d.err"; then
        bad "p26_diag_$1" "expected a non-zero exit"
    elif grep -qF "test/ast/errors/$1.ct:$2: error: $3" "$work/p26d.err"; then
        ok "p26_diag_$1"
    else
        bad "p26_diag_$1" "$(head -2 "$work/p26d.err")"
    fi
}
p26_diag generic_missing_arg 10:14 "generic function 'id' needs a type argument"
# P34 S1b: L26-2 lifted — `pub T id<T>(T x)` is now legal. The old generic_pub
# error fixture lives at test/ast/228_pub_generic_fn/prog.ct as a positive case.
p26_diag generic_two_params 2:9 "only one type parameter is supported"
p26_diag generic_void_arg 9:19 "'void' cannot be a generic type argument"
p26_diag generic_recursive 10:17 "recursive generic calls are not supported"

# L34-3 (E34-10): an enum has no monomorphisation axis; the parser names it
# instead of stopping at the `<` with an unexpected token.
p34_diag() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p34d.c" \
            >"$work/p34d.out" 2>"$work/p34d.err"; then
        bad "p34_diag_$1" "expected a non-zero exit"
    elif grep -qF "test/ast/errors/$1.ct:$2: error: $3" "$work/p34d.err"; then
        ok "p34_diag_$1"
    else
        bad "p34_diag_$1" "$(head -2 "$work/p34d.err")"
    fi
}
p34_diag generic_enum 2:12 "generic enums are not supported"
# Capacity is not an L26 code, but it must fail loudly at the 65th instance
# (R7). The position is the `(` of the 65th call, i.e. the token that found the
# table full.
p26_diag generic_too_many 76:80 "too many generic instances in this unit"
# `_Generic` is copied verbatim; a type parameter inside it would leak into the
# emitted C. SH-62 requires a hard error, never an exit-0 bad product.
p26_diag generic_generic_selector 7:24 "type parameter cannot be used inside _Generic"
# SH-64: a type parameter is never a value. Each of the four identifier shapes
# used to exit 0 and emit the bare `T`; the guard sits at the shared entry of
# the identifier branch, so argument, return, `sizeof T * T` and
# `sizeof T + T` all report the same diagnostic and position.
p26_diag generic_tparam_value_return 6:13 "type parameter 'T' cannot be used as a value"
p26_diag generic_tparam_value_arg 11:15 "type parameter 'T' cannot be used as a value"
p26_diag generic_tparam_value_mul 6:30 "type parameter 'T' cannot be used as a value"
p26_diag generic_tparam_value_add 6:30 "type parameter 'T' cannot be used as a value"
# SH-66: the two silent paths SH-62 / SH-64 left open. An array dimension is
# copied verbatim, so it is not a substitution point either; and a template has
# no C symbol, so a bare template name is never a value.
p26_diag generic_tparam_array_dim 6:8 "type parameter 'T' cannot be used in an array dimension"
p26_diag generic_template_value 10:23 "generic function 'id' needs a type argument"

# E8: `ct check` shares the parser diagnostics, so the same fixtures fail
# in check mode with the same wording (no separate check channel).
p26_chk() {
    if "$work/ct-ast" check "test/ast/errors/$1.ct" \
            >"$work/p26c.out" 2>"$work/p26c.err"; then
        bad "p26_check_$1" "expected a non-zero exit"
    elif grep -qF "$2" "$work/p26c.err"; then
        ok "p26_check_$1"
    else
        bad "p26_check_$1" "$(head -2 "$work/p26c.err")"
    fi
}
p26_chk generic_missing_arg "generic function 'id' needs a type argument"
# P34 S1b: L26-2 lifted — `pub T id<T>(T x)` is now legal.
p26_chk generic_two_params "only one type parameter is supported"
p26_chk generic_void_arg "'void' cannot be a generic type argument"
p26_chk generic_recursive "recursive generic calls are not supported"
p26_chk generic_too_many "too many generic instances in this unit"
p26_chk generic_generic_selector "type parameter cannot be used inside _Generic"
p26_chk generic_tparam_value_return "type parameter 'T' cannot be used as a value"
p26_chk generic_tparam_value_arg "type parameter 'T' cannot be used as a value"
p26_chk generic_tparam_value_mul "type parameter 'T' cannot be used as a value"
p26_chk generic_tparam_value_add "type parameter 'T' cannot be used as a value"
p26_chk generic_tparam_array_dim "type parameter 'T' cannot be used in an array dimension"
p26_chk generic_template_value "generic function 'id' needs a type argument"

# Phase 28 (28.1): one optional trait bound on a type parameter. The bound is
# resolved and validated while the declaration is parsed, before any instance
# exists, so the negatives run in compile mode and again through `ct check`
# (E28-3 / E28-7 share one wording).
p28_diag() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p28d.c" \
            >"$work/p28d.out" 2>"$work/p28d.err"; then
        bad "p28_diag_$1" "expected a non-zero exit"
    elif grep -qF "test/ast/errors/$1.ct:$2: error: $3" "$work/p28d.err"; then
        ok "p28_diag_$1"
    else
        bad "p28_diag_$1" "$(head -2 "$work/p28d.err")"
    fi
}
p28_diag generic_bound_unknown 6:11 "unknown trait 'Nope' in a generic bound"
p28_diag generic_bound_multi 10:19 "only one trait bound is supported"
p28_diag generic_bound_builtin 7:11 "trait 'Drop' cannot bound a type parameter"

p28_chk() {
    if "$work/ct-ast" check "test/ast/errors/$1.ct" \
            >"$work/p28c.out" 2>"$work/p28c.err"; then
        bad "p28_check_$1" "expected a non-zero exit"
    elif grep -qF "$2" "$work/p28c.err"; then
        ok "p28_check_$1"
    else
        bad "p28_check_$1" "$(head -2 "$work/p28c.err")"
    fi
}
p28_chk generic_bound_unknown "unknown trait 'Nope' in a generic bound"
p28_chk generic_bound_multi "only one trait bound is supported"
p28_chk generic_bound_builtin "trait 'Drop' cannot bound a type parameter"

p28_diag generic_bound_missing_impl 24:12 "type argument 'Point' does not implement trait 'Compare'"
p28_diag generic_bound_nonstruct 16:12 "type argument 'int' cannot satisfy trait 'Compare' (not a struct)"
p28_diag generic_bound_no_method 8:14 "trait 'Compare' has no method 'nope'"
p28_chk generic_bound_missing_impl "type argument 'Point' does not implement trait 'Compare'"
p28_chk generic_bound_nonstruct "type argument 'int' cannot satisfy trait 'Compare' (not a struct)"
p28_chk generic_bound_no_method "trait 'Compare' has no method 'nope'"

# A3's negative: the D21 closure rules are not relaxed inside a template. The
# same "cannot escape through 'return'" wording and position apply.
p28_diag generic_closure_escape 24:5 "a closure cannot escape through 'return'"
p28_chk generic_closure_escape "a closure cannot escape through 'return'"

# A `.m.ct` static trait has no vtable, so it cannot bound a type parameter;
# only build mode can declare one, hence a module fixture.
if "$work/ct-ast" build --emit-c test/modules/p28_bound_static/prog.ct \
        -o "$work/p28bs" >"$work/p28bs.out" 2>"$work/p28bs.err"; then
    bad "p28_static_trait_bound" "expected a non-zero exit"
elif grep -qF "test/modules/p28_bound_static/prog.ct:6:11: error: trait 'Fac' cannot bound a type parameter" \
        "$work/p28bs.err"; then
    ok "p28_static_trait_bound"
else
    bad "p28_static_trait_bound" "$(head -2 "$work/p28bs.err")"
fi

# E28-1: the two value instances each call their own vtable object, and the
# body carries no interface vptr read (D28/D28-3). E28-4: the instance body
# names neither the type parameter nor `__<trait>_vptr`.
rm -rf "$work/p28g136" "$work/p28g137"
mkdir -p "$work/p28g136" "$work/p28g137"
if "$work/ct-ast" test/ast/136_generic_bound/prog.ct -o "$work/p28g136/prog.c" \
        >"$work/p28g136.out" 2>"$work/p28g136.err" \
   && grep -qF 'static struct Point max2__ct1(struct Point, struct Point);' "$work/p28g136/prog.c" \
   && grep -qF 'static struct Range max2__ct2(struct Range, struct Range);' "$work/p28g136/prog.c" \
   && grep -qF 'Point_Compare_vtable.cmp(&a, (&b))' "$work/p28g136/prog.c" \
   && grep -qF 'Range_Compare_vtable.cmp(&a, (&b))' "$work/p28g136/prog.c" \
   && ! grep -qF '__ord_vptr' "$work/p28g136/prog.c" \
   && ! sed -n '/^static struct Point max2__ct1(struct Point a/,/^}/p' "$work/p28g136/prog.c" \
        | grep -qE '__[a-z]+_vptr'; then
    ok "p28_bound_value (two structs, one vtable slot each, no vptr read)"
else
    bad "p28_bound_value" "$(cat "$work/p28g136.err" 2>/dev/null | head -3)"
fi

rm -rf "$work/p28g137"
mkdir -p "$work/p28g137"
if "$work/ct-ast" test/ast/137_generic_bound_ptr/prog.ct -o "$work/p28g137/prog.c" \
        >"$work/p28g137.out" 2>"$work/p28g137.err" \
   && grep -qF 'Point_Compare_vtable.cmp(a, b)' "$work/p28g137/prog.c" \
   && grep -qF 'Point_Compare_vtable.cmp(&xs[i], (&xs[j]))' "$work/p28g137/prog.c" \
   && grep -qF 'Point_Compare_vtable.label(&xs[i])' "$work/p28g137/prog.c" \
   && ! sed -n '/^static struct Point \* maxp__ct1/,/^}/p' "$work/p28g137/prog.c" \
        | grep -qE '__[a-z]+_vptr'; then
    ok "p28_bound_ptr (pointer receiver, array element, default method)"
else
    bad "p28_bound_ptr" "$(cat "$work/p28g137.err" 2>/dev/null | head -3)"
fi

# A5: the impl lives in the dependency unit, the template and its instance in
# the entry unit. The header exports the vtable object only (E28-2).
rm -rf "$work/p28xu"
mkdir -p "$work/p28xu"
if "$work/ct-ast" build --emit-c test/modules/p28_bound_cross_unit/prog.ct \
        -o "$work/p28xu" >"$work/p28xu.out" 2>"$work/p28xu.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/p28xu"/*.c -o "$work/p28xu/prog" \
        >"$work/p28xu.cc" 2>&1 \
   && "$work/p28xu/prog" > "$work/p28xu.run" \
   && cmp -s "$work/p28xu.run" test/modules/p28_bound_cross_unit/expected.out \
   && grep -qF 'extern struct Compare_vtbl Point_Compare_vtable;' "$work/p28xu/lib.h" \
   && grep -qF 'Point_Compare_vtable.cmp(&a, (&b))' "$work/p28xu/prog.c"; then
    ok "p28_bound_cross_unit (impl in the dependency, instance in the entry)"
else
    bad "p28_bound_cross_unit" "$(cat "$work/p28xu.err" "$work/p28xu.cc" 2>/dev/null | head -5)"
fi

# P20-03 regression: the arity pre-check must fold integer aliases exactly as
# the emitter does. Each row is `host|receiver|alias-decl`: the `.m.ct` host
# spelling and the consumer's receiver spelling name the same integer type but
# differ by an alias fold (`unsigned` / `unsigned int`, `long` / `long int`,
# `signed long` / `long`, ...), or one side is a `pub type` synonym. `tnorm`
# used to skip the fold, so the recipe still expanded while the pre-check saw
# no host and a surplus actual was dropped with no diagnostic at all.
ha_cases=(
    'unsigned|unsigned int|'
    'unsigned int|unsigned|'
    'signed|int|'
    'signed int|int|'
    'long|long int|'
    'long int|long|'
    'unsigned long|unsigned long int|'
    'unsigned long int|unsigned long|'
    'long long|long long int|'
    'long long int|long long|'
    'unsigned long long|unsigned long long int|'
    'unsigned long long int|unsigned long long|'
    'short|short int|'
    'short int|short|'
    'unsigned short|unsigned short int|'
    'unsigned short int|unsigned short|'
    'signed short|short|'
    'signed long|long|'
    'signed long long|long long|'
    'MyU|unsigned int|pub type MyU = unsigned;'
    'unsigned|MyU|pub type MyU = unsigned;'
    'MyL|long int|pub type MyL = long;'
)
ha_i=0
for ha in "${ha_cases[@]}"; do
    ha_i=$((ha_i + 1))
    ha_host="${ha%%|*}"
    ha_rest="${ha#*|}"
    ha_recv="${ha_rest%%|*}"
    ha_decl="${ha_rest#*|}"
    ha="$work/ha$ha_i"
    rm -rf "$ha"
    mkdir -p "$ha/mout" "$ha/fout"
    {
        if [ -n "$ha_decl" ]; then printf '%s\n\n' "$ha_decl"; fi
        printf 'pub trait Num {\n    long long plus(int d);\n}\n\n'
        printf 'map trait Num for type %s {\n    plus(v, d) -> ct_add(v, d);\n}\n' "$ha_host"
    } >"$ha/num.m.ct"
    printf 'static inline long long ct_add(long long v, int d) { return v + d; }\n' >"$ha/num.shim.h"
    printf 'import num;\nint main(void) { %s x = 1; return (int)x.plus(2, 3); }\n' \
        "$ha_recv" >"$ha/more.ct"
    printf 'import num;\nint main(void) { %s x = 1; return (int)x.plus(); }\n' \
        "$ha_recv" >"$ha/few.ct"
    if "$work/ct-ast" build --emit-c -I "$ha" "$ha/more.ct" -o "$ha/mout" \
            >"$ha/more.out" 2>"$ha/more.err" \
       && grep -qF "warning: arity mismatch: 'plus' takes 1 argument(s), 2 given" "$ha/more.err"; then
        ok "p20_host_arity_int_more[$ha_i $ha_host/$ha_recv]"
    else
        bad "p20_host_arity_int_more[$ha_i $ha_host/$ha_recv]" "$(head -3 "$ha/more.err")"
    fi
    if "$work/ct-ast" build --emit-c -I "$ha" "$ha/few.ct" -o "$ha/fout" \
            >"$ha/few.out" 2>"$ha/few.err"; then
        bad "p20_host_arity_int_few[$ha_i $ha_host/$ha_recv]" "expected a non-zero exit"
    elif grep -qF "a map call has fewer arguments than its binding" "$ha/few.err"; then
        ok "p20_host_arity_int_few[$ha_i $ha_host/$ha_recv]"
    else
        bad "p20_host_arity_int_few[$ha_i $ha_host/$ha_recv]" "$(head -3 "$ha/few.err")"
    fi
done

# The exact spelling still binds and runs, so the fold widened the pre-check
# rather than breaking the recipe.
rm -rf "$work/haok"
mkdir -p "$work/haok/out"
printf 'pub trait Num {\n    long long plus(int d);\n}\n\nmap trait Num for type unsigned {\n    plus(v, d) -> ct_add(v, d);\n}\n' >"$work/haok/num.m.ct"
printf 'static inline long long ct_add(long long v, int d) { return v + d; }\n' >"$work/haok/num.shim.h"
printf 'import num;\n#include <stdio.h>\nint main(void) { unsigned x = 1; printf("%%lld\\n", x.plus(2)); return 0; }\n' >"$work/haok/main.ct"
if "$work/ct-ast" build --emit-c -I "$work/haok" "$work/haok/main.ct" -o "$work/haok/out" \
        >"$work/haok.out" 2>"$work/haok.err" \
   && ! grep -qF "arity mismatch" "$work/haok.err" \
   && "$CC" -Wall -Wextra -std=c99 -I "$work/haok" "$work/haok/out"/*.c -o "$work/haok.bin" 2>"$work/haok.cc" \
   && [ "$("$work/haok.bin")" = "3" ]; then
    ok "p20_host_arity_int_exact (same spelling binds and runs)"
else
    bad "p20_host_arity_int_exact" "$(cat "$work/haok.err" "$work/haok.cc" 2>/dev/null | head -5)"
fi

# P20-06: `namespace = app` in a package's ct.pkg claims the first import
# segment, so `import app::model::Item` names model/Item.h.ct at the root; the
# doubled `app/legacy/Thing.h.ct` layout keeps resolving as the fallback.
rm -rf "$mod-pns"
mkdir -p "$mod-pns"
if "$work/ct-ast" build --emit-c -I test/modules/p20_pkg_namespace \
        test/modules/p20_pkg_namespace/main.ct -o "$mod-pns" \
        >"$work/mpns.out" 2>"$work/mpns.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-pns"/*.c -o "$work/mpns.bin" 2>"$work/mpns.cc" \
   && "$work/mpns.bin" >"$work/mpns.stdout" 2>&1 \
   && cmp -s "$work/mpns.stdout" test/modules/p20_pkg_namespace/expected.out; then
    ok "p20_pkg_namespace (ct.pkg namespace = app; flat and doubled layouts)"
else
    bad "p20_pkg_namespace" "$(cat "$work/mpns.err" "$work/mpns.cc" "$work/mpns.stdout")"
fi

# One unit name in two `-I` roots is an error that names both, never a silent
# first-root win.
rm -rf "$mod-pdu"
mkdir -p "$mod-pdu"
if "$work/ct-ast" build --emit-c -I test/modules/p20_dup_unit/a \
        -I test/modules/p20_dup_unit/b test/modules/p20_dup_unit/main.ct \
        -o "$mod-pdu" >"$work/mpdu.out" 2>"$work/mpdu.err"; then
    bad "p20_dup_unit" "expected a non-zero exit"
elif grep -qF "unit 'Uart' exists in two import roots: 'test/modules/p20_dup_unit/a/Uart.h.ct' and 'test/modules/p20_dup_unit/b/Uart.h.ct'" \
        "$work/mpdu.err"; then
    ok "p20_dup_unit (one unit in two import roots names both)"
else
    bad "p20_dup_unit" "$(head -2 "$work/mpdu.err")"
fi

# Naming a package is not an exemption either: two plain `-I` roots (neither has
# a ct.pkg) that both ship the unit are reported the same way. Only an identical
# path, an identical root string, or a first hit in the importer's own directory
# are exempt.
rm -rf "$mod-pdp"
mkdir -p "$mod-pdp"
if "$work/ct-ast" build --emit-c -I test/modules/p20_dup_plain/a \
        -I test/modules/p20_dup_plain/b test/modules/p20_dup_plain/main.ct \
        -o "$mod-pdp" >"$work/mpdp.out" 2>"$work/mpdp.err"; then
    bad "p20_dup_plain" "expected a non-zero exit"
elif grep -qF "unit 'Uart' exists in two import roots: 'test/modules/p20_dup_plain/a/Uart.h.ct' and 'test/modules/p20_dup_plain/b/Uart.h.ct'" \
        "$work/mpdp.err"; then
    ok "p20_dup_plain (two plain -I roots, no ct.pkg, still a clash)"
else
    bad "p20_dup_plain" "$(head -2 "$work/mpdp.err")"
fi

# M1: one root spelled twice (`-I a -I ./a`) is one directory. The roots and the
# resolved units are compared after realpath, so the duplicate names one file
# instead of a phantom clash.
rm -rf "$mod-m1s"
mkdir -p "$mod-m1s"
if "$work/ct-ast" build --emit-c -I test/modules/p20_dup_samepath/a \
        -I ./test/modules/p20_dup_samepath/a \
        test/modules/p20_dup_samepath/main.ct -o "$mod-m1s" \
        >"$work/m1s.out" 2>"$work/m1s.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-m1s"/*.c -o "$work/m1s.bin" 2>"$work/m1s.cc" \
   && "$work/m1s.bin" >"$work/m1s.stdout" 2>&1 \
   && cmp -s "$work/m1s.stdout" test/modules/p20_dup_samepath/expected.out; then
    ok "p20_dup_samepath (-I a -I ./a names one root)"
else
    bad "p20_dup_samepath" "$(cat "$work/m1s.err" "$work/m1s.cc" "$work/m1s.stdout")"
fi

# M1: the ct.pkg namespace check normalizes the same way -- one root spelled
# twice is one package, while two different roots claiming one namespace clash.
rm -rf "$mod-m1n"
mkdir -p "$mod-m1n"
if "$work/ct-ast" build --emit-c -I test/modules/p20_ns_clash/a \
        -I ./test/modules/p20_ns_clash/a \
        test/modules/p20_ns_clash/main.ct -o "$mod-m1n" \
        >"$work/m1n.out" 2>"$work/m1n.err"; then
    ok "p20_ns_samepath (one ct.pkg namespace, root spelled twice)"
else
    bad "p20_ns_samepath" "$(head -2 "$work/m1n.err")"
fi
if "$work/ct-ast" build --emit-c -I test/modules/p20_ns_clash/a \
        -I test/modules/p20_ns_clash/b \
        test/modules/p20_ns_clash/main.ct -o "$mod-m1n" \
        >"$work/m1nb.out" 2>"$work/m1nb.err"; then
    bad "p20_ns_clash" "expected a non-zero exit"
elif grep -qF "package namespace 'app' is declared by two import roots: 'test/modules/p20_ns_clash/a' and 'test/modules/p20_ns_clash/b'" \
        "$work/m1nb.err"; then
    ok "p20_ns_clash (two roots claiming one namespace)"
else
    bad "p20_ns_clash" "$(head -2 "$work/m1nb.err")"
fi

# M6: one import exists in the flat layout and in the doubled compatibility
# layout. The resolver must report the pair instead of silently taking the flat
# candidate.
rm -rf "$work/mod-m6"
mkdir -p "$work/mod-m6"
if "$work/ct-ast" build --emit-c -I test/modules/p20_pkg_layout_clash \
        test/modules/p20_pkg_layout_clash/main.ct -o "$work/mod-m6" \
        >"$work/m6.out" 2>"$work/m6.err"; then
    bad "p20_pkg_layout_clash" "expected a non-zero exit"
elif grep -qF "import 'app/model/Item' is ambiguous: both test/modules/p20_pkg_layout_clash/model/Item.h.ct and test/modules/p20_pkg_layout_clash/app/model/Item.h.ct exist" \
        "$work/m6.err"; then
    ok "p20_pkg_layout_clash (the flat and doubled layouts both hit)"
else
    bad "p20_pkg_layout_clash" "$(head -2 "$work/m6.err")"
fi

rm -rf "$mod-hdr"
mkdir -p "$mod-hdr"
if "$work/ct-ast" build --emit-c test/modules/hdr/main.h.ct -o "$mod-hdr" \
        >"$work/mhdr.out" 2>"$work/mhdr.err" \
   && grep -q '^#include <stdio.h>$' "$mod-hdr/main.h" \
   && [ -z "$(hdr_instances "$mod-hdr/main.h")" ] \
   && "$CC" -Wall -Wextra -std=c99 "$mod-hdr"/*.c -o "$work/mhdr.bin" 2>"$work/mhdr.cc" \
   && "$work/mhdr.bin" >"$work/mhdr.stdout" 2>&1 \
   && cmp -s "$work/mhdr.stdout" test/modules/hdr/expected.out; then
    ok "hdr (foo.h.ct header unit; the source's #include leads main.h)"
else
    bad "hdr" "$(cat "$work/mhdr.err" "$work/mhdr.cc" "$work/mhdr.stdout")"
fi

echo
echo "== static map units (batch 38) =="
# A `.m.ct` unit is a mapping, not an implementation: it writes no `.c` / `.h`,
# and every bound call is expanded at the consumer's call site. The generated C
# must therefore read like hand-written C -- no wrapper, no interface value.
rm -rf "$mod-mu"
mkdir -p "$mod-mu"
if "$work/ct-ast" build --emit-c test/modules/map_unit/main.ct -o "$mod-mu" \
        >"$work/mmu.out" 2>"$work/mmu.err" \
   && [ ! -f "$mod-mu/libc.c" ] && [ ! -f "$mod-mu/libc.h" ] \
   && grep -qF 'atoi((a))' "$mod-mu/main.c" \
   && grep -qF "memset((b), ('z'), (3))" "$mod-mu/main.c" \
   && grep -qF 'getenv(("HOME"))' "$mod-mu/main.c" \
   && ! grep -Eq '_iface|_vtbl|vtable|vt->|(void \*)0' "$mod-mu/main.c" \
   && grep -q '^#include <stdlib.h>' "$mod-mu/main.c" \
   && ! grep -q 'libc\.c' "$work/mmu.out" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-mu"/*.c -o "$work/mmu.bin" 2>"$work/mmu.cc" \
   && "$work/mmu.bin" >"$work/mmu.stdout" 2>&1 \
   && cmp -s "$work/mmu.stdout" test/modules/map_unit/expected.out; then
    ok "map_unit (a namespace + type host expands inline; no artefact, no vtable)"
else
    bad "map_unit" "$(cat "$work/mmu.err" "$work/mmu.cc" "$work/mmu.stdout" 2>/dev/null | head -5)"
fi

rm -rf "$mod-mut"
mkdir -p "$mod-mut"
if "$work/ct-ast" build --emit-c test/modules/map_unit_type/main.ct -o "$mod-mut" \
        >"$work/mmut.out" 2>"$work/mmut.err" \
   && grep -qF 'strtol((a), &(char *){0}, 10)' "$mod-mut/main.c" \
   && grep -qF '((void)(a), ct_probe_void(""))' "$mod-mut/main.c" \
   && "$CC" -Wall -Wextra -std=c99 -I test/modules/map_unit_type/ctypes \
        "$mod-mut"/*.c -o "$work/mmut.bin" 2>"$work/mmut.cc" \
   && "$work/mmut.bin" >"$work/mmut.stdout" 2>&1 \
   && cmp -s "$work/mmut.stdout" test/modules/map_unit_type/expected.out; then
    ok "map_unit_type (array decay, pointer argument, compound literal, unused receiver)"
else
    bad "map_unit_type" "$(cat "$work/mmut.err" "$work/mmut.cc" "$work/mmut.stdout" 2>/dev/null | head -5)"
fi

# One mapping, two consumers (a `.h.ct` and a `.ct`): neither one gets a
# wrapper symbol, and the map JSON describes the static shape.
rm -rf "$mod-muc"
mkdir -p "$mod-muc"
if "$work/ct-ast" build --emit-c --emit-map "$work/mmuc.map" test/modules/map_unit_cross/main.ct \
        -o "$mod-muc" >"$work/mmuc.out" 2>"$work/mmuc.err" \
   && [ -f "$mod-muc/main.c" ] && [ -f "$mod-muc/parse.c" ] && [ -f "$mod-muc/parse.h" ] \
   && [ ! -f "$mod-muc/text.c" ] && [ ! -f "$mod-muc/text.h" ] \
   && grep -qF 'atoi((s))' "$mod-muc/parse.c" \
   && grep -q '^#include <stdlib.h>' "$mod-muc/parse.c" \
   && grep -q '^#include <stdlib.h>' "$mod-muc/main.c" \
   && grep -q '"static":true' "$work/mmuc.map" \
   && grep -q '"host":"type"' "$work/mmuc.map" \
   && grep -q '"type":"char \*"' "$work/mmuc.map" \
   && grep -q '"inline":true' "$work/mmuc.map" \
   && ! grep -q 'text\.c' "$work/mmuc.out" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-muc"/*.c -o "$work/mmuc.bin" 2>"$work/mmuc.cc" \
   && "$work/mmuc.bin" >"$work/mmuc.stdout" 2>&1 \
   && cmp -s "$work/mmuc.stdout" test/modules/map_unit_cross/expected.out; then
    ok "map_unit_cross (one .m.ct shared by a .h.ct and a .ct consumer; both inline)"
else
    bad "map_unit_cross" "$(cat "$work/mmuc.err" "$work/mmuc.cc" "$work/mmuc.stdout" 2>/dev/null | head -5)"
fi

# A chain of mapping units: `lib.m.ct` imports `base.m.ct`, so one consumer sees
# both maps and both prologues, and a change to the deeper unit still reaches
# the consumer's cache (the `.m` dependency digest follows the chain).
rm -rf "$work/mmch" "$work/mmchsrc"
mkdir -p "$work/mmch"
cp -r test/modules/map_unit_chain "$work/mmchsrc"
if "$work/ct-ast" build --emit-c "$work/mmchsrc/main.ct" -o "$work/mmch" \
        >"$work/mmch.out" 2>"$work/mmch.err" \
   && [ ! -f "$work/mmch/lib.c" ] && [ ! -f "$work/mmch/lib.h" ] \
   && [ ! -f "$work/mmch/base.c" ] && [ ! -f "$work/mmch/base.h" ] \
   && grep -q '^#include <stdlib.h>' "$work/mmch/main.c" \
   && grep -q '^#include <string.h>' "$work/mmch/main.c" \
   && ! grep -Eq '_iface|_vtbl|vtable|vt->|(void \*)0' "$work/mmch/main.c" \
   && ! grep -q 'lib\.c' "$work/mmch.out" \
   && "$CC" -Wall -Wextra -std=c99 "$work/mmch"/*.c -o "$work/mmch.bin" 2>"$work/mmch.cc" \
   && "$work/mmch.bin" >"$work/mmch.stdout" 2>&1 \
   && cmp -s "$work/mmch.stdout" test/modules/map_unit_chain/expected.out; then
    ok "map_unit_chain (a mapping unit imports another; both prologues reach the consumer)"
else
    bad "map_unit_chain" "$(cat "$work/mmch.err" "$work/mmch.cc" "$work/mmch.stdout" 2>/dev/null | head -5)"
fi

stamp() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
t0=$(stamp "$work/mmch/main.c")
"$work/ct-ast" build --emit-c "$work/mmchsrc/main.ct" -o "$work/mmch" >/dev/null 2>&1
if [ "$(stamp "$work/mmch/main.c")" = "$t0" ]; then
    ok "map_unit_chain cache: a warm build reuses the consumer"
else
    bad "map_unit_chain cache" "main.c was regenerated although nothing changed"
fi
sleep 1
touch "$work/mmchsrc/lib/base.m.ct"
"$work/ct-ast" build --emit-c "$work/mmchsrc/main.ct" -o "$work/mmch" >/dev/null 2>&1
if [ "$(stamp "$work/mmch/main.c")" != "$t0" ]; then
    ok "map_unit_chain cache: a transitive .m.ct change rebuilds the consumer"
else
    bad "map_unit_chain cache" "main.c was not rebuilt after the transitive .m.ct changed"
fi

# `sizeof p` is not an evaluation (spec §4.10): a side-effecting actual is still
# wrapped in the `(void)(…)` prefix, and two occurrences are not a duplicate use.
rm -rf "$work/mso"
mkdir -p "$work/mso/lib" "$work/mso/out"
printf '#include <stdlib.h>\nnamespace lib;\npub trait T { int sz(); }\nmap trait T for type char * { sz(s) -> pair(sizeof s, 0); }\npub trait U { int twice(); }\nmap trait U for type char * { twice(s) -> pair(sizeof s, sizeof s); }\n' >"$work/mso/lib/lib.m.ct"
printf 'import lib::lib;\n#include <stdio.h>\nstatic int hits;\nint pair(int a, int b) { return a + b; }\nchar *side(void) { hits++; return "x"; }\nint main(void)\n{\n    int n = side().sz();\n    int m = side().twice();\n    (void)n;\n    (void)m;\n    printf("%%d\\n", hits);\n    return 0;\n}\n' >"$work/mso/main.ct"
if "$work/ct-ast" build --emit-c "$work/mso/main.ct" -o "$work/mso/out" \
        >"$work/mso.out" 2>"$work/mso.err" \
   && grep -qF 'sizeof(char *)' "$work/mso/out/main.c" \
   && grep -qF 'sizeof(char *), sizeof(char *)' "$work/mso/out/main.c" \
   && grep -qF '(void)(' "$work/mso/out/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$work/mso/out"/*.c -o "$work/mso.bin" 2>"$work/mso.cc" \
   && "$work/mso.bin" >"$work/mso.stdout" 2>&1 \
   && [ "$(cat "$work/mso.stdout")" = "2" ]; then
    ok "static sizeof (not evaluated; the prefix keeps the side effect; duplicates allowed)"
else
    bad "static sizeof" "$(cat "$work/mso.err" "$work/mso.cc" "$work/mso.stdout" 2>/dev/null | head -5)"
fi

# A mapping unit may ship a sibling C shim (batch 39): `<base>.shim.h` declares
# what a recipe cannot spell (a global such as `errno`) and `<base>.shim.c`
# carries the implementation. The consumer's `.c` includes the header by base
# name, and the suggested `cc` line carries the include root and the shim source.
rm -rf "$work/mmsh" "$work/mmshsrc"
mkdir -p "$work/mmsh"
cp -r test/modules/map_unit_shim "$work/mmshsrc"
if "$work/ct-ast" build --emit-c "$work/mmshsrc/main.ct" -o "$work/mmsh" \
        >"$work/mmsh.out" 2>"$work/mmsh.err" \
   && [ ! -f "$work/mmsh/lib.c" ] && [ ! -f "$work/mmsh/lib.h" ] \
   && grep -qF '#include "lib.shim.h"' "$work/mmsh/main.c" \
   && grep -qF -- "-I $work/mmshsrc/lib" "$work/mmsh.out" \
   && grep -qF "$work/mmshsrc/lib/lib.shim.c" "$work/mmsh.out" \
   && "$CC" -Wall -Wextra -std=c99 -I "$work/mmshsrc/lib" "$work/mmsh"/*.c \
        "$work/mmshsrc/lib/lib.shim.c" -o "$work/mmsh.bin" 2>"$work/mmsh.cc" \
   && "$work/mmsh.bin" >"$work/mmsh.stdout" 2>&1 \
   && cmp -s "$work/mmsh.stdout" test/modules/map_unit_shim/expected.out; then
    ok "map_unit_shim (sibling shim header/source wired into the consumer)"
else
    bad "map_unit_shim" "$(cat "$work/mmsh.err" "$work/mmsh.cc" "$work/mmsh.stdout" 2>/dev/null | head -5)"
fi

t0=$(stamp "$work/mmsh/main.c")
"$work/ct-ast" build --emit-c "$work/mmshsrc/main.ct" -o "$work/mmsh" >/dev/null 2>&1
if [ "$(stamp "$work/mmsh/main.c")" = "$t0" ]; then
    ok "map_unit_shim cache: a warm build reuses the consumer"
else
    bad "map_unit_shim cache" "main.c was regenerated although nothing changed"
fi
sleep 1
touch "$work/mmshsrc/lib/lib.shim.h"
"$work/ct-ast" build --emit-c "$work/mmshsrc/main.ct" -o "$work/mmsh" >/dev/null 2>&1
if [ "$(stamp "$work/mmsh/main.c")" != "$t0" ]; then
    ok "map_unit_shim cache: a shim change rebuilds the consumer"
else
    bad "map_unit_shim cache" "main.c was not rebuilt after the shim header changed"
fi

# A static map's JSON names its shim, so a tool that consumes the map (an IDE,
# a packager) can carry the two C files; a map without one keeps the old shape.
rm -rf "$work/mmshmap" "$work/mnumap"
mkdir -p "$work/mmshmap" "$work/mnumap"
if "$work/ct-ast" build --emit-c --emit-map "$work/mmshmap/main.map" "$work/mmshsrc/main.ct" \
        -o "$work/mmshmap" >"$work/mmshmap.out" 2>"$work/mmshmap.err" \
   && grep -qF "\"shim\":{\"header\":\"$work/mmshsrc/lib/lib.shim.h\"" "$work/mmshmap/main.map" \
   && grep -qF "\"source\":\"$work/mmshsrc/lib/lib.shim.c\"" "$work/mmshmap/main.map" \
   && "$work/ct-ast" build --emit-c --emit-map "$work/mnumap/main.map" test/modules/map_unit/main.ct \
        -o "$work/mnumap" >/dev/null 2>&1 \
   && ! grep -qF '"shim"' "$work/mnumap/main.map"; then
    ok "map_unit_shim (--emit-map names the shim files; a plain map says nothing)"
else
    bad "map_unit_shim map JSON" "$(cat "$work/mmshmap.err" 2>/dev/null | head -5)"
fi

# A shim source without its header cannot declare anything for a recipe, so it
# is rejected by name rather than left for the linker.
rm -rf "$work/mbsc"
mkdir -p "$work/mbsc/lib" "$work/mbsc/out"
printf 'namespace lib;\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> ct_x(); }\n' \
    >"$work/mbsc/lib/lib.m.ct"
printf 'int ct_x(void) { return 1; }\n' >"$work/mbsc/lib/lib.shim.c"
printf 'import lib::lib;\n\nint main(void) { return lib::T.m(); }\n' >"$work/mbsc/main.ct"
if "$work/ct-ast" build --emit-c "$work/mbsc/main.ct" -o "$work/mbsc/out" \
        >"$work/mbsc.out" 2>"$work/mbsc.err"; then
    bad "batch 39: shim_source_without_header" "expected a non-zero exit"
elif grep -qF 'a shim source needs a matching .shim.h' "$work/mbsc.err" \
     && grep -qF "$work/mbsc/lib/lib.shim.h" "$work/mbsc.err"; then
    ok "batch 39 (shim_source_without_header)"
else
    bad "batch 39: shim_source_without_header" "$(head -2 "$work/mbsc.err")"
fi

# A shim header must be a regular file: a directory with that name is rejected
# up front rather than left to the C compiler's include search.
rm -rf "$work/mbsd"
mkdir -p "$work/mbsd/lib" "$work/mbsd/out"
printf 'namespace lib;\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> ct_x(); }\n' \
    >"$work/mbsd/lib/lib.m.ct"
mkdir "$work/mbsd/lib/lib.shim.h"
printf 'import lib::lib;\n\nint main(void) { return lib::T.m(); }\n' >"$work/mbsd/main.ct"
if "$work/ct-ast" build --emit-c "$work/mbsd/main.ct" -o "$work/mbsd/out" \
        >/dev/null 2>"$work/mbsd.err"; then
    bad "batch 39: shim_header_not_a_file" "expected a non-zero exit"
elif grep -qF 'a shim header is not a readable file' "$work/mbsd.err"; then
    ok "batch 39 (shim_header_not_a_file)"
else
    bad "batch 39: shim_header_not_a_file" "$(head -2 "$work/mbsd.err")"
fi

# Batch 40: a literal receiver reaches a type host, the shim beside the unit
# supplies what a recipe cannot spell, and two `toString()` calls in one
# expression take two ring slots -- a single static buffer would print `6 6`.
rm -rf "$work/mmlit"
mkdir -p "$work/mmlit"
if "$work/ct-ast" build --emit-c test/modules/map_unit_literals/main.ct -o "$work/mmlit" \
        >"$work/mmlit.out" 2>"$work/mmlit.err" \
   && [ ! -f "$work/mmlit/lit.c" ] && [ ! -f "$work/mmlit/lit.h" ] \
   && grep -qF '#include "lit.shim.h"' "$work/mmlit/main.c" \
   && grep -qF 'ct_lit_int((5))' "$work/mmlit/main.c" \
   && grep -qF 'ct_lit_str(("lit"))' "$work/mmlit/main.c" \
   && "$CC" -Wall -Wextra -std=c99 -I test/modules/map_unit_literals/lit "$work/mmlit"/*.c \
        -o "$work/mmlit.bin" 2>"$work/mmlit.cc" \
   && "$work/mmlit.bin" >"$work/mmlit.stdout" 2>&1 \
   && cmp -s "$work/mmlit.stdout" test/modules/map_unit_literals/expected.out; then
    ok "map_unit_literals (literal receivers, a sibling shim, two ring slots in one expression)"
else
    bad "map_unit_literals" "$(cat "$work/mmlit.err" "$work/mmlit.cc" "$work/mmlit.stdout" 2>/dev/null | head -5)"
fi

# `ct check` accepts a mapping unit (P0-3): a valid one exits 0, and a binding
# whose parameter count drifts from the trait's method is still an error.
if "$work/ct-ast" check test/modules/map_unit_literals/lit/lit.m.ct \
        >"$work/mchk.out" 2>"$work/mchk.err"; then
    ok "ct check (a valid .m.ct exits 0)"
else
    bad "ct check (valid .m.ct)" "$(head -2 "$work/mchk.err")"
fi
printf 'namespace drift;\npub trait T { int m(); }\nmap trait T for type char * { m(s, extra) -> strchr(s, extra); }\n' \
    >"$work/drift.m.ct"
if "$work/ct-ast" check "$work/drift.m.ct" >"$work/mchk2.out" 2>"$work/mchk2.err"; then
    bad "ct check (signature drift)" "expected a non-zero exit"
elif grep -qF "a type host binding has 2 parameters but method 'm' takes 0" "$work/mchk2.err"; then
    ok "ct check (a drifted .m.ct signature exits non-zero)"
else
    bad "ct check (signature drift)" "$(head -2 "$work/mchk2.err")"
fi

# Batch 41: a static map is expanded at the call site, so a method may end in
# `...` and the recipe forwards every actual the named parameters left over.
# The same fixture drops the trait segment (`std::io::puts`), which resolves to
# the one recipe bound on that namespace host.
rm -rf "$mod-mmv"
mkdir -p "$mod-mmv"
if "$work/ct-ast" build --emit-c test/modules/map_unit_varargs/main.ct -o "$mod-mmv" \
        >"$work/mmv.out" 2>"$work/mmv.err" \
   && [ ! -f "$mod-mmv/io.c" ] && [ ! -f "$mod-mmv/io.h" ] \
   && grep -qF 'puts(("ns-puts"))' "$mod-mmv/main.c" \
   && grep -qF 'printf(("ns-zero\n"))' "$mod-mmv/main.c" \
   && grep -qF 'printf(("ns-one %d\n"), (1))' "$mod-mmv/main.c" \
   && grep -qF 'printf(("ns-six %d %d %d %d %d %d\n"), (1), (2), (3), (4), (5), (6))' \
        "$mod-mmv/main.c" \
   && grep -qF 'snprintf((buf), (sizeof(buf)), ("%d/%d"), (7), (9))' "$mod-mmv/main.c" \
   && grep -qF 'printf(("type %d %d\n"), (4), (5))' "$mod-mmv/main.c" \
   && ! grep -Eq '_iface|_vtbl|vtable|vt->' "$mod-mmv/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-mmv"/*.c -o "$work/mmv.bin" 2>"$work/mmv.cc" \
   && "$work/mmv.bin" >"$work/mmv.stdout" 2>&1 \
   && cmp -s "$work/mmv.stdout" test/modules/map_unit_varargs/expected.out; then
    ok "map_unit_varargs (0/1/3/6 forwarded actuals, snprintf reorder, bare namespace call)"
else
    bad "map_unit_varargs" \
        "$(cat "$work/mmv.err" "$work/mmv.cc" "$work/mmv.stdout" 2>/dev/null | head -5)"
fi

# P20-01: two packages bind `len` to `char *`. A qualified call picks one map;
# the unqualified call still fails and names both qualified spellings.
rm -rf "$work/p20mm"
mkdir -p "$work/p20mm"
if "$work/ct-ast" build --emit-c test/modules/p20_two_pkg_same_method/main.ct -o "$work/p20mm" \
        >"$work/p20mm.out" 2>"$work/p20mm.err" \
   && grep -qF 'strlen((s))' "$work/p20mm/main.c" \
   && grep -qF 'strlen((buf))' "$work/p20mm/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$work/p20mm"/*.c -o "$work/p20mm.bin" 2>"$work/p20mm.cc" \
   && "$work/p20mm.bin" >"$work/p20mm.stdout" 2>&1 \
   && cmp -s "$work/p20mm.stdout" test/modules/p20_two_pkg_same_method/expected.out; then
    ok "p20_two_pkg_same_method (qualified call picks one of two char * len maps)"
else
    bad "p20_two_pkg_same_method" \
        "$(cat "$work/p20mm.err" "$work/p20mm.cc" "$work/p20mm.stdout" 2>/dev/null | head -5)"
fi
if "$work/ct-ast" build --emit-c test/modules/p20_two_pkg_same_method/ambig.ct -o "$work/p20mm" \
        >"$work/p20amb.out" 2>"$work/p20amb.err"; then
    bad "p20_two_pkg_ambiguous" "expected a non-zero exit"
elif grep -qF "use 'a_ALen::len' or 'b_BLen::len'" "$work/p20amb.err" \
     && grep -qF "ambiguous type-host map for method 'len' on type 'char *'" "$work/p20amb.err"; then
    ok "p20_two_pkg_ambiguous (both qualified spellings in the hint)"
else
    bad "p20_two_pkg_ambiguous" "$(head -3 "$work/p20amb.err")"
fi

# P20-01 builds the qualified-call node itself (`aux == 6`), so it must still run
# the arity check the other static-recipe forms run; otherwise the recipe drops
# an extra actual with no diagnostic (the receiver is not one of the method's
# parameters).
rm -rf "$work/p20qa"
mkdir -p "$work/p20qa"
if "$work/ct-ast" build --emit-c test/modules/p20_qual_arity/ok.ct -o "$work/p20qa" \
        >"$work/p20qa.out" 2>"$work/p20qa.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/p20qa"/*.c -o "$work/p20qa.bin" 2>"$work/p20qa.cc" \
   && "$work/p20qa.bin" >"$work/p20qa.stdout" 2>&1 \
   && cmp -s "$work/p20qa.stdout" test/modules/p20_qual_arity/expected.out; then
    ok "p20_qual_arity_ok (qualified call with exactly the method's parameters)"
else
    bad "p20_qual_arity_ok" \
        "$(cat "$work/p20qa.err" "$work/p20qa.cc" "$work/p20qa.stdout" 2>/dev/null | head -5)"
fi
rm -rf "$work/p20qa2"
mkdir -p "$work/p20qa2"
if ! "$work/ct-ast" build --emit-c test/modules/p20_qual_arity/more.ct -o "$work/p20qa2" \
        >"$work/p20qa2.out" 2>"$work/p20qa2.err"; then
    bad "p20_qual_arity_more" "expected a build with an arity warning: $(head -2 "$work/p20qa2.err")"
elif grep -qF "warning: arity mismatch: 'len' takes 0 argument(s), 1 given" "$work/p20qa2.err"; then
    ok "p20_qual_arity_more (qualified call reports the extra actual)"
else
    bad "p20_qual_arity_more" "$(head -3 "$work/p20qa2.err")"
fi

# A shim is wired by its base name: the consumer includes `<base>.shim.h`, so a
# header under any other name is silently never included and the recipe's C
# helper stays undeclared. This is the negative for the naming rule the std
# mapping units rely on (`String.m.ct` needs `String.shim.h`, not `StrUtil.shim.h`).
rm -rf "$work/mbsn"
mkdir -p "$work/mbsn/lib" "$work/mbsn/out"
printf 'namespace lib;\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> ct_x(); }\n' \
    >"$work/mbsn/lib/lib.m.ct"
printf 'static inline int ct_x(void) { return 1; }\n' >"$work/mbsn/lib/Wrong.shim.h"
printf 'import lib::lib;\n\nint main(void) { return lib::T.m(); }\n' >"$work/mbsn/main.ct"
"$work/ct-ast" build --emit-c "$work/mbsn/main.ct" -o "$work/mbsn/out" \
    >"$work/mbsn.out" 2>"$work/mbsn.err"
mbsn_ct=$?
if [ "$mbsn_ct" -eq 0 ] \
   && ! grep -qF 'Wrong.shim.h' "$work/mbsn/out/main.c" \
   && ! "$CC" -std=c99 "$work/mbsn/out/main.c" -o "$work/mbsn/main.bin" \
        >/dev/null 2>"$work/mbsn.cc"; then
    ok "batch 39 (a shim header must share the .m.ct base name)"
else
    bad "batch 39: shim_base_name_mismatch" \
        "$(cat "$work/mbsn.err" "$work/mbsn.cc" 2>/dev/null | head -2)"
fi

# Two mapping units in different directories may share a base name; both would
# become include roots for `<base>.shim.h`, so the build refuses to pick one.
rm -rf "$work/mdup"
mkdir -p "$work/mdup/a" "$work/mdup/b" "$work/mdup/out"
printf 'namespace a;\npub trait TA { int m(); }\nmap trait TA for namespace a { m() -> ct_a_x(); }\n' \
    >"$work/mdup/a/lib.m.ct"
printf 'static inline int ct_a_x(void) { return 1; }\n' >"$work/mdup/a/lib.shim.h"
printf 'namespace b;\npub trait TB { int m(); }\nmap trait TB for namespace b { m() -> ct_b_x(); }\n' \
    >"$work/mdup/b/lib.m.ct"
printf 'static inline int ct_b_x(void) { return 2; }\n' >"$work/mdup/b/lib.shim.h"
printf 'import a::lib;\nimport b::lib;\n\nint main(void) { return a::TA.m() + b::TB.m(); }\n' \
    >"$work/mdup/main.ct"
if "$work/ct-ast" build --emit-c "$work/mdup/main.ct" -o "$work/mdup/out" \
        >/dev/null 2>"$work/mdup.err"; then
    bad "batch 39: shim_base_ambiguous" "expected a non-zero exit"
elif grep -qF "shim base name 'lib' is ambiguous" "$work/mdup.err" \
     && grep -qF "$work/mdup/b" "$work/mdup.err" \
     && [ ! -f "$work/mdup/out/main.c" ]; then
    ok "batch 39 (shim_base_ambiguous, no artifacts)"
else
    bad "batch 39: shim_base_ambiguous" "$(head -2 "$work/mdup.err")"
fi

# The reference binding: a POSIX socket mapping whose shim holds the casts, the
# out-parameter and the `errno` accessor. Header-only, so no `.shim.c` is listed.
rm -rf "$work/mpsock"
mkdir -p "$work/mpsock"
if "$work/ct-ast" build --emit-c test/bindings/posix-socket/demo.ct -o "$work/mpsock" \
        >"$work/mpsock.out" 2>"$work/mpsock.err" \
   && grep -qF '#include "socket.shim.h"' "$work/mpsock/demo.c" \
   && grep -qF -- '-I test/bindings/posix-socket/posix' "$work/mpsock.out" \
   && ! grep -qF '.shim.c' "$work/mpsock.out" \
   && "$CC" -Wall -Wextra -std=c99 -I test/bindings/posix-socket/posix "$work/mpsock"/*.c \
        -o "$work/mpsock.bin" 2>"$work/mpsock.cc" \
   && "$work/mpsock.bin" >"$work/mpsock.stdout" 2>&1 \
   && cmp -s "$work/mpsock.stdout" test/bindings/posix-socket/demo.expected.out; then
    ok "posix-socket binding (shim casts + errno accessor; header-only)"
else
    bad "posix-socket binding" "$(cat "$work/mpsock.err" "$work/mpsock.cc" "$work/mpsock.stdout" 2>/dev/null | head -5)"
fi

echo
echo "== header prologue (build mode copies the source's #include lines) =="
rm -rf "$mod-pro"
mkdir -p "$mod-pro"
if "$work/ct-ast" build --emit-c test/modules/hdr_prologue/main.h.ct -o "$mod-pro" \
        >"$work/mpro.out" 2>"$work/mpro.err" \
   && grep -q '^#include <stdio.h>$' "$mod-pro/main.h" \
   && ! grep -q 'PROLOGUE_MACRO' "$mod-pro/main.h" \
   && [ -z "$(hdr_instances "$mod-pro/main.h")" ] \
   && "$CC" -Wall -Wextra -std=c99 "$mod-pro"/*.c -o "$work/mpro.bin" 2>"$work/mpro.cc" \
   && "$work/mpro.bin" >"$work/mpro.stdout" 2>&1 \
   && cmp -s "$work/mpro.stdout" test/modules/hdr_prologue/expected.out; then
    ok "hdr_prologue (#include yes, #define no)"
else
    bad "hdr_prologue" "$(cat "$work/mpro.err" "$work/mpro.cc" "$work/mpro.stdout")"
fi

echo
echo "== cross-unit linking (Batch 2) =="
# A `pub` global is defined by its own unit and declared `extern` in that unit's
# header, so an importing unit sees the same object instead of a private copy.
rm -rf "$mod-pg"
mkdir -p "$mod-pg"
if "$work/ct-ast" build --emit-c test/modules/pub_global/main.ct -o "$mod-pg" \
        >"$work/mpg.out" 2>"$work/mpg.err" \
   && grep -q '^extern int g_counter;$' "$mod-pg/count.h" \
   && grep -q '^int g_counter = 5;$' "$mod-pg/count.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-pg"/*.c -o "$work/mpg.bin" 2>"$work/mpg.cc" \
   && "$work/mpg.bin" >"$work/mpg.stdout" 2>&1 \
   && cmp -s "$work/mpg.stdout" test/modules/pub_global/expected.out; then
    ok "pub_global (the header declares, the owning unit defines)"
else
    bad "pub_global" "$(cat "$work/mpg.err" "$work/mpg.cc" "$work/mpg.stdout" 2>/dev/null)"
fi

# A `pub trait` implemented for a `pub struct` gives its vtable external
# linkage: the owning unit defines it, its header declares it `extern`, and
# another unit may box an instance of that struct. Three identical imports must
# still produce a single `#include`.
rm -rf "$mod-xb"
mkdir -p "$mod-xb"
if "$work/ct-ast" build --emit-c test/modules/xunit_box/main.ct -o "$mod-xb" \
        >"$work/mxb.out" 2>"$work/mxb.err" \
   && grep -q '^extern struct Stream_vtbl Conn_Stream_vtable;$' "$mod-xb/net.h" \
   && grep -q '^struct Stream_vtbl Conn_Stream_vtable = {$' "$mod-xb/net.c" \
   && [ "$(grep -c '#include "net.h"' "$mod-xb/main.c")" = "1" ] \
   && "$CC" -Wall -Wextra -std=c99 "$mod-xb"/*.c -o "$work/mxb.bin" 2>"$work/mxb.cc" \
   && "$work/mxb.bin" >"$work/mxb.stdout" 2>&1 \
   && cmp -s "$work/mxb.stdout" test/modules/xunit_box/expected.out; then
    ok "xunit_box (a public vtable crosses the unit boundary; imports dedupe)"
else
    bad "xunit_box" "$(cat "$work/mxb.err" "$work/mxb.cc" "$work/mxb.stdout" 2>/dev/null)"
fi

# An `extern` declaration names a symbol the C library owns: it lands in the
# header and defines nothing, so a hand-written C file can supply the object.
rm -rf "$mod-ex"
mkdir -p "$mod-ex"
if "$work/ct-ast" build --emit-c test/modules/extern_decl/main.ct -o "$mod-ex" \
        >"$work/mex.out" 2>"$work/mex.err" \
   && grep -q '^extern int lib_flag;$' "$mod-ex/lib.h" \
   && ! grep -Eq '^int lib_flag[ ;=]' "$mod-ex/lib.c" \
   && grep -q '^int lib_fn(int);$' "$mod-ex/lib.h" \
   && ! grep -q 'lib_fn(int x) {' "$mod-ex/lib.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-ex"/*.c test/modules/extern_decl/lib_impl.c \
        -o "$work/mex.bin" 2>"$work/mex.cc" \
   && "$work/mex.bin" >"$work/mex.stdout" 2>&1 \
   && cmp -s "$work/mex.stdout" test/modules/extern_decl/expected.out; then
    ok "extern_decl (declaration only; the C library owns the symbol)"
else
    bad "extern_decl" "$(cat "$work/mex.err" "$work/mex.cc" "$work/mex.stdout" 2>/dev/null)"
fi

# 2b.3: a map instance may be spelled namespace-qualified. Globals carry their
# namespace in the C name, so the instance and everything named after it are
# mangled together.
rm -rf "$mod-mn"
mkdir -p "$mod-mn"
if "$work/ct-ast" build --emit-c test/modules/map_ns/main.ct -o "$mod-mn" \
        >"$work/mmn.out" 2>"$work/mmn.err" \
   && grep -q 'hal_uart1_hal_Writer_vtable' "$mod-mn/uart.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-mn"/*.c -o "$work/mmn.bin" 2>"$work/mmn.cc" \
   && "$work/mmn.bin" >"$work/mmn.stdout" 2>&1 \
   && cmp -s "$work/mmn.stdout" test/modules/map_ns/expected.out; then
    ok "map_ns (a qualified instance name resolves to the declared name)"
else
    bad "map_ns" "$(cat "$work/mmn.err" "$work/mmn.cc" "$work/mmn.stdout" 2>/dev/null)"
fi

# SH-20: a namespace host crosses units through the header. The provider
# defines the exported vtable, the wrapper stays static, and the consumer boxes
# NULL through `Trait::ns` (it declares no instance).
rm -rf "$mod-nh"
mkdir -p "$mod-nh"
if "$work/ct-ast" build --emit-c test/modules/ns_host/main.ct -o "$mod-nh" \
        >"$work/mnh4.out" 2>"$work/mnh4.err" \
   && grep -q '^extern struct hal_Writer_vtbl hal_Writer_vtable;$' "$mod-nh/writer.h" \
   && grep -q '^struct hal_Writer_vtbl hal_Writer_vtable = {' "$mod-nh/writer.c" \
   && grep -q '^static int hal_Writer_write(void \*self' "$mod-nh/writer.c" \
   && grep -q '(void \*)0, &hal_Writer_vtable' "$mod-nh/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-nh"/*.c -o "$work/mnh4.bin" 2>"$work/mnh4.cc" \
   && "$work/mnh4.bin" >"$work/mnh4.stdout" 2>&1 \
   && cmp -s "$work/mnh4.stdout" test/modules/ns_host/expected.out; then
    ok "ns_host (a namespace host exports its vtable and boxes NULL cross-unit)"
else
    bad "ns_host" "$(cat "$work/mnh4.err" "$work/mnh4.cc" "$work/mnh4.stdout" 2>/dev/null)"
fi

# Globals are mangled by their namespace, so two units may each export `h`.
# The consumer reads and writes both through the qualified form.
rm -rf "$mod-ng"
mkdir -p "$mod-ng"
if "$work/ct-ast" build --emit-c test/modules/ns_globals/main.ct -o "$mod-ng" \
        >"$work/mng.out" 2>"$work/mng.err" \
   && grep -q '^extern int a_h;$' "$mod-ng/one.h" \
   && grep -q '^extern int b_h;$' "$mod-ng/two.h" \
   && grep -q '^int a_h = 1;$' "$mod-ng/one.c" \
   && grep -q '^int b_h = 10;$' "$mod-ng/two.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-ng"/*.c -o "$work/mng.bin" 2>"$work/mng.cc" \
   && "$work/mng.bin" >"$work/mng.stdout" 2>&1 \
   && cmp -s "$work/mng.stdout" test/modules/ns_globals/expected.out; then
    ok "ns_globals (the namespace prefixes the C name; a::h names one object)"
else
    bad "ns_globals" "$(cat "$work/mng.err" "$work/mng.cc" "$work/mng.stdout" 2>/dev/null)"
fi

# Two imports exporting one source name: a bare reference is refused, and the
# diagnostic asks for the qualified form.
if "$work/ct-ast" build --emit-c test/modules/ambig_global/main.ct -o "$work/mod-bad" \
        >"$work/mag.out" 2>"$work/mag.err"; then
    bad "ambig_global" "expected a non-zero exit"
elif grep -q "variable 'h' is exported by more than one namespace" "$work/mag.err"; then
    ok "ambig_global (a bare name that two namespaces export is refused)"
else
    bad "ambig_global" "no ambiguity diagnostic: $(cat "$work/mag.err")"
fi

# M4: the same ambiguity inside a braced static initialiser, whose text is
# rewritten by name. It used to be emitted verbatim for `cc` to reject.
if "$work/ct-ast" build --emit-c test/modules/ambig_global/main_init.ct -o "$work/mod-bad" \
        >"$work/magi.out" 2>"$work/magi.err"; then
    bad "ambig_global_init" "expected a non-zero exit"
elif grep -qF "global 'h' is declared by more than one import and cannot be named in a static initializer" \
        "$work/magi.err"; then
    ok "ambig_global_init (an ambiguous global is diagnosed in a static initialiser)"
else
    bad "ambig_global_init" "no ambiguity diagnostic: $(cat "$work/magi.err")"
fi

# M4: two namespaces export `size`; a static initialiser cannot pick a C
# spelling, so the ambiguity is a diagnostic rather than a silent choice.
if "$work/ct-ast" build --emit-c test/modules/ambig_func_init/main.ct -o "$work/mod-bad" \
        >"$work/maf.out" 2>"$work/maf.err"; then
    bad "ambig_func_init" "expected a non-zero exit"
elif grep -qF "function 'size' is declared by more than one namespace and cannot be named in a static initializer" \
        "$work/maf.err"; then
    ok "ambig_func_init (an ambiguous function is diagnosed in a static initialiser)"
else
    bad "ambig_func_init" "no ambiguity diagnostic: $(cat "$work/maf.err")"
fi

# SH-18: an exported type in a namespace is reachable by its bare name, so a
# consumer need not alias-import it. `Uart` becomes `struct hal_Uart` and
# `Writer` becomes `struct hal_Writer_iface`.
rm -rf "$mod-nt"
mkdir -p "$mod-nt"
if "$work/ct-ast" build --emit-c test/modules/ns_types/main.ct -o "$mod-nt" \
        >"$work/mnt.out" 2>"$work/mnt.err" \
   && grep -q 'struct hal_Uart u' "$mod-nt/main.c" \
   && grep -q 'struct hal_Writer_iface w;' "$mod-nt/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-nt"/*.c -o "$work/mnt.bin" 2>"$work/mnt.cc" \
   && "$work/mnt.bin" >"$work/mnt.stdout" 2>&1 \
   && cmp -s "$work/mnt.stdout" test/modules/ns_types/expected.out; then
    ok "ns_types (a bare exported type name resolves to its namespaced C name)"
else
    bad "ns_types" "$(cat "$work/mnt.err" "$work/mnt.cc" "$work/mnt.stdout" 2>/dev/null)"
fi

# Batch 5: a `pub enum` reaches the dependency's header and its members import
# as constants. The consumer writes `Level` (bare), `Mid` (bare member) and
# `app::High` (qualified member), and the compiler emits the owner's C names.
rm -rf "$mod-ne"
mkdir -p "$mod-ne"
if "$work/ct-ast" build --emit-c test/modules/enum_export/main.ct -o "$mod-ne" \
        >"$work/mne.out" 2>"$work/mne.err" \
   && grep -q 'enum app_Level {' "$mod-ne/kinds.h" \
   && grep -q 'enum app_Level l' "$mod-ne/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-ne"/*.c -o "$work/mne.bin" 2>"$work/mne.cc" \
   && "$work/mne.bin" >"$work/mne.stdout" 2>&1 \
   && cmp -s "$work/mne.stdout" test/modules/enum_export/expected.out; then
    ok "enum_export (an exported enum reaches the header and its members import)"
else
    bad "enum_export" "$(cat "$work/mne.err" "$work/mne.cc" "$work/mne.stdout" 2>/dev/null)"
fi

# ... and an exported union travels the same route: the header carries the tag
# under its namespace prefix and a consumer reaches it by its bare name.
rm -rf "$mod-nu"
mkdir -p "$mod-nu"
if "$work/ct-ast" build --emit-c test/modules/union_export/main.ct -o "$mod-nu" \
        >"$work/mnu.out" 2>"$work/mnu.err" \
   && grep -q 'union app_Value {' "$mod-nu/kinds.h" \
   && grep -q 'union app_Value v' "$mod-nu/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-nu"/*.c -o "$work/mnu.bin" 2>"$work/mnu.cc" \
   && "$work/mnu.bin" >"$work/mnu.stdout" 2>&1 \
   && cmp -s "$work/mnu.stdout" test/modules/union_export/expected.out; then
    ok "union_export (an exported union reaches the header and imports by bare name)"
else
    bad "union_export" "$(cat "$work/mnu.err" "$work/mnu.cc" "$work/mnu.stdout" 2>/dev/null)"
fi

# ... and a container element that lives in another unit is supported: the unit
# that names the instance writes private copies of the element helpers and the
# instance methods, so the element's definition is in scope (Phase 33 O3).
rm -rf "$mod-fx"
mkdir -p "$mod-fx"
if "$work/ct-ast" build --emit-c test/modules/p31_cross_unit_elem/main.ct -o "$mod-fx" \
        >"$work/mfx.out" 2>"$work/mfx.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-fx"/*.c -o "$work/mfx.bin" 2>"$work/mfx.cc" \
   && "$work/mfx.bin" >"$work/mfx.stdout" 2>&1; then
    ok "p31_cross_unit_elem (an interface element from another unit is emitted in the consumer)"
else
    bad "p31_cross_unit_elem" "$(cat "$work/mfx.err" "$work/mfx.cc" "$work/mfx.stdout" 2>/dev/null)"
fi
# ... the same holds for an owning element (one that carries `retain` /
# `release`): the consumer writes its helper pair and method copies too.
rm -rf "$mod-fx"
mkdir -p "$mod-fx"
if "$work/ct-ast" build --emit-c test/modules/p31_cross_unit_owned/main.ct -o "$mod-fx" \
        >"$work/mfo.out" 2>"$work/mfo.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-fx"/*.c -o "$work/mfo.bin" 2>"$work/mfo.cc" \
   && "$work/mfo.bin" >"$work/mfo.stdout" 2>&1; then
    ok "p31_cross_unit_owned (an owning element from another unit is emitted in the consumer)"
else
    bad "p31_cross_unit_owned" "$(cat "$work/mfo.err" "$work/mfo.cc" "$work/mfo.stdout" 2>/dev/null)"
fi

# Phase 33 O3 (E33-13/E33-14): the consumer's generated C carries private static
# copies of a foreign element's instance methods, the container header keeps the
# type only, and the program runs to its recorded output.
rm -rf "$work/cu-out"
mkdir -p "$work/cu-out"
if "$work/ct-ast" build --emit-c test/modules/cross_unit_elem/main.ct -o "$work/cu-out" \
        >"$work/cu.out" 2>"$work/cu.err" \
   && ! grep -q 'Vec_Point_push\|Vec_Show__iface_push\|__elem_retain' "$work/cu-out/Vec.h" \
   && grep -q 'static .*Vec_Point_push' "$work/cu-out/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$work/cu-out"/*.c -o "$work/cu.bin" 2>"$work/cu.cc" \
   && "$work/cu.bin" >"$work/cu.stdout" 2>&1 \
   && cmp -s "$work/cu.stdout" test/modules/cross_unit_elem/expected.out; then
    ok "p33_cross_unit (a foreign element runs; the header keeps the type only)"
else
    bad "p33_cross_unit" "$(cat "$work/cu.err" "$work/cu.cc" "$work/cu.stdout" 2>/dev/null)"
fi
# ... and every copied method stays a local symbol: no `Vec_<element>_*` method
# is a duplicate global, so two consumers never collide at link time.
rm -rf "$work/cu-obj"
mkdir -p "$work/cu-obj"
cu_obj_ok=1
for cu_c in "$work/cu-out"/*.c; do
    if [ ! -f "$cu_c" ]; then cu_obj_ok=0; break; fi
    "$CC" -Wall -Wextra -std=c99 -c "$cu_c" \
        -o "$work/cu-obj/$(basename "$cu_c" .c).o" 2>/dev/null || cu_obj_ok=0
done
if [ "$cu_obj_ok" -eq 1 ] \
   && ! nm "$work/cu-obj"/*.o 2>/dev/null | grep -Eq '^[0-9a-fA-F]+ T _?Vec_(Point|Show__iface)_' \
   && nm "$work/cu-obj/main.o" 2>/dev/null | grep -Eq ' t _?Vec_Point_push$'; then
    ok "p33_nm (the consumer copies are local symbols, no duplicate global)"
else
    bad "p33_nm" "a copied method is not a local symbol, or a global duplicate appeared"
fi
# E33-15: the same block's second build, in its own directory: a bound trait the
# instantiating unit cannot see is one L33-6, never a silent pass.
rm -rf "$work/cu-bad"
mkdir -p "$work/cu-bad"
if "$work/ct-ast" build --emit-c test/modules/errors/bound_trait_invisible/main.ct \
        -o "$work/cu-bad" >"$work/cub.out" 2>"$work/cub.err"; then
    bad "p33_cross_unit (bound visibility)" "the build was accepted"
elif ! grep -q "unknown trait 'Show' in a generic bound" "$work/cub.err"; then
    bad "p33_cross_unit (bound visibility)" "$(cat "$work/cub.err")"
elif [ "$(grep -c 'error:' "$work/cub.err")" -ne 1 ]; then
    bad "p33_cross_unit (bound visibility)" "expected exactly one diagnostic: $(cat "$work/cub.err")"
else
    ok "p33_cross_unit (an invisible bound trait is one L33-6)"
fi
# E35-8: a generic trait instance must be created in the unit that owns the
# template; a consumer naming `Iter<int>` is one L35-4, never a silent pass.
rm -rf "$work/cu-p35"
mkdir -p "$work/cu-p35"
if "$work/ct-ast" build --emit-c test/modules/errors/p35_cross_unit/main.ct \
        -o "$work/cu-p35" >"$work/cu35.out" 2>"$work/cu35.err"; then
    bad "p35_cross_unit" "the build was accepted"
elif ! grep -q "a generic trait instance must be created in its owner unit" "$work/cu35.err"; then
    bad "p35_cross_unit" "$(cat "$work/cu35.err")"
elif [ "$(grep -c 'error:' "$work/cu35.err")" -ne 1 ]; then
    bad "p35_cross_unit" "expected exactly one diagnostic: $(cat "$work/cu35.err")"
else
    ok "p35_cross_unit (a foreign generic trait instance is one L35-4)"
fi
# ... and a bounded declaration with no instantiation is accepted. 208 has no
# `prog.ct` on purpose: it is driven here, not by the behavioural loop.
rm -rf "$work/cu-208"
mkdir -p "$work/cu-208"
if "$work/ct-ast" build --emit-c test/ast/208_bound_decl_only/decl.ct \
        -o "$work/cu-208" >"$work/cu208.out" 2>"$work/cu208.err"; then
    ok "p33_cross_unit (a bounded declaration alone is accepted)"
else
    bad "p33_cross_unit (declaration only)" "$(cat "$work/cu208.err")"
fi

# ... and two namespaces exporting one bare type name make it ambiguous.
if "$work/ct-ast" build --emit-c test/modules/ambig_type/main.ct -o "$work/mod-bad" \
        >"$work/mat.out" 2>"$work/mat.err"; then
    bad "ambig_type" "expected a non-zero exit"
elif grep -q "that type is exported by more than one namespace" "$work/mat.err"; then
    ok "ambig_type (a bare type name that two namespaces export is refused)"
else
    bad "ambig_type" "no ambiguity diagnostic: $(cat "$work/mat.err")"
fi

# SH-20: a map instance must be declared, and the diagnostic names the
# `void *` placeholder that serves as a host.
if "$work/ct-ast" test/ast/errors/map_no_instance.ct -o "$work/mni.c" \
        >"$work/mni.out" 2>"$work/mni.err"; then
    bad "map instance" "expected a non-zero exit"
elif grep -q "use 'void \*missing;' as its host" "$work/mni.err"; then
    ok "map (an undeclared instance names the void * placeholder)"
else
    bad "map instance" "$(cat "$work/mni.err")"
fi

# Nested function pointers and function-pointer array parameters are refused
# with a message of their own (batch 3: D-7 and the parameter rule), never with
# the generic "declarator has no name" / "unexpected token" fallback.
if "$work/ct-ast" test/ast/errors/fnptr_nested.ct -o "$work/fpn.c" \
        >"$work/fpn.out" 2>"$work/fpn.err"; then
    bad "fnptr nested" "expected a non-zero exit"
elif grep -q "nested function pointers are not supported" "$work/fpn.err"; then
    ok "fnptr (a nested declarator is refused by name)"
else
    bad "fnptr nested" "$(cat "$work/fpn.err")"
fi

if "$work/ct-ast" test/ast/errors/fnptr_array_param.ct -o "$work/fpa.c" \
        >"$work/fpa.out" 2>"$work/fpa.err"; then
    bad "fnptr array parameter" "expected a non-zero exit"
elif grep -q "function-pointer arrays are not supported as parameters" "$work/fpa.err"; then
    ok "fnptr (an array parameter is refused by name)"
else
    bad "fnptr array parameter" "$(cat "$work/fpa.err")"
fi

# An impl may ignore a parameter (the trait owns the signature). The casts that
# silence the warning must lead the body: a trailing `(void)_self;` would sit
# after the `return`, where it can never run.
if "$work/ct-ast" test/ast/23_impl_unused/prog.ct -o "$work/munused.c" \
        >"$work/munused.out" 2>"$work/munused.err" \
   && grep -q '    (void)mode;$' "$work/munused.c" \
   && awk '/\(void\)_self;/{u=NR} /return/{if(!r) r=NR} END{exit !(u>0 && r>0 && u<r)}' \
        "$work/munused.c"; then
    ok "impl (an unused parameter is silenced at the top of the body)"
else
    bad "impl unused parameter" "$(cat "$work/munused.err")"
fi

echo
echo "== metadata (map + #line) =="
if "$work/ct-ast" --emit-map - test/ast/11_map/prog.ct -o "$work/m11.c" \
        >"$work/m11.map" 2>"$work/m11.err" \
   && grep -q '"name":"Greeter"' "$work/m11.map" \
   && grep -q '"callee":"add"' "$work/m11.map" \
   && grep -q '"line":11' "$work/m11.map" \
   && grep -q '"symbol":"Person_Greeter_greet"' "$work/m11.map"; then
    ok "--emit-map - (traits/structs/functions/impls/calls)"
else
    bad "map stdout" "$(cat "$work/m11.err")"
fi
if grep -q '^#line ' "$work/m11.c"; then
    bad "compile default" "an unexpected #line directive"
else
    ok "compile default (no #line)"
fi
if "$work/ct-ast" --line test/ast/11_map/prog.ct -o "$work/m11l.c" >/dev/null 2>&1 \
   && grep -q '^#line 1 "test/ast/11_map/prog.ct"' "$work/m11l.c"; then
    ok "--line (directive emitted)"
else
    bad "--line" "no directive in the generated C"
fi

rm -rf "$work/m11b"
mkdir -p "$work/m11b"
if "$work/ct-ast" build --emit-c --emit-map "$work/m11b/prog.map" test/ast/11_map/prog.ct \
        -o "$work/m11b" >"$work/m11b.out" 2>"$work/m11b.err" \
   && grep -q '^#line 1 "test/ast/11_map/prog.ct"' "$work/m11b/prog.c" \
   && grep -q '"compiler": "ct v' "$work/m11b/prog.map"; then
    ok "build default (#line on, map to a file)"
else
    bad "build metadata" "$(cat "$work/m11b.err")"
fi

rm -rf "$work/m11n"
mkdir -p "$work/m11n"
if "$work/ct-ast" build --emit-c --no-line test/ast/11_map/prog.ct -o "$work/m11n" \
        >"$work/m11n.out" 2>"$work/m11n.err" \
   && ! grep -q '^#line ' "$work/m11n/prog.c"; then
    ok "build --no-line (directive suppressed)"
else
    bad "build --no-line" "a directive survived"
fi

if "$work/ct-ast" --emit-map >"$work/mapa.out" 2>"$work/mapa.err"; then
    bad "--emit-map without an argument" "expected a non-zero exit"
elif grep -q "needs an argument" "$work/mapa.err"; then
    ok "--emit-map without an argument"
else
    bad "--emit-map without an argument" "no diagnostic on stderr"
fi
# the directory does not exist (and sits inside $work, so no sandbox rule is
# involved); the map write must fail with a diagnostic
if "$work/ct-ast" --emit-map "$work/no-such-dir/x.map" test/ast/11_map/prog.ct \
        -o "$work/m11u.c" >"$work/mapu.out" 2>"$work/mapu.err"; then
    bad "--emit-map to an unwritable path" "expected a non-zero exit"
elif grep -q "cannot write the map" "$work/mapu.err"; then
    ok "--emit-map to an unwritable path"
else
    bad "--emit-map to an unwritable path" "no diagnostic on stderr"
fi

echo
echo "== map construct (11.1-11.2) =="
# A `map` binding emits an instance-level wrapper plus a vtable, described by the
# `maps` field of the map JSON; 11.2 boxes the bound instance with that vtable.
if "$work/ct-ast" test/ast/13_map_instance/prog.ct -o "$work/mmap.c" \
        >"$work/mmap.out" 2>"$work/mmap.err" \
   && grep -q 'static int uart1_Controller_send(void \*self' "$work/mmap.c" \
   && grep -q 'static struct Controller_vtbl uart1_Controller_vtable __attribute__((unused)) = {' "$work/mmap.c"; then
    ok "map (wrapper + vtable emitted)"
else
    bad "map emit" "$(cat "$work/mmap.err")"
fi
# `Controller c; c = uart1;` boxes the instance with `&uart1_Controller_vtable`,
# not the struct-level `&Uart_Controller_vtable` (which does not exist).
if "$work/ct-ast" test/ast/14_map_dispatch/prog.ct -o "$work/mmap2.c" \
        >"$work/mmap2.out" 2>"$work/mmap2.err" \
   && grep -q '(void \*)&uart1, &uart1_Controller_vtable }' "$work/mmap2.c" \
   && ! grep -q 'Uart_Controller_vtable' "$work/mmap2.c"; then
    ok "map (dispatch: the instance-level vtable boxes the instance)"
else
    bad "map dispatch" "$(cat "$work/mmap2.err")"
fi
if "$work/ct-ast" --emit-map - test/ast/13_map_instance/prog.ct -o "$work/mmapm.c" \
        >"$work/mmap.map" 2>"$work/mmapm.err" \
   && grep -Eq '"maps": *\[' "$work/mmap.map" \
   && grep -q '"instance":"uart1"' "$work/mmap.map" \
   && grep -q '"symbol":"uart1_Controller_send"' "$work/mmap.map"; then
    ok "map (maps field in the map JSON)"
else
    bad "map JSON" "$(cat "$work/mmapm.err")"
fi
# The 65th map overflows MAX_MAPS (64). Each map needs its own instance now that
# a duplicate (instance, trait) pair is refused before the cap can be reached.
mi=0
{
    printf 'trait Controller {\n    int send(char *buf, int len);\n}\n'
    printf 'struct Uart {\n    int fd;\n};\n'
    printf 'int mock_send(struct Uart *u, char *b, int n) {\n    (void)b;\n    return n + u->fd;\n}\n'
    while [ "$mi" -le 65 ]; do
        printf 'struct Uart u%d;\n' "$mi"
        mi=$((mi + 1))
    done
    mi=0
    while [ "$mi" -lt 65 ]; do
        printf 'map trait Controller for instance u%d {\n    send(buf, len) -> mock_send(&u%d, buf, len);\n}\n' "$mi" "$mi"
        mi=$((mi + 1))
    done
    printf 'int main(void) { return 0; }\n'
} > "$work/map-many.ct"
if "$work/ct-ast" "$work/map-many.ct" -o "$work/map-many.c" \
        >"$work/map-many.out" 2>"$work/map-many.err"; then
    bad "map cap" "expected a non-zero exit"
elif grep -q "too many maps" "$work/map-many.err"; then
    ok "map (MAX_MAPS cap)"
else
    bad "map cap" "no diagnostic on stderr"
fi
# 11.3: a map must bind every trait method; an unbound slot would be a null
# function pointer (calling it crashes at run time).
if "$work/ct-ast" test/ast/errors/map_partial.ct -o "$work/mmap3.c" \
        >"$work/mmap3.out" 2>"$work/mmap3.err"; then
    bad "map completeness" "expected a non-zero exit"
elif grep -q "is not bound by the map" "$work/mmap3.err"; then
    ok "map (every trait method must be bound)"
else
    bad "map completeness" "$(cat "$work/mmap3.err")"
fi
# 11.3: a CALL argument may be `&<another global>` or a member path on the
# instance. `15_map_args` also runs the boxed instance end to end.
if "$work/ct-ast" test/ast/15_map_args/prog.ct -o "$work/mmap4.c" \
        >"$work/mmap4.out" 2>"$work/mmap4.err" \
   && grep -q 'return pick(&box_b, box_a.base);' "$work/mmap4.c"; then
    ok "map (CALL args: &other-global and instance member path)"
else
    bad "map args" "$(cat "$work/mmap4.err")"
fi
# 2b.1 / 2b.5: a bare name binds the C function itself - no wrapper is emitted,
# the slot points at the function, and the map JSON marks the binding.
if "$work/ct-ast" test/ast/22_map_direct/prog.ct -o "$work/mmd.c" \
        >"$work/mmd.out" 2>"$work/mmd.err" \
   && ! grep -q 'buf1_Sink_put' "$work/mmd.c" \
   && grep -q '^    \.put = real_put$' "$work/mmd.c" \
   && "$work/ct-ast" --emit-map - test/ast/22_map_direct/prog.ct -o "$work/mmd2.c" \
        >"$work/mmd.map" 2>/dev/null \
   && grep -q '"symbol":"real_put","wrapper":false' "$work/mmd.map"; then
    ok "map (direct binding: no wrapper, JSON says wrapper:false)"
else
    bad "map direct" "$(cat "$work/mmd.err")"
fi
# A parenthesised CALL keeps its wrapper, and the JSON says so.
if "$work/ct-ast" --emit-map - test/ast/15_map_args/prog.ct -o "$work/mmd3.c" \
        >"$work/mmd3.map" 2>"$work/mmd3.err" \
   && grep -q '"symbol":"box_a_Reader_read","wrapper":true' "$work/mmd3.map"; then
    ok "map (expression argument keeps the wrapper; JSON says wrapper:true)"
else
    bad "map wrapper flag" "$(cat "$work/mmd3.err")"
fi
# SH-20: a namespace host boxes NULL and names the vtable after the namespace
# (no object exists), and the map JSON says `"host":"namespace"`.
if "$work/ct-ast" --emit-map - test/ast/26_ns_host/prog.ct -o "$work/mnh.c" \
        >"$work/mnh.map" 2>"$work/mnh.err" \
   && grep -q '(void \*)0, &hal_Writer_vtable' "$work/mnh.c" \
   && grep -q '^static int hal_Writer_write(void \*self' "$work/mnh.c" \
   && grep -q '^struct hal_Writer_vtbl hal_Writer_vtable = {' "$work/mnh.c" \
   && grep -q '"host":"namespace"' "$work/mnh.map"; then
    ok "map (namespace host: NULL self, exported vtable, JSON host)"
else
    bad "map namespace host" "$(cat "$work/mnh.err")"
fi
if "$work/ct-ast" test/ast/errors/ns_host_no_map.ct -o "$work/mnh2.c" \
        >"$work/mnh2.out" 2>"$work/mnh2.err"; then
    bad "ns_host_no_map" "expected a non-zero exit"
elif grep -q "no map binds trait 'Writer' to namespace 'nosuch'" "$work/mnh2.err"; then
    ok "map (a namespace host with no map is refused at the box site)"
else
    bad "ns_host_no_map" "$(cat "$work/mnh2.err")"
fi
if "$work/ct-ast" test/ast/errors/ns_host_direct.ct -o "$work/mnh3.c" \
        >"$work/mnh3.out" 2>"$work/mnh3.err"; then
    bad "ns_host_direct" "expected a non-zero exit"
elif grep -q "a namespace host has no self: bind with a wrapper call" "$work/mnh3.err"; then
    ok "map (a namespace host refuses a direct binding)"
else
    bad "ns_host_direct" "$(cat "$work/mnh3.err")"
fi

echo
echo "== negative cases =="
rm -rf "$work/mod-bad"
mkdir -p "$work/mod-bad"
if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_dir_mismatch \
        test/modules/ns_dir_mismatch/a/uart.ct -o "$work/mod-bad" \
        >"$work/mnbad.out" 2>"$work/mnbad.err"; then
    bad "ns_dir_mismatch" "expected a non-zero exit"
elif grep -q "^ctc: " "$work/mnbad.err"; then
    ok "ns_dir_mismatch (namespace/directory check)"
else
    bad "ns_dir_mismatch" "no diagnostic on stderr"
fi
if "$work/ct-ast" build --emit-c test/modules/inc_missing/main.ct -o "$work/mod-bad" \
        >"$work/mincm.out" 2>"$work/mincm.err"; then
    bad "inc_missing" "expected a non-zero exit"
elif grep -q "^ctc: " "$work/mincm.err"; then
    ok "inc_missing (unresolved import)"
else
    bad "inc_missing" "no diagnostic on stderr"
fi
# Only a `.h.ct` unit publishes an interface, so importing a plain `.ct` is a
# named error that also spells the fix.
rm -rf "$work/impbad"
mkdir -p "$work/impbad"
printf 'pub int helper(void);\nint helper(void) { return 1; }\n' >"$work/impbad/helper.ct"
printf 'import helper;\n\nint main(void) { return helper(); }\n' >"$work/impbad/main.ct"
if "$work/ct-ast" build --emit-c "$work/impbad/main.ct" -o "$work/mod-bad" \
        >"$work/mimpb.out" 2>"$work/mimpb.err"; then
    bad "import_plain_ct" "expected a non-zero exit"
elif grep -qF "only a .h.ct unit can be imported: rename 'helper.ct' to 'helper.h.ct'" "$work/mimpb.err"; then
    ok "import_plain_ct (a plain .ct unit is not importable)"
else
    bad "import_plain_ct" "no diagnostic: $(cat "$work/mimpb.err")"
fi
if "$work/ct-ast" build --emit-c --ns-root test/modules/alias_dup/src \
        test/modules/alias_dup/src/main.ct -o "$work/mod-bad" \
        >"$work/madup.out" 2>"$work/madup.err"; then
    bad "alias_dup" "expected a non-zero exit"
elif grep -q "one alias names two imports" "$work/madup.err"; then
    ok "alias_dup (one alias, two imports)"
else
    bad "alias_dup" "no alias diagnostic: $(cat "$work/madup.err")"
fi
if "$work/ct-ast" build --emit-c --ns-root test/modules/alias_missing/src \
        test/modules/alias_missing/src/main.ct -o "$work/mod-bad" \
        >"$work/mamiss.out" 2>"$work/mamiss.err"; then
    bad "alias_missing" "expected a non-zero exit"
elif grep -q "does not export that name" "$work/mamiss.err"; then
    ok "alias_missing (by-name import of an unknown name)"
else
    bad "alias_missing" "no alias diagnostic: $(cat "$work/mamiss.err")"
fi
if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_scoped_mismatch/src \
        test/modules/ns_scoped_mismatch/src/app/unit.ct -o "$work/mod-bad" \
        >"$work/mnsm.out" 2>"$work/mnsm.err"; then
    bad "ns_scoped_mismatch" "expected a non-zero exit"
elif grep -q "does not match the directory" "$work/mnsm.err"; then
    ok "ns_scoped_mismatch (file-scoped namespace vs --ns-root)"
else
    bad "ns_scoped_mismatch" "no namespace diagnostic: $(cat "$work/mnsm.err")"
fi
if "$work/ct-ast" build --emit-c test/modules/ns_block/src/main.ct -o "$work/mod-bad" \
        >"$work/mnsb.out" 2>"$work/mnsb.err"; then
    bad "ns_block" "expected a non-zero exit"
elif grep -q "a namespace is file-scoped" "$work/mnsb.err"; then
    ok "ns_block (the block form is rejected)"
else
    bad "ns_block" "no namespace diagnostic: $(cat "$work/mnsb.err")"
fi
if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_fn_ambiguous/src \
        test/modules/ns_fn_ambiguous/src/main.ct -o "$work/mod-bad" \
        >"$work/mnfa.out" 2>"$work/mnfa.err"; then
    bad "ns_fn_ambiguous" "expected a non-zero exit"
elif grep -q "exported by more than one namespace" "$work/mnfa.err"; then
    ok "ns_fn_ambiguous (an unqualified call to a doubly exported name is refused)"
else
    bad "ns_fn_ambiguous" "no ambiguity diagnostic: $(cat "$work/mnfa.err")"
fi

if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_qual_missing/src \
        test/modules/ns_qual_missing/src/main.ct -o "$work/mod-bad" \
        >"$work/mnqm.out" 2>"$work/mnqm.err"; then
    bad "ns_qual_missing" "expected a non-zero exit"
elif grep -q "no function of that name in that namespace" "$work/mnqm.err"; then
    ok "ns_qual_missing (a qualified call to a missing function is refused)"
else
    bad "ns_qual_missing" "no qualified-call diagnostic: $(cat "$work/mnqm.err")"
fi

if "$work/ct-ast" build --emit-c --ns-root test/modules/ns_bare_call/src \
        test/modules/ns_bare_call/src/main.ct -o "$work/mod-bad" \
        >"$work/mnbc.out" 2>"$work/mnbc.err"; then
    bad "ns_bare_call" "expected a non-zero exit"
elif grep -q "lives in another namespace and needs a qualified call" "$work/mnbc.err"; then
    ok "ns_bare_call (reaching into another namespace takes a qualified call)"
else
    bad "ns_bare_call" "no unqualified-call diagnostic: $(cat "$work/mnbc.err")"
fi

# 2a.4: a second impl of the same (struct, trait) would define the same externally
# linked vtable twice, so it is refused and the first definition is named.
if "$work/ct-ast" build --emit-c test/modules/dup_impl/main.ct -o "$work/mod-bad" \
        >"$work/mdup.out" 2>"$work/mdup.err"; then
    bad "dup_impl" "expected a non-zero exit"
elif grep -q "duplicate impl of trait 'Speak' for struct 'Dog'" "$work/mdup.err" \
     && grep -q "first at .*a\.h\.ct:" "$work/mdup.err"; then
    ok "dup_impl (one impl per struct and trait, the first one is named)"
else
    bad "dup_impl" "no duplicate diagnostic: $(cat "$work/mdup.err")"
fi

echo
echo "== static map units: negatives (batch 38) =="
# Every `.m.ct` fixture is a two-unit tree: lib/lib.m.ct carries the construct
# under test, main.ct imports it. A shared header keeps the fixtures one
# construct apart.
mapbad() {
    label="$1"; body="$2"; want="$3"
    mainbody='import lib::lib;\nint main(void) { return 0; }\n'
    if [ $# -ge 4 ]; then mainbody="$4"; fi
    rm -rf "$work/mb"
    mkdir -p "$work/mb/lib" "$work/mb/out"
    printf '%b' "#include <stdlib.h>\nnamespace lib;\n$body" >"$work/mb/lib/lib.m.ct"
    printf '%b' "$mainbody" >"$work/mb/main.ct"
    if "$work/ct-ast" build --emit-c "$work/mb/main.ct" -o "$work/mb/out" \
            >"$work/mb/out.txt" 2>"$work/mb/err.txt"; then
        bad "${mapbad_batch:-batch 38}: $label" "expected a non-zero exit"
    elif grep -qF "$want" "$work/mb/err.txt"; then
        ok "${mapbad_batch:-batch 38} ($label)"
    else
        bad "${mapbad_batch:-batch 38}: $label" "$(head -2 "$work/mb/err.txt")"
    fi
}

mapbad funcs \
    'pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\nint helper(void) { return 1; }\n' \
    'a .m.ct unit cannot define a function'
mapbad proto \
    'pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\nint helper(void);\n' \
    'a .m.ct unit cannot declare a function'
mapbad global \
    'pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\nint g;\n' \
    'a .m.ct unit cannot declare a global variable'
mapbad type_decl \
    'pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\nstruct S { int v; };\n' \
    'a .m.ct unit cannot declare a type'
mapbad impl_unit \
    'pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\nimpl T for S { int m() { return 1; } }\n' \
    'a .m.ct unit cannot contain an impl'
mapbad instance_host \
    'pub trait T { int m(); }\nmap trait T for instance g { m() -> rand(); }\n' \
    'a .m.ct unit cannot bind a trait to an instance'
mapbad prologue_line \
    '#pragma once\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    'a .m.ct unit allows only #include and #define in its prologue; put the C implementation in <base>.shim.h'
mapbad nonpub \
    'trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    "a trait in a .m.ct unit must be 'pub'"
mapbad default_body \
    'pub trait T { int m() { return 1; } }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    'a .m.ct trait cannot carry a default body'
mapbad ns_host_mismatch \
    'pub trait T { int m(); }\nmap trait T for namespace other { m() -> rand(); }\n' \
    'a static trait for a namespace host must be declared in that namespace'
mapbad for_type_missing \
    'pub trait T { int m(); }\nmap trait T for type { m() -> rand(); }\n' \
    "expected a type after 'for type'"
mapbad for_type_array \
    'pub trait T { int m(); }\nmap trait T for type char[] { m(s) -> 0; }\n' \
    "expected a type after 'for type'"
mapbad type_arity \
    'pub trait T { int m(int a); }\nmap trait T for type char * { m(s) -> 1; }\n' \
    "a type host binding has 1 parameters but method 'm' takes 1"
mapbad recipe_name \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> strcmp(s, k); }\n' \
    "map recipe names 'k' but it is not a binding parameter"
mapbad recipe_modifies \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> strcmp(s = s, s); }\n' \
    "map recipe modifies binding parameter 's'"
mapbad recipe_not_call \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> atoi(s) + 1; }\n' \
    'a map recipe must be a single call'
mapbad no_type_hit \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> strlen(s); }\n' \
    "no method 'm' for type 'struct P'" \
    'import lib::lib;\nstruct P { int v; };\n\nint main(void)\n{\n    struct P p = { 1 };\n    int x = p.m();\n    (void)x;\n    return 0;\n}\n'
mapbad recipe_twice \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> strcmp(s, s); }\n' \
    "map recipe uses 's' more than once; bind the argument to a local first" \
    'import lib::lib;\nchar *mk(void) { return "x"; }\n\nint main(void)\n{\n    int x = mk().m();\n    (void)x;\n    return 0;\n}\n'
mapbad ambiguous_type_host \
    'pub trait T { int m(); }\npub trait U { int m(); }\nmap trait T for type char * { m(s) -> atoi(s); }\nmap trait U for type char * { m(s) -> strlen(s); }\n' \
    "ambiguous type-host map for method 'm' on type 'char *'" \
    'import lib::lib;\n\nint main(void)\n{\n    char *a = "1";\n    int x = a.m();\n    (void)x;\n    return 0;\n}\n'
# `sizeof s` is the declared type's size, so a parenthesised form would silently
# mean `sizeof((actual))`; the recipe must spell it without parentheses (§4.10).
mapbad sizeof_paren \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> malloc(sizeof(s)); }\n' \
    "map recipe takes 'sizeof s', not 'sizeof(s)'" \
    'import lib::lib;\n\nint main(void) { return 0; }\n'

# Batch 41: the forwarded tail is one marker, it must be last, and it has to
# agree with the signature on both sides -- a binding that drops it would throw
# the actuals away silently (the very bug the lower-bound check closes).
mapbad_batch='batch 41'
mapbad tail_not_last_param \
    'pub trait T { int m(char *f, ...); }\nmap trait T for namespace lib { m(..., f) -> printf(f); }\n' \
    "'...' must be the last binding parameter"
mapbad tail_not_last_recipe \
    'pub trait T { int m(char *f, ...); }\nmap trait T for namespace lib { m(f, ...) -> printf(..., f); }\n' \
    "'...' must be the last recipe argument"
mapbad tail_unbound \
    'pub trait T { int m(char *f); }\nmap trait T for namespace lib { m(f) -> printf(f, ...); }\n' \
    "a map recipe uses '...' but the binding has no variadic tail"
mapbad tail_missing \
    'pub trait T { int m(char *f, ...); }\nmap trait T for namespace lib { m(f) -> printf(f); }\n' \
    "a variadic trait method must forward '...' in its binding"
mapbad tail_undeclared \
    'pub trait T { int m(char *f); }\nmap trait T for namespace lib { m(f, ...) -> printf(f, ...); }\n' \
    "this binding forwards '...' but the trait method is not variadic"
mapbad tail_nonstatic \
    'pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    'a trait method cannot be variadic' \
    'import lib::lib;\ntrait P { int m(int a, ...); }\nint main(void) { return 0; }\n'
# Two traits bound to one namespace host may both answer `get`; a bare
# `lib::get(...)` has no way to choose, so the message names both.
mapbad bare_ambiguous \
    'pub trait T { int get(char *n); }\npub trait U { int get(char *n); }\nmap trait T for namespace lib { get(n) -> atoi(n); }\nmap trait U for namespace lib { get(n) -> atoi(n); }\n' \
    "'get' is ambiguous on 'lib': bound by lib_T and lib_U" \
    'import lib::lib;\n\nint main(void) { return lib::get("1"); }\n'
mapbad_batch='batch 38'

mapbad_batch='batch 42'
# Type aliases in a `.m.ct` unit: `pub` is mandatory, and the declaration
# shares the type-name space with traits and with itself.
mapbad alias_nonpub \
    'type X = int;\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    "a type alias in a .m.ct unit must be 'pub'"
mapbad alias_duplicate \
    'pub type X = int;\npub type X = int;\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    "duplicate type alias 'X'"
mapbad alias_conflicts_trait \
    'pub trait T { int m(); }\npub type T = int;\nmap trait T for namespace lib { m() -> rand(); }\n' \
    "type alias 'T' conflicts with an existing type"
# The alias and the underlying spelling fold into one host key, so the two maps
# coexist at declaration time and only the call site reports the ambiguity.
mapbad alias_ambiguous \
    'pub type S = char *;\npub trait T { int m(); }\nmap trait T for type S { m(s) -> atoi(s); }\nmap trait T for type char * { m(s) -> strlen(s); }\n' \
    "ambiguous type-host map for method 'm' on type 'char *'" \
    'import lib::lib;\n\nint main(void)\n{\n    S a = "1";\n    int x = a.m();\n    (void)x;\n    return 0;\n}\n'
mapbad_batch='batch 38'

# A type host needs the `.m.ct` whitelist: a normal unit maps instances only.
rm -rf "$work/mbto"
mkdir -p "$work/mbto/lib" "$work/mbto/out"
printf '%b' '#include <stdlib.h>\nnamespace lib;\npub trait T { int m(); }\nmap trait T for type char * { m(s) -> atoi(s); }\n' \
    >"$work/mbto/lib/lib.h.ct"
printf 'import lib::lib;\n\nint main(void) { return 0; }\n' >"$work/mbto/main.ct"
if "$work/ct-ast" build --emit-c "$work/mbto/main.ct" -o "$work/mbto/out" \
        >"$work/mbto/out.txt" 2>"$work/mbto/err.txt"; then
    bad "batch 38: type_host_outside" "expected a non-zero exit"
elif grep -qF 'a type host is only allowed in a .m.ct unit' "$work/mbto/err.txt"; then
    ok "batch 38 (type_host_outside)"
else
    bad "batch 38: type_host_outside" "$(head -2 "$work/mbto/err.txt")"
fi

# An alias is only visible through the import closure. The declaring unit is in
# the build (so the compiler knows the name), but `main` neither imports it nor
# reaches it through another unit: the diagnostic must say so instead of
# silently treating `Text` as an opaque C type.
rm -rf "$work/mtani"
mkdir -p "$work/mtani/lib" "$work/mtani/out"
printf 'namespace lib;\n\npub type Text = char *;\n' >"$work/mtani/lib/lib.h.ct"
printf 'Text g;\n\nint main(void) { return 0; }\n' >"$work/mtani/main.ct"
if "$work/ct-ast" build --emit-c "$work/mtani/lib/lib.h.ct" "$work/mtani/main.ct" \
        -o "$work/mtani/out" >"$work/mtani/out.txt" 2>"$work/mtani/err.txt"; then
    bad "batch 42: alias_not_imported" "expected a non-zero exit"
elif grep -qF "type alias 'Text' is declared in" "$work/mtani/err.txt" \
        && grep -qF "but this unit does not import it" "$work/mtani/err.txt"; then
    ok "batch 42 (alias_not_imported)"
else
    bad "batch 42: alias_not_imported" "$(head -2 "$work/mtani/err.txt")"
fi

# A static trait is bound by its `map`, never implemented / adopted / boxed.
static_trait='pub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n'
mapbad impl_static "$static_trait" 'a static trait cannot be implemented' \
    'import lib::lib;\nstruct S { int v; }\nimpl T for S { int m() { return 1; } }\nint main(void) { return 0; }\n'
mapbad adopt_static "$static_trait" 'a static trait cannot be adopted' \
    'import lib::lib;\nstruct S { int v; } use T;\nint main(void) { return 0; }\n'
mapbad static_as_type "$static_trait" 'a static trait has no interface value' \
    'import lib::lib;\nint use(T t) { return 0; }\nint main(void) { return 0; }\n'
mapbad box_static "$static_trait" "call 'lib::T.<method>()'" \
    'import lib::lib;\nint main(void) { void *v = T::lib; (void)v; return 0; }\n'

# `ct compile` has no import closure, so a `.m.ct` input is refused outright.
if "$work/ct-ast" compile test/modules/map_unit/libc/libc.m.ct -o "$work/mc.c" \
        >"$work/mc.out" 2>"$work/mc.err"; then
    bad "batch 38: compile_map" "expected a non-zero exit"
elif grep -qF 'a .m.ct unit produces no output; import it from a .ct unit' "$work/mc.err"; then
    ok "batch 38 (compile_map)"
else
    bad "batch 38: compile_map" "$(head -2 "$work/mc.err")"
fi

# A `.m.ct` unit may import only another `.m.ct` unit.
rm -rf "$work/mbimp"
mkdir -p "$work/mbimp/lib/x" "$work/mbimp/out"
printf 'pub int h(void);\nint h(void) { return 1; }\n' >"$work/mbimp/lib/x/plain.h.ct"
printf '%b' 'import x::plain;\n#include <stdlib.h>\nnamespace lib;\npub trait T { int m(); }\nmap trait T for namespace lib { m() -> rand(); }\n' \
    >"$work/mbimp/lib/lib.m.ct"
printf 'import lib::lib;\n\nint main(void) { return 0; }\n' >"$work/mbimp/main.ct"
if "$work/ct-ast" build --emit-c "$work/mbimp/main.ct" -o "$work/mbimp/out" \
        >"$work/mbimp/out.txt" 2>"$work/mbimp/err.txt"; then
    bad "batch 38: map_imports_plain" "expected a non-zero exit"
elif grep -qF 'a .m.ct unit can only import another .m.ct unit' "$work/mbimp/err.txt"; then
    ok "batch 38 (map_imports_plain)"
else
    bad "batch 38: map_imports_plain" "$(head -2 "$work/mbimp/err.txt")"
fi

# A circular import must be a diagnostic, not a crash. A unit still on the
# depth-first stack has `prog == -1`; the dependency walk used to read the arena
# at that index and segfault (exit 139, empty stderr). The loader now names the
# two units that close the cycle. A diamond (two parents, one shared child) is
# not a cycle and must still build.
rm -rf "$work/cyc2"
mkdir -p "$work/cyc2/out"
printf 'import a;\n#include <stdio.h>\nint main(void) { return 0; }\n' >"$work/cyc2/main.ct"
printf 'import b;\nint a_v(void) { return 1; }\n' >"$work/cyc2/a.h.ct"
printf 'import a;\nint b_v(void) { return 1; }\n' >"$work/cyc2/b.h.ct"
"$work/ct-ast" build --emit-c -I "$work/cyc2" "$work/cyc2/main.ct" -o "$work/cyc2/out" \
    >"$work/cyc2.out" 2>"$work/cyc2.err"
circ_rc=$?
if [ "$circ_rc" -eq 0 ]; then
    bad "circular_import_2" "expected a non-zero exit"
elif [ "$circ_rc" -eq 139 ]; then
    bad "circular_import_2" "crashed with 139 instead of a diagnostic"
elif grep -Eq "circular import: '[^']+' imports '[^']+'" "$work/cyc2.err"; then
    ok "circular_import_2 (A<->B names the closing pair, exit $circ_rc)"
else
    bad "circular_import_2" "$(head -3 "$work/cyc2.err")"
fi

rm -rf "$work/cyc3"
mkdir -p "$work/cyc3/out"
printf 'import a;\n#include <stdio.h>\nint main(void) { return 0; }\n' >"$work/cyc3/main.ct"
printf 'import b;\nint a_v(void) { return 1; }\n' >"$work/cyc3/a.h.ct"
printf 'import c;\nint b_v(void) { return 1; }\n' >"$work/cyc3/b.h.ct"
printf 'import a;\nint c_v(void) { return 1; }\n' >"$work/cyc3/c.h.ct"
"$work/ct-ast" build --emit-c -I "$work/cyc3" "$work/cyc3/main.ct" -o "$work/cyc3/out" \
    >"$work/cyc3.out" 2>"$work/cyc3.err"
circ_rc=$?
if [ "$circ_rc" -eq 0 ]; then
    bad "circular_import_3" "expected a non-zero exit"
elif [ "$circ_rc" -eq 139 ]; then
    bad "circular_import_3" "crashed with 139 instead of a diagnostic"
elif grep -Eq "circular import: '[^']+' imports '[^']+'" "$work/cyc3.err"; then
    ok "circular_import_3 (A->B->C->A, exit $circ_rc)"
else
    bad "circular_import_3" "$(head -3 "$work/cyc3.err")"
fi

rm -rf "$work/cycs"
mkdir -p "$work/cycs/out"
printf 'import a;\n#include <stdio.h>\nint main(void) { return 0; }\n' >"$work/cycs/main.ct"
printf 'import a;\nint a_v(void) { return 1; }\n' >"$work/cycs/a.h.ct"
"$work/ct-ast" build --emit-c -I "$work/cycs" "$work/cycs/main.ct" -o "$work/cycs/out" \
    >"$work/cycs.out" 2>"$work/cycs.err"
circ_rc=$?
if [ "$circ_rc" -eq 0 ]; then
    bad "circular_import_self" "expected a non-zero exit"
elif [ "$circ_rc" -eq 139 ]; then
    bad "circular_import_self" "crashed with 139 instead of a diagnostic"
elif grep -Eq "circular import: '[^']+' imports '[^']+'" "$work/cycs.err"; then
    ok "circular_import_self (a unit importing itself, exit $circ_rc)"
else
    bad "circular_import_self" "$(head -3 "$work/cycs.err")"
fi

rm -rf "$work/dia"
mkdir -p "$work/dia/out"
printf 'import left;\nimport right;\n#include <stdio.h>\nint main(void) { printf("%%d\\n", left_v() + right_v() + base_v()); return 0; }\n' >"$work/dia/main.ct"
printf 'import base;\npub int left_v(void);\nint left_v(void) { return base_v(); }\n' >"$work/dia/left.h.ct"
printf 'import base;\npub int right_v(void);\nint right_v(void) { return base_v() + 1; }\n' >"$work/dia/right.h.ct"
printf 'pub int base_v(void);\nint base_v(void) { return 10; }\n' >"$work/dia/base.h.ct"
if "$work/ct-ast" build -I "$work/dia" "$work/dia/main.ct" -o "$work/dia.bin" \
        >"$work/dia.out" 2>"$work/dia.err" \
   && [ "$("$work/dia.bin")" = "31" ]; then
    ok "diamond_import (two parents, one shared child, no false cycle)"
else
    bad "diamond_import" "$(cat "$work/dia.err" 2>/dev/null | head -3)"
fi

# Both importable suffixes in one root is an ambiguity, and the message names
# the two candidates.
rm -rf "$work/mbamb"
mkdir -p "$work/mbamb/foo" "$work/mbamb/out"
printf 'pub int helper(void);\n' >"$work/mbamb/foo/foo.h.ct"
printf '%b' '#include <stdlib.h>\nnamespace foo;\npub trait T { int m(); }\nmap trait T for namespace foo { m() -> rand(); }\n' \
    >"$work/mbamb/foo/foo.m.ct"
printf 'import foo::foo;\n\nint main(void) { return 0; }\n' >"$work/mbamb/main.ct"
if "$work/ct-ast" build --emit-c "$work/mbamb/main.ct" -o "$work/mbamb/out" \
        >"$work/mbamb/out.txt" 2>"$work/mbamb/err.txt"; then
    bad "batch 38: import_ambiguous" "expected a non-zero exit"
elif grep -qF "import 'foo/foo' is ambiguous: both" "$work/mbamb/err.txt"; then
    ok "batch 38 (import_ambiguous)"
else
    bad "batch 38: import_ambiguous" "$(head -2 "$work/mbamb/err.txt")"
fi

echo
echo "== p32 types (L32) =="

# Phase 32 S8 (L32-7): `--types` is an opt-in gate on `ct check` only. A
# non-check invocation names the rule instead of failing as an unknown option,
# and `check --types` stays silent on a legal program.
p32_cli_x="$work/p32_cli_x.ct"
printf 'int main(void) { return 0; }\n' >"$p32_cli_x"
p32_cli_reject() {
    if "$work/ct-ast" "$@" >"$work/p32cli.out" 2>"$work/p32cli.err"; then
        bad "p32 CLI ($*)" "expected a non-zero exit"
    elif [ "$(grep -cF "ctc: --types is only valid with 'ct check'" "$work/p32cli.err")" -ne 1 ]; then
        bad "p32 CLI ($*)" "$(head -2 "$work/p32cli.err")"
    elif grep -q ': error:' "$work/p32cli.err"; then
        bad "p32 CLI ($*)" "a source diagnostic leaked: $(head -2 "$work/p32cli.err")"
    else
        ok "p32 CLI ($*: refused by name)"
    fi
}
p32_cli_reject build --types "$p32_cli_x"
p32_cli_reject --types "$p32_cli_x"
if ! "$work/ct-ast" check --types "$p32_cli_x" \
        >"$work/p32cli.out" 2>"$work/p32cli.err"; then
    bad "p32 CLI (check --types)" "expected a zero exit: $(head -2 "$work/p32cli.err")"
elif [ -s "$work/p32cli.err" ]; then
    bad "p32 CLI (check --types)" "a legal program drew a diagnostic: $(head -2 "$work/p32cli.err")"
else
    ok "p32 CLI (check --types accepts a legal program)"
fi

# Phase 32 S10 (L32-1..L32-6): one fixture per shape, each judged on its own.
# A file's exit code alone would hide a second or a missing L32 line, so the
# first line's position and the exact wording are both pinned here.
p32_error() {
    p32_f="$1"
    p32_pos="$2"
    p32_want="$3"
    p32_out=$("$work/ct-ast" check --types "$p32_f" 2>&1)
    p32_rc=$?
    if [ "$p32_rc" -ne 1 ]; then
        bad "p32 $p32_f" "expected rc=1, got $p32_rc: $(printf '%s\n' "$p32_out" | head -1)"
    elif [ "$(printf '%s\n' "$p32_out" | grep -cF "$p32_want")" -ne 1 ]; then
        bad "p32 $p32_f" "expected exactly one '$p32_want': $p32_out"
    elif [ "$(printf '%s\n' "$p32_out" | grep -cE 'initializer:|assignment:|return:|argument [0-9]+:')" -ne 1 ]; then
        bad "p32 $p32_f" "expected exactly one L32 line: $p32_out"
    elif ! printf '%s\n' "$p32_out" | head -1 | grep -qF "$p32_f:$p32_pos: error: "; then
        bad "p32 $p32_f" "expected first line '$p32_f:$p32_pos: error: ...', got: $p32_out"
    else
        ok "p32 $p32_f ($p32_pos, one L32 line)"
    fi
}
p32_error test/ast/check_errors/check_init_ptr.ct 3:13 "initializer: expected 'int', got 'char *'"
p32_error test/ast/check_errors/check_assign_ptr.ct 4:9 "assignment: expected 'int', got 'char *'"
p32_error test/ast/check_errors/check_struct_assign.ct 7:9 "assignment: expected 'struct A', got 'struct B'"
p32_error test/ast/check_errors/check_return_ptr.ct 3:12 "return: expected 'int', got 'char *'"
p32_error test/ast/check_errors/check_return_struct.ct 6:12 "return: expected 'struct A', got 'struct B'"
p32_error test/ast/check_errors/check_return_missing.ct 3:5 "return: missing a value (function returns 'int')"
p32_error test/ast/check_errors/check_return_in_void.ct 3:12 "return: a value is not allowed in a void function"
p32_error test/ast/check_errors/check_container_push.ct 4:12 "argument 1: expected 'int', got 'char *'"
p32_error test/ast/check_errors/check_container_set.ct 4:14 "argument 2: expected 'int', got 'char *'"
p32_error test/ast/check_errors/check_container_put.ct 4:16 "argument 2: expected 'int', got 'char *'"
p32_error test/ast/check_errors/check_container_struct.ct 6:12 "argument 1: expected 'int', got 'struct A'"
p32_error test/ast/check_errors/check_generic_arg.ct 10:18 "argument 1: expected 'int', got 'struct A'"

# E32-10: the existing boxing diagnostic stays exactly one line, at the same
# position, with or without `--types`; the new gate must not add a second one.
p32_iface="test/ast/errors/check_iface_use.ct"
p32_iface_plain=$("$work/ct-ast" check "$p32_iface" 2>&1)
p32_iface_plain_rc=$?
p32_iface_typed=$("$work/ct-ast" check --types "$p32_iface" 2>&1)
p32_iface_typed_rc=$?
if [ "$p32_iface_plain_rc" -ne 1 ] || [ "$p32_iface_typed_rc" -ne 1 ]; then
    bad "p32 iface" "expected rc=1 in both modes ($p32_iface_plain_rc/$p32_iface_typed_rc)"
elif [ "$(printf '%s\n' "$p32_iface_plain" | grep -cF 'the struct does not use this trait')" -ne 1 ] \
    || [ "$(printf '%s\n' "$p32_iface_typed" | grep -cF 'the struct does not use this trait')" -ne 1 ]; then
    bad "p32 iface" "expected exactly one existing diagnostic in both modes"
elif ! printf '%s\n' "$p32_iface_typed" | head -1 | grep -qF "$p32_iface:7:16: error: the struct does not use this trait"; then
    bad "p32 iface" "expected the baseline position, got: $(printf '%s\n' "$p32_iface_typed" | head -1)"
elif [ "$(printf '%s\n' "$p32_iface_plain" | head -1)" != "$(printf '%s\n' "$p32_iface_typed" | head -1)" ]; then
    bad "p32 iface" "--types changed the positioned line"
else
    ok "p32 iface (existing diagnostic unchanged under --types)"
fi

# E32-12/E32-13: the legal corpus. `prog.ct` is judged twice (with and without
# `--types`); the `check_only/` forms only with the gate, since cc rejects or
# warns on them. Every one must stay silent.
p32_legal() {
    p32_f="$1"
    p32_out=$("$work/ct-ast" check "$p32_f" 2>&1)
    p32_rc=$?
    if [ "$p32_rc" -ne 0 ] || [ -n "$p32_out" ]; then
        bad "p32 legal $p32_f (check)" "expected rc=0 and no output: $p32_out"
        return
    fi
    p32_out=$("$work/ct-ast" check --types "$p32_f" 2>&1)
    p32_rc=$?
    if [ "$p32_rc" -ne 0 ] || [ -n "$p32_out" ]; then
        bad "p32 legal $p32_f (--types)" "expected rc=0 and no output: $p32_out"
        return
    fi
    ok "p32 legal $p32_f (silent with and without --types)"
}
p32_legal test/ast/209_valid_assignments/prog.ct
p32_legal test/ast/210_valid_skip_forms/prog.ct
for p32_f in test/ast/209_valid_assignments/check_only/*.ct \
             test/ast/210_valid_skip_forms/check_only/*.ct; do
    [ -f "$p32_f" ] || continue
    p32_out=$("$work/ct-ast" check --types "$p32_f" 2>&1)
    p32_rc=$?
    if [ "$p32_rc" -ne 0 ] || [ -n "$p32_out" ]; then
        bad "p32 skip $p32_f" "expected rc=0 and no output: $p32_out"
    else
        ok "p32 skip $p32_f"
    fi
done

# E32-18: the coverage matrix. The expectation below is the source of truth;
# `check_coverage.tsv` must equal it byte for byte, and each row is then
# executed. Closure actuals have no row: phase 21 refuses a closure
# expression at assign/return/container before L32 can run (deviation, §14).
cat >"$work/p32_coverage.expected.tsv" <<'P32COV'
position	formal_class	actual_class	result	fixture	expected
assign	arithmetic	pointer	L32-1	check_errors/check_init_ptr.ct	initializer: expected 'int', got 'char *'
assign	struct A	struct B	L32-2	check_errors/check_struct_assign.ct	assignment: expected 'struct A', got 'struct B'
return	arithmetic	pointer	L32-3	check_errors/check_return_ptr.ct	return: expected 'int', got 'char *'
return	struct A	struct B	L32-3	check_errors/check_return_struct.ct	return: expected 'struct A', got 'struct B'
return	void	arithmetic	L32-5	check_errors/check_return_in_void.ct	return: a value is not allowed in a void function
container	arithmetic	pointer	L32-6	check_errors/check_container_push.ct	argument 1: expected 'int', got 'char *'
container	arithmetic	struct A	L32-6	check_errors/check_container_struct.ct	argument 1: expected 'int', got 'struct A'
assign	interface	struct	ok	211_coverage_aux/prog.ct	-
assign	arithmetic	arithmetic	ok	211_coverage_aux/prog.ct	-
return	interface	struct	ok	211_coverage_aux/prog.ct	-
return	arithmetic	arithmetic	ok	211_coverage_aux/prog.ct	-
container	interface	struct	ok	211_coverage_aux/prog.ct	-
container	arithmetic	arithmetic	ok	211_coverage_aux/prog.ct	-
assign	arithmetic	void	skip	211_coverage_aux/check_only/void_actual.ct	-
container	arithmetic	void	skip	211_coverage_aux/check_only/void_actual.ct	-
assign	pointer	array	skip	211_coverage_aux/check_only/array_actual.ct	-
return	pointer	array	skip	211_coverage_aux/check_only/array_actual.ct	-
container	pointer	array	skip	211_coverage_aux/check_only/array_actual.ct	-
assign	arithmetic	fnptr	skip	211_coverage_aux/check_only/fnptr_actual.ct	-
return	arithmetic	fnptr	skip	211_coverage_aux/check_only/fnptr_actual.ct	-
container	arithmetic	fnptr	skip	211_coverage_aux/check_only/fnptr_actual.ct	-
P32COV
if ! cmp -s "$work/p32_coverage.expected.tsv" test/ast/check_coverage.tsv; then
    bad "p32 coverage (matrix)" "check_coverage.tsv differs from the hardcoded expectation"
else
    ok "p32 coverage (matrix matches its expected source)"
fi
p32_legal test/ast/211_coverage_aux/prog.ct
p32_cov_l=0
p32_cov_ok=0
p32_cov_skip=0
p32_cov_names=""
p32_tab="$(printf '\t')"
while IFS="$p32_tab" read -r p32_pos p32_fc p32_ac p32_res p32_fx p32_exp; do
    [ "$p32_pos" = "position" ] && continue
    [ -n "$p32_pos" ] || continue
    case "$p32_res" in
    L32-*)
        p32_cov_l=$((p32_cov_l + 1))
        case "$p32_fx" in
        check_errors/check_init_ptr.ct) p32_at=3:13 ;;
        check_errors/check_struct_assign.ct) p32_at=7:9 ;;
        check_errors/check_return_ptr.ct) p32_at=3:12 ;;
        check_errors/check_return_struct.ct) p32_at=6:12 ;;
        check_errors/check_return_in_void.ct) p32_at=3:12 ;;
        check_errors/check_container_push.ct) p32_at=4:12 ;;
        check_errors/check_container_struct.ct) p32_at=6:12 ;;
        *) p32_at="" ;;
        esac
        p32_out=$("$work/ct-ast" check --types "test/ast/$p32_fx" 2>&1)
        p32_rc=$?
        if [ "$p32_rc" -ne 1 ] || [ "$(printf '%s\n' "$p32_out" | grep -cF "$p32_exp")" -ne 1 ]; then
            bad "p32 coverage ($p32_pos/$p32_fc<-$p32_ac)" "expected one '$p32_exp': $p32_out"
        elif [ -n "$p32_at" ] && ! printf '%s\n' "$p32_out" | head -1 | grep -qF "test/ast/$p32_fx:$p32_at: error: "; then
            bad "p32 coverage ($p32_pos/$p32_fc<-$p32_ac)" "wrong position: $(printf '%s\n' "$p32_out" | head -1)"
        else
            ok "p32 coverage ($p32_pos $p32_fc <- $p32_ac, $p32_res)"
        fi
        ;;
    ok)
        p32_cov_ok=$((p32_cov_ok + 1))
        p32_cov_names="$p32_cov_names $p32_pos/$p32_fc<-$p32_ac"
        ;;
    skip)
        p32_cov_skip=$((p32_cov_skip + 1))
        p32_out=$("$work/ct-ast" check --types "test/ast/$p32_fx" 2>&1)
        p32_rc=$?
        if [ "$p32_rc" -ne 0 ] || [ -n "$p32_out" ]; then
            bad "p32 coverage (skip $p32_pos/$p32_fc<-$p32_ac)" "$p32_out"
        else
            ok "p32 coverage (skip $p32_pos $p32_fc <- $p32_ac)"
        fi
        ;;
    esac
done <"$work/p32_coverage.expected.tsv"
p32_want_names=" assign/interface<-struct assign/arithmetic<-arithmetic return/interface<-struct return/arithmetic<-arithmetic container/interface<-struct container/arithmetic<-arithmetic"
if [ "$p32_cov_l" -ne 7 ] || [ "$p32_cov_ok" -ne 6 ] || [ "$p32_cov_skip" -ne 8 ] \
    || [ "$p32_cov_names" != "$p32_want_names" ]; then
    bad "p32 coverage (counts)" "got L=$p32_cov_l ok=$p32_cov_ok skip=$p32_cov_skip names=[$p32_cov_names]"
else
    ok "coverage: 21 rows, 7 L32-n, 6 ok, 8 skip, 0 n/a"
fi

# E32-15: the legal corpus is an explicit list. Each row records what the
# baseline `ct check` produced; `--types` must reproduce it exactly, so a new
# diagnostic on any listed file fails here. Error tours and import-only units
# keep their baseline exit code and text instead of being forced to rc=0.
p32_manifest_bad=0
p32_manifest_n=0
while IFS="$p32_tab" read -r p32_mp p32_mr p32_me; do
    [ "$p32_mp" = "path" ] && continue
    [ -n "$p32_mp" ] || continue
    p32_manifest_n=$((p32_manifest_n + 1))
    p32_out=$("$work/ct-ast" check --types "$p32_mp" 2>&1)
    p32_rc=$?
    p32_enc=${p32_out//$'\n'/\\n}
    if [ "$p32_rc" != "$p32_mr" ] || [ "$p32_enc" != "$p32_me" ]; then
        p32_manifest_bad=$((p32_manifest_bad + 1))
        bad "p32 legal manifest ($p32_mp)" "rc=$p32_rc expected $p32_mr; output [$p32_enc]"
    fi
done < test/probes/p32_legal_manifest.tsv
if [ "$p32_manifest_bad" -eq 0 ]; then
    ok "p32 legal manifest ($p32_manifest_n rows: --types reproduces the baseline)"
fi

echo
echo "== negative cases (test/ast/errors/*.ct) =="
# Every source diagnostic now carries the full position (`file:line:col: error:`);
# driver-level failures (an unreadable input, a limit) keep the `ctc:` prefix and
# are asserted where they are produced.
for f in test/ast/errors/*.ct; do
    [ -f "$f" ] || continue
    b="$(basename "$f" .ct)"
    # Phase 37: signature fixtures must exit 0 in compile mode (warning);
    # their build/check severity is asserted by the dedicated probe below.
    case "$b" in p37_sig_*) continue;; esac
    if "$work/ct-ast" "$f" -o "$work/bad-$b.c" \
            >"$work/bad-$b.out" 2>"$work/bad-$b.err"; then
        bad "$b" "expected a non-zero exit"
    elif grep -Eq '^[^:]+:[0-9]+:[0-9]+: error: ' "$work/bad-$b.err"; then
        ok "$b (rejected with a positioned diagnostic)"
    else
        bad "$b" "no positioned diagnostic on stderr: $(cat "$work/bad-$b.err")"
    fi
done

# Phase 37: signature mismatch is a hard error for build/check and a warning
# for compile; the missing-method path stays a hard error (E37-1 / E37-2).
if bash test/ast/p37_probe.sh "$work/ct-ast" >"$work/p37.out" 2>"$work/p37.err"; then
    ok "p37 signature severity"
else
    bad "p37 signature severity" "$(cat "$work/p37.out" "$work/p37.err")"
fi

# Phase 37 example: --runtime-checks on a valid program keeps the output.
if "$work/ct-ast" build --runtime-checks --outdir "$work/p37ex" \
        examples/41_runtime_checks/prog.ct -o "$work/p37ex.bin" \
        >"$work/p37ex.out" 2>"$work/p37ex.err" \
   && "$work/p37ex.bin" >"$work/p37ex.stdout" 2>"$work/p37ex.run.err" \
   && cmp -s "$work/p37ex.stdout" examples/41_runtime_checks/prog.expected.out; then
    ok "p37 example (--runtime-checks keeps the valid path)"
else
    bad "p37 example" "$(cat "$work/p37ex.err" "$work/p37ex.run.err" 2>/dev/null)"
fi

# Phase 38: defer diagnostics and the first positive defer program.
if bash test/ast/p38_probe.sh "$work/ct-ast" >"$work/p38.out" 2>"$work/p38.err"; then
    ok "p38 defer probe"
else
    bad "p38 defer probe" "$(cat "$work/p38.out" "$work/p38.err")"
fi

# Phase 39 R1: --lib is build-only; empty root reports L39-2.
if bash test/modules/p39_lib/r1_probe.sh "$work/ct-ast" >"$work/p39r1.out" 2>"$work/p39r1.err"; then
    ok "p39 r1"
else
    bad "p39 r1" "$(cat "$work/p39r1.out" "$work/p39r1.err")"
fi

# Phase 39 R2: root export classification.
if bash test/modules/p39_lib/r2_probe.sh "$work/ct-ast" >"$work/p39r2.out" 2>"$work/p39r2.err"; then
    ok "p39 r2"
else
    bad "p39 r2" "$(cat "$work/p39r2.out" "$work/p39r2.err")"
fi

# Phase 39 R3: ABI header contract.
if bash test/modules/p39_lib/r3_probe.sh "$work/ct-ast" >"$work/p39r3.out" 2>"$work/p39r3.err"; then
    ok "p39 r3"
else
    bad "p39 r3" "$(cat "$work/p39r3.out" "$work/p39r3.err")"
fi

# Phase 39 R4: static non-exports, export visibility, hidden compile.
if bash test/modules/p39_lib/r4_probe.sh "$work/ct-ast" >"$work/p39r4.out" 2>"$work/p39r4.err"; then
    ok "p39 r4"
else
    bad "p39 r4" "$(cat "$work/p39r4.out" "$work/p39r4.err")"
fi

# Phase 39 R5: archive + nm surface.
if bash test/modules/p39_lib/r5_probe.sh "$work/ct-ast" >"$work/p39r5.out" 2>"$work/p39r5.err"; then
    ok "p39 r5"
else
    bad "p39 r5" "$(cat "$work/p39r5.out" "$work/p39r5.err")"
fi

# Phase 39 R6: C consumer link/run.
if bash test/modules/p39_lib/r6_probe.sh "$work/ct-ast" >"$work/p39r6.out" 2>"$work/p39r6.err"; then
    ok "p39 r6"
else
    bad "p39 r6" "$(cat "$work/p39r6.out" "$work/p39r6.err")"
fi

# Phase 39 R7: deterministic archive.
if bash test/modules/p39_lib/r7_probe.sh "$work/ct-ast" >"$work/p39r7.out" 2>"$work/p39r7.err"; then
    ok "p39 r7"
else
    bad "p39 r7" "$(cat "$work/p39r7.out" "$work/p39r7.err")"
fi

# Phase 39 R8: --emit-c zero regression against the S0 baseline.
if bash test/modules/p39_lib/r8_probe.sh "$work/ct-ast" >"$work/p39r8.out" 2>"$work/p39r8.err"; then
    ok "p39 r8"
else
    bad "p39 r8" "$(cat "$work/p39r8.out" "$work/p39r8.err")"
fi

# Phase 39 R9: the ABI guide is discoverable and states the nm caveat.
if grep -Fq -- '--lib' docs/package-guide.md && grep -Fq 'nm -g' docs/package-guide.md; then
    ok "p39 docs"
else
    bad "p39 docs" "docs/package-guide.md lacks --lib or the nm caveat"
fi

# Phase 40 R1: err: syntax and L40-1..4.
if bash test/ast/p40_err_syntax.sh "$work/ct-ast" >"$work/p40r1.out" 2>"$work/p40r1.err"; then
    ok "p40 r1"
else
    bad "p40 r1" "$(cat "$work/p40r1.out" "$work/p40r1.err")"
fi

# Phase 40 R2: errdefer scope/control/own/goto.
if bash test/ast/p40_errdefer_scope.sh "$work/ct-ast" >"$work/p40r2.out" 2>"$work/p40r2.err"; then
    ok "p40 r2"
else
    bad "p40 r2" "$(cat "$work/p40r2.out" "$work/p40r2.err")"
fi

# Phase 40 R4: defer/errdefer/own order and own conflict.
if bash test/ast/p40_order_own.sh "$work/ct-ast" >"$work/p40r4.out" 2>"$work/p40r4.err"; then
    ok "p40 r4"
else
    bad "p40 r4" "$(cat "$work/p40r4.out" "$work/p40r4.err")"
fi

# Phase 37 O2: --runtime-checks guards a null vtable; off is unchanged.
if bash test/ast/p37_rt_probe.sh "$work/ct-ast" >"$work/p37rt.out" 2>"$work/p37rt.err"; then
    ok "p37 runtime guard"
else
    bad "p37 runtime guard" "$(cat "$work/p37rt.out" "$work/p37rt.err")"
fi

# Phase 21 S4: closure escape / capture / arity diagnostics are stable text,
# and every one is followed by the tier-1 hint through the independent `note:`
# channel. The generic sweep above only proves *a* positioned diagnostic; pin
# the wording, position and note verbatim so a later refactor cannot drift it.
for pair in \
    "closure_escape_return|4:5|a closure cannot escape through 'return'" \
    "closure_store_global|5:5|a closure cannot be stored in 'g' (its scope outlives the closure)" \
    "closure_store_outer|6:9|a closure cannot be stored in 'd' (its scope outlives the closure)" \
    "closure_store_static|5:5|a closure cannot be stored in 's' (its scope outlives the closure)" \
    "closure_store_field|6:5|a closure cannot be stored in a field, an element or a container" \
    "closure_store_element|5:5|a closure cannot be stored in a field, an element or a container" \
    "closure_capture_own|8:1|a closure cannot capture 'b' (it is 'own' or 'borrow')" \
    "closure_capture_borrow|3:1|a closure cannot capture 'c' (it is 'own' or 'borrow')" \
    "closure_capture_closure|4:1|a closure cannot capture another closure" \
    "closure_copy_local|4:5|this closure is a binding, not a value (inline it or use a struct + trait)" \
    "closure_reassign|5:5|this closure is a binding, not a value (inline it or use a struct + trait)" \
    "closure_capture_write|3:1|a captured variable cannot be reassigned inside a closure" \
    "closure_capture_incr|3:1|a captured variable cannot be reassigned inside a closure" \
    "closure_capture_addassign|3:1|a captured variable cannot be reassigned inside a closure" \
    "closure_capture_addr|3:1|the address of a captured variable cannot be taken inside a closure" \
    "closure_capture_shadow|3:1|a local cannot shadow the captured 'n'" \
    "closure_plain_fnptr|5:12|a closure cannot be used where a plain function pointer is expected" \
    "closure_fnptr_void_ptr_tail|7:12|a closure cannot be used where a plain function pointer is expected" \
    "closure_not_a_pair|5:12|a closure argument must fill a '(fn, env)' parameter pair" \
    "closure_capture_array|4:1|a closure cannot capture the array 'arr' (capture a pointer to it instead)" \
    "closure_global_init|1:8|a closure cannot be stored in 'handler' (its scope outlives the closure)" \
    "closure_hdr_export.h|3:5|a closure cannot be stored in 'handler' (its scope outlives the closure)"
do
    cf="${pair%%|*}"
    rest="${pair#*|}"
    pos="${rest%%|*}"
    cfmsg="${rest#*|}"
    f="test/ast/errors/$cf.ct"
    if "$work/ct-ast" "$f" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "p21-s4: $cf" "expected a non-zero exit"
    elif ! grep -Fq "$f:$pos: error: $cfmsg" "$work/$cf.err"; then
        bad "p21-s4: $cf" "missing pinned error: $(cat "$work/$cf.err")"
    elif ! grep -Fq "$f:$pos: note: tier 1:" "$work/$cf.err"; then
        bad "p21-s4: $cf" "missing tier-1 note: $(cat "$work/$cf.err")"
    elif [ "$(grep -c 'error: ' "$work/$cf.err")" -ne 1 ]; then
        bad "p21-s4: $cf" "expected exactly one error: $(cat "$work/$cf.err")"
    elif ! grep -Fq 'ctc: 1 error(s) generated' "$work/$cf.err"; then
        bad "p21-s4: $cf" "the note changed the error count: $(cat "$work/$cf.err")"
    else
        ok "p21-s4 ($cf)"
    fi
done

# D21-1: CT has no type inference, so `auto` is not a type name. Rejecting it
# here keeps a closure's return type coming from the declaration on the left
# instead of letting `cc` read `auto` as a C99 storage class.
if "$work/ct-ast" test/ast/errors/auto_keyword.ct -o "$work/auto_keyword.c" \
        >"$work/auto_keyword.out" 2>"$work/auto_keyword.err"; then
    bad "p21-d21-1: auto_keyword" "expected a non-zero exit"
elif ! grep -Fq "test/ast/errors/auto_keyword.ct:3:5: error: 'auto' is not a type in CT (write the type explicitly)" "$work/auto_keyword.err"; then
    bad "p21-d21-1: auto_keyword" "$(cat "$work/auto_keyword.err")"
else
    ok "p21-d21-1 (auto_keyword)"
fi

# R10: `__ct_` is one predicate for every declaration category, so a function,
# global, struct or field name is refused with the same positioned message.
for cf in reserved_fn_name reserved_global_name reserved_type_name reserved_field_name; do
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "p21-r10: $cf" "expected a non-zero exit"
    elif ! grep -Fq "identifier '__ct_' is reserved for the compiler" "$work/$cf.err"; then
        bad "p21-r10: $cf" "$(cat "$work/$cf.err")"
    elif ! grep -Eq '^[^:]+:[0-9]+:[0-9]+: error: ' "$work/$cf.err"; then
        bad "p21-r10: $cf" "no positioned diagnostic: $(cat "$work/$cf.err")"
    else
        ok "p21-r10 ($cf)"
    fi
done

# The boundaries that need more than one assertion:
#  - E8 is a note, not a JSON key, and appears only when the callee is opaque;
#  - R03 lets a declared binding fill the pair, so its parameter tail must match
#    the host and the mismatch is a CT-level error, not a `cc` failure;
#  - arity counts the env slot, so a pair actual produces no "takes N
#    argument(s)" line.
if grep -Fq "note: the compiler cannot see whether the callee keeps the environment; the environment dies with this frame" \
        "$work/closure_not_a_pair.err"; then
    ok "p21-s4: E8 note wording"
else
    bad "p21-s4: E8 note" "$(cat "$work/closure_not_a_pair.err")"
fi
if "$work/ct-ast" test/ast/errors/closure_param_type_mismatch.ct -o "$work/cptm.c" \
        >"$work/cptm.out" 2>"$work/cptm.err"; then
    bad "p21-r03: binding pair type" "expected a non-zero exit"
elif ! grep -Fq "test/ast/errors/closure_param_type_mismatch.ct:4:1: error: this closure's parameter 1 is 'char *', but the expected type is 'int'" "$work/cptm.err"; then
    bad "p21-r03: binding pair type" "$(cat "$work/cptm.err")"
elif [ "$(grep -c 'error: ' "$work/cptm.err")" -ne 1 ]; then
    bad "p21-r03: binding pair type" "expected exactly one error: $(cat "$work/cptm.err")"
else
    ok "p21-r03: a declared binding's parameter tail must match the host pair"
fi
if "$work/ct-ast" test/ast/errors/closure_literal_arity.ct -o "$work/cla.c" \
        >"$work/cla.out" 2>"$work/cla.err"; then
    bad "p21-audit: literal arity" "expected a non-zero exit"
elif ! grep -Fq "test/ast/errors/closure_literal_arity.ct:5:1: error: this closure takes 2 parameters, but the expected type takes 1" "$work/cla.err"; then
    bad "p21-audit: literal arity" "$(cat "$work/cla.err")"
else
    ok "p21-audit: a literal's parameter count is compared with its hosting type"
fi
if "$work/ct-ast" test/ast/75_closure_param_pair/prog.ct -o "$work/clpair.c" \
        >"$work/clpair.out" 2>"$work/clpair.err" \
   && ! grep -q "takes [0-9]* argument(s)" "$work/clpair.err"; then
    ok "p21-s4: a closure actual counts as two arguments for arity, without a second wording"
else
    bad "p21-s4: arity counts env" "$(cat "$work/clpair.err")"
fi

# The note channel must not touch the JSON document, the severity field or the
# exit code. `check` stays strict; `compile` stays byte-identical on units with
# no closures.
"$work/ct-ast" check --diagnostics=json "test/ast/errors/closure_escape_return.ct" \
    >"$work/cl_json.out" 2>"$work/cl_json.err"
clrc=$?
if [ "$clrc" -eq 1 ] && [ ! -s "$work/cl_json.out" ] \
        && ! grep -q 'note' "$work/cl_json.out" \
        && grep -Fq 'note: tier 1:' "$work/cl_json.err"; then
    ok "p21-s4: a closure error is not in the JSON warnings and the note adds no key"
else
    bad "p21-s4: closure JSON" "exit $clrc; $(cat "$work/cl_json.out" "$work/cl_json.err")"
fi
cat > "$work/cl_arity.ct" <<'EOF'
int add(int a, int b) { return a + b; }
int main(void) { return add(1); }
EOF
"$work/ct-ast" check --diagnostics=json "$work/cl_arity.ct" \
    >"$work/cl_arity.json" 2>"$work/cl_arity.err"
clrc=$?
if [ "$clrc" -eq 1 ] \
        && grep -Fq '"severity":"error"' "$work/cl_arity.json" \
        && grep -Fq '"type":"arity_mismatch"' "$work/cl_arity.json"; then
    ok "p21-s4: the pre-existing severity field and top-level warnings key are unchanged"
else
    bad "p21-s4: JSON shape" "exit $clrc; $(cat "$work/cl_arity.json")"
fi

# Phase 21 S5: the argument form (D21-14) is for inline literals only; a literal
# in a plain function-pointer slot keeps the S4 wording and its tier-1 note.
if "$work/ct-ast" test/ast/errors/closure_literal_plain_fnptr.ct -o "$work/cllpf.c" \
        >"$work/cllpf.out" 2>"$work/cllpf.err"; then
    bad "p21-s5: literal plain fnptr" "expected a non-zero exit"
elif ! grep -Fq "test/ast/errors/closure_literal_plain_fnptr.ct:4:12: error: a closure cannot be used where a plain function pointer is expected" "$work/cllpf.err"; then
    bad "p21-s5: literal plain fnptr" "$(cat "$work/cllpf.err")"
elif ! grep -Fq 'note: tier 1:' "$work/cllpf.err"; then
    bad "p21-s5: literal plain fnptr note" "$(cat "$work/cllpf.err")"
else
    ok "p21-s5: a literal in a plain function-pointer slot keeps the S4 wording"
fi

# Phase 21 S5 probe 79: two implementation units, each with its own closure.
# Both generated .c files carry a `static` trampoline numbered from zero, which
# file scope keeps apart; a literal crosses the boundary as a `(fn, env)` pair.
rm -rf "$work/cl79"
mkdir -p "$work/cl79"
if ! "$work/ct-ast" build --emit-c test/ast/79_closure_two_units/main.ct -o "$work/cl79" \
        >"$work/cl79.out" 2>"$work/cl79.err"; then
    bad "p21-s5: two units" "build failed: $(cat "$work/cl79.err")"
elif ! grep -Fq '__ct_cl_tramp_' "$work/cl79/main.c" \
        || ! grep -Fq '__ct_cl_tramp_' "$work/cl79/dep.c"; then
    bad "p21-s5: two units" "a unit lost its static trampoline"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/cl79"/*.c -o "$work/cl79.bin" 2>"$work/cl79.cc"; then
    bad "p21-s5: two units" "generated C did not build: $(cat "$work/cl79.cc")"
elif ! "$work/cl79.bin" >"$work/cl79.stdout" 2>&1; then
    bad "p21-s5: two units" "the program exited non-zero"
elif ! cmp -s "$work/cl79.stdout" test/ast/79_closure_two_units/expected.out; then
    bad "p21-s5: two units" "program output differs: $(cat "$work/cl79.stdout")"
else
    ok "p21-s5: two units (same static trampoline name; a literal crosses the boundary)"
fi

# Phase 21 exit criterion 4: the emitted shape itself, not just the behaviour.
# A bound literal is a stack struct plus a `static` trampoline -- never a heap
# allocation and never a vtable -- and the three spellings of one closure
# (`env` / `tramp` / `env_v`) share one id. Within a unit the ids are unique and
# ascending in allocation order (outer before inner), and a struct is complete
# before the trampoline that builds an instance of it.
cl_shape() {
    clf="$1"
    cltag="$2"
    clwant="$3"
    # P36 S4a1: `Str` is a concrete built-in unit, so compile mode splices its
    # `free`-bearing drop in front of every program. The predicate is unchanged;
    # the scan starts at the closure lowering output (`__ct_cl_env_*`), which is
    # what "no heap allocation, no vtable" is about.
    if sed -n '/^struct __ct_cl_env_[0-9][0-9]* {/,$p' "$clf" | grep -Eq 'malloc\(|free\(|vtable'; then
        bad "$cltag" "heap allocation or vtable in the generated C"
        return
    fi
    env="$(grep -o '^struct __ct_cl_env_[0-9][0-9]* {' "$clf" | grep -o '[0-9][0-9]*' | sort -n | uniq | tr '\n' ' ')"
    trm="$(grep -o '__ct_cl_tramp_[0-9][0-9]*' "$clf" | grep -o '[0-9][0-9]*' | sort -n | uniq | tr '\n' ' ')"
    # an instance is either a named local (`__ct_cl_env_v_N`) or, for an inline
    # actual, a compound literal (`&(struct __ct_cl_env_N){ … }`)
    ins="$({
        grep -o '__ct_cl_env_v_[0-9][0-9]*' "$clf" | grep -o '[0-9][0-9]*'
        grep -o '&(struct __ct_cl_env_[0-9][0-9]*){' "$clf" | grep -o '[0-9][0-9]*'
    } | sort -n | uniq | tr '\n' ' ')"
    if [ -z "$env" ] || [ "$env" != "$trm" ] || [ "$env" != "$ins" ]; then
        bad "$cltag" "env/tramp/instance ids differ: '$env' / '$trm' / '$ins'"
        return
    fi
    if [ -n "$clwant" ] && [ "$(printf '%s\n' $env | wc -l | tr -d ' ')" -ne "$clwant" ]; then
        bad "$cltag" "expected $clwant closures, saw '$env'"
        return
    fi
    # Ascending envelope structs: the parser hands out ids depth-first, so this
    # is also the outer-before-inner order.
    if ! awk '
        BEGIN { last = -1 }
        /^struct __ct_cl_env_[0-9]+ \{/ {
            s = $0; sub(/^struct __ct_cl_env_/, "", s); sub(/ .*/, "", s)
            if (s + 0 <= last) { print "not ascending: " s; exit 1 }
            last = s + 0
        }' "$clf" >"$work/clorder.txt" 2>&1; then
        bad "$cltag" "$(cat "$work/clorder.txt")"
        return
    fi
    # Every instance and trampoline follows a complete struct, and each id is
    # used exactly once (no reuse).
    if ! awk '
        /^struct __ct_cl_env_[0-9]+ \{/ {
            s = $0; sub(/^struct __ct_cl_env_/, "", s); sub(/ .*/, "", s)
            env[s] = NR; nenv++
        }
        /^static .*__ct_cl_tramp_[0-9]+\(void \*self/ && $0 !~ /\);/ {
            s = $0; sub(/.*__ct_cl_tramp_/, "", s); sub(/\(.*/, "", s)
            trm[s] = NR; ntrm++
        }
        /__ct_cl_env_v_[0-9]+ =/ {
            s = $0; sub(/.*__ct_cl_env_v_/, "", s); sub(/[^0-9].*/, "", s)
            ins[s] = NR; nins++
        }
        /&\(struct __ct_cl_env_[0-9]+\)\{/ {
            s = $0; sub(/.*&\(struct __ct_cl_env_/, "", s); sub(/\).*/, "", s)
            ins[s] = NR; nins++
        }
        END {
            bad = 0
            for (id in trm) {
                if (!(id in env)) { print "no struct for " id; bad = 1 }
                else if (env[id] > trm[id]) { print "struct after trampoline " id; bad = 1 }
                if (!(id in ins)) { print "no instance for " id; bad = 1 }
                else if (env[id] > ins[id]) { print "struct after instance " id; bad = 1 }
            }
            if (nenv != ntrm || nenv != nins) { print "counts differ"; bad = 1 }
            exit bad
        }' "$clf" >"$work/clorder.txt" 2>&1; then
        bad "$cltag" "$(cat "$work/clorder.txt")"
        return
    fi
    ok "$cltag (stack struct + static trampoline, one id per closure)"
}
cl_shape "$work/70_closure_basic.c" "p21-shape: 70" 3
cl_shape "$work/71_closure_nested_block.c" "p21-shape: 71" 3
cl_shape "$work/cl79/main.c" "p21-shape: 79 main" 1
cl_shape "$work/cl79/dep.c" "p21-shape: 79 dep" 1


# Phase 21 S5 probe 80: the debug mapping. `--line` anchors the struct and the
# trampoline at the literal's line; the closure-at comment appears either way.
if "$work/ct-ast" --line test/ast/80_closure_debug_line/main.ct -o "$work/cl80.c" \
        >"$work/cl80.out" 2>"$work/cl80.err" \
   && grep -Fq '/* closure at test/ast/80_closure_debug_line/main.ct:7 */' "$work/cl80.c" \
   && grep -Fq '#line 7 "test/ast/80_closure_debug_line/main.ct"' "$work/cl80.c"; then
    ok "p21-s5: the closure product carries a source anchor"
else
    bad "p21-s5: closure anchor" "$(cat "$work/cl80.err"; head -5 "$work/cl80.c")"
fi
rm -rf "$work/cl80n"
mkdir -p "$work/cl80n"
if "$work/ct-ast" build --emit-c --no-line test/ast/80_closure_debug_line/main.ct \
        -o "$work/cl80n" >"$work/cl80n.out" 2>"$work/cl80n.err" \
   && grep -Fq '/* closure at test/ast/80_closure_debug_line/main.ct:7 */' "$work/cl80n/main.c" \
   && ! grep -q '^#line ' "$work/cl80n/main.c"; then
    ok "p21-s5: --no-line drops the anchor but keeps the closure-at comment"
else
    bad "p21-s5: no-line closure anchor" "$(cat "$work/cl80n.err")"
fi

# P20-02: an import after the first declaration is rejected at the import line,
# with a message that names the fix. The generic loop above only checks for any
# positioned diagnostic; pin this text so it cannot drift into a parse error.
for cf in late_import_after_global late_import_after_fn; do
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "p20-02: $cf" "expected a non-zero exit"
    elif grep -qF "imports must be at the top of the file; move this import above the first declaration" "$work/$cf.err"; then
        ok "p20-02 ($cf)"
    else
        bad "p20-02: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 42: type-alias diagnostics that need no build tree. The message is
# pinned verbatim so a later refactor cannot drift it into a generic parse error.
for pair in \
    "ct|type_alias_plain|a type alias is only allowed in a .h.ct or .m.ct unit" \
    "h|type_alias_cycle|type alias cycle: 'B' -> 'A' -> 'B'" \
    "h|type_alias_use_before|type alias 'Text' must be declared before it is used" \
    "h|type_alias_conflict|type alias 'Thing' conflicts with an existing type" \
    "h|type_alias_duplicate|duplicate type alias 'Text'" \
    "h|type_alias_trait|type alias 'G' cannot name a trait"
do
    kind="${pair%%|*}"
    rest="${pair#*|}"
    cf="${rest%%|*}"
    cfmsg="${rest#*|}"
    if [ "$kind" = h ]; then cf="$cf.h"; fi
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 42: $cf" "expected a non-zero exit"
    elif grep -qF "$cfmsg" "$work/$cf.err"; then
        ok "batch 42 ($cf)"
    else
        bad "batch 42: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 4: `switch` and `do-while` carry diagnostics of their own, so a mistake
# never falls through to the expression path's "undeclared variable" report.
# Each fixture is also swept by the loop above; the message is pinned here.
for pair in \
    "case_outside_switch|a case label is only allowed inside a switch" \
    "case_after_decl|a declaration cannot follow a case label; wrap it in a block" \
    "case_no_statement|a case label needs a statement" \
    "case_nonconstant|a case label must be an integer constant" \
    "do_missing_while|a do statement must be followed by while (...)" \
    "own_in_switch|own is not supported inside a switch"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "control flow: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "control flow ($cf)"
    else
        bad "control flow: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 5: each enum / constant-expression / offsetof diagnostic is pinned
# verbatim. `case_nonconstant` is already covered above; the four below are new.
for pair in \
    "enum_duplicate|duplicate enum 'Color'" \
    "enum_bad_value|an enum value must be an integer constant" \
    "enum_no_name|expected an enum name" \
    "offsetof_bad_type|offsetof needs a struct type" \
    "offsetof_bad_field|struct 'S' has no field 'b'"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 5: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 5 ($cf)"
    else
        bad "batch 5: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 6: a union is a record without a vptr, so it gets its own three
# diagnostics (a second body, a `use` clause, an `offsetof` on a bad member).
for pair in \
    "union_duplicate|duplicate union 'Value'" \
    "union_use|a union cannot use a trait" \
    "offsetof_union_field|union 'Value' has no field 'd'"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 6: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 6 ($cf)"
    else
        bad "batch 6: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 7: labels are function-scoped, so the four goto diagnostics are judged
# without help from the C compiler (an undefined target, a duplicate, a
# declaration behind a label, and a label that guards nothing).
for pair in \
    "goto_undefined|label 'missing' is not defined" \
    "label_duplicate|duplicate label 'again'" \
    "label_decl|a declaration cannot follow a label; wrap it in a block" \
    "label_no_statement|a label needs a statement"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 7: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 7 ($cf)"
    else
        bad "batch 7: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 8: a bit-field width is an integer constant expression and the field
# itself has to be a plain integer, so four shapes are refused up front.
for pair in \
    "bitfield_nonconstant|a bit-field width must be an integer constant" \
    "bitfield_missing_width|expected a bit-field width" \
    "bitfield_array|a bit-field cannot be an array" \
    "bitfield_pointer|a bit-field must have an integer type"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 8: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 8 ($cf)"
    else
        bad "batch 8: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 9: an anonymous member promotes its names into the enclosing record, so
# the three rejected shapes are a named untagged member, a promoted name that
# collides, and a body with nothing to promote.
for pair in \
    "anon_member_name|an anonymous record member cannot have a name; tag the record instead" \
    "anon_member_dup|duplicate member 'i'" \
    "anon_member_empty|an anonymous record needs a member"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 9: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 9 ($cf)"
    else
        bad "batch 9: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 10: a static local outlives its scope, so it cannot be `own`, and the
# keyword has to introduce a declaration.
for pair in \
    "static_own|a static local cannot be 'own'" \
    "static_no_decl|expected a declaration after 'static'"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 10: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 10 ($cf)"
    else
        bad "batch 10: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 11: a compound literal builds an object, so a pointer type is refused.
for pair in \
    "compound_pointer|a compound literal needs an object type"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 11: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 11 ($cf)"
    else
        bad "batch 11: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 13: `...` needs a named parameter in front of it, and a vtable slot
# cannot be variadic.
for pair in \
    "variadic_no_named|'...' needs a named parameter before it" \
    "variadic_impl|a trait method cannot be variadic"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 13: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 13 ($cf)"
    else
        bad "batch 13: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 14: `inline` is a function specifier, so a variable behind it is refused.
for pair in \
    "inline_var|'inline' can only declare a function"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 14: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 14 ($cf)"
    else
        bad "batch 14: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 15: a floating literal is not an integer constant expression.
for pair in \
    "float_case|a case label must be an integer constant"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 15: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 15 ($cf)"
    else
        bad "batch 15: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 16: a case range checks both ends, so a variable in the high end is
# refused exactly like one in a single value.
for pair in \
    "case_range_nonconstant|a case label must be an integer constant"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 16: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 16 ($cf)"
    else
        bad "batch 16: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 17: a static assertion checks its two operands up front -- the condition
# must be constant and the message must be a string literal.
for pair in \
    "static_assert_nonconstant|a static assertion needs a constant condition" \
    "static_assert_msg|a static assertion message must be a string literal"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 17: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 17 ($cf)"
    else
        bad "batch 17: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 22: a variadic tail in a function-pointer declarator needs a named
# parameter in front of it; `void` is the empty list, so it does not count.
for pair in \
    "vararg_fnptr_no_named|a variadic function pointer needs a named parameter before '...'" \
    "vararg_fnptr_void|a variadic function pointer needs a named parameter before '...'"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 22: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 22 ($cf)"
    else
        bad "batch 22: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 28: an `own` variable is tracked by statement-level assignments, so a
# value-position assignment to one is refused by name.
for pair in \
    "assign_own_value|an 'own' variable can only be assigned in a statement"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 28: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 28 ($cf)"
    else
        bad "batch 28: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 29: each C11 form must be followed by its parenthesized list, and the
# alignment query takes a type name only (`sizeof`'s operand form is not C11).
for pair in \
    "alignas_no_paren|expected '(' after _Alignas" \
    "alignof_operand|_Alignof needs a type in parentheses" \
    "generic_no_paren|expected '(' after _Generic"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 29: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 29 ($cf)"
    else
        bad "batch 29: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 31: a GNU `__attribute__((…))` is captured verbatim and re-emitted; its
# list must close, and one declaration carries at most one captured group.
for pair in \
    "attribute_unterminated|unterminated __attribute__" \
    "attribute_duplicate|duplicate __attribute__ on one declaration"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 31: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 31 ($cf)"
    else
        bad "batch 31: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 32: an integer suffix is U at most once and L at most twice; any other
# run is refused with one message.
for cf in integer_suffix_lll integer_suffix_uu
do
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 32: $cf" "expected a non-zero exit"
    elif grep -q "an integer suffix may be U, L or LL" "$work/$cf.err"; then
        ok "batch 32 ($cf)"
    else
        bad "batch 32: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 33: the header-order forms. Each malformed shape has one message.
for pair in \
    "atomic_unterminated|unterminated _Atomic" \
    "attribute_misplaced|an attribute must prefix a declaration" \
    "attribute_duplicate_local|duplicate __attribute__ on one declaration" \
    "alignas_duplicate|duplicate _Alignas on one declaration"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 33: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 33 ($cf)"
    else
        bad "batch 33: $cf" "$(cat "$work/$cf.err")"
    fi
done

# Batch 37 pins the message text of the twelve negatives that only asserted a
# position, and covers the identifier-length guard (a name longer than the
# token buffer used to be truncated silently).
for pair in \
    "assign_target|assignment target is not assignable" \
    "bitops_assign_target|assignment target is not assignable" \
    "extern_function|an extern declaration cannot define a function" \
    "map_bad_arg|map argument 'free_name' is not allowed" \
    "map_bad_arity|map binding for 'm' takes 0 parameter(s), the trait declares 1" \
    "map_bad_method|'nope' is not a method of trait 'T'" \
    "map_dup|duplicate binding for method 'm'" \
    "map_unknown_arg|map argument 'missing' is not allowed" \
    "map_unknown_trait|map of an unknown trait" \
    "missing_semi|unexpected token" \
    "undeclared_var|use of an undeclared variable" \
    "unknown_trait|impl of an unknown trait" \
    "identifier_too_long|identifier is too long"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 37: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 37 ($cf)"
    else
        bad "batch 37: $cf" "$(cat "$work/$cf.err")"
    fi
done

# SH-8: a missing impl method must be reported the way L0/L2 report it, and no
# artifact may be left behind (a NULL vtable slot would crash at run time).
if "$work/ct-ast" test/ast/errors/null_vtable_slot.ct -o "$work/mmethod.c" \
        >"$work/mmethod.out" 2>"$work/mmethod.err"; then
    bad "impl completeness" "expected a non-zero exit"
elif grep -q "trait method 'b' is not implemented for struct 'P'" "$work/mmethod.err" \
        && [ ! -f "$work/mmethod.c" ]; then
    ok "impl (every trait method must be implemented)"
else
    bad "impl completeness" "$(cat "$work/mmethod.err")"
fi

# Batch 36 (trait default methods): a cycle among default bodies, an abstract
# method that only `use` leaves missing, and a default body that cannot expand
# for one struct are pinned verbatim. Each fixture is also swept by the
# test/ast/errors loop above.
for pair in \
    "default_cycle|trait 'T' has no non-default method to break the cycle" \
    "abstract_missing|trait method 'write' is not implemented for struct 'S'" \
    "default_bad_field|cannot be expanded for struct S: no field 'fd'"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "batch 36: $cf" "expected a non-zero exit"
    elif grep -q "$cfmsg" "$work/$cf.err"; then
        ok "batch 36 ($cf)"
    else
        bad "batch 36: $cf" "$(cat "$work/$cf.err")"
    fi
done

# SH-11: an rvalue receiver below the statement's expression root has no point to
# hoist to without reordering evaluation, so it is rejected. The position must be
# the node's own line (the lexer sits at EOF during emission), and the `.c` is
# opened before emission, so the failure must not leave a truncated artefact.
cat > "$work/hoist-mid.ct" <<'HOISTEOF'
#include <stdio.h>

trait G { int m(); }
struct P { int v; } use G;

impl G for P {
    int m() { return self->v; }
}

int gi = 0;

struct P mk(void)
{
    struct P p = { .v = 1 };
    return p;
}

int main(void)
{
    int x = 0;
    x = (gi++) + mk().m();
    printf("%d\n", x);
    return 0;
}
HOISTEOF
if "$work/ct-ast" "$work/hoist-mid.ct" -o "$work/hoist-mid.c" \
        >"$work/hoist-mid.out" 2>"$work/hoist-mid.err"; then
    bad "rvalue hoist" "expected a non-zero exit"
elif grep -q "hoist-mid.ct:21:1: error: a method call on a temporary" "$work/hoist-mid.err" \
        && [ ! -f "$work/hoist-mid.c" ]; then
    ok "rvalue hoist (mid-expression receiver rejected at its own line)"
else
    bad "rvalue hoist" "$(cat "$work/hoist-mid.err")"
fi

echo
echo "== output contract =="
# Only a `.h.ct` source publishes a header: a plain `.ct` input writes just the
# `.c`, and a header unit's `.c` never includes its own header (it is a
# standalone type artifact).
if "$work/ct-ast" compile test/ast/02_expr/prog.ct -o "$work/contract.c" \
        >"$work/contract.out" 2>"$work/contract.err" \
   && [ ! -f "$work/contract.h" ]; then
    ok "compile mode: a .ct input emits no header"
else
    bad "output contract" "a plain .ct input emitted a header: $(cat "$work/contract.err")"
fi
cp test/ast/02_expr/prog.ct "$work/contract.h.ct"
if "$work/ct-ast" compile "$work/contract.h.ct" -o "$work/contract2.c" \
        >"$work/contract2.out" 2>"$work/contract2.err" \
   && [ -f "$work/contract2.h" ] \
   && ! grep -q '^#include "contract2.h"' "$work/contract2.c"; then
    ok "compile mode: a .h.ct input emits a header the .c does not include"
else
    bad "output contract" "the .h.ct header is missing, or the .c includes it: $(cat "$work/contract2.err")"
fi

echo
echo "== CLI and identity (10.1) =="
# D44: `-v`/usage derive the program name from argv[0]; the `ct-ast` name stays
# for the development binary, while `ct` and `ctc` are the shipped names.
ln -sf "$work/ct-ast" "$work/ct"
ln -sf "$work/ct-ast" "$work/ctc"
devv="$("$work/ct-ast" -v 2>/dev/null)"
ctv="$("$work/ct" -v 2>/dev/null)"
ctcv="$("$work/ctc" -v 2>/dev/null)"
case "$devv" in
    "ct-ast v"*) ok "identity: the development binary prints 'ct-ast'" ;;
    *) bad "identity dev" "got '$devv'" ;;
esac
case "$ctv" in
    "ct v"*) ok "identity: a binary named 'ct' prints 'ct'" ;;
    *) bad "identity ct" "got '$ctv'" ;;
esac
case "$ctcv" in
    "ctc v"*) ok "identity: a binary named 'ctc' prints 'ctc'" ;;
    *) bad "identity ctc" "got '$ctcv'" ;;
esac

if "$work/ct-ast" --diagnostics=text test/ast/02_expr/prog.ct -o "$work/cli-diag.c" \
        >"$work/cli-diag.out" 2>"$work/cli-diag.err"; then
    ok "compile accepts --diagnostics=text"
else
    bad "--diagnostics=text" "$(cat "$work/cli-diag.err")"
fi
if "$work/ct-ast" --diagnostics=bogus test/ast/02_expr/prog.ct -o "$work/cli-diag2.c" \
        >"$work/cli-diag2.out" 2>"$work/cli-diag2.err"; then
    bad "--diagnostics=bogus" "expected a non-zero exit"
elif grep -q "unknown diagnostics format" "$work/cli-diag2.err"; then
    ok "--diagnostics=bogus is rejected"
else
    bad "--diagnostics=bogus" "wrong diagnostic: $(cat "$work/cli-diag2.err")"
fi

if "$work/ct-ast" -I /tmp test/ast/02_expr/prog.ct -o "$work/cli-i.c" \
        >"$work/cli-i.out" 2>"$work/cli-i.err" \
   && grep -Fq "ctc: warning: -I is ignored by compile mode; imports require 'ct build'" \
        "$work/cli-i.err"; then
    ok "compile accepts -I and says it is ignored (SH-54)"
else
    bad "compile -I" "exit/diagnostic: $(cat "$work/cli-i.err")"
fi

rm -rf "$work/cli-b"
mkdir -p "$work/cli-b"
if "$work/ct-ast" build --emit-c --std=gnu99 test/ast/11_map/prog.ct -o "$work/cli-b" \
        >"$work/cli-b.out" 2>"$work/cli-b.err" \
   && grep -q '^cc -std=gnu99 .* -o a.out$' "$work/cli-b.out"; then
    ok "build suggests the target C standard"
else
    bad "build --std=gnu99" "$(cat "$work/cli-b.err") $(cat "$work/cli-b.out")"
fi
if "$work/ct-ast" --std=c11 test/ast/02_expr/prog.ct -o "$work/cli-std.c" \
        >"$work/cli-std.out" 2>"$work/cli-std.err"; then
    bad "--std=c11" "expected a non-zero exit"
elif grep -q "unknown C standard" "$work/cli-std.err"; then
    ok "--std=c11 is rejected"
else
    bad "--std=c11" "wrong diagnostic: $(cat "$work/cli-std.err")"
fi

echo
echo "== capacity limits (generated) =="
# A fixed cap must fail loudly and never truncate. These fixtures are generated
# (a 4097-line file is not worth checking in) and each asserts the message.
cap_check() {
    cap_name="$1"
    cap_msg="$2"
    cap_file="$3"
    if "$work/ct-ast" "$cap_file" -o "$work/cap-$cap_name.c" \
            >"$work/cap-$cap_name.out" 2>"$work/cap-$cap_name.err"; then
        bad "cap $cap_name" "expected a non-zero exit"
    elif grep -q "$cap_msg" "$work/cap-$cap_name.err"; then
        ok "cap $cap_name"
    else
        bad "cap $cap_name" "$(cat "$work/cap-$cap_name.err")"
    fi
}
{
    printf 'int f(int a0'
    i=1
    while [ "$i" -lt 17 ]; do printf ', int a%d' "$i"; i=$((i + 1)); done
    printf ');\nint main(void) { return 0; }\n'
} >"$work/cap_params.ct"
cap_check params "too many parameters in unit 'cap_params.ct' (limit 16)" "$work/cap_params.ct"
{
    printf 'trait T {\n'
    i=0
    while [ "$i" -lt 65 ]; do printf '    int m%d();\n' "$i"; i=$((i + 1)); done
    printf '}\nint main(void) { return 0; }\n'
} >"$work/cap_methods.ct"
cap_check methods "too many trait methods" "$work/cap_methods.ct"
{
    i=0
    while [ "$i" -lt 256 ]; do printf 'int f%d(void) { return 0; }\n' "$i"; i=$((i + 1)); done
    printf 'int main(void) { return 0; }\n'
} >"$work/cap_funcs.ct"
cap_check funcs "too many functions in unit 'cap_funcs.ct' (limit 256)" "$work/cap_funcs.ct"
# The boundary itself: 255 helpers plus `main` is exactly the cap and must build,
# while one more is refused above.
{
    i=0
    while [ "$i" -lt 255 ]; do printf 'int f%d(void) { return 0; }\n' "$i"; i=$((i + 1)); done
    printf 'int main(void) { return 0; }\n'
} >"$work/cap_funcs_max.ct"
if "$work/ct-ast" "$work/cap_funcs_max.ct" -o "$work/cap-funcs-max.c" \
        >"$work/cap-funcs-max.out" 2>"$work/cap-funcs-max.err"; then
    ok "cap funcs (256 accepted)"
else
    bad "cap funcs (256 accepted)" "$(cat "$work/cap-funcs-max.err")"
fi
{
    printf 'int main(void)\n'
    i=0
    while [ "$i" -lt 257 ]; do printf '{'; i=$((i + 1)); done
    printf '\nreturn 0;\n'
    i=0
    while [ "$i" -lt 257 ]; do printf '}'; i=$((i + 1)); done
    printf '\n}\n'
} >"$work/cap_scopes.ct"
cap_check scopes "too many nested scopes" "$work/cap_scopes.ct"
{
    printf 'int main(void) {\n'
    i=0
    while [ "$i" -lt 4097 ]; do printf '    int v%d = 0;\n' "$i"; i=$((i + 1)); done
    printf '    return 0;\n}\n'
} >"$work/cap_vars.ct"
cap_check vars "too many variables in unit 'cap_vars.ct' (limit 4096)" "$work/cap_vars.ct"
{
    printf 'struct Big {\n'
    i=0
    while [ "$i" -lt 65 ]; do printf '    int f%d;\n' "$i"; i=$((i + 1)); done
    printf '};\nint main(void) { return 0; }\n'
} >"$work/cap_fields.ct"
cap_check fields "too many fields in struct 'Big' (limit 64)" "$work/cap_fields.ct"
{
    i=0
    while [ "$i" -lt 129 ]; do printf 'struct S%d { int x; };\n' "$i"; i=$((i + 1)); done
    printf 'int main(void) { return 0; }\n'
} >"$work/cap_structs.ct"
cap_check structs "too many structs in unit 'cap_structs.ct' (limit 128)" "$work/cap_structs.ct"
# R09: the closure table and the nesting stack now fail hard instead of silently
# dropping the binding or pretending the literal is a plain call.
{
    printf 'int main(void)\n{\n    int n = 1;\n'
    i=0
    while [ "$i" -lt 65 ]; do
        printf '    int (*c%d)(int) = (int x) => x + n;\n' "$i"
        i=$((i + 1))
    done
    printf '    return c0(0);\n}\n'
} >"$work/cap_closures.ct"
cap_check closures "too many closures in unit 'cap_closures.ct' (limit 64)" "$work/cap_closures.ct"
{
    printf 'int main(void)\n{\n    int n = 1;\n'
    i=0
    while [ "$i" -lt 16 ]; do
        printf '    int (*c%d)(int) = (int x) => {\n' "$i"
        i=$((i + 1))
    done
    printf '    int (*c16)(int) = (int x) => x + n;\n'
    i=15
    while [ "$i" -ge 0 ]; do
        printf '    };\n'
        i=$((i - 1))
    done
    printf '    return 0;\n}\n'
} >"$work/cap_closure_nest.ct"
cap_check closure_nest "a closure is nested too deeply (limit 16)" "$work/cap_closure_nest.ct"

# A struct whose body opens on the line after its name makes the parser look
# ahead across a newline. The lookahead has to restore the lexer's line state
# with the cursor, or every later diagnostic in the file shifts by one; the
# duplicate member on line 4 is the witness.
{
    printf 'struct Foo\n{\n    int a;\n    int a;\n};\nint main(void) { return 0; }\n'
} >"$work/lahead.ct"
if "$work/ct-ast" "$work/lahead.ct" -o "$work/lahead.c" \
        >"$work/lahead.out" 2>"$work/lahead.err"; then
    bad "struct lookahead line" "expected a non-zero exit"
elif grep -q ":4:1: error: duplicate member 'a'" "$work/lahead.err"; then
    ok "struct lookahead restores the line state"
else
    bad "struct lookahead line" "wrong line: $(cat "$work/lahead.err")"
fi

# The remaining driver branches (Phase 9 review §3.2-1): help, missing
# option arguments, unknown options, an unreadable input, an unwritable
# output, `import` in compile mode and a build without `-o`.
if "$work/ct-ast" -h >"$work/cli-h.out" 2>"$work/cli-h.err" \
   && grep -q '^usage: ' "$work/cli-h.out" \
   && grep -q ' get <' "$work/cli-h.out" \
   && grep -q ' install$' "$work/cli-h.out"; then
    ok "-h lists usage and the get/install subcommands"
else
    bad "-h" "$(cat "$work/cli-h.out") $(cat "$work/cli-h.err")"
fi
if "$work/ct-ast" >"$work/cli-none.out" 2>"$work/cli-none.err"; then
    bad "compile with no input" "expected a non-zero exit"
elif grep -q '^usage: ' "$work/cli-none.err"; then
    ok "compile with no input prints usage"
else
    bad "compile with no input" "wrong diagnostic: $(cat "$work/cli-none.err")"
fi
if "$work/ct-ast" test/ast/02_expr/prog.ct test/ast/02_expr/prog.ct \
        -o "$work/cli-two.c" >"$work/cli-two.out" 2>"$work/cli-two.err"; then
    bad "compile with two inputs" "expected a non-zero exit"
elif grep -q "compile mode takes one input" "$work/cli-two.err"; then
    ok "compile mode refuses a second input"
else
    bad "compile with two inputs" "wrong diagnostic: $(cat "$work/cli-two.err")"
fi
if "$work/ct-ast" -o >"$work/cli-o.out" 2>"$work/cli-o.err"; then
    bad "-o needs an argument" "expected a non-zero exit"
elif grep -q -- "-o needs an argument" "$work/cli-o.err"; then
    ok "-o without an argument is rejected"
else
    bad "-o needs an argument" "wrong diagnostic: $(cat "$work/cli-o.err")"
fi
if "$work/ct-ast" -I >"$work/cli-iarg.out" 2>"$work/cli-iarg.err"; then
    bad "-I needs an argument" "expected a non-zero exit"
elif grep -q -- "-I needs an argument" "$work/cli-iarg.err"; then
    ok "-I without an argument is rejected"
else
    bad "-I needs an argument" "wrong diagnostic: $(cat "$work/cli-iarg.err")"
fi
if "$work/ct-ast" build --emit-c test/ast/02_expr/prog.ct --ns-root \
        >"$work/cli-ns.out" 2>"$work/cli-ns.err"; then
    bad "--ns-root needs an argument" "expected a non-zero exit"
elif grep -q -- "--ns-root needs an argument" "$work/cli-ns.err"; then
    ok "build: --ns-root without an argument is rejected"
else
    bad "--ns-root needs an argument" "wrong diagnostic: $(cat "$work/cli-ns.err")"
fi
if "$work/ct-ast" --bogus test/ast/02_expr/prog.ct -o "$work/cli-u.c" \
        >"$work/cli-u.out" 2>"$work/cli-u.err"; then
    bad "unknown option" "expected a non-zero exit"
elif grep -q "unknown option '--bogus'" "$work/cli-u.err"; then
    ok "an unknown option is rejected"
else
    bad "unknown option" "wrong diagnostic: $(cat "$work/cli-u.err")"
fi
if "$work/ct-ast" "$work/no-such.ct" -o "$work/cli-co.c" \
        >"$work/cli-co.out" 2>"$work/cli-co.err"; then
    bad "cannot open input" "expected a non-zero exit"
elif grep -q "cannot open the input file" "$work/cli-co.err"; then
    ok "an unreadable input is reported"
else
    bad "cannot open input" "wrong diagnostic: $(cat "$work/cli-co.err")"
fi
if "$work/ct-ast" test/ast/02_expr/prog.ct -o "$work" \
        >"$work/cli-cw.out" 2>"$work/cli-cw.err"; then
    bad "cannot write output" "expected a non-zero exit"
elif grep -q "cannot write" "$work/cli-cw.err"; then
    ok "an unwritable output is reported"
else
    bad "cannot write output" "wrong diagnostic: $(cat "$work/cli-cw.err")"
fi
if "$work/ct-ast" test/modules/inc/main.ct -o "$work/cli-im.c" \
        >"$work/cli-im.out" 2>"$work/cli-im.err"; then
    bad "import in compile mode" "expected a non-zero exit"
elif grep -Fq "'import' requires multi-file mode: use 'ct build'" "$work/cli-im.err" \
        && ! grep -Fq "ct check is single-unit" "$work/cli-im.err"; then
    ok "compile mode rejects 'import' and names the way out (SH-55)"
else
    bad "import in compile mode" "wrong diagnostic: $(cat "$work/cli-im.err")"
fi
if "$work/ct-ast" build --emit-c test/modules/split/main.ct \
        >"$work/cli-bo.out" 2>"$work/cli-bo.err"; then
    bad "build without -o" "expected a non-zero exit"
elif grep -q "build needs -o" "$work/cli-bo.err"; then
    ok "build without -o is rejected"
else
    bad "build without -o" "wrong diagnostic: $(cat "$work/cli-bo.err")"
fi
if "$work/ct-ast" build --emit-c -o >"$work/cli-boa.out" 2>"$work/cli-boa.err"; then
    bad "build: -o needs an argument" "expected a non-zero exit"
elif grep -q -- "-o needs an argument" "$work/cli-boa.err"; then
    ok "build: -o without an argument is rejected"
else
    bad "build: -o needs an argument" "wrong diagnostic: $(cat "$work/cli-boa.err")"
fi
if "$work/ct-ast" build --emit-c -I >"$work/cli-bia.out" 2>"$work/cli-bia.err"; then
    bad "build: -I needs an argument" "expected a non-zero exit"
elif grep -q -- "-I needs an argument" "$work/cli-bia.err"; then
    ok "build: -I without an argument is rejected"
else
    bad "build: -I needs an argument" "wrong diagnostic: $(cat "$work/cli-bia.err")"
fi
if "$work/ct-ast" build --emit-c --std=c11 test/ast/02_expr/prog.ct -o "$work/cli-bdir" \
        >"$work/cli-bstd.out" 2>"$work/cli-bstd.err"; then
    bad "build: --std=c11" "expected a non-zero exit"
elif grep -q "unknown C standard 'c11'" "$work/cli-bstd.err"; then
    ok "build: an unknown --std is rejected"
else
    bad "build: --std=c11" "wrong diagnostic: $(cat "$work/cli-bstd.err")"
fi
if "$work/ct-ast" build --emit-c --bogus test/ast/02_expr/prog.ct -o "$work/cli-bdir" \
        >"$work/cli-bu.out" 2>"$work/cli-bu.err"; then
    bad "build: unknown option" "expected a non-zero exit"
elif grep -q "unknown option '--bogus'" "$work/cli-bu.err"; then
    ok "build: an unknown option is rejected"
else
    bad "build: unknown option" "wrong diagnostic: $(cat "$work/cli-bu.err")"
fi
mkdir -p "$work/cli-bdir"
if "$work/ct-ast" build --emit-c -o "$work/cli-bdir" >"$work/cli-bnone.out" 2>"$work/cli-bnone.err"; then
    bad "build: no input" "expected a non-zero exit"
elif grep -q "usage: .* build " "$work/cli-bnone.err"; then
    ok "build: no input prints usage"
else
    bad "build: no input" "wrong diagnostic: $(cat "$work/cli-bnone.err")"
fi
bargs="-I /tmp"
i=0
while [ "$i" -lt 17 ]; do bargs="$bargs -I /tmp"; i=$((i + 1)); done
if "$work/ct-ast" build --emit-c $bargs test/ast/02_expr/prog.ct -o "$work/cli-bdir" \
        >"$work/cli-binc.out" 2>"$work/cli-binc.err"; then
    bad "build: 17 -I roots" "expected a non-zero exit"
elif grep -q "too many -I roots" "$work/cli-binc.err"; then
    ok "build: the 17th -I root is rejected"
else
    bad "build: 17 -I roots" "wrong diagnostic: $(cat "$work/cli-binc.err")"
fi
bargs=""
i=0
while [ "$i" -lt 65 ]; do bargs="$bargs test/ast/02_expr/prog.ct"; i=$((i + 1)); done
if "$work/ct-ast" build --emit-c $bargs -o "$work/cli-bdir" \
        >"$work/cli-bin.out" 2>"$work/cli-bin.err"; then
    bad "build: 65 inputs" "expected a non-zero exit"
elif grep -q "too many inputs" "$work/cli-bin.err"; then
    ok "build: too many inputs is rejected"
else
    bad "build: 65 inputs" "wrong diagnostic: $(cat "$work/cli-bin.err")"
fi

echo
echo "== one-step build (17.6) =="
# The default form emits the C into .ctbuild/ (or --outdir) and then runs the
# local cc; --emit-c keeps the old emit-only shape and must not spawn a compiler.
rm -rf "$work/cli-one"
mkdir -p "$work/cli-one"
if ( cd "$work/cli-one" && "$work/ct-ast" build "$root/test/ast/02_expr/prog.ct" -o prog ) \
        >"$work/cli-one.out" 2>"$work/cli-one.err" \
   && [ -f "$work/cli-one/.ctbuild/prog.c" ] && [ -x "$work/cli-one/prog" ] \
   && grep -q "prog.c" "$work/cli-one.out" \
   && "$work/cli-one/prog" >"$work/cli-one.stdout" 2>&1 \
   && cmp -s "$work/cli-one.stdout" test/ast/02_expr/prog.expected.out; then
    ok "build: the default form emits C into .ctbuild/ and produces a runnable binary"
else
    bad "build one-step" "$(cat "$work/cli-one.err" "$work/cli-one.stdout" 2>/dev/null)"
fi

rm -rf "$work/cli-oneout"
mkdir -p "$work/cli-oneout"
if ( cd "$work/cli-oneout" && "$work/ct-ast" build "$root/test/ast/02_expr/prog.ct" \
        --outdir gen -o prog ) >"$work/cli-oneout.out" 2>"$work/cli-oneout.err" \
   && [ -f "$work/cli-oneout/gen/prog.c" ] && [ -x "$work/cli-oneout/prog" ] \
   && "$work/cli-oneout/prog" >"$work/cli-oneout.stdout" 2>&1 \
   && cmp -s "$work/cli-oneout.stdout" test/ast/02_expr/prog.expected.out; then
    ok "build: --outdir keeps the C, -o names the binary"
else
    bad "build --outdir" "$(cat "$work/cli-oneout.err" "$work/cli-oneout.stdout" 2>/dev/null)"
fi

# CC pointing at a script that fails and leaves a marker: --emit-c must never
# call it, so a marker means the old contract (zero subprocesses) broke.
printf '#!/bin/sh\n: >"${FAKE_CC_MARK}"\nexit 1\n' >"$work/cli-fakecc"
chmod +x "$work/cli-fakecc"
rm -rf "$work/cli-emitc"
mkdir -p "$work/cli-emitc"
if CC="$work/cli-fakecc" FAKE_CC_MARK="$work/cli-emitc/mark" \
   "$work/ct-ast" build --emit-c test/ast/02_expr/prog.ct -o "$work/cli-emitc" \
        >"$work/cli-emitc.out" 2>"$work/cli-emitc.err" \
   && [ ! -e "$work/cli-emitc/mark" ] && [ -f "$work/cli-emitc/prog.c" ] \
   && grep -q '^cc -std=c99 .* -o a.out$' "$work/cli-emitc.out"; then
    ok "--emit-c emits only C and never invokes the compiler"
else
    bad "--emit-c no cc" "$(cat "$work/cli-emitc.err" "$work/cli-emitc.out")"
fi

rm -rf "$work/cli-badcc"
mkdir -p "$work/cli-badcc"
if ( cd "$work/cli-badcc" && "$work/ct-ast" build "$root/test/ast/02_expr/prog.ct" \
        -o prog --cc /nope/cc ) >"$work/cli-badcc.out" 2>"$work/cli-badcc.err"; then
    bad "build --cc missing" "expected a non-zero exit"
elif grep -q "cannot run '/nope/cc'" "$work/cli-badcc.err"; then
    ok "build: an unusable --cc is reported as 'cannot run'"
else
    bad "build --cc missing" "wrong diagnostic: $(cat "$work/cli-badcc.err")"
fi

# --cflags / --ldflags are pass-through: they land on the composed line, and a
# program that needs the math library still links.
{
    printf '#include <math.h>\n#include <stdio.h>\n\nint main(void)\n{\n'
    printf '    printf("%%.0f\\n", sqrt(4.0));\n    return 0;\n}\n'
} >"$work/cli-sqrt.ct"
rm -rf "$work/cli-flags"
mkdir -p "$work/cli-flags"
if ( cd "$work/cli-flags" && "$work/ct-ast" build "$work/cli-sqrt.ct" -o prog \
        --cflags "-O2 -Wall" --ldflags "-lm" ) >"$work/cli-flags.out" 2>"$work/cli-flags.err" \
   && grep -q -- "-O2 -Wall" "$work/cli-flags.out" \
   && grep -q -- "-lm" "$work/cli-flags.out" \
   && "$work/cli-flags/prog" >"$work/cli-flags.stdout" 2>&1 \
   && [ "$(cat "$work/cli-flags.stdout")" = "2" ]; then
    ok "build: --cflags / --ldflags pass through to the compiler"
else
    bad "build --cflags/--ldflags" "$(cat "$work/cli-flags.err" "$work/cli-flags.stdout" 2>/dev/null)"
fi

echo
echo "== semantic diagnostics (10.2) =="
# The module fixtures are staged like check-archive does: the compiler runs on
# `prog.ct` in a scratch directory, so the recorded path matches the goldens.
sem="$work/sem"
for c in dup_struct dup_trait; do
    rm -rf "$sem-$c"
    mkdir -p "$sem-$c"
    cp "test/modules/$c/prog.ct" "$sem-$c/"
    if ( cd "$sem-$c" && "$work/ct-ast" prog.ct -o prog.c ) >"$sem-$c.out" 2>"$sem-$c.err"; then
        bad "$c" "expected a non-zero exit"
    elif ! cmp -s "$sem-$c.err" "test/modules/$c/expected.stderr"; then
        bad "$c" "stderr differs from expected.stderr: $(cat "$sem-$c.err")"
    elif [ -f "$sem-$c/prog.c" ] || [ -f "$sem-$c/prog.h" ]; then
        bad "$c" "artifacts survived a failed compile"
    else
        ok "$c (L2-identical diagnostic, no artifacts)"
    fi
done

rm -rf "$sem-sig"
mkdir -p "$sem-sig"
cp test/modules/sig_mismatch/prog.ct "$sem-sig/"
if ( cd "$sem-sig" && "$work/ct-ast" prog.ct -o prog.c ) >"$sem-sig.out" 2>"$sem-sig.err" \
   && cmp -s "$sem-sig.err" test/modules/sig_mismatch/expected.stderr \
   && "$CC" "$sem-sig/prog.c" -o "$sem-sig.bin" 2>"$sem-sig.cc" \
   && "$sem-sig.bin" >"$sem-sig.stdout" 2>&1 \
   && cmp -s "$sem-sig.stdout" test/modules/sig_mismatch/expected.out; then
    ok "sig_mismatch (warning matches L2, the program runs)"
else
    bad "sig_mismatch" "$(cat "$sem-sig.err" "$sem-sig.stdout" 2>/dev/null)"
fi

rm -rf "$sem-json"
mkdir -p "$sem-json"
cp test/modules/sig_mismatch_json/prog.ct "$sem-json/"
if ( cd "$sem-json" && "$work/ct-ast" --diagnostics=json prog.ct -o prog.c ) \
        >"$sem-json.out" 2>"$sem-json.err" \
   && cmp -s "$sem-json.out" test/modules/sig_mismatch_json/expected.stdout; then
    ok "sig_mismatch_json (JSON document matches L2)"
else
    bad "sig_mismatch_json" "stdout differs: $(cat "$sem-json.out")"
fi

echo
echo "== call-site arity (19.1) =="
# A resolved signature owns the argument count: a function call and a trait
# method call are compared, while a function-pointer call, a C library name,
# a `map` recipe and a static type host stay unknown and pass. A mismatch is a
# warning in compile mode (D19-4 keeps `ct compile` / `ct build` exit codes
# unchanged); `ct check` (19.4) raises the same record to an error.
cat > "$work/arity_fn.ct" <<'AFEOF'
int add(int a, int b) { return a + b; }

int main(void)
{
    return add(1);
}
AFEOF
if "$work/ct-ast" "$work/arity_fn.ct" -o "$work/arity_fn.c" \
        >"$work/arity_fn.out" 2>"$work/arity_fn.err" \
   && grep -q "warning: arity mismatch: 'add' takes 2 argument(s), 1 given" "$work/arity_fn.err"; then
    ok "arity: a function call with a missing argument warns"
else
    bad "arity: function call" "$(cat "$work/arity_fn.err")"
fi

cat > "$work/arity_m.ct" <<'AMEOF'
trait Shape {
    int area(int scale);
}

struct Sq { int side; } use Shape;

impl Shape for Sq {
    int area(int scale) { return self->side * scale; }
}

int main(void)
{
    struct Sq s;
    s.side = 2;
    return s.area();
}
AMEOF
if "$work/ct-ast" "$work/arity_m.ct" -o "$work/arity_m.c" \
        >"$work/arity_m.out" 2>"$work/arity_m.err" \
   && grep -q "warning: arity mismatch: 'area' takes 1 argument(s), 0 given" "$work/arity_m.err"; then
    ok "arity: a trait method call with a missing argument warns"
else
    bad "arity: trait method" "$(cat "$work/arity_m.err")"
fi

cat > "$work/arity_ok.ct" <<'AKEOF'
int add(int a, int b) { return a + b; }
int total(int n, ...) { return n; }

int main(void)
{
    int (*p)(int, int) = add;
    return add(1, 2) + total(1, 2, 3) + p(4, 5);
}
AKEOF
if "$work/ct-ast" "$work/arity_ok.ct" -o "$work/arity_ok.c" \
        >"$work/arity_ok.out" 2>"$work/arity_ok.err" \
   && [ ! -s "$work/arity_ok.err" ]; then
    ok "arity: an exact call, a variadic tail and a function pointer stay quiet"
else
    bad "arity: known-good calls" "$(cat "$work/arity_ok.err")"
fi

echo
echo "== argument types (19.2) =="
# Coarse compatibility against the resolved signature: a struct pointer whose
# tag provably differs is reported, while numeric conversions, qualifiers,
# `void *`, arrays (decay), casts, string literals and interface formals all
# stay unknown and pass. Warning severity like 19.1 (D19-4).
cat > "$work/atype_fn.ct" <<'TFEOF'
struct P { int x; }
struct Q { int y; }
void setp(struct P *p) { p->x = 1; }

int main(void)
{
    struct Q q;
    setp(&q);
    return 0;
}
TFEOF
if "$work/ct-ast" "$work/atype_fn.ct" -o "$work/atype_fn.c" \
        >"$work/atype_fn.out" 2>"$work/atype_fn.err" \
   && grep -q "warning: type mismatch: 'setp' argument 1: expected 'struct P \*', got 'struct Q \*'" "$work/atype_fn.err"; then
    ok "argtype: a function call with a wrong struct pointer warns"
else
    bad "argtype: function call" "$(cat "$work/atype_fn.err")"
fi

cat > "$work/atype_m.ct" <<'TMEOF'
struct P { int x; }
struct Q { int y; }
trait Sink { void put(struct P *p); }
struct S { int v; } use Sink;
impl Sink for S { void put(struct P *p) { p->x = self->v; } }

int main(void)
{
    struct S s;
    struct Q q;
    s.put(&q);
    return 0;
}
TMEOF
if "$work/ct-ast" "$work/atype_m.ct" -o "$work/atype_m.c" \
        >"$work/atype_m.out" 2>"$work/atype_m.err" \
   && grep -q "warning: type mismatch: 'put' argument 1: expected 'struct P \*', got 'struct Q \*'" "$work/atype_m.err"; then
    ok "argtype: a trait method call with a wrong struct pointer warns"
else
    bad "argtype: trait method" "$(cat "$work/atype_m.err")"
fi

cat > "$work/atype_ok.ct" <<'TOEOF'
struct P { int x; }
trait Shape { int area(int scale); }
struct Sq { int side; } use Shape;
impl Shape for Sq { int area(int scale) { return self->side * scale; } }
void setp(struct P *p) { p->x = 1; }
void setl(long n) { (void)n; }
void setc(const char *s) { (void)s; }
void setv(void *p) { (void)p; }
int show(struct Shape_iface *s) { return s->area(2); }

int main(void)
{
    struct P p;
    struct Sq sq;
    char buf[8];
    char *s;
    int i;
    s = buf;
    i = 2;
    sq.side = 1;
    setp(&p);
    setl(i);
    setc(s);
    setc(buf);
    setc("lit");
    setv(s);
    setv(&p);
    setl((long)i);
    return show(&sq);
}
TOEOF
if "$work/ct-ast" "$work/atype_ok.ct" -o "$work/atype_ok.c" \
        >"$work/atype_ok.out" 2>"$work/atype_ok.err" \
   && [ ! -s "$work/atype_ok.err" ]; then
    ok "argtype: conversions, void *, arrays, casts, literals and interface formals stay quiet"
else
    bad "argtype: known-good calls" "$(cat "$work/atype_ok.err")"
fi

echo
echo "== trait-method ambiguity and cross-unit signatures (19.3) =="
# SH-46: a bare call two traits of the receiver both declare keeps the first
# match in `use` order (the spec pins that resolution) and now names both
# traits in a warning. A method only one trait declares and a call through an
# interface variable are unambiguous and stay quiet. Warning severity (D19-4).
cat > "$work/amb.ct" <<'AMBEOF'
trait A { void f(); }
trait B { void f(); }
struct S { int n; } use A, B;
impl A for S { void f() {} }
impl B for S { void f() {} }

int main(void)
{
    struct S s;
    s.n = 1;
    s.f();
    return 0;
}
AMBEOF
if "$work/ct-ast" "$work/amb.ct" -o "$work/amb.c" \
        >"$work/amb.out" 2>"$work/amb.err" \
   && grep -q "warning: ambiguous method: 'f' declared by 'A' and 'B'; 'A' is used" "$work/amb.err"; then
    ok "ambiguity: a bare call two traits declare warns and names both"
else
    bad "ambiguity: two-trait bare call" "$(cat "$work/amb.err")"
fi

cat > "$work/amb_ok.ct" <<'AOEOF'
trait A { void f(); void only_a(); }
trait B { void f(); void only_b(); }
struct S { int n; } use A, B;
impl A for S { void f() {} void only_a() {} }
impl B for S { void f() {} void only_b() {} }
int show(struct A_iface *a) { a->f(); return 0; }

int main(void)
{
    struct S s;
    s.n = 1;
    s.only_a();
    s.only_b();
    return show(&s);
}
AOEOF
if "$work/ct-ast" "$work/amb_ok.ct" -o "$work/amb_ok.c" \
        >"$work/amb_ok.out" 2>"$work/amb_ok.err" \
   && [ ! -s "$work/amb_ok.err" ]; then
    ok "ambiguity: single-trait methods and interface dispatch stay quiet"
else
    bad "ambiguity: known-good calls" "$(cat "$work/amb_ok.err")"
fi

# Cross-unit signature drift: an imported unit's exported trait signature is
# checked against the local impl beyond the return type and the parameter
# count -- the parameter types themselves, with the coarse 19.2 rules. The
# mismatch here is one cc would reject on the vtable initialiser; the matching
# impl stays quiet.
mkdir -p "$work/xu"
cat > "$work/xu/W.h.ct" <<'XWEOF'
namespace xu;
pub trait W { int put(int v); }
XWEOF
# the entry sits outside the namespace directory: the namespace check anchors
# at the entry's root, and $work/xu must stay the namespace's own directory
cat > "$work/xu_main.ct" <<'XMEOF'
import xu::W;
struct P { int n; } use W;
impl W for P { int put(struct P *v) { (void)v; return 0; } }

int main(void)
{
    struct P p;
    p.n = 1;
    return p.put(1);
}
XMEOF
mkdir -p "$work/xu-out"
if "$work/ct-ast" build --emit-c -I "$work" "$work/xu_main.ct" -o "$work/xu-out" \
        >"$work/xu.out" 2>"$work/xu.err"; then
    bad "cross-unit: impl drift" "expected a hard error; got success"
elif grep -q "error: signature mismatch: 'put' in impl of 'xu_W' for 'P': parameter 1 type 'struct P \*' does not match the trait's 'int'" "$work/xu.err"; then
    ok "cross-unit: a local impl drifting from an imported trait's parameter type is a hard error"
else
    bad "cross-unit: impl drift" "$(cat "$work/xu.err")"
fi

cat > "$work/xu_main.ct" <<'XOEOF'
import xu::W;
struct P { int n; } use W;
impl W for P { int put(int v) { return v + self->n; } }

int main(void)
{
    struct P p;
    p.n = 1;
    return p.put(1);
}
XOEOF
rm -rf "$work/xu-out"
mkdir -p "$work/xu-out"
if "$work/ct-ast" build --emit-c -I "$work" "$work/xu_main.ct" -o "$work/xu-out" \
        >"$work/xu_ok.out" 2>"$work/xu_ok.err" \
   && [ ! -s "$work/xu_ok.err" ]; then
    ok "cross-unit: a matching impl of an imported trait stays quiet"
else
    bad "cross-unit: known-good impl" "$(cat "$work/xu_ok.err")"
fi

echo
echo "== memory: auto-drop and leak warnings (10.3) =="
# AutoDrop releases every `own` object at its scope exit, in reverse order; the
# three negative fixtures pin the layout / Drop / scope diagnostics. Every
# warning is byte-diffed against L2's, since D39 keeps diagnostics identical.
mem="$work/mem"
for c in autodrop autodrop_layout autodrop_nodrop autodrop_scope; do
    rm -rf "$mem-$c"
    mkdir -p "$mem-$c"
    cp "test/modules/$c/prog.ct" "$mem-$c/"
    args=$(cat "test/modules/$c/compile.args")
    if ( cd "$mem-$c" && "$work/ct-ast" $args ) \
            >"$mem-$c.out" 2>"$mem-$c.err"; then
        if [ -f "test/modules/$c/expected.err" ]; then
            bad "$c" "expected a non-zero exit"
        elif "$CC" -Wall -Wextra -std=c99 "$mem-$c/prog.c" -o "$mem-$c.bin" \
                2>"$mem-$c.cc" \
             && "$mem-$c.bin" >"$mem-$c.stdout" 2>&1 \
             && cmp -s "$mem-$c.stdout" "test/modules/$c/expected.out"; then
            ok "$c (auto-drop releases at scope exit)"
        else
            bad "$c" "$(cat "$mem-$c.cc" "$mem-$c.stdout" 2>/dev/null | head -5)"
        fi
    elif [ -f "test/modules/$c/expected.err" ] \
         && cmp -s "$mem-$c.err" "test/modules/$c/expected.err"; then
        ok "$c (L2-identical diagnostic)"
    else
        bad "$c" "unexpected result: $(cat "$mem-$c.err")"
    fi
done

# SH-33: an `own` object is released on the `return` path, before the value
# leaves. In the 61 fixture every return in `pick` / `pick2` is directly
# preceded by its release, and the pointer is nulled afterwards; a release
# emitted after the return (the defect) fails the first check, because the
# preceding line is then no longer the release.
"$work/ct-ast" test/ast/61_autodrop_return/prog.ct -o "$work/sh33.c" \
    >"$work/sh33.out" 2>"$work/sh33.err"
if [ $? -ne 0 ]; then
    bad "sh33" "ct-ast failed: $(cat "$work/sh33.err")"
else
    for fn in pick pick2; do
        # the definition, not the prototype: the prototype line ends with `;`
        awk -v fn="$fn" '
            !inb && $0 ~ ("^int " fn "\\(") && index($0, "{") { inb = 1 }
            inb { print }
            inb && /^}/ { exit }
        ' "$work/sh33.c" >"$work/sh33-$fn.body"
        if [ ! -s "$work/sh33-$fn.body" ]; then
            bad "sh33 $fn" "could not extract the function body"
        elif ! awk 'prev !~ /Box_Drop_drop/ && /^ *return/ { bad = 1 } { prev = $0 } END { exit bad }' \
                "$work/sh33-$fn.body"; then
            bad "sh33 $fn" "a return is not preceded by its release"
        elif ! grep -q 'b = 0;' "$work/sh33-$fn.body"; then
            bad "sh33 $fn" "the release does not null the pointer"
        else
            ok "sh33 $fn (release runs before the return, then nulls)"
        fi
    done
fi

for c in leak leak_path leak_call leak_method; do
    rm -rf "$mem-$c"
    mkdir -p "$mem-$c"
    cp "test/modules/$c/prog.ct" "$mem-$c/"
    args=$(cat "test/modules/$c/compile.args")
    if ( cd "$mem-$c" && "$work/ct-ast" $args ) \
            >"$mem-$c.out" 2>"$mem-$c.err" \
       && cmp -s "$mem-$c.err" "test/modules/$c/expected.stderr" \
       && "$CC" -Wall -Wextra -std=c99 "$mem-$c/prog.c" -o "$mem-$c.bin" \
            2>"$mem-$c.cc" \
       && "$mem-$c.bin" >"$mem-$c.stdout" 2>&1 \
       && cmp -s "$mem-$c.stdout" "test/modules/$c/expected.out"; then
        ok "$c (leak warning matches L2, the program runs)"
    else
        bad "$c" "$(cat "$mem-$c.err" "$mem-$c.cc" 2>/dev/null | head -5)"
    fi
done

for c in leak_json leak_path_json; do
    rm -rf "$mem-$c"
    mkdir -p "$mem-$c"
    cp "test/modules/$c/prog.ct" "$mem-$c/"
    args=$(cat "test/modules/$c/compile.args")
    if ( cd "$mem-$c" && "$work/ct-ast" $args ) \
            >"$mem-$c.out" 2>"$mem-$c.err" \
       && cmp -s "$mem-$c.out" "test/modules/$c/expected.stdout"; then
        ok "$c (JSON leak document matches L2)"
    else
        bad "$c" "stdout differs: $(cat "$mem-$c.out")"
    fi
done

# build mode: the JSON document goes to stderr (stdout carries the cc hint) and
# the recorded path is the one given on the command line.
rm -rf "$mem-leak_build"
mkdir -p "$mem-leak_build"
if "$work/ct-ast" build --emit-c --diagnostics=json test/modules/leak_build/prog.ct \
        -o "$mem-leak_build" >"$mem-leak_build.out" 2>"$mem-leak_build.err" \
   && cmp -s "$mem-leak_build.err" test/modules/leak_build/expected.stderr \
   && "$CC" -Wall -Wextra -std=c99 "$mem-leak_build/prog.c" \
        -o "$mem-leak_build.bin" 2>"$mem-leak_build.cc" \
   && "$mem-leak_build.bin" >"$mem-leak_build.stdout" 2>&1 \
   && cmp -s "$mem-leak_build.stdout" test/modules/leak_build/expected.out; then
    ok "leak_build (build-mode JSON on stderr, the program runs)"
else
    bad "leak_build" "$(cat "$mem-leak_build.err" "$mem-leak_build.cc" 2>/dev/null | head -5)"
fi

echo
echo "== borrow parameter annotations (stage one) =="
# A `borrow` annotation is a lifetime hint, not a code-generation switch: the
# same function compiled with and without it must produce the same C text.
# The banner names the input path, so it is dropped before the comparison.
rm -rf "$work/bw-a" "$work/bw-b"
mkdir -p "$work/bw-a" "$work/bw-b"
cat > "$work/bw-a/prog.ct" <<'BWEOF'
#include <stdio.h>

struct Req { int n; };

void render(struct Req *r)
{
    printf("%d\n", r->n);
}

int main(void)
{
    struct Req q;
    q.n = 7;
    render(&q);
    return 0;
}
BWEOF
cat > "$work/bw-b/prog.ct" <<'BWEOF'
#include <stdio.h>

struct Req { int n; };

void render(borrow struct Req *r)
{
    printf("%d\n", r->n);
}

int main(void)
{
    struct Req q;
    q.n = 7;
    render(&q);
    return 0;
}
BWEOF
if ( cd "$work/bw-a" && "$work/ct-ast" prog.ct -o prog.c ) >"$work/bw-a.out" 2>"$work/bw-a.err" \
   && ( cd "$work/bw-b" && "$work/ct-ast" prog.ct -o prog.c ) >"$work/bw-b.out" 2>"$work/bw-b.err" \
   && tail -n +2 "$work/bw-a/prog.c" >"$work/bw-a.body" \
   && tail -n +2 "$work/bw-b/prog.c" >"$work/bw-b.body" \
   && cmp -s "$work/bw-a.body" "$work/bw-b.body" \
   && "$CC" -Wall -Wextra -std=c99 "$work/bw-b/prog.c" -o "$work/bw-b.bin" 2>"$work/bw-b.cc" \
   && printf '7\n' >"$work/bw-b.want" \
   && "$work/bw-b.bin" >"$work/bw-b.run" 2>&1 \
   && cmp -s "$work/bw-b.run" "$work/bw-b.want"; then
    ok "borrow annotation leaves the generated C unchanged (the program runs)"
else
    bad "borrow annotation" "$(cat "$work/bw-a.err" "$work/bw-b.err" "$work/bw-b.cc" 2>/dev/null | head -5)"
fi

# The four refusals. Each fixture is compiled and its stderr grepped for the
# exact message the design fixes.
bw_neg() {
    bw_name="$1"
    bw_msg="$2"
    bw_src="$3"
    printf '%s' "$bw_src" >"$work/$bw_name.ct"
    if "$work/ct-ast" "$work/$bw_name.ct" -o "$work/$bw_name.c" \
            >"$work/$bw_name.out" 2>"$work/$bw_name.err"; then
        bad "borrow $bw_name" "expected a non-zero exit"
    elif grep -qF "$bw_msg" "$work/$bw_name.err"; then
        ok "borrow $bw_name"
    else
        bad "borrow $bw_name" "$(cat "$work/$bw_name.err")"
    fi
}
bw_neg non_struct_ptr "'borrow' requires a struct pointer parameter" \
'#include <stdio.h>
void f(borrow int *p)
{
    (void)p;
}
int main(void) { return 0; }
'
bw_neg array_param "'borrow' requires a struct pointer parameter" \
'#include <stdio.h>
struct Req { int n; };
void f(borrow struct Req *r[])
{
    (void)r;
}
int main(void) { return 0; }
'
bw_neg delete_borrow "a borrowed pointer cannot be deleted" \
'#include <stdio.h>
struct Req { int n; };
void f(borrow struct Req *r)
{
    delete r;
}
int main(void) { return 0; }
'
bw_neg store_global "a borrowed pointer cannot be stored in 'g' (its scope outlives the borrow)" \
'#include <stdio.h>
struct Req { int n; };
struct Req *g;
void f(borrow struct Req *r)
{
    g = r;
}
int main(void) { return 0; }
'

# Stage two: a `borrow` declaration hands the object back at scope exit.
# The 62 fixture is the behavioural proof (reverse order, one handback each,
# and the program's own output); the generated C is checked here for the
# shape design 5 fixes: handback plus nulling, never `free`.
"$work/ct-ast" test/ast/62_borrow_handback/prog.ct -o "$work/bh62.c" \
    >"$work/bh62.out" 2>"$work/bh62.err"
if [ $? -ne 0 ]; then
    bad "borrow handback" "ct-ast failed: $(cat "$work/bh62.err")"
elif ! grep -q 'if (a) { Conn_Handback_handback(a); a = 0; }' "$work/bh62.c"; then
    bad "borrow handback" "the exit does not hand back and null"
elif ! grep -q 'if (b) { Conn_Handback_handback(b); b = 0; }' "$work/bh62.c"; then
    bad "borrow handback" "the second exit does not hand back and null"
elif grep -q 'free(a)' "$work/bh62.c" || grep -q 'free(b)' "$work/bh62.c"; then
    bad "borrow handback" "a borrow is freed instead of handed back"
elif grep -q 'Handback_vtbl' "$work/bh62.c" || grep -q '__Handback_vptr' "$work/bh62.c"; then
    bad "borrow handback" "Handback must not carry a vptr or a vtable"
else
    ok "borrow handback (exit hands back and nulls, never frees)"
fi

# The refusals and the escape warning. Fixtures are inline; the messages are
# the ones design 6 lists.
bw_neg no_handback "struct 'Conn' does not use trait 'Handback'" \
'#include <stdio.h>
struct Conn { int fd; int in_use; };
static struct Conn g;
int main(void)
{
    borrow struct Conn *c = &g;
    c->in_use = 1;
    return 0;
}
'
bw_neg no_impl "struct 'Conn' uses trait 'Handback' but this unit has no impl" \
'#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
static struct Conn g;
int main(void)
{
    borrow struct Conn *c = &g;
    c->in_use = 1;
    return 0;
}
'
bw_neg borrow_no_init "'borrow' requires an initialiser of struct pointer type" \
'#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn {
    void handback() { self->in_use = 0; }
}
int main(void)
{
    borrow struct Conn *c;
    (void)c;
    return 0;
}
'
bw_neg borrow_array "'borrow' does not support arrays" \
'#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn {
    void handback() { self->in_use = 0; }
}
static struct Conn g[2];
int main(void)
{
    borrow struct Conn *a[2];
    a[0] = &g[0];
    return 0;
}
'
bw_neg borrow_static "a static local cannot be 'borrow'" \
'#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn {
    void handback() { self->in_use = 0; }
}
static struct Conn g;
int main(void)
{
    static borrow struct Conn *c = &g;
    c->in_use = 1;
    return 0;
}
'
bw_neg borrow_switch "'borrow' is not supported inside a switch" \
'#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn {
    void handback() { self->in_use = 0; }
}
static struct Conn g;
int main(void)
{
    int n = 1;
    switch (n) {
    case 1:
        borrow struct Conn *c = &g;
        c->in_use = 1;
        break;
    }
    return 0;
}
'

# `return c;` on a local borrow: a warning, and the handout injection is cancelled
# (returning the object to the pool while the caller still reads the slot would
# be worse than leaking it).
cat >"$work/bw_escape.ct" <<'BWEOF'
#include <stdio.h>

struct Conn { int fd; int in_use; } use Handback;

impl Handback for Conn {
    void handback() { self->in_use = 0; }
}

static struct Conn g_slot;

static struct Conn *get(void)
{
    borrow struct Conn *c = &g_slot;
    return c;
}

int main(void)
{
    struct Conn *p = get();
    printf("%d\n", p->fd);
    return 0;
}
BWEOF
if "$work/ct-ast" "$work/bw_escape.ct" -o "$work/bw_escape.c" \
        >"$work/bw_escape.out" 2>"$work/bw_escape.err"; then
    if grep -q "warning: a borrowed pointer escapes through 'return'" "$work/bw_escape.err" \
       && ! grep -q 'Handback_handback(c)' "$work/bw_escape.c"; then
        ok "borrow escape (warns and cancels the handback)"
    else
        bad "borrow escape" "$(cat "$work/bw_escape.err")"
    fi
else
    bad "borrow escape" "expected generation to succeed with a warning: $(cat "$work/bw_escape.err")"
fi

# `borrow` is a block-scope keyword: a file-scope declaration is refused rather
# than silently parsed as a plain pointer.
bw_neg borrow_file_scope "'borrow' is only allowed inside a function body" \
'struct Conn { int fd; } use Handback;
impl Handback for Conn { void handback() { self->fd = 0; } }
borrow struct Conn *g = 0;
int main(void) { return 0; }
'

# A borrowed handle may not be stored where the borrow cannot see it end: a
# `static` block-scope local outlives the block exactly as a global does.
bw_neg store_static "a borrowed pointer cannot be stored in 's' (its scope outlives the borrow)" \
'struct Conn { int fd; } use Handback;
impl Handback for Conn { void handback() { self->fd = 0; } }
static struct Conn g_c;
static struct Conn *acq(void) { return &g_c; }
void f(void) {
    static struct Conn *s;
    borrow struct Conn *c = acq();
    s = c;
}
int main(void) { return 0; }
'

# Rebinding a borrowed handle would drop the old object's handback without
# handing it back, so the assignment is refused instead of leaking it silently.
bw_neg borrow_reassign "a borrowed pointer cannot be reassigned" \
'struct Conn { int fd; } use Handback;
impl Handback for Conn { void handback() { self->fd = 0; } }
static struct Conn g_c;
static struct Conn *acq(int k) { g_c.fd = k; return &g_c; }
int main(void) {
    borrow struct Conn *c = acq(1);
    c = acq(2);
    return 0;
}
'

# A same-scope copy (`struct Conn *q = c;`) is allowed: its lifetime ends with
# the borrow, so the handback at the exit must survive that copy (it used to be
# cancelled by the copy's own leak bookkeeping).
cat >"$work/bw_copy.ct" <<'BWEOF'
#include <stdio.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn { void handback() { self->in_use = 0; } }
static struct Conn g_c;
static struct Conn *acq(void) { g_c.fd = 1; g_c.in_use = 1; return &g_c; }
int main(void)
{
    borrow struct Conn *c = acq();
    struct Conn *q = c;
    printf("%d\n", q->fd);
    return 0;
}
BWEOF
if "$work/ct-ast" "$work/bw_copy.ct" -o "$work/bw_copy.c" \
        >"$work/bw_copy.out" 2>"$work/bw_copy.err" \
   && grep -q 'if (c) { Conn_Handback_handback(c); c = 0; }' "$work/bw_copy.c"; then
    ok "borrow same-scope copy keeps the handback"
else
    bad "borrow same-scope copy" "$(cat "$work/bw_copy.err")"
fi

# A `return` hands back the object it actually owns: `return c->fd;` releases
# nothing, so the borrow's handback (and the `own`'s drop) must still run first.
cat >"$work/bw_ret.ct" <<'BWEOF'
#include <stdlib.h>
struct Conn { int fd; int in_use; } use Handback;
impl Handback for Conn { void handback() { self->in_use = 0; } }
struct Box { int n; } use Drop;
impl Drop for Box { void drop() { } }
static struct Conn g_c;
static struct Conn *acq(void) { g_c.fd = 9; g_c.in_use = 1; return &g_c; }
int from_field(void)
{
    borrow struct Conn *c = acq();
    return c->fd;
}
int drop_field(void)
{
    own Box *b = malloc(sizeof(struct Box));
    b->n = 7;
    return b->n;
}
int main(void) { return from_field() + drop_field(); }
BWEOF
if "$work/ct-ast" "$work/bw_ret.ct" -o "$work/bw_ret.c" \
        >"$work/bw_ret.out" 2>"$work/bw_ret.err" \
   && grep -q 'if (c) { Conn_Handback_handback(c); c = 0; }' "$work/bw_ret.c" \
   && grep -q 'if (b) { Box_Drop_drop(b); free(b); b = 0; }' "$work/bw_ret.c" \
   && "$CC" -Wall -Wextra -std=c99 -c "$work/bw_ret.c" -o "$work/bw_ret.o" 2>"$work/bw_ret.cc"; then
    ok "return of a member still releases the borrow / own object"
else
    bad "return of a member" "$(cat "$work/bw_ret.err" "$work/bw_ret.cc" 2>/dev/null | head -5)"
fi

# `delete` only nulls an assignable operand: `delete get();` must stay a plain
# `if (get()) { free(get()); }` (a call is not an lvalue).
cat >"$work/bw_delete.ct" <<'BWEOF'
#include <stdlib.h>
static int *get(void) { return 0; }
int main(void)
{
    delete get();
    return 0;
}
BWEOF
if "$work/ct-ast" "$work/bw_delete.ct" -o "$work/bw_delete.c" \
        >"$work/bw_delete.out" 2>"$work/bw_delete.err" \
   && ! grep -q 'get() = 0' "$work/bw_delete.c" \
   && "$CC" -Wall -Wextra -std=c99 -c "$work/bw_delete.c" -o "$work/bw_delete.o" 2>"$work/bw_delete.cc"; then
    ok "delete of a call does not assign to it"
else
    bad "delete of a call" "$(cat "$work/bw_delete.err" "$work/bw_delete.cc" 2>/dev/null | head -5)"
fi

# A `return` that hands an `own` object back is a transfer, not a leak: no
# `potential leak` may be reported for it.
cat >"$work/bw_handoff.ct" <<'BWEOF'
#include <stdlib.h>
struct Box { int n; } use Drop;
impl Drop for Box { void drop() { } }
struct Box *make(void)
{
    own Box *b = malloc(sizeof(struct Box));
    b->n = 5;
    return b;
}
int main(void) { struct Box *p = make(); return p->n; }
BWEOF
if "$work/ct-ast" "$work/bw_handoff.ct" -o "$work/bw_handoff.c" \
        >"$work/bw_handoff.out" 2>"$work/bw_handoff.err" \
   && ! grep -q 'potential leak' "$work/bw_handoff.err"; then
    ok "returning an own object is a handoff, not a leak"
else
    bad "returning an own object" "$(cat "$work/bw_handoff.err" | head -5)"
fi

echo
echo "== multi-error recovery (10.4) =="
# A bad construct must not hide the rest of the file: every error is reported and
# the run closes with the summary. Both fixtures are byte-diffed against L2 and
# must leave no .c/.h behind.
rec="$work/rec"
rm -rf "$rec-multi_err"
mkdir -p "$rec-multi_err"
cp test/modules/multi_err/prog.ct "$rec-multi_err/"
if ( cd "$rec-multi_err" && "$work/ct-ast" prog.ct -o prog.c ) \
        >"$rec-multi_err.out" 2>"$rec-multi_err.err"; then
    bad "multi_err" "expected a non-zero exit"
elif ! cmp -s "$rec-multi_err.err" test/modules/multi_err/expected.stderr; then
    bad "multi_err" "stderr differs: $(cat "$rec-multi_err.err")"
elif [ -f "$rec-multi_err/prog.c" ] || [ -f "$rec-multi_err/prog.h" ]; then
    bad "multi_err" "artifacts survived a failed compile"
else
    ok "multi_err (three errors, L2-identical, no artifacts)"
fi

rm -rf "$rec-multi_err_build"
mkdir -p "$rec-multi_err_build"
if "$work/ct-ast" build --emit-c test/modules/multi_err_build/prog.ct -o "$rec-multi_err_build" \
        >"$rec-multi_err_build.out" 2>"$rec-multi_err_build.err"; then
    bad "multi_err_build" "expected a non-zero exit"
elif ! cmp -s "$rec-multi_err_build.err" test/modules/multi_err_build/expected.stderr; then
    bad "multi_err_build" "stderr differs: $(cat "$rec-multi_err_build.err")"
elif [ -n "$(ls -A "$rec-multi_err_build" 2>/dev/null)" ]; then
    bad "multi_err_build" "artifacts survived a failed build"
else
    ok "multi_err_build (build reports every error, no artifacts)"
fi

# Past MAX_ERRORS both compilers stop with the same line instead of a summary.
rm -rf "$rec-cap"
mkdir -p "$rec-cap"
i=1
{
    echo 'trait T { void f(); }'
    while [ "$i" -le 25 ]; do
        echo "impl T for M$i { void f() { } }"
        i=$((i + 1))
    done
} >"$rec-cap/cap.ct"
if ( cd "$rec-cap" && "$work/l2" cap.ct -o l2.c ) >/dev/null 2>"$rec-cap/l2.err"; then
    bad "max_errors" "L2 was expected to fail"
elif ( cd "$rec-cap" && "$work/ct-ast" cap.ct -o ast.c ) >/dev/null 2>"$rec-cap/ast.err"; then
    bad "max_errors" "expected a non-zero exit"
elif ! cmp -s "$rec-cap/l2.err" "$rec-cap/ast.err"; then
    bad "max_errors" "the report differs from L2"
elif ! grep -q '^ctc: too many errors, stopping$' "$rec-cap/ast.err"; then
    bad "max_errors" "the cap line is missing"
else
    ok "max_errors (same cap and report as L2)"
fi

echo
echo "== incremental cache (10.5) =="
# The key is a pure function of the source stamp, the run's options and the
# dependency digests, so a warm build must leave the artefacts alone while a
# dependency change or a deleted artefact must rebuild. The key spelling is
# byte-compared with L2's (D41).
cac="$work/cache"
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }
rm -rf "$cac"
mkdir -p "$cac/src" "$cac/ast" "$cac/l2"
cp test/modules/split/*.ct "$cac/src/"
if "$work/ct-ast" build --emit-c "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>"$cac/ast.err" \
   && [ -f "$cac/ast/.ctcache/main.c.key" ]; then
    ok "cache: a cold build stamps every unit"
else
    bad "cache" "cold build failed: $(cat "$cac/ast.err")"
fi
if "$work/l2" build "$cac/src/main.ct" -o "$cac/l2" >/dev/null 2>&1 \
   && cmp -s "$cac/ast/.ctcache/main.c.key" "$cac/l2/.ctcache/main.c.key" \
   && cmp -s "$cac/ast/.ctcache/shapes.c.key" "$cac/l2/.ctcache/shapes.c.key" \
   && cmp -s "$cac/ast/.ctcache/impl_dog.c.key" "$cac/l2/.ctcache/impl_dog.c.key"; then
    ok "cache: keys match L2 byte for byte"
else
    bad "cache keys" "the key spelling differs from L2"
fi
touch -t 200001010000 "$cac/ast/main.c" "$cac/ast/shapes.c" "$cac/ast/impl_dog.c"
cached=$(mtime "$cac/ast/main.c")
"$work/ct-ast" build --emit-c "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>&1
if [ "$(mtime "$cac/ast/main.c")" = "$cached" ]; then
    ok "cache: a warm build reuses unchanged units"
else
    bad "cache warm" "main.c was regenerated although nothing changed"
fi
touch -t 201001010000 "$cac/src/shapes.h.ct"
"$work/ct-ast" build --emit-c "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>&1
if [ "$(mtime "$cac/ast/main.c")" != "$cached" ] \
   && [ "$(mtime "$cac/ast/impl_dog.c")" != "$cached" ]; then
    ok "cache: a dependency change invalidates downstream units"
else
    bad "cache dep" "main.c/impl_dog.c were not rebuilt after shapes changed"
fi
rm -f "$cac/ast/shapes.c"
"$work/ct-ast" build --emit-c "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>&1
if [ -f "$cac/ast/shapes.c" ]; then
    ok "cache: a missing artefact is regenerated"
else
    bad "cache artifact" "shapes.c was not restored"
fi
# L2's build shares one symbol table across the units it compiles, so a unit it
# recompiles needs every imported unit compiled too -- including a clean
# dependency that sits *after* the first dirty unit in the order. The shape:
# A (dirty) -> B (clean) -> C (dirty, imports both).
inc="$work/incremental"
rm -rf "$inc"
mkdir -p "$inc/pa" "$inc/cache" "$inc/m" "$inc/out"
cat > "$inc/pa/A.h.ct" <<'INCEOF'
namespace pa;
pub struct A {
    int x;
};
INCEOF
cat > "$inc/cache/B.h.ct" <<'INCEOF'
namespace cache;
pub struct B {
    int y;
};
INCEOF
cat > "$inc/m/C.h.ct" <<'INCEOF'
import pa::A;
import cache::B;
namespace m;
pub struct C {
    struct A *a;
    struct B *b;
};
INCEOF
cat > "$inc/main.ct" <<'INCEOF'
import pa::A;
import m::C;
int main(void)
{
    struct A *a = 0;
    struct C *c = 0;
    return (a != 0) || (c != 0);
}
INCEOF
if "$work/l2" build -I "$inc" --ns-root "$inc" "$inc/main.ct" -o "$inc/out" \
        >/dev/null 2>"$inc/1.err" \
   && grep -q "struct cache_B" "$inc/out/C.h"; then
    ok "cache: L2 cold build resolves imported types"
else
    bad "cache: L2 cold build" "$(cat "$inc/1.err" "$inc/out/C.h" 2>/dev/null)"
fi
printf '\n/* changed */\n' >> "$inc/pa/A.h.ct"
if "$work/l2" build -I "$inc" --ns-root "$inc" "$inc/main.ct" -o "$inc/out" \
        >/dev/null 2>"$inc/2.err" \
   && grep -q "struct cache_B" "$inc/out/C.h" \
   && "$CC" -Wall -Wextra -std=c99 "$inc/out"/*.c -o "$inc/bin" >/dev/null 2>"$inc/cc.err"; then
    ok "cache: L2 recompiles the dependency closure of a dirty unit"
else
    bad "cache: L2 dependency closure" "$(cat "$inc/2.err" "$inc/cc.err" 2>/dev/null)"
fi

echo
echo "== self-hosting (9.6) =="
# The AST compiler builds its own source; the result must compile warning-free,
# and the rebuilt compiler must reproduce the same output byte for byte (a
# fixpoint: the compiler agrees with itself on its own subset). The source is a
# multi-unit tree now, so the build mode drives both halves and the whole output
# directory is compared.
mkdir -p "$work/self1" "$work/self2"
if "$work/ct-ast" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/self1" \
        >"$work/self1.out" 2>"$work/self1.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/self1"/*.c -o "$work/ct-ast2" 2>"$work/selfcc.log" \
   && "$work/ct-ast2" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/self2" \
        >"$work/self2.out" 2>"$work/self2.err" \
   && diff -r -q -x .ctcache "$work/self1" "$work/self2" >/dev/null 2>&1; then
    ok "self-compile (fixpoint: ct-ast2 reproduces ct-ast's output)"
else
    bad "self-compile" "$(cat "$work/self1.err" "$work/selfcc.log" "$work/self2.err" 2>/dev/null | head -5)"
fi

echo
echo "== the L0 seed (ct-ast compiles ctc.c itself) =="
# The C-subset coverage the batch probes established, kept as a gate: every
# construct `selfhost/l0/ctc.c` uses must parse, the generated C must compile,
# the compiler that comes out must reproduce every L0 golden byte for byte, and
# it must run an example end to end. Without this a parse branch could narrow
# again and only the probes would notice.
mkdir -p "$work/seed" "$work/seed/goldens"
if "$work/ct-ast" compile selfhost/l0/ctc.c -o "$work/seed/ctc.c" \
        >"$work/seed.out" 2>"$work/seed.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/seed/ctc.c" -o "$work/seed/ctc" 2>"$work/seedcc.log"; then
    ok "L0 seed (ctc.c compiles; the generated C builds)"
else
    bad "L0 seed compile" "$(cat "$work/seed.err" "$work/seedcc.log" 2>/dev/null | head -5)"
fi

if [ -x "$work/seed/ctc" ]; then
    seed_bad=""
    for f in test/cases/*.ct; do
        b="$(basename "$f" .ct)"
        if ! "$work/seed/ctc" "$f" -o "$work/seed/goldens/$b.c" \
                >"$work/seed/$b.out" 2>"$work/seed/$b.err"; then
            seed_bad="$b (compile failed)"
            break
        fi
        if ! diff -q "$work/seed/goldens/$b.c" "test/cases/$b.expected.c" >/dev/null 2>&1; then
            seed_bad="$b (output differs)"
            break
        fi
    done
    if [ -z "$seed_bad" ]; then
        ok "L0 seed (every test/cases golden is reproduced byte for byte)"
    else
        bad "L0 seed goldens" "$seed_bad"
    fi

    if "$work/seed/ctc" examples/01_greeter/greeter.ct -o "$work/seed/greeter.c" \
            >"$work/seedrun.out" 2>"$work/seedrun.err" \
       && "$CC" "$work/seed/greeter.c" -o "$work/seed/greeter" 2>"$work/seedgreet.log" \
       && "$work/seed/greeter" >"$work/seed/greeter.out" 2>&1 \
       && diff -u examples/01_greeter/greeter.expected.out "$work/seed/greeter.out" >/dev/null 2>&1; then
        ok "L0 seed (the result runs an example end to end)"
    else
        bad "L0 seed example" "$(cat "$work/seedrun.err" "$work/seedgreet.log" 2>/dev/null | head -5)"
    fi
fi

echo
echo "== Phase 22: loop(n), the countable shorthand =="
# `loop(<count>) { … }` is pure sugar for the native `for` it prints. Every
# probe prints both spellings, so "equivalent" is executable. `loop` is a
# contextual keyword (D22-4): only `loop(` in statement position is special.

# 1) The three header diagnostics are pinned verbatim; the generic errors sweep
#    only checks the positioned shape.
for pair in \
    "loop_missing_count|loop needs a count expression" \
    "loop_non_block|loop body must be a block" \
    "loop_two_counts|loop takes exactly one count; use a native for to name the counter"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "loop: $cf" "expected a non-zero exit"
    elif grep -Fq "$cfmsg" "$work/$cf.err"; then
        ok "loop ($cf)"
    else
        bad "loop: $cf" "$(cat "$work/$cf.err")"
    fi
done

# 2) A closure cannot escape the body; the existing escape wording is reused.
if "$work/ct-ast" test/ast/errors/loop_closure_escape.ct -o "$work/lce.c" \
        >"$work/lce.out" 2>"$work/lce.err"; then
    bad "loop: closure escape" "expected a non-zero exit"
elif grep -Fq "a closure cannot be stored in 'f' (its scope outlives the closure)" "$work/lce.err"; then
    ok "loop (a closure cannot escape the body)"
else
    bad "loop: closure escape" "$(cat "$work/lce.err")"
fi

# 3) L22-5: a statically known non-integer count compiles with one warning and
#    still runs; `ct check` raises the same record to an error.
if "$work/ct-ast" test/ast/loop_count_type/prog.ct -o "$work/lct.c" \
        >"$work/lct.out" 2>"$work/lct.err"; then
    if grep -Fq "warning: type mismatch: 'loop' count must be an integer (got 'double'); the value is converted to int" "$work/lct.err" \
       && grep -Fq '__ct_loop_n_' "$work/lct.c"; then
        ok "loop (L22-5 warns in compile mode and still emits a for)"
    else
        bad "loop: L22-5 compile" "$(cat "$work/lct.err")"
    fi
else
    bad "loop: L22-5 compile" "expected exit 0; $(cat "$work/lct.err")"
fi
"$work/ct-ast" check --diagnostics=json test/ast/loop_count_type/prog.ct \
    >"$work/lct.json" 2>"$work/lct.json.err"
lrc=$?
if [ "$lrc" -eq 1 ] \
        && grep -Fq '"severity":"error"' "$work/lct.json" \
        && grep -Fq '"type":"type_mismatch"' "$work/lct.json" \
        && grep -Fq 'count must be an integer' "$work/lct.json"; then
    ok "loop (L22-5 is an error under ct check)"
else
    bad "loop: L22-5 check" "exit $lrc; $(cat "$work/lct.json")"
fi

# 4) L22-4: nested `loop` warns in compile mode and becomes a `loop_shadow`
#    finding under `ct check`. Only loop-in-loop is reported.
if "$work/ct-ast" test/ast/97_loop_nested_shadow/prog.ct -o "$work/lsh.c" \
        >"$work/lsh.out" 2>"$work/lsh.err"; then
    if grep -Fq "warning: loop shadows the outer 'i'; use a native for to name the inner counter" "$work/lsh.err"; then
        ok "loop (nested loop warns in compile mode)"
    else
        bad "loop: nested warning" "$(cat "$work/lsh.err")"
    fi
else
    bad "loop: nested warning" "expected exit 0; $(cat "$work/lsh.err")"
fi
"$work/ct-ast" check --diagnostics=json test/ast/97_loop_nested_shadow/prog.ct \
    >"$work/lsh.json" 2>"$work/lsh.json.err"
lrc=$?
if [ "$lrc" -eq 1 ] \
        && grep -Fq '"type":"loop_shadow"' "$work/lsh.json" \
        && grep -Fq '"severity":"error"' "$work/lsh.json"; then
    ok "loop (nested loop is loop_shadow, an error under ct check)"
else
    bad "loop: nested JSON" "exit $lrc; $(cat "$work/lsh.json")"
fi

# A hand-written `int i` in the body is ordinary C shadowing: no warning.
cat > "$work/l_own_i.ct" <<'LIEOF'
#include <stdio.h>

int main(void)
{
    loop(2) {
        int i = 7;

        printf("%d\n", i);
    }
    return 0;
}
LIEOF
"$work/ct-ast" "$work/l_own_i.ct" -o "$work/l_own_i.c" \
    >"$work/l_own_i.out" 2>"$work/l_own_i.err"
if [ -s "$work/l_own_i.err" ]; then
    bad "loop: a hand-written int i" "$(cat "$work/l_own_i.err")"
else
    ok "loop (a hand-written int i in the body stays silent)"
fi

# 5) The lowering is exactly one native `for`: the count is bound once in a
#    private temporary and the test reads that temporary, never the expression.
#    (The byte-level golden check lives in the L0-seed section above; ct-ast's
#    formatting is its own and is covered by the behavioural cases.)
if "$work/ct-ast" test/ast/92_loop_basic/prog.ct -o "$work/l92c.c" \
        >"$work/l92c.out" 2>"$work/l92c.err" \
   && grep -Fq 'for (int i = 0, __ct_loop_n_' "$work/l92c.c" \
   && ! grep -Fq 'i < (' "$work/l92c.c"; then
    ok "loop (lowers to one for with a once-evaluated bound)"
else
    bad "loop: lowering shape" "$(cat "$work/l92c.err")"
fi

echo
echo "== Phase 23: loop(a..b), the half-open range =="
# `loop(<start>..<stop>) { … }` is sugar for
# `for (int i = <start>; i < <stop>; i++) { … }`. `..` is now one token, so the
# diagnostics below are pinned with columns: before the lexer change `1..2` split
# into `1.` and `.2`, and every reported position moved.

# 1) A one-sided range and a chained range are syntax errors.
for pair in \
    "loop_range_missing_low|a loop range needs both bounds" \
    "loop_range_missing_high|a loop range needs both bounds" \
    "loop_range_chained|unexpected token"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "range: $cf" "expected a non-zero exit"
    elif grep -Fq "$cfmsg" "$work/$cf.err"; then
        ok "range ($cf)"
    else
        bad "range: $cf" "$(cat "$work/$cf.err")"
    fi
done

# The column proves `..` is a single token: `1..2..3` reaches the second `..`
# (column 14) instead of stopping at the dot that used to follow the number.
if "$work/ct-ast" test/ast/errors/loop_range_chained.ct -o "$work/lrc.c" \
        >"$work/lrc.out" 2>"$work/lrc.err"; then
    bad "range: chained column" "expected a non-zero exit"
elif grep -Fq "loop_range_chained.ct:3:14: error: unexpected token" "$work/lrc.err"; then
    ok "range (a second '..' is one token, reported at column 14)"
else
    bad "range: chained column" "$(cat "$work/lrc.err")"
fi

# 2) D23-8: an address-shaped or aggregate bound is a hard error. The array case
#    used to be silent -- its type string is indistinguishable from a pointer's,
#    so only the symbol table can see it.
for pair in \
    "loop_range_pointer|a loop bound must be an integer (got 'int *')" \
    "loop_range_struct|a loop bound must be an integer (got 'struct Pair')" \
    "loop_range_array|a loop bound must be an integer (got the array 'a')" \
    "loop_range_array_member|a loop bound must be an integer (got 'int[2][3]')"
do
    cf="${pair%%|*}"
    cfmsg="${pair#*|}"
    if "$work/ct-ast" "test/ast/errors/$cf.ct" -o "$work/$cf.c" \
            >"$work/$cf.out" 2>"$work/$cf.err"; then
        bad "range: $cf" "expected a non-zero exit"
    elif grep -Fq "$cfmsg" "$work/$cf.err"; then
        ok "range ($cf)"
    else
        bad "range: $cf" "$(cat "$work/$cf.err")"
    fi
done

# 3) D23-2: `loop(0..b)` is `loop(b)`. The lowering must be identical, banner
#    aside -- line 1 names the input file, so it cannot match.
cat > "$work/lr_count.ct" <<'LREOF'
int main(void)
{
    int n = 3;

    loop(n) {
        n = n + i;
    }
    return n;
}
LREOF
cat > "$work/lr_range.ct" <<'LREOF'
int main(void)
{
    int n = 3;

    loop(0..n) {
        n = n + i;
    }
    return n;
}
LREOF
if "$work/ct-ast" "$work/lr_count.ct" -o "$work/lr_count.c" \
        >"$work/lr_count.out" 2>"$work/lr_count.err" \
   && "$work/ct-ast" "$work/lr_range.ct" -o "$work/lr_range.c" \
        >"$work/lr_range.out" 2>"$work/lr_range.err" \
   && tail -n +2 "$work/lr_count.c" > "$work/lr_count.tail" \
   && tail -n +2 "$work/lr_range.c" > "$work/lr_range.tail" \
   && cmp -s "$work/lr_count.tail" "$work/lr_range.tail"; then
    ok "range (loop(0..n) lowers exactly like loop(n))"
else
    bad "range: 0..n normalisation" \
        "$(cat "$work/lr_count.err" "$work/lr_range.err"; diff -u "$work/lr_count.tail" "$work/lr_range.tail" 2>/dev/null | head -6)"
fi

# 4) The shape: one native `for`, both bounds snapshotted once into private
#    temporaries, and the lower one assigned before the upper one inside `i`'s
#    single initializer -- the comma operator sequences them (C99 §6.5.17)
#    instead of relying on declarator-initializer order (§6.7.8). It must never
#    print as `i < (<expr>)`, which would re-evaluate the bound every round.
if "$work/ct-ast" test/ast/102_loop_range_basic/prog.ct -o "$work/l102c.c" \
        >"$work/l102c.out" 2>"$work/l102c.err" \
   && grep -Fq 'for (int __ct_loop_n_' "$work/l102c.c" \
   && grep -Fq ', i = ((__ct_loop_n_' "$work/l102c.c" \
   && grep -Fq ')), (__ct_loop_hi_' "$work/l102c.c" \
   && grep -Fq ')), __ct_loop_n_' "$work/l102c.c" \
   && grep -Fq '; i < __ct_loop_hi_' "$work/l102c.c" \
   && ! grep -Fq 'i < (' "$work/l102c.c"; then
    ok "range (one for, both bounds assigned left to right by a comma expression)"
else
    bad "range: lowering shape" "$(cat "$work/l102c.err")"
fi

# 5) L22-4 is reused unchanged: a nested range loop shadows the outer `i`.
if "$work/ct-ast" test/ast/106_loop_range_nested/prog.ct -o "$work/lrn.c" \
        >"$work/lrn.out" 2>"$work/lrn.err"; then
    if grep -Fq "warning: loop shadows the outer 'i'; use a native for to name the inner counter" "$work/lrn.err"; then
        ok "range (nested range loop warns in compile mode)"
    else
        bad "range: nested warning" "$(cat "$work/lrn.err")"
    fi
else
    bad "range: nested warning" "expected exit 0; $(cat "$work/lrn.err")"
fi
"$work/ct-ast" check --diagnostics=json test/ast/106_loop_range_nested/prog.ct \
    >"$work/lrn.json" 2>"$work/lrn.json.err"
lrc=$?
if [ "$lrc" -eq 1 ] \
        && grep -Fq '"type":"loop_shadow"' "$work/lrn.json" \
        && grep -Fq '"severity":"error"' "$work/lrn.json"; then
    ok "range (nested range loop is loop_shadow, an error under ct check)"
else
    bad "range: nested JSON" "exit $lrc; $(cat "$work/lrn.json")"
fi

echo
echo "== Phase 24: array range initialisers =="

# 1) Shape: the expansion is a brace list on one line, with one `((int)k)` per
#    element and neither the loop form nor the range source left in it. The
#    fixture owns a hand-written `for` of its own, so the check is scoped to the
#    emitted declaration instead of the whole file.
if "$work/ct-ast" test/ast/109_range_init_basic/prog.ct -o "$work/r109.c" \
        >"$work/r109.out" 2>"$work/r109.err" \
   && grep 'int odd\[\] = {' "$work/r109.c" > "$work/r109.decl" \
   && grep -Fq '((int)1)' "$work/r109.decl" \
   && ! grep -Fq 'for' "$work/r109.decl" \
   && ! grep -Fq '$' "$work/r109.decl" \
   && ! grep -Fq '0..13' "$work/r109.decl"; then
    ok "range (brace list, no loop, no '\$', no '0..13')"
else
    bad "range: expansion shape" "$(cat "$work/r109.err")"
fi

# 2) One element per slot: the initialiser splits into exactly 13 items.
r109n=$(awk -F, '/int odd\[\] = \{/ { print NF }' "$work/r109.c")
if [ "$r109n" = "13" ]; then
    ok "range (13 elements: one per slot)"
else
    bad "range: element count" "counted '$r109n'"
fi

# 3) Byte layer: the expansion is the hand-written list and nothing else. The
#    manual fixture is a plain `{ … }` initialiser, which is copied verbatim, so
#    `cmp` on the declaration pins spacing, parentheses and all 13 `((int)k)`.
if "$work/ct-ast" test/ast/109_range_init_basic/manual.ct -o "$work/r109m.c" \
        >"$work/r109m.out" 2>"$work/r109m.err" \
   && grep 'int odd\[\] = {' "$work/r109.c" > "$work/r109.a" \
   && grep 'int odd\[\] = {' "$work/r109m.c" > "$work/r109.b" \
   && cmp -s "$work/r109.a" "$work/r109.b"; then
    ok "range (byte-identical to the hand-written 13-element list)"
else
    bad "range: byte equivalence" \
        "$(cat "$work/r109m.err"; diff -u "$work/r109.a" "$work/r109.b" 2>/dev/null | head -6)"
fi

# 4) Semantic layer: 109 and its literal twin run separately and print the same
#    bytes -- the values, not just the shape, are the claim.
if "$CC" -std=c99 "$work/r109.c" -o "$work/r109.bin" 2>"$work/r109.cc" \
   && "$work/ct-ast" test/ast/109_range_init_basic/literal.ct -o "$work/r109l.c" \
        >"$work/r109l.out" 2>"$work/r109l.err" \
   && "$CC" -std=c99 "$work/r109l.c" -o "$work/r109l.bin" 2>>"$work/r109.cc" \
   && "$work/r109.bin" >"$work/r109.run" \
   && "$work/r109l.bin" >"$work/r109l.run" \
   && cmp -s "$work/r109.run" "$work/r109l.run"; then
    ok "range (same output as the literal table, byte for byte)"
else
    bad "range: semantic equivalence" \
        "$(cat "$work/r109.cc" "$work/r109l.err"; diff -u "$work/r109.run" "$work/r109l.run" 2>/dev/null | head -6)"
fi

# 5) The payoff: a file-scope `static const` table is an initialiser, not a
#    statement, so it needs no function and no loop.
if "$work/ct-ast" test/ast/110_range_init_static_const/prog.ct -o "$work/r110.c" \
        >"$work/r110.out" 2>"$work/r110.err" \
   && grep -Eq '^static const int sq\[\] = \{ ' "$work/r110.c"; then
    ok "range (file-scope static const table)"
else
    bad "range: file scope" "$(cat "$work/r110.err")"
fi

# 6) `$` and the bound reader: every one of these must be a positioned
#    diagnostic, and none of them may fall back to "undeclared variable".
rng_neg() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/rneg.c" \
            >"$work/rneg.out" 2>"$work/rneg.err"; then
        bad "range: $1" "expected a diagnostic, got exit 0"
    elif grep -Fq "$2" "$work/rneg.err" && ! grep -Fiq 'undeclared' "$work/rneg.err"; then
        ok "range ($1: $2)"
    else
        bad "range: $1" "$(cat "$work/rneg.err")"
    fi
}
rng_neg range_index_outside "unexpected token"
rng_neg range_index_in_dim "'\$' cannot be used in an array dimension"
rng_neg range_index_assigned "unexpected token"
rng_neg range_index_address "the range index '\$' is not a variable"
rng_neg range_index_address_post "the range index '\$' is not a variable"
rng_neg range_index_address_pre "the range index '\$' is not a variable"
rng_neg range_init_missing_end "a range initializer needs both bounds"
rng_neg range_init_nonliteral_bound "a range bound must be an integer literal (got 'n')"
rng_neg range_init_nonliteral_bound_base "a range bound must be an integer literal (got 'BASE')"
rng_neg range_init_bad_hex "got '0x'"
rng_neg range_init_overflow "a range bound is out of range"
rng_neg range_init_empty "an empty range has no elements"
rng_neg range_init_too_many "too many range elements (limit 1024)"
rng_neg range_init_scalar_decl "a range initializer declares an array"
rng_neg range_init_element_struct "a range initializer cannot initialize 'struct Pair' elements"
rng_neg range_init_dim_mismatch "the array size '4' does not match the range (3 elements)"

# ---- Phase 27: `foreach` statement form ----
# E27-2: every non-iterable shape is refused with its own wording, never with a
# silent exit 0 and never as an `undeclared` fallback.
p27_diag() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p27.c" \
            >"$work/p27.out" 2>"$work/p27.err"; then
        bad "foreach: $1" "expected a diagnostic, got exit 0"
    elif grep -Fq "$2" "$work/p27.err"; then
        ok "foreach ($1: $2)"
    else
        bad "foreach: $1" "$(cat "$work/p27.err")"
    fi
}
p27_diag foreach_pointer "foreach needs an array or a Vec/Map; 'p' is not iterable"
p27_diag foreach_multidim "foreach does not support multidimensional arrays ('grid')"
p27_diag foreach_param "foreach cannot iterate the array parameter 'a' (its length is lost)"
p27_diag foreach_struct "foreach needs an array or a Vec/Map; 'p' is not iterable"
p27_diag foreach_member "foreach needs a plain array variable"
p27_diag foreach_unsized_global "foreach needs an array with a known length ('ext')"
p27_diag foreach_scope "use of an undeclared variable"
p27_diag foreach_empty "foreach needs a collection expression"
p27_diag foreach_non_block "foreach body must be a block"
p27_diag foreach_fnptr_array "its declarator is not a plain array"

# E27-3: the product is one plain `for`, and the length is read once from
# `sizeof`, so `T a[] = {…}` works without parsing the initialiser.
if "$work/ct-ast" test/ast/132_foreach_array_values/prog.ct -o "$work/p27c.c" \
        >"$work/p27c.out" 2>"$work/p27c.err"; then
    if grep -Fq 'int __ct_foreach_n_0 = (int)(sizeof(nums) / sizeof((nums)[0]));' "$work/p27c.c" \
       && grep -Fq 'for (int __ct_foreach_i_0 = 0; __ct_foreach_i_0 < __ct_foreach_n_0; __ct_foreach_i_0++) {' "$work/p27c.c" \
       && grep -Fq 'int item = (nums)[__ct_foreach_i_0];' "$work/p27c.c"; then
        ok "foreach (expands to one plain for over sizeof)"
    else
        bad "foreach: expansion" "$(grep -n '__ct_foreach' "$work/p27c.c" | head -4)"
    fi
else
    bad "foreach: expansion" "expected exit 0; $(cat "$work/p27c.err")"
fi

# E27-3: the lowered program and a hand-written `for` agree byte for byte.
cat > "$work/p27_twin.ct" <<'P27EOF'
#include <stdio.h>

int main(void)
{
    int nums[5] = {2, 4, 6, 8, 10};
    int s = 0;

    foreach (nums) {
        s = s + item;
    }
    printf("%d\n", s);
    return 0;
}
P27EOF
cat > "$work/p27_hand.ct" <<'P27EOF'
#include <stdio.h>

int main(void)
{
    int nums[5] = {2, 4, 6, 8, 10};
    int s = 0;

    for (int i = 0; i < 5; i++) {
        int item = nums[i];
        s = s + item;
    }
    printf("%d\n", s);
    return 0;
}
P27EOF
if "$work/ct-ast" build "$work/p27_twin.ct" -o "$work/p27_twin" >"$work/p27t.out" 2>"$work/p27t.err" \
   && "$work/ct-ast" build "$work/p27_hand.ct" -o "$work/p27_hand" >"$work/p27h.out" 2>"$work/p27h.err"; then
    if "$work/p27_twin" >"$work/p27_twin.out" && "$work/p27_hand" >"$work/p27_hand.out" \
       && cmp -s "$work/p27_twin.out" "$work/p27_hand.out"; then
        ok "foreach (runtime output matches a hand-written for)"
    else
        bad "foreach: equivalence" "$(cat "$work/p27_twin.out") vs $(cat "$work/p27_hand.out")"
    fi
else
    bad "foreach: equivalence" "$(cat "$work/p27t.err") $(cat "$work/p27h.err")"
fi

# E27-4: nested `foreach` warns in compile mode and becomes an error under
# `ct check`; the wording names `item`, not the loop counter.
if "$work/ct-ast" test/ast/134_foreach_nested_pointer/prog.ct -o "$work/p27n.c" \
        >"$work/p27n.out" 2>"$work/p27n.err"; then
    if grep -Fq "warning: foreach shadows the outer 'item'; use a native for to name the binding" "$work/p27n.err"; then
        ok "foreach (nested item warns in compile mode)"
    else
        bad "foreach: nested warning" "$(cat "$work/p27n.err")"
    fi
else
    bad "foreach: nested warning" "expected exit 0; $(cat "$work/p27n.err")"
fi
"$work/ct-ast" check --diagnostics=json test/ast/134_foreach_nested_pointer/prog.ct \
    >"$work/p27n.json" 2>"$work/p27n.json.err"
p27rc=$?
if [ "$p27rc" -eq 1 ] \
        && grep -Fq '"severity":"error"' "$work/p27n.json" \
        && grep -Fq "foreach shadows the outer 'item'" "$work/p27n.json"; then
    ok "foreach (nested item is an error under ct check)"
else
    bad "foreach: nested JSON" "exit $p27rc; $(cat "$work/p27n.json")"
fi

# ---------------------------------------------------------------------------
# Phase 29: generic structs, inherent impls and the built-in containers.
# The diagnostics are the ones docs/design/phase29.md 2.6 freezes; the shape
# assertions pin the C names (D29-7) and the container loop expansion (D29-13).
# ---------------------------------------------------------------------------
p29_diag() {
    # $1 fixture, $2 line:column, $3 frozen message (E29-7). The position and
    # the single-error rule are part of the criterion, so a message that drifts
    # by one token or a second diagnostic is caught here.
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p29e.c" \
            >"$work/p29e.out" 2>"$work/p29e.err"; then
        bad "p29: $1" "expected a diagnostic, got exit 0"
    elif ! grep -qF "test/ast/errors/$1.ct:$2: error: $3" "$work/p29e.err"; then
        bad "p29: $1" "missing pinned diagnostic: $(head -2 "$work/p29e.err")"
    elif [ "$(grep -c 'error: ' "$work/p29e.err")" -ne 1 ]; then
        bad "p29: $1" "expected exactly one error: $(cat "$work/p29e.err")"
    else
        ok "p29 ($1)"
    fi
}
p29_diag generic_struct_arity 10:20 "a generic struct takes at most 2 type parameters"
p29_diag generic_struct_void 5:13 "type argument 'void' cannot instantiate a generic struct"
p29_diag generic_struct_depth 9:25 "generic type arguments nest deeper than 4"
p29_diag builtin_type_redecl 3:1 "'Vec' is a built-in type and cannot be redeclared"
p29_diag foreach_container_element 7:5 "foreach cannot iterate a container of 'struct MapEntry_char_p_int' (interface, vptr-bearing or container element)"
p29_diag foreach_container_index_write 9:1 "the foreach index 'i' is read-only"
p29_diag foreach_container_redeclare 9:1 "cannot redeclare the foreach binding 'item'"
p29_diag foreach_container_map_i 11:1 "'i' has no meaning in a Map foreach; use item.key / item.value"
p29_diag container_copy 4:5 "a container is moved, not copied; use retain() or a function result"
p29_diag container_own 13:10 "a container cannot hold an 'own' or 'borrow' value"
# E29-12: the user template and the built-in container hit the same over-arity
# text; the built-in layer has no private branch.
p29_diag generic_struct_user_arity 10:21 "a generic struct takes at most 2 type parameters"
p29_diag generic_builtin_arity 5:19 "a generic struct takes at most 2 type parameters"
"$work/ct-ast" test/ast/errors/generic_builtin_arity.ct -o "$work/p29a1.c" \
    >"$work/p29a1.out" 2>"$work/p29a1.err"
p29a1_rc=$?
"$work/ct-ast" test/ast/errors/generic_struct_user_arity.ct -o "$work/p29a2.c" \
    >"$work/p29a2.out" 2>"$work/p29a2.err"
p29a2_rc=$?
if [ "$p29a1_rc" -eq 0 ] || [ "$p29a2_rc" -eq 0 ]; then
    bad "p29: E29-12 arity" "expected both fixtures to fail"
else
    sed 's/.*error: //' "$work/p29a1.err" | head -1 >"$work/p29a1.msg"
    sed 's/.*error: //' "$work/p29a2.err" | head -1 >"$work/p29a2.msg"
    if cmp -s "$work/p29a1.msg" "$work/p29a2.msg" \
       && [ "$(cat "$work/p29a1.msg")" = "a generic struct takes at most 2 type parameters" ]; then
        ok "p29 (E29-12 same arity text)"
    else
        bad "p29: E29-12 arity" "$(cat "$work/p29a1.msg" "$work/p29a2.msg" 2>/dev/null)"
    fi
fi

# E29-9: `ct check` and `ct build` report the same frozen diagnostic as the
# compile path. The three modes share the parser, so the first error line must
# be byte-identical.
for p29neg in container_copy container_own \
             generic_builtin_arity generic_struct_user_arity; do
    "$work/ct-ast" "test/ast/errors/$p29neg.ct" -o "$work/p29md.c" \
        >"$work/p29md1.out" 2>"$work/p29md1.err"
    "$work/ct-ast" check "test/ast/errors/$p29neg.ct" \
        >"$work/p29md2.out" 2>"$work/p29md2.err"
    "$work/ct-ast" build "test/ast/errors/$p29neg.ct" -o "$work/p29md" \
        --outdir "$work/p29mdd" >"$work/p29md3.out" 2>"$work/p29md3.err"
    grep 'error: ' "$work/p29md1.err" | head -1 >"$work/p29md1.msg"
    grep 'error: ' "$work/p29md2.err" | head -1 >"$work/p29md2.msg"
    grep 'error: ' "$work/p29md3.err" | head -1 >"$work/p29md3.msg"
    if cmp -s "$work/p29md1.msg" "$work/p29md2.msg" \
       && cmp -s "$work/p29md1.msg" "$work/p29md3.msg" \
       && [ -s "$work/p29md1.msg" ]; then
        ok "p29 (check/build agree on $p29neg)"
    else
        bad "p29: check/build $p29neg" "$(cat "$work/p29md1.msg" "$work/p29md2.msg" "$work/p29md3.msg" 2>/dev/null)"
    fi
done

# ---------------------------------------------------------------------------
# Phase 33 O1 (A block): bounded generic structs. The three diagnostics are the
# ones docs/design/phase33-draft.md 4 freezes (L33-1/2/3); the compile, check
# and build paths share the parser, so the first error line must agree (E33-20).
# ---------------------------------------------------------------------------
p33_diag() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p33e.c" \
            >"$work/p33e.out" 2>"$work/p33e.err"; then
        bad "p33: $1" "expected a diagnostic, got exit 0"
    elif ! grep -qF "test/ast/errors/$1.ct:$2: error: $3" "$work/p33e.err"; then
        bad "p33: $1" "missing pinned diagnostic: $(head -2 "$work/p33e.err")"
    elif [ "$(grep -c 'error: ' "$work/p33e.err")" -ne 1 ]; then
        bad "p33: $1" "expected exactly one error: $(cat "$work/p33e.err")"
    else
        ok "p33 ($1)"
    fi
}
p33_diag bound_unsatisfied 11:9 "instance argument 'int' does not satisfy the bound 'Show'"
p33_diag impl_bound_dup 9:9 "impl type parameter 'T' cannot repeat the bound 'Show'"
p33_diag multi_bound 8:17 "a struct type parameter cannot carry more than one bound"
for p33neg in bound_unsatisfied impl_bound_dup multi_bound; do
    "$work/ct-ast" "test/ast/errors/$p33neg.ct" -o "$work/p33md.c" \
        >"$work/p33md1.out" 2>"$work/p33md1.err"
    "$work/ct-ast" check "test/ast/errors/$p33neg.ct" \
        >"$work/p33md2.out" 2>"$work/p33md2.err"
    "$work/ct-ast" build "test/ast/errors/$p33neg.ct" -o "$work/p33mdd" \
        --outdir "$work/p33mdb" >"$work/p33md3.out" 2>"$work/p33md3.err"
    grep 'error: ' "$work/p33md1.err" | head -1 >"$work/p33md1.msg"
    grep 'error: ' "$work/p33md2.err" | head -1 >"$work/p33md2.msg"
    grep 'error: ' "$work/p33md3.err" | head -1 >"$work/p33md3.msg"
    if cmp -s "$work/p33md1.msg" "$work/p33md2.msg" \
       && cmp -s "$work/p33md1.msg" "$work/p33md3.msg" \
       && [ -s "$work/p33md1.msg" ]; then
        ok "p33 (check/build agree on $p33neg)"
    else
        bad "p33: check/build $p33neg" "$(cat "$work/p33md1.msg" "$work/p33md2.msg" "$work/p33md3.msg" 2>/dev/null)"
    fi
done

# E33-7..E33-12 (O2): the positive fixtures run in the behavioural loop above;
# here the negative texts are frozen, `ct check`/`build` must agree on each
# (E33-20), and the generated C must carry no pseudo instance (E33-10a) while
# keeping the measured nested encoding (E33-10b).
p33_diag nested_pattern_depth 3:32 "impl pattern nesting exceeds 4 levels"
p33_diag nested_pattern_wild 5:13 "unsupported impl pattern '_'"
p33_diag nested_pattern_arr 5:13 "unsupported impl pattern 'T[2]'"
p33_diag nested_pattern_ptr 5:13 "unsupported impl pattern 'T*'"
p33_diag nested_pattern_fnptr 5:13 "unsupported impl pattern 'int(*)(int)'"
p33_diag nested_pattern_mismatch 16:1 "no method 'pick' for type 'struct Pair_char_p_Box__int'"
p33_diag nested_pattern_repeat_mismatch 17:1 "no method 'same' for type 'struct Pair_int_Box__long'"

for p33o2 in nested_pattern_depth nested_pattern_wild nested_pattern_arr \
             nested_pattern_ptr nested_pattern_fnptr; do
    "$work/ct-ast" "test/ast/errors/$p33o2.ct" -o "$work/p33o2m.c" \
        >"$work/p33o2m1.out" 2>"$work/p33o2m1.err"
    "$work/ct-ast" check "test/ast/errors/$p33o2.ct" \
        >"$work/p33o2m2.out" 2>"$work/p33o2m2.err"
    "$work/ct-ast" build "test/ast/errors/$p33o2.ct" -o "$work/p33o2md" \
        --outdir "$work/p33o2mb" >"$work/p33o2m3.out" 2>"$work/p33o2m3.err"
    grep 'error: ' "$work/p33o2m1.err" | head -1 >"$work/p33o2m1.msg"
    grep 'error: ' "$work/p33o2m2.err" | head -1 >"$work/p33o2m2.msg"
    grep 'error: ' "$work/p33o2m3.err" | head -1 >"$work/p33o2m3.msg"
    if cmp -s "$work/p33o2m1.msg" "$work/p33o2m2.msg" \
       && cmp -s "$work/p33o2m1.msg" "$work/p33o2m3.msg" \
       && [ -s "$work/p33o2m1.msg" ]; then
        ok "p33 (check/build agree on $p33o2)"
    else
        bad "p33: check/build $p33o2" \
            "$(cat "$work/p33o2m1.msg" "$work/p33o2m2.msg" "$work/p33o2m3.msg" 2>/dev/null)"
    fi
done

rm -rf "$work/p33o2"
mkdir -p "$work/p33o2"
p33o2_bad=""
for p33o2n in 203_nested_pattern 204_nested_pattern_mixed 205_nested_pattern_repeat \
              206_nested_pattern_depth3; do
    if ! "$work/ct-ast" "test/ast/$p33o2n/prog.ct" -o "$work/p33o2/$p33o2n.c" \
            >"$work/p33o2/$p33o2n.out" 2>"$work/p33o2/$p33o2n.err"; then
        p33o2_bad="$p33o2_bad $p33o2n:compile"
    elif grep -qF 'struct Box_T' "$work/p33o2/$p33o2n.c"; then
        p33o2_bad="$p33o2_bad $p33o2n:pseudo"
    fi
done
if [ -n "$p33o2_bad" ]; then
    bad "p33: E33-10a" "pseudo instance or build failure:$p33o2_bad"
else
    ok "p33 (E33-10a no pseudo instance)"
fi

if grep -qF 'Box_Box__int' "$work/p33o2/206_nested_pattern_depth3.c" \
   && ! grep -qF 'Box_Box_int' "$work/p33o2/206_nested_pattern_depth3.c"; then
    ok "p33 (E33-10b nested encoding)"
else
    bad "p33: E33-10b" \
        "$(grep -o 'Box_Box[A-Za-z_]*int' "$work/p33o2/206_nested_pattern_depth3.c" | sort -u | tr '\n' ' ')"
fi

if grep -qF 'Box_Box__Circle_depth' "$work/p33o2/203_nested_pattern.c"; then
    ok "p33 (E33-7 nested dispatch keeps the instance prefix)"
else
    bad "p33: E33-7" \
        "$(grep -o 'Box_Box_[A-Za-z_]*' "$work/p33o2/203_nested_pattern.c" | sort -u | tr '\n' ' ')"
fi

# E33-3: the literal `Box<Box<Circle>>` lives in ast/201_bounded_nested, whose
# runnable path also proves no vptr is needed; the same shape under `int` is
# L33-1 through `errors/bound_unsatisfied`'s single-argument form.

# E33-4: an inherited bound body names the vtable and never reads a vptr; the
# only allowed occurrence is an interface assignment, which this body has none
# of. Everything else in the extracted function fails the slice.
rm -rf "$work/p33o4"
mkdir -p "$work/p33o4"
if ! "$work/ct-ast" test/ast/202_bound_inherit/prog.ct -o "$work/p33o4/prog.c" \
        >"$work/p33o4/out" 2>"$work/p33o4/err"; then
    bad "p33: E33-4 body" "$(head -2 "$work/p33o4/err")"
else
    awk '/Box_Circle_show\(void \*self\)/ { inb = 1 } inb { print } inb && /^\}/ { exit }' \
        "$work/p33o4/prog.c" >"$work/p33o4/body"
    if ! grep -qF "Circle_Show_vtable" "$work/p33o4/body"; then
        bad "p33: E33-4 body" "no static dispatch in: $(cat "$work/p33o4/body")"
    elif grep -v '\.__show_vptr =' "$work/p33o4/body" | grep -q '__show_vptr'; then
        bad "p33: E33-4 body" "a vptr is read: $(cat "$work/p33o4/body")"
    else
        ok "p33 (E33-4 static dispatch, no vptr)"
    fi
fi

# E29-5 / L29-W1: a project-local `vendor/std` is shadowed by the built-in
# layer, with one warning, and the decoy module inside it is never read.
repo_root=$(pwd)
( cd test/modules/p29_builtin_std \
  && CT_STD_DIR="$repo_root/lib/std" "$work/ct-ast" main.ct -o "$work/p29w1.c" ) \
  >"$work/p29w1.out" 2>"$work/p29w1.err"
if [ $? -eq 0 ] \
   && grep -Fq "the built-in Vec/Map supersede a project-local 'vendor/std' (ignored)" "$work/p29w1.err" \
   && grep -Fq "struct Vec_int" "$work/p29w1.c"; then
    if cc -Wall -Wextra -std=c99 "$work/p29w1.c" -o "$work/p29w1" \
            >"$work/p29w1.cc.out" 2>"$work/p29w1.cc.err" \
       && "$work/p29w1" >"$work/p29w1.run" 2>&1 \
       && cmp -s "$work/p29w1.run" test/modules/p29_builtin_std/expected.out; then
        ok "p29 (builtin_std shadow warning)"
    else
        bad "p29: builtin_std" "$(head -2 "$work/p29w1.cc.err")"
    fi
else
    bad "p29: builtin_std" "$(head -2 "$work/p29w1.err")"
fi

# E29-5: the built-in layer is containers only -- `std::str` still needs
# `ct get std`, so an uninstalled module must not resolve.
if "$work/ct-ast" build test/modules/p29_builtin_std/needs_std.ct -o "$work/p29e5" \
        >"$work/p29e5.out" 2>"$work/p29e5.err"; then
    bad "p29: builtin_std scope" "expected a resolve failure for std::str"
elif grep -Fq "cannot resolve import 'std/str'" "$work/p29e5.err"; then
    ok "p29 (builtin_std is containers only)"
else
    bad "p29: builtin_std scope" "$(head -2 "$work/p29e5.err")"
fi

# E29-5 on the `ct build` path: the same fixture (no import, no `ct get`) must
# compile as a multi-unit build, link, run and warn about `vendor/std`.
( cd test/modules/p29_builtin_std \
  && CT_STD_DIR="$repo_root/lib/std" "$work/ct-ast" build main.ct \
       -o "$work/p29w1b" --outdir "$work/p29w1bd" ) \
  >"$work/p29w1b.out" 2>"$work/p29w1b.err"
if [ $? -eq 0 ] \
   && grep -Fq "the built-in Vec/Map supersede a project-local 'vendor/std' (ignored)" "$work/p29w1b.err" \
   && grep -Fq "struct Vec_int" "$work/p29w1bd/Vec.h" \
   && "$work/p29w1b" >"$work/p29w1b.run" 2>&1 \
   && cmp -s "$work/p29w1b.run" test/modules/p29_builtin_std/expected.out; then
    ok "p29 (builtin_std in ct build)"
else
    bad "p29: builtin_std build" "$(head -3 "$work/p29w1b.err")"
fi

# E29-13 / B6: P34 S1b — L26-2 is lifted. A `pub` generic function in a `.h.ct`
# header now compiles, links and runs: the consumer emits its own `static`
# instance while the header unit writes none. The old negative fixture is gone
# and this positive case replaces it (E34-1).
rm -rf "$work/p34g"
if "$work/ct-ast" build test/modules/p34_pub_generic/main.ct -o "$work/p34g" \
        >"$work/p34g.out" 2>"$work/p34g.err" \
   && "$work/p34g" >"$work/p34g.stdout" 2>&1 \
   && cmp -s "$work/p34g.stdout" test/modules/p34_pub_generic/expected.out; then
    ok "p29→p34 (a pub generic function runs across units)"
else
    bad "p29→p34 pub generic" "$(cat "$work/p34g.err" "$work/p34g.stdout" 2>/dev/null)"
fi

# P34 S2b: each unit numbers its own static instances from one. The owner
# (lib.h.ct) instantiates id<long> and the consumer (main.ct) id<int>; both
# must spell their copy id__ct1. Before S2b the consumer leaked the global
# counter and got id__ct2.
rm -rf "$work/p34g-emit"
mkdir -p "$work/p34g-emit"
if "$work/ct-ast" build --emit-c test/modules/p34_pub_generic/main.ct \
        -o "$work/p34g-emit" >"$work/p34ge.out" 2>"$work/p34ge.err" \
   && grep -q 'id__ct1' "$work/p34g-emit/main.c" \
   && ! grep -q 'id__ct2' "$work/p34g-emit/main.c"; then
    ok "p34 S2b (consumer instance is id__ct1, per-owner numbering)"
else
    bad "p34 S2b per-owner numbering" \
        "$(cat "$work/p34ge.err" 2>/dev/null | head -2) :: $(grep -oE 'id__ct[0-9_]+' "$work/p34g-emit/main.c" 2>/dev/null | sort -u | tr '\n' ' ')"
fi

# 144: one C struct per instance, and an inherent method per instance.
"$work/ct-ast" test/ast/144_generic_struct_user/prog.ct -o "$work/p29s.c" \
    >"$work/p29s.out" 2>"$work/p29s.err"
if [ $? -ne 0 ]; then
    bad "p29: generic struct shape" "ct-ast failed: $(head -3 "$work/p29s.err")"
elif ! grep -q 'struct Stack_int {' "$work/p29s.c"; then
    bad "p29: generic struct shape" "no struct Stack_int"
elif ! grep -q 'struct Stack_char_p {' "$work/p29s.c"; then
    bad "p29: generic struct shape" "no struct Stack_char_p"
elif ! grep -q 'Stack_int_top(' "$work/p29s.c"; then
    bad "p29: generic struct shape" "inherent method is not <Instance>_<method>"
else
    ok "p29 (generic struct instances and inherent method names)"
fi

# E29-1: two instances of the same user template become two distinct C tags,
# each with its fields substituted (`Pair<int, char *>` and `Pair<int, int>`).
"$work/ct-ast" test/ast/138_generic_struct/prog.ct -o "$work/p29g.c" \
    >"$work/p29g.out" 2>"$work/p29g.err"
if [ $? -ne 0 ]; then
    bad "p29: pair tags" "ct-ast failed: $(head -3 "$work/p29g.err")"
elif ! grep -q 'struct Pair_int_char_p {' "$work/p29g.c"; then
    bad "p29: pair tags" "no struct Pair_int_char_p"
elif ! grep -q 'struct Pair_int_int {' "$work/p29g.c"; then
    bad "p29: pair tags" "no struct Pair_int_int"
else
    ok "p29 (two instances, two distinct tags)"
fi

# 147: a pattern argument narrows the impl; `use` keeps the trait/vptr path.
"$work/ct-ast" test/ast/147_generic_impl/prog.ct -o "$work/p29i.c" \
    >"$work/p29i.out" 2>"$work/p29i.err"
if [ $? -ne 0 ]; then
    bad "p29: generic impl" "ct-ast failed: $(head -3 "$work/p29i.err")"
elif ! grep -q 'Pair_int_int_second(' "$work/p29i.c"; then
    bad "p29: generic impl" "no Pair_int_int_second"
elif ! grep -q 'Stack_int_Show_show(' "$work/p29i.c"; then
    bad "p29: generic impl" "no Stack_int_Show_show"
elif ! grep -q 'Stack_int_Show_vtable' "$work/p29i.c"; then
    bad "p29: generic impl" "the use block published no vtable"
else
    ok "p29 (impl pattern narrows, use keeps the vtable)"
fi

# 140/141: the container loop reads its length once and steps through the
# inherent getter; only an array or a `Vec` prints the `i` binding.
"$work/ct-ast" test/ast/140_foreach_vec/prog.ct -o "$work/p29v.c" \
    >"$work/p29v.out" 2>"$work/p29v.err"
if [ $? -ne 0 ]; then
    bad "p29: foreach Vec" "ct-ast failed: $(head -3 "$work/p29v.err")"
elif ! grep -q 'Vec_int_get(__ct_foreach_c_' "$work/p29v.c"; then
    bad "p29: foreach Vec" "the loop does not call Vec_int_get"
elif ! grep -q 'int i = __ct_foreach_i_' "$work/p29v.c"; then
    bad "p29: foreach Vec" "no i binding"
elif ! grep -q '__ct_foreach_n_' "$work/p29v.c"; then
    bad "p29: foreach Vec" "the length is not snapshotted before the loop"
elif ! grep -q '(void)i;' "$work/p29v.c"; then
    bad "p29: foreach Vec" "i is not voided"
else
    ok "p29 (foreach Vec walks get with an i binding)"
fi
"$work/ct-ast" test/ast/141_foreach_map/prog.ct -o "$work/p29m.c" \
    >"$work/p29m.out" 2>"$work/p29m.err"
if [ $? -ne 0 ]; then
    bad "p29: foreach Map" "ct-ast failed: $(head -3 "$work/p29m.err")"
elif ! grep -q 'Map_char_p_int_entry(__ct_foreach_c_' "$work/p29m.c"; then
    bad "p29: foreach Map" "the loop does not call Map_char_p_int_entry"
elif grep -q 'int i = __ct_foreach_i_' "$work/p29m.c"; then
    bad "p29: foreach Map" "a Map body must not bind i"
else
    ok "p29 (foreach Map walks entry without an index)"
fi
# E29-3: two compilations of the same input agree byte for byte, and two runs
# of the linked program print the same bytes (the Map keeps insertion order).
"$work/ct-ast" test/ast/141_foreach_map/prog.ct -o "$work/p29m2.c" \
    >"$work/p29m2.out" 2>"$work/p29m2.err" \
  && cc -Wall -Wextra -std=c99 "$work/p29m.c" -o "$work/p29m" \
    >"$work/p29mcc.out" 2>"$work/p29mcc.err" \
  && "$work/p29m" >"$work/p29mrun1.out" 2>&1 \
  && "$work/p29m" >"$work/p29mrun2.out" 2>&1
if [ $? -ne 0 ]; then
    bad "p29: Map determinism" "$(head -2 "$work/p29m2.err" "$work/p29mcc.err")"
elif ! cmp -s "$work/p29m.c" "$work/p29m2.c"; then
    bad "p29: Map determinism" "two compilations differ"
elif ! cmp -s "$work/p29mrun1.out" "$work/p29mrun2.out"; then
    bad "p29: Map determinism" "two runs differ"
else
    ok "p29 (Map: two builds and two runs agree)"
fi

# 139: `>>` closes two argument lists; the compressed name stays stable.
"$work/ct-ast" test/ast/139_generic_struct_two/prog.ct -o "$work/p29n.c" \
    >"$work/p29n.out" 2>"$work/p29n.err"
if [ $? -ne 0 ]; then
    bad "p29: nested arguments" "ct-ast failed: $(head -3 "$work/p29n.err")"
elif ! grep -q 'struct Box_Box__Box____int {' "$work/p29n.c"; then
    bad "p29: nested arguments" "no Box_Box__Box____int"
else
    ok "p29 (>> splits, nested instance name is stable)"
fi

# Cross-unit: the template's unit publishes the instance definitions, and a
# second unit that names the same instance does not redefine it (D29-9).
p29mod_src=test/modules/p29_generic_struct
rm -rf "$work/p29mod"
mkdir -p "$work/p29mod"
if ! "$work/ct-ast" build --emit-c -I "$p29mod_src" "$p29mod_src/main.ct" -o "$work/p29mod" \
        >"$work/p29mod.out" 2>"$work/p29mod.err"; then
    bad "p29: cross-unit instances" "$(head -3 "$work/p29mod.err")"
elif [ "$(grep -c 'struct Pair_int_int {' "$work/p29mod/shapes.h")" -ne 1 ]; then
    bad "p29: cross-unit instances" "shapes.h does not publish the instance once"
elif grep -q 'struct Pair_int_int {' "$work/p29mod/two.h"; then
    bad "p29: cross-unit instances" "two.h redefines the instance"
elif ! "$CC" -Wall -Wextra -std=c99 -I "$work/p29mod" "$work/p29mod"/*.c \
        -o "$work/p29mod.bin" 2>"$work/p29mod.cc"; then
    bad "p29: cross-unit instances" "$(head -3 "$work/p29mod.cc")"
elif ! "$work/p29mod.bin" >"$work/p29mod.stdout" 2>&1 \
        || ! cmp -s "$work/p29mod.stdout" "$p29mod_src/expected.out"; then
    bad "p29: cross-unit instances" "$(cat "$work/p29mod.stdout")"
else
    ok "p29 (the template's unit publishes the instance; a second unit reuses it)"
fi

# ---- Phase 29 P29: the range initialiser builds a `Vec<T>` ----
# P29-1/P29-3: `4..8 { $ * $ }` is pure lowering -- the emitter writes a
# composite literal and hands it to `Vec_<enc>_from`, and the container's fields
# never enter the compiler (the generated `.c` has no `->h` / `->data` here).
"$work/ct-ast" examples/26_range_vec/range_vec.ct -o "$work/p29rv.c" \
    >"$work/p29rv.out" 2>"$work/p29rv.err"
if [ $? -ne 0 ]; then
    bad "p29 P29-1: range Vec" "ct-ast failed: $(head -3 "$work/p29rv.err")"
elif ! grep -Fq 'Vec_int_from((int[4]){ ' "$work/p29rv.c"; then
    bad "p29 P29-1: range Vec" "no composite literal handed to Vec_int_from"
elif ! grep -Fq 'Vec_char_p_from(' "$work/p29rv.c"; then
    bad "p29 P29-1: range Vec" "the static entry is not callable from source"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/p29rv.c" -o "$work/p29rv.bin" \
        2>"$work/p29rv.cc" \
      || ! "$work/p29rv.bin" >"$work/p29rv.run" 2>&1; then
    bad "p29 P29-1: range Vec" "$(head -4 "$work/p29rv.cc")"
elif ! diff -u examples/26_range_vec/range_vec.expected.out "$work/p29rv.run" \
        >"$work/p29rv.diff"; then
    bad "p29 P29-1: range Vec" "$(head -6 "$work/p29rv.diff")"
else
    ok "p29 P29-1 (range initialiser builds a Vec through the entry)"
fi
# P29-2: `$` scope, empty range, the 1024 cap and a `Map` target each keep a
# single positioned diagnostic -- never an `undeclared` fallback.
# $1 fixture name, $2 expected wording, $3 its `line:col`. A negative fixture is
# only evidence when the diagnostic is the promised one, positioned, and the
# single error -- not an `undeclared` fallback or a cascade.
p29_neg() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p29neg.c" \
            >"$work/p29neg.out" 2>"$work/p29neg.err"; then
        bad "p29: $1" "expected a diagnostic, got exit 0"
    elif ! grep -Fq "$2" "$work/p29neg.err"; then
        bad "p29: $1" "$(cat "$work/p29neg.err")"
    elif grep -Fiq 'undeclared' "$work/p29neg.err"; then
        bad "p29: $1" "fell back to 'undeclared': $(cat "$work/p29neg.err")"
    elif [ "$(grep -c 'error:' "$work/p29neg.err")" -ne 1 ]; then
        bad "p29: $1" "expected exactly one diagnostic: $(cat "$work/p29neg.err")"
    elif ! grep -Fq "test/ast/errors/$1.ct:$3: error:" "$work/p29neg.err"; then
        bad "p29: $1" "expected the diagnostic at $3: $(cat "$work/p29neg.err")"
    else
        ok "p29 ($1: $2 at $3)"
    fi
}
p29_neg range_vec_index_scope "unexpected token" 8:9
p29_neg range_vec_empty "an empty range has no elements" 6:18
p29_neg range_vec_too_many "too many range elements (limit 1024)" 6:18
p29_neg range_vec_map_target "a range initializer declares an array" 6:26
p29_neg impl_static_trait "a static method cannot implement a trait" 13:5
p29_neg generic_impl_missing_method "no method 'nope' for type 'struct Pair_int_int'" 20:1
p29_neg container_vptr_struct "interface and vptr-bearing values cannot be stored in a container" 13:14
# ---- Phase 31 S11b: the `Vec` brace initializer's local boundaries ----
# Five boundaries keep one positioned diagnostic each: a known element type
# that does not fit (L31-6), an element whose type cannot be pinned (L31-7), a
# nested brace list (L31-9), a file-scope list (L31-10) and an assignment
# (L31-11). The 1024 cap (L31-8) is generated below so the fixture stays
# compact, and 1024 elements stay a positive case.
p29_neg L31_6_vec_elem_type "initializer element 1 has type 'char *', expected 'int'" 5:19
p29_neg L31_7_vec_elem_unknown "cannot determine the type of initializer element 1" 7:19
p29_neg L31_9_vec_nested_brace "a brace list cannot appear inside another brace initializer; build the inner container first" 5:24
p29_neg L31_10_vec_global_brace "a Vec brace initializer is only supported in a local declaration" 3:14
p29_neg L31_11_vec_brace_assign "a brace list is not an expression; use Vec<T>::from or push" 6:9
# Phase 31 O3 (E31-10): the five write forms of a subscript each report once,
# at the subscript's own position, with the read-only / address text.
p29_neg L31_3_vec_assign "a Vec subscript is read-only; use set(i, v)" 8:6
p29_neg L31_3_vec_compound "a Vec subscript is read-only; use set(i, v)" 8:6
p29_neg L31_3_vec_inc "a Vec subscript is read-only; use set(i, v)" 7:6
p29_neg L31_3_vec_member_assign "a Vec subscript is read-only; use set(i, v)" 16:6
p29_neg L31_4_map_assign "a Map subscript is read-only; use put(k, v)" 7:6
p29_neg L31_5_vec_addr "cannot take the address of a container subscript; bind it to a local first" 7:16
# S20b review: the instance tag is a C struct name, and a nested key is
# reported by that tag.
p29_neg L31_inst_tag_collision "the instance name 'Vec_int' collides with a declared struct" 11:14
p29_neg L31_nested_map_key "Map does not support key type 'struct Vec_int' (use int, long or char *)" 7:24
# ---- Phase 31 S23a: a borrowed view carries no ownership ----
# The bit lives on the local symbol and is set from `get` / `entry` / `foreach
# item` (and propagated through an assignment), so every release form below is
# refused at the method name rather than at a later C error.
p29_neg L31_14_borrowed_release "cannot release a borrowed container view; call retain() first" 11:7
p29_neg L31_14_copy_release "cannot release a borrowed container view; call retain() first" 14:7
p29_neg L31_14_copy_init "cannot release a borrowed container view; call retain() first" 12:7
p29_neg L31_14_assign "cannot release a borrowed container view; call retain() first" 12:7
p29_neg L31_13_foreach_release "cannot release a borrowed container view; call retain() first" 11:14
p29_neg L31_14_chain_release "cannot release a borrowed container view; call retain() first" 10:14
# ---- Phase 31 S23b: no mutation while iterating, no stale view ----
# Each fixture carries exactly one item, so the automatic sweep above and the
# pinned text below both see a single positioned diagnostic.
p29_neg L31_22_clear "cannot mutate the container being iterated; take a copy or collect the indices first" 8:12
p29_neg L31_22_remove "cannot mutate the container being iterated; take a copy or collect the indices first" 8:11
p29_neg L31_22_set "cannot mutate the container being iterated; take a copy or collect the indices first" 8:12
p29_neg L31_22_put "cannot mutate the container being iterated; take a copy or collect the indices first" 8:11
p29_neg L31_22_push "cannot mutate the container being iterated; take a copy or collect the indices first" 8:12
p29_neg L31_23_get_ptr "a borrowed view is invalidated by a later mutation of its container; copy it with retain() first" 9:21
p29_neg L31_23_entry "a borrowed view is invalidated by a later mutation of its container; copy it with retain() first" 11:13
# 1025 elements: the cap refuses the list before any element is materialised.
{
    printf 'int main(void)\n{\n    Vec<int> v = {'
    i=1
    while [ "$i" -le 1025 ]; do
        if [ "$i" -gt 1 ]; then printf ', '; fi
        printf '1'
        i=$((i + 1))
    done
    printf '};\n    return v.len();\n}\n'
} >"$work/p31b1025.ct"
if "$work/ct-ast" "$work/p31b1025.ct" -o "$work/p31b1025.c" \
        >"$work/p31b1025.out" 2>"$work/p31b1025.err"; then
    bad "p31 L31-8: 1025 elements" "expected a diagnostic, got exit 0"
elif ! grep -Fq 'too many initializer elements (limit 1024)' "$work/p31b1025.err"; then
    bad "p31 L31-8: 1025 elements" "$(cat "$work/p31b1025.err")"
elif [ "$(grep -c 'error:' "$work/p31b1025.err")" -ne 1 ]; then
    bad "p31 L31-8: 1025 elements" "expected exactly one diagnostic: $(cat "$work/p31b1025.err")"
else
    ok "p31 (L31-8: a 1025-element list is refused at the cap)"
fi
# 1024 elements remain a positive case and run.
{
    printf '#include <stdio.h>\n\nint main(void)\n{\n    Vec<int> v = {'
    i=1
    while [ "$i" -le 1024 ]; do
        if [ "$i" -gt 1 ]; then printf ', '; fi
        printf '1'
        i=$((i + 1))
    done
    printf '};\n    printf("%%d\\n", v.len());\n    v.release();\n    return 0;\n}\n'
} >"$work/p31b1024.ct"
"$work/ct-ast" "$work/p31b1024.ct" -o "$work/p31b1024.c" \
    >"$work/p31b1024.out" 2>"$work/p31b1024.err"
if [ $? -ne 0 ]; then
    bad "p31 1024 elements" "ct-ast failed: $(head -3 "$work/p31b1024.err")"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/p31b1024.c" -o "$work/p31b1024.bin" \
        2>"$work/p31b1024.cc" \
      || ! "$work/p31b1024.bin" >"$work/p31b1024.run" 2>&1; then
    bad "p31 1024 elements" "$(head -4 "$work/p31b1024.cc")"
elif ! grep -qx '1024' "$work/p31b1024.run"; then
    bad "p31 1024 elements" "$(cat "$work/p31b1024.run")"
else
    ok "p31 (a 1024-element list builds and reports its length)"
fi

# ---- Phase 31 S16b: the `Map` literal's boundaries ----
# The key slot (L31-17), a file-scope list (L31-19) and an assignment (L31-20)
# each keep one positioned diagnostic. The 1024 cap (L31-18) is generated below
# so the fixture stays compact, and 1024 items stay a positive case.
p29_neg L31_17_map_key_type "initializer item 1 has key type 'int', expected 'char *'" 5:27
p29_neg L31_16_map_dup_enum "duplicate key 'RED' in a Map initializer (first at line 7)" 7:41
p29_neg L31_16_map_dup_int_fold "duplicate key '2' in a Map initializer (first at line 5)" 5:34
p29_neg L31_16_map_dup_str_escape "duplicate key 'a' in a Map initializer (first at line 5)" 5:38
p29_neg L31_16_map_dup_str_concat "duplicate key 'ab' in a Map initializer (first at line 5)" 5:39
p29_neg L31_19_map_global_brace "a Map brace initializer is only supported in a local declaration" 3:22
p29_neg L31_20_map_brace_assign "a brace list is not an expression; use Map<K, V>::from or put" 6:9
{
    printf 'int main(void)\n{\n    Map<int, int> m = {'
    i=1
    while [ "$i" -le 1025 ]; do
        if [ "$i" -gt 1 ]; then printf ', '; fi
        printf '%d: 1' "$i"
        i=$((i + 1))
    done
    printf '};\n    return m.len();\n}\n'
} >"$work/p31m1025.ct"
if "$work/ct-ast" "$work/p31m1025.ct" -o "$work/p31m1025.c" \
        >"$work/p31m1025.out" 2>"$work/p31m1025.err"; then
    bad "p31 L31-18: 1025 items" "expected a diagnostic, got exit 0"
elif ! grep -Fq 'too many initializer items (limit 1024)' "$work/p31m1025.err"; then
    bad "p31 L31-18: 1025 items" "$(cat "$work/p31m1025.err")"
elif [ "$(grep -c 'error:' "$work/p31m1025.err")" -ne 1 ]; then
    bad "p31 L31-18: 1025 items" "expected exactly one diagnostic: $(cat "$work/p31m1025.err")"
else
    ok "p31 (L31-18: a 1025-item map is refused at the cap)"
fi
{
    printf '#include <stdio.h>\n\nint main(void)\n{\n    Map<int, int> m = {'
    i=1
    while [ "$i" -le 1024 ]; do
        if [ "$i" -gt 1 ]; then printf ', '; fi
        printf '%d: 1' "$i"
        i=$((i + 1))
    done
    printf '};\n    printf("%%d\\n", m.len());\n    m.release();\n    return 0;\n}\n'
} >"$work/p31m1024.ct"
"$work/ct-ast" "$work/p31m1024.ct" -o "$work/p31m1024.c" \
    >"$work/p31m1024.out" 2>"$work/p31m1024.err"
if [ $? -ne 0 ]; then
    bad "p31 1024 map items" "ct-ast failed: $(head -3 "$work/p31m1024.err")"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/p31m1024.c" -o "$work/p31m1024.bin" \
        2>"$work/p31m1024.cc" \
      || ! "$work/p31m1024.bin" >"$work/p31m1024.run" 2>&1; then
    bad "p31 1024 map items" "$(head -4 "$work/p31m1024.cc")"
elif ! grep -qx '1024' "$work/p31m1024.run"; then
    bad "p31 1024 map items" "$(cat "$work/p31m1024.run")"
else
    ok "p31 (a 1024-item map builds and reports its length)"
fi

# ---- Phase 29 V29-1: separate key blocks, no `sizeof` guess ----
# A `long` key is as wide as a pointer on LP64, so the generic block compares it
# by bytes; the `char *` block declared first owns `put` / `get` / `remove` for
# string keys and the emitter skips the shadowed duplicates.
cat >"$work/p29ml.ct" <<'EOF'
int main(void)
{
    Map<long, int> m;
    m.h = 0;
    return m.put(1L, 2) - 1;
}
EOF
"$work/ct-ast" "$work/p29ml.ct" -o "$work/p29ml.c" >"$work/p29ml.out" 2>"$work/p29ml.err"
if [ $? -ne 0 ]; then
    bad "p29 V29-1: Map<long>" "ct-ast failed: $(head -3 "$work/p29ml.err")"
elif [ "$(grep -c 'Map_long_int_put(void \*self' "$work/p29ml.c")" -ne 1 ]; then
    bad "p29 V29-1: Map<long>" "expected exactly one definition of Map_long_int_put"
elif grep -q 'strcmp' "$work/p29ml.c"; then
    bad "p29 V29-1: Map<long>" "the generated C still compares a long key with strcmp"
elif ! grep -q 'memcmp' "$work/p29ml.c"; then
    bad "p29 V29-1: Map<long>" "the generated C does not compare the long key by bytes"
else
    ok "p29 V29-1 (a long key takes the byte comparison; no strcmp in the product)"
fi
"$work/ct-ast" examples/27_map_keys/map_keys.ct -o "$work/p29mk.c" \
    >"$work/p29mk.out" 2>"$work/p29mk.err"
if [ $? -ne 0 ]; then
    bad "p29 V29-1: Map keys" "ct-ast failed: $(head -3 "$work/p29mk.err")"
elif [ "$(grep -c 'Map_char_p_int_put(void \*self' "$work/p29mk.c")" -ne 1 ]; then
    bad "p29 V29-1: Map keys" "the string and the generic block both emitted Map_char_p_int_put"
elif [ "$(grep -c 'Map_char_p_int_get(void \*self' "$work/p29mk.c")" -ne 1 ]; then
    bad "p29 V29-1: Map keys" "the string and the generic block both emitted Map_char_p_int_get"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/p29mk.c" -o "$work/p29mk.bin" \
        2>"$work/p29mk.cc" \
      || ! "$work/p29mk.bin" >"$work/p29mk.run" 2>&1; then
    bad "p29 V29-1: Map keys" "$(head -4 "$work/p29mk.cc")"
elif ! diff -u examples/27_map_keys/map_keys.expected.out "$work/p29mk.run" \
        >"$work/p29mk.diff"; then
    bad "p29 V29-1: Map keys" "$(head -6 "$work/p29mk.diff")"
else
    ok "p29 V29-1 (int / long / char * keys: one definition each, expected output)"
fi
p29_neg map_key_bad "Map does not support key type 'char' (use int, long or char *)" 6:20

# ---- Phase 29 V29-2: a released handle cannot be released twice ----
# `v.retain()` makes a second handle; releasing `v` twice must not decrement the
# count the sibling still owns (that freed the buffer while `w` was live).
cat >"$work/p29dr.ct" <<'EOF'
#include <stdio.h>

int main(void)
{
    Vec<int> v;
    Vec<int> w;
    v.h = 0;
    v.push(41);
    w = v.retain();
    v.release();
    printf("sibling %d\n", w.len());
    fflush(stdout);
    v.release();
    printf("unreachable\n");
    return 0;
}
EOF
if ! "$work/ct-ast" "$work/p29dr.ct" -o "$work/p29dr.c" >"$work/p29dr.out" 2>"$work/p29dr.err"; then
    bad "p29 V29-2: double release" "ct-ast failed: $(head -3 "$work/p29dr.err")"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/p29dr.c" -o "$work/p29dr.bin" \
        2>"$work/p29dr.cc"; then
    bad "p29 V29-2: double release" "$(head -4 "$work/p29dr.cc")"
else
    { "$work/p29dr.bin" >"$work/p29dr.run" 2>"$work/p29dr.stderr"; p29dr_rc=$?; } 2>/dev/null
    if [ "$p29dr_rc" -eq 0 ]; then
        bad "p29 V29-2: double release" "a second release on a released handle exited 0"
    elif ! grep -Fq 'sibling 1' "$work/p29dr.run"; then
        bad "p29 V29-2: double release" "the retained sibling was not readable: $(cat "$work/p29dr.run")"
    elif ! grep -Fq 'Vec: release on a released handle' "$work/p29dr.stderr"; then
        bad "p29 V29-2: double release" "$(cat "$work/p29dr.stderr")"
    else
        ok "p29 V29-2 (a second release aborts; the retained sibling stays readable)"
    fi
fi

# ---- Phase 30: the receiver-context block (`expr into { … }`) ----
p30_neg() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p30neg.c" \
            >"$work/p30neg.out" 2>"$work/p30neg.err"; then
        bad "p30: $1" "expected a diagnostic, got exit 0"
    elif ! grep -Fq "$2" "$work/p30neg.err"; then
        bad "p30: $1" "$(cat "$work/p30neg.err")"
    elif grep -Fiq 'undeclared' "$work/p30neg.err"; then
        bad "p30: $1" "fell back to 'undeclared': $(cat "$work/p30neg.err")"
    elif [ "$(grep -c 'error:' "$work/p30neg.err")" -ne 1 ]; then
        bad "p30: $1" "expected exactly one diagnostic: $(cat "$work/p30neg.err")"
    elif ! grep -Fq "test/ast/errors/$1.ct:$3: error:" "$work/p30neg.err"; then
        bad "p30: $1" "expected the diagnostic at $3: $(cat "$work/p30neg.err")"
    else
        ok "p30 ($1: $2 at $3)"
    fi
}
p30_neg into_not_allowed "'into' block is not allowed here" 12:12
p30_neg into_bad_left "'into' needs a variable, field or call on its left" 11:11
p30_neg into_unknown_type "cannot determine the receiver type of this 'into' block" 6:10
p30_neg into_iface "'into' cannot take an interface or 'own' receiver" 13:7
p30_neg into_own "'into' cannot take an interface or 'own' receiver" 15:7
p30_neg into_missing_member "no member 'nope' on the 'into' receiver" 9:15
p30_neg into_rvalue_stmt "an 'into' statement needs a writable receiver" 16:12
p30_neg into_nested "nested 'into' blocks are not supported" 11:11
p30_neg into_recv_reserved "identifier '__ct_' is reserved for the compiler" 4:16

# E30-6: `ct check` shares the parser diagnostics, so every negative fails in
# check mode with the same wording and position.
p30_chk() {
    if "$work/ct-ast" check "test/ast/errors/$1.ct" \
            >"$work/p30chk.out" 2>"$work/p30chk.err"; then
        bad "p30 check: $1" "expected a non-zero exit"
    elif ! grep -Fq "test/ast/errors/$1.ct:$2: error: $3" "$work/p30chk.err"; then
        bad "p30 check: $1" "$(head -2 "$work/p30chk.err")"
    else
        ok "p30 check ($1: same wording under ct check)"
    fi
}
p30_chk into_not_allowed 12:12 "'into' block is not allowed here"
p30_chk into_bad_left 11:11 "'into' needs a variable, field or call on its left"
p30_chk into_unknown_type 6:10 "cannot determine the receiver type of this 'into' block"
p30_chk into_iface 13:7 "'into' cannot take an interface or 'own' receiver"
p30_chk into_own 15:7 "'into' cannot take an interface or 'own' receiver"
p30_chk into_missing_member 9:15 "no member 'nope' on the 'into' receiver"
p30_chk into_rvalue_stmt 16:12 "an 'into' statement needs a writable receiver"
p30_chk into_nested 11:11 "nested 'into' blocks are not supported"
p30_chk into_recv_reserved 4:16 "identifier '__ct_' is reserved for the compiler"

# E30-8: a static-map type host expands at the use site, so the program unit
# names the recipe's C function and carries no wrapper, vtable or boxed value.
p30_bare() {
    d="test/ast/$1"
    rm -rf "$work/p30bare"
    mkdir -p "$work/p30bare"
    incs=""
    for h in $(find "$d" -name '*.shim.h'); do incs="$incs -I $(dirname "$h")"; done
    if ! "$work/ct-ast" build --emit-c "$d/prog.ct" $incs -o "$work/p30bare" \
            >"$work/p30bare.log" 2>&1; then
        bad "p30 E30-8 ($1)" "build failed: $(head -3 "$work/p30bare.log")"
    elif ! grep -Fq "$2" "$work/p30bare/prog.c"; then
        bad "p30 E30-8 ($1)" "the product does not call $2 directly"
    elif grep -Eq '_vtable|_iface|_vtbl' "$work/p30bare/prog.c"; then
        bad "p30 E30-8 ($1)" "the product carries a wrapper or vtable: $(grep -E '_vtable|_iface|_vtbl' "$work/p30bare/prog.c" | head -2)"
    else
        ok "p30 E30-8 ($1: bare C call, no wrapper or vtable)"
    fi
}
p30_bare 153_into_type_host ct_file_write
p30_bare 155_into_value_host builder_add
p30_bare 156_into_scalar ct_twice

# E30-2: the receiver is evaluated exactly once, and the product contains
# neither `$` nor an `into {` block.
cat >"$work/p30rc.ct" <<'EOF'
#include <stdio.h>

int calls = 0;

struct Box { int n; };

struct Box build_box(void)
{
    struct Box b;
    b.n = 1;
    calls = calls + 1;
    return b;
}

int main(void)
{
    struct Box v = build_box() into {
        .n = 4;
    };
    printf("%d %d\n", v.n, calls);
    return 0;
}
EOF
if ! "$work/ct-ast" "$work/p30rc.ct" -o "$work/p30rc.c" \
        >"$work/p30rc.out" 2>"$work/p30rc.err"; then
    bad "p30 E30-2" "ct-ast failed: $(head -3 "$work/p30rc.err")"
elif [ "$(grep -c 'build_box()' "$work/p30rc.c")" -ne 1 ]; then
    bad "p30 E30-2" "the receiver expression was emitted $(grep -c 'build_box()' "$work/p30rc.c") times"
elif [ "$(grep -c '\$' "$work/p30rc.c")" -ne 0 ]; then
    bad "p30 E30-2" "the generated C still contains '\$'"
elif [ "$(grep -c 'into {' "$work/p30rc.c")" -ne 0 ]; then
    bad "p30 E30-2" "the generated C still contains 'into {'"
elif ! "$CC" -Wall -Wextra -std=c99 "$work/p30rc.c" -o "$work/p30rc.bin" \
        2>"$work/p30rc.cc" \
      || ! "$work/p30rc.bin" >"$work/p30rc.run" 2>&1; then
    bad "p30 E30-2" "$(head -4 "$work/p30rc.cc")"
elif [ "$(cat "$work/p30rc.run")" != "4 1" ]; then
    bad "p30 E30-2" "expected '4 1', got '$(cat "$work/p30rc.run")'"
else
    ok "p30 E30-2 (one evaluation, no '\$', no 'into {' in the product)"
fi

# E30-2 (fixture 159): each statement's receiver expression is emitted exactly
# once -- two statements, so exactly two `make_box()` calls in the product --
# and the product contains neither `$` nor an `into {` block.
if ! "$work/ct-ast" test/ast/159_into_once/prog.ct -o "$work/p159.c" \
        >"$work/p159.out" 2>"$work/p159.err"; then
    bad "p30 E30-2 (159)" "ct-ast failed: $(head -3 "$work/p159.err")"
elif [ "$(grep -c 'make_box()' "$work/p159.c")" -ne 2 ]; then
    bad "p30 E30-2 (159)" "the receiver was emitted $(grep -c 'make_box()' "$work/p159.c") times, expected 2"
elif [ "$(grep -c '\$' "$work/p159.c")" -ne 0 ]; then
    bad "p30 E30-2 (159)" "the generated C still contains '\$'"
elif [ "$(grep -c 'into {' "$work/p159.c")" -ne 0 ]; then
    bad "p30 E30-2 (159)" "the generated C still contains 'into {'"
else
    ok "p30 E30-2 (159: one evaluation per statement, no '\$', no 'into {')"
fi

# E30-9: the comparison groups of §3.1. A group is two sources -- the `into`
# version (`prog.ct`) and the hand-written one (`hand.ct`) -- that must compile,
# run to the same output, and emit byte-identical C after the frozen
# normalisation: drop the banner, drop `#line`, fold `__ct_recv<N>` to
# `__ct_recvN`.
p30_cmp() {
    d="test/ast/$1"
    # A group whose sources import a mapping or a header unit cannot use
    # compile mode; each side is built on its own and the main unit's product
    # is the one that must match.
    if [ -n "$(find "$d" \( -name '*.m.ct' -o -name '*.h.ct' \) -print -quit)" ]; then
        incs=""
        for h in $(find "$d" -name '*.shim.h'); do incs="$incs -I $(dirname "$h")"; done
        rm -rf "$work/p30$1.pd" "$work/p30$1.hd"
        mkdir -p "$work/p30$1.pd" "$work/p30$1.hd"
        if ! "$work/ct-ast" build --emit-c "$d/prog.ct" $incs \
                -o "$work/p30$1.pd" >"$work/p30$1.po" 2>&1; then
            bad "p30 E30-9 ($1)" "build failed on prog.ct: $(head -3 "$work/p30$1.po")"
            return
        elif ! "$work/ct-ast" build --emit-c "$d/hand.ct" $incs \
                -o "$work/p30$1.hd" >"$work/p30$1.ho" 2>&1; then
            bad "p30 E30-9 ($1)" "build failed on hand.ct: $(head -3 "$work/p30$1.ho")"
            return
        fi
        pc="$work/p30$1.pd/prog.c"
        hc="$work/p30$1.hd/hand.c"
        if ! "$CC" -Wall -Wextra -std=c99 $incs -I "$work/p30$1.pd" \
                "$work/p30$1.pd"/*.c $(find "$d" -name '*.shim.c') \
                -o "$work/p30$1.pb" 2>"$work/p30$1.pc" \
                || ! "$work/p30$1.pb" >"$work/p30$1.pr" 2>&1; then
            bad "p30 E30-9 ($1)" "the into side did not run: $(head -4 "$work/p30$1.pc")"
            return
        elif ! "$CC" -Wall -Wextra -std=c99 $incs -I "$work/p30$1.hd" \
                "$work/p30$1.hd"/*.c $(find "$d" -name '*.shim.c') \
                -o "$work/p30$1.hb" 2>"$work/p30$1.hc" \
                || ! "$work/p30$1.hb" >"$work/p30$1.hr" 2>&1; then
            bad "p30 E30-9 ($1)" "the hand side did not run: $(head -4 "$work/p30$1.hc")"
            return
        fi
    else
        pc="$work/p30$1.prog.c"
        hc="$work/p30$1.hand.c"
        if ! "$work/ct-ast" "$d/prog.ct" -o "$pc" >"$work/p30$1.po" 2>&1; then
            bad "p30 E30-9 ($1)" "ct-ast failed on prog.ct: $(head -3 "$work/p30$1.po")"
            return
        elif ! "$work/ct-ast" "$d/hand.ct" -o "$hc" >"$work/p30$1.ho" 2>&1; then
            bad "p30 E30-9 ($1)" "ct-ast failed on hand.ct: $(head -3 "$work/p30$1.ho")"
            return
        elif ! "$CC" -Wall -Wextra -std=c99 "$pc" -o "$work/p30$1.pb" \
                2>"$work/p30$1.pc" || ! "$work/p30$1.pb" >"$work/p30$1.pr" 2>&1; then
            bad "p30 E30-9 ($1)" "the into side did not run: $(head -4 "$work/p30$1.pc")"
            return
        elif ! "$CC" -Wall -Wextra -std=c99 "$hc" -o "$work/p30$1.hb" \
                2>"$work/p30$1.hc" || ! "$work/p30$1.hb" >"$work/p30$1.hr" 2>&1; then
            bad "p30 E30-9 ($1)" "the hand side did not run: $(head -4 "$work/p30$1.hc")"
            return
        fi
    fi
    if ! cmp -s "$work/p30$1.pr" "$d/prog.expected.out" \
        || ! cmp -s "$work/p30$1.hr" "$d/prog.expected.out"; then
        bad "p30 E30-9 ($1)" "output mismatch: into '$(cat "$work/p30$1.pr")', hand '$(cat "$work/p30$1.hr")'"
    elif ! sed -E -e '/^\/\* Generated by /d' -e '/^#line /d' \
            -e 's/__ct_recv[0-9]+/__ct_recvN/g' \
            -e 's/recv_demo[0-9]+/__ct_recvN/g' "$pc" >"$work/p30$1.prog.n" \
        || ! sed -E -e '/^\/\* Generated by /d' -e '/^#line /d' \
            -e 's/__ct_recv[0-9]+/__ct_recvN/g' \
            -e 's/recv_demo[0-9]+/__ct_recvN/g' "$hc" >"$work/p30$1.hand.n" \
        || ! cmp -s "$work/p30$1.prog.n" "$work/p30$1.hand.n"; then
        bad "p30 E30-9 ($1)" "the normalised products differ: $(diff "$work/p30$1.hand.n" "$work/p30$1.prog.n" | head -4)"
    else
        ok "p30 E30-9 ($1: same output, byte-identical after normalisation)"
    fi
}
for g in 160_group_a 161_group_b 162_group_c 163_group_d; do p30_cmp "$g"; done

# Phase 31 O3 (E31-24): a chained receiver is an rvalue, so the product must
# name it in a temporary instead of taking the address of the call. The fixture
# output check above already proves the chain runs; this one inspects the C.
if ! "$work/ct-ast" test/ast/190_chain_access/prog.ct -o "$work/p31chain.c" \
        >"$work/p31chain.log" 2>&1; then
    bad "p31 E31-24 (chain product)" "ct-ast failed: $(head -3 "$work/p31chain.log")"
elif grep -Eq '&(Vec|Map)_[A-Za-z0-9_]*_get\(' "$work/p31chain.c"; then
    bad "p31 E31-24 (chain product)" "a product still takes the address of a get call"
elif ! grep -q "__ct_tmp" "$work/p31chain.c"; then
    bad "p31 E31-24 (chain product)" "no receiver temporary appears in the product"
else
    ok "p31 E31-24 (chain product: receivers named, no address of a call)"
fi

# Phase 31 S20b: a nested container value in a Map literal has one spelling.
# Every `MapEntry_*` the product names must be defined, and no argument may
# still be encoded from a source spelling (`Vec_lint_r` was that bug).
if ! "$work/ct-ast" test/ast/200_map_container_value/prog.ct -o "$work/p31map.c" \
        >"$work/p31map.log" 2>&1; then
    bad "p31 S20b (nested Map value product)" "ct-ast failed: $(head -3 "$work/p31map.log")"
else
    missing=""
    for n in $(grep -o 'MapEntry_[A-Za-z0-9_]*' "$work/p31map.c" | sort -u); do
        grep -q "struct $n {" "$work/p31map.c" || missing="$missing $n"
    done
    if [ -n "$missing" ]; then
        bad "p31 S20b (nested Map value product)" "entry names without a definition:$missing"
    elif grep -q '_lint_r' "$work/p31map.c"; then
        bad "p31 S20b (nested Map value product)" "an argument is still encoded from its source spelling"
    else
        ok "p31 S20b (nested Map value: one spelling, every entry defined)"
    fi
fi

# Phase 31 S24 (E31-27): a capacity failure leaves before any element is
# retained. Each emitted body runs to its closing brace, and the failure return
# must come first, so a half-grown receiver never takes a reference.
p31_order() {
    fn=$1; ret=$2; tag=$3
    sed -n "/^[^[:space:]].*${fn}(/,/^}/p" "$work/p31own.c" >"$work/p31fn.c"
    r=$(grep -n "$ret" "$work/p31fn.c" | head -1 | cut -d: -f1)
    t=$(grep -n '__elem_retain' "$work/p31fn.c" | head -1 | cut -d: -f1)
    if [ -z "$r" ] || [ -z "$t" ]; then
        bad "p31 E31-27 ($fn)" "missing '$ret' or a retain call in the body"
    elif [ "$r" -ge "$t" ]; then
        bad "p31 E31-27 ($fn)" "retain at $t is not after '$ret' at $r"
    else
        ok "p31 E31-27 ($tag: $fn leaves before retaining)"
    fi
}
p31_from_order() {
    fn=$1
    sed -n "/^[^[:space:]].*${fn}(/,/^}/p" "$work/p31own.c" >"$work/p31fn.c"
    rl=$(grep -n 'realloc(' "$work/p31fn.c" | head -1 | cut -d: -f1)
    r=$(grep -n 'return m;' "$work/p31fn.c" | cut -d: -f1 | awk -v R="$rl" '$1 > R { print; exit }')
    if [ -z "$rl" ] || [ -z "$r" ]; then
        bad "p31 E31-27 ($fn)" "no realloc / failure return in the body"
    elif sed -n "${rl},${r}p" "$work/p31fn.c" | grep -q '__elem_retain'; then
        bad "p31 E31-27 ($fn)" "the failure branch retains before returning the partial map"
    else
        ok "p31 E31-27 (from capacity: $fn returns the partial map before retaining)"
    fi
}
if ! "$work/ct-ast" test/ast/191_alloc_order/prog.ct -o "$work/p31own.c" \
        >"$work/p31own.log" 2>&1; then
    bad "p31 E31-27 (ownership product)" "ct-ast failed: $(head -3 "$work/p31own.log")"
else
    p31_order Vec_int_push 'return 0;' 'push capacity'
    p31_order Map_char_p_int_put 'return 0;' 'put capacity'
    p31_from_order Map_char_p_int_from
fi

# Phase 31 S24 (E31-29): the OOM contract. Every `malloc(` in a `from` body must
# reach `abort()` within two lines, `from` never frees, and the header alloc of
# `push` / `put` / `Map::from` aborts exactly once. The card's "3 aborts" count
# predates S19's single header allocation; the real body has one header and one
# data malloc, so the count asserted here is one abort per malloc.
p31_oom() {
    fn=$1; body="$work/p31oom.c"
    sed -n "/^[^[:space:]].*${fn}(/,/^}/p" "$body" >"$work/p31fn.c"
    m=$(grep -c 'malloc(' "$work/p31fn.c")
    a=$(grep -c 'abort();' "$work/p31fn.c")
    miss=""
    for l in $(grep -n 'malloc(' "$work/p31fn.c" | cut -d: -f1); do
        sed -n "${l},$((l + 2))p" "$work/p31fn.c" | grep -q 'abort();' || miss="$miss $l"
    done
    if [ -n "$miss" ]; then
        bad "p31 E31-29 ($fn)" "malloc lines without abort: $miss"
    elif [ "$m" -ne "$a" ]; then
        bad "p31 E31-29 ($fn)" "$m mallocs but $a aborts"
    elif grep -q 'free(' "$work/p31fn.c"; then
        bad "p31 E31-29 ($fn)" "from still frees on the failure path"
    else
        ok "p31 E31-29 ($fn: every allocation aborts, no free)"
    fi
}
p31_hdr() {
    fn=$1; body="$work/p31oom.c"
    sed -n "/^[^[:space:]].*${fn}(/,/^}/p" "$body" >"$work/p31fn.c"
    l=$(grep -n 'malloc(sizeof(struct ct_buf))' "$work/p31fn.c" | head -1 | cut -d: -f1)
    a=$(grep -c 'abort();' "$work/p31fn.c")
    if [ -z "$l" ]; then
        bad "p31 E31-29 ($fn)" "no header allocation in the body"
    elif ! sed -n "${l},$((l + 2))p" "$work/p31fn.c" | grep -q 'abort();'; then
        bad "p31 E31-29 ($fn)" "the header allocation does not abort"
    elif [ "$a" -ne 1 ]; then
        bad "p31 E31-29 ($fn)" "the body holds $a aborts, expected 1"
    else
        ok "p31 E31-29 ($fn: header allocation aborts once)"
    fi
}
if ! "$work/ct-ast" test/ast/193_alloc_contract/prog.ct -o "$work/p31oom.c" \
        >"$work/p31oom.log" 2>&1; then
    bad "p31 E31-29 (OOM product)" "ct-ast failed: $(head -3 "$work/p31oom.log")"
else
    for f in $(grep -oE 'Vec_[A-Za-z0-9_]*_from\(' "$work/p31oom.c" | sed 's/($//' | sort -u); do
        p31_oom "$f"
    done
    p31_hdr Vec_int_push
    p31_hdr Map_char_p_int_put
    p31_hdr Map_int_int_put
    p31_hdr Map_char_p_int_from
    p31_hdr Map_int_int_from
fi

# Phase 31 S28 (E31-30): the H-A layout. Every `Vec_*` / `Map_*` instance is a
# bare `ct_buf *` handle (no data pointer beside `h`), and `Vec_*_get` reads
# through `h->data`, so a sibling's growth cannot leave a stale pointer behind.
p31_ha() {
    f=$1; badv=""
    for s in $(grep -oE '^struct (Vec|Map)_[A-Za-z0-9_]* \{' "$f" | sed 's/^struct //; s/ {$//'); do
        body="$(sed -n "/^struct $s {/,/^};/{/^struct /d;/^};/d;p;}" "$f")"
        if [ "$(printf '%s\n' "$body" | grep -c ';')" -ne 1 ] \
           || [ "$body" != "    struct ct_buf * h;" ]; then
            badv="$badv $s"
        fi
    done
    if [ -n "$badv" ]; then
        bad "p31 E31-30 (H-A layout)" "handles that are not a bare ct_buf pointer:$badv"
    else
        ok "p31 E31-30 (H-A layout: every container handle is one h pointer)"
    fi
}
if ! "$work/ct-ast" test/ast/194_handle_alias/prog.ct -o "$work/p31ha.c" \
        >"$work/p31ha.log" 2>&1 \
   || ! "$work/ct-ast" test/ast/195_map_value_alias/prog.ct -o "$work/p31ha2.c" \
        >>"$work/p31ha.log" 2>&1; then
    bad "p31 E31-30 (H-A product)" "ct-ast failed: $(head -3 "$work/p31ha.log")"
else
    p31_ha "$work/p31ha.c"
    p31_ha "$work/p31ha2.c"
    if ! sed -n '/^[^[:space:]].*Vec_int_get(/,/^}/p' "$work/p31ha.c" | grep -q -- '->h->data'; then
        bad "p31 E31-30 (H-A get)" "Vec_int_get does not read through h->data"
    else
        ok "p31 E31-30 (H-A get: Vec_int_get reads through h->data)"
    fi
fi

# Phase 36 S4a1 (E36-8): `own Str *` + `delete` reuses the existing AutoDrop
# path. The explicit `impl Drop for Str` frees the buffer; `delete` frees the
# struct and nulls the pointer. The drop must not free the struct handle itself.
if ! "$work/ct-ast" test/ast/232_str_own_pointer/prog.ct -o "$work/p36s4a1.c" \
        >"$work/p36s4a1.log" 2>&1; then
    bad "p36 E36-8 (own Str product)" "ct-ast failed: $(head -3 "$work/p36s4a1.log")"
else
    body="$(sed -n '/^static .*Str_Drop_drop(void \*self) {/,/^}/p' "$work/p36s4a1.c")"
    if printf '%s\n' "$body" | grep -q 'free(_self->data);' \
       && printf '%s\n' "$body" | grep -q '_self->data = 0;' \
       && printf '%s\n' "$body" | grep -q '_self->len = (-1);' \
       && ! printf '%s\n' "$body" | grep -q 'free(_self);'; then
        ok "p36 E36-8 (Str_Drop_drop frees data, not the struct)"
    else
        bad "p36 E36-8 (Str_Drop_drop body)" "$(printf '%s\n' "$body" | head -6)"
    fi
    if grep -q 'Str_Drop_drop(p); free(p); p = 0;' "$work/p36s4a1.c"; then
        ok "p36 E36-8 (delete runs the drop, frees the struct, nulls the pointer)"
    else
        bad "p36 E36-8 (delete shape)" "$(grep 'Str_Drop_drop' "$work/p36s4a1.c" | head -3)"
    fi
fi

# Phase 36 S1b (L36-1): a `drop` body may not `release()` the same `self`
# field twice. The diagnostic names the offending field and points at the
# second call.
p36_diag() {
    if "$work/ct-ast" "test/ast/errors/$1.ct" -o "$work/p36d.c" \
            >"$work/p36d.out" 2>"$work/p36d.err"; then
        bad "p36_diag_$1" "expected a non-zero exit"
    elif grep -qF "test/ast/errors/$1.ct:$2: error: $3" "$work/p36d.err"; then
        ok "p36_diag_$1"
    else
        bad "p36_diag_$1" "$(head -2 "$work/p36d.err")"
    fi
}
p36_diag double_drop 14:0 "field 'p' is released more than once in drop()"

# Phase 36 S1a (E36-1): an explicit `impl<T> Drop for Box<T>` is instantiated
# per concrete type: one `<S>_Drop_drop` definition per instance, no template
# `Box_Drop_drop` and no vtable. The explicit body owns the drop; no field glue.
if ! "$work/ct-ast" test/ast/225_generic_drop/prog.ct -o "$work/p36s1a.c" \
        >"$work/p36s1a.log" 2>&1; then
    bad "p36 E36-1 (generic Drop product)" "ct-ast failed: $(head -3 "$work/p36s1a.log")"
else
    if ! "$CC" -o "$work/p36s1a.bin" "$work/p36s1a.c" 2>"$work/p36s1a.cc"; then
        bad "p36 E36-1 (build)" "$(cat "$work/p36s1a.cc")"
    else
        n="$(nm "$work/p36s1a.bin" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ [Tt] _?Box_int_Drop_drop$/ { c++ } END { print c + 0 }')"
        if [ "$n" = "1" ]; then
            ok "p36 E36-1 (Box_int_Drop_drop: one definition)"
        else
            bad "p36 E36-1 (Box_int_Drop_drop count)" "got $n"
        fi
        n="$(nm "$work/p36s1a.bin" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ [Tt] _?Box_Str_Drop_drop$/ { c++ } END { print c + 0 }')"
        if [ "$n" = "1" ]; then
            ok "p36 E36-1 (Box_Str_Drop_drop: one definition)"
        else
            bad "p36 E36-1 (Box_Str_Drop_drop count)" "got $n"
        fi
        n="$(nm "$work/p36s1a.bin" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ [Tt] _?Box_Drop_drop$/ { c++ } END { print c + 0 }')"
        if [ "$n" = "0" ]; then
            ok "p36 E36-1 (no template Box_Drop_drop)"
        else
            bad "p36 E36-1 (template Box_Drop_drop leaked)" "got $n"
        fi
        if nm "$work/p36s1a.bin" 2>/dev/null | grep -q '_Box_.*_vtable'; then
            bad "p36 E36-1 (Drop has no vtable)" "$(nm "$work/p36s1a.bin" | grep vtable | head -2)"
        else
            ok "p36 E36-1 (Drop emits no vtable)"
        fi
    fi
fi

# Phase 36 S1a (E36-2): without an explicit `impl Drop`, the glue drops fields
# in declaration order; a generic `impl<T> Drop` declared after the first use
# still binds. The fixture loop already checks the stdout order; here we pin
# that each instance owns exactly one drop definition (no duplicate glue).
if ! "$work/ct-ast" test/ast/226_drop_order/prog.ct -o "$work/p36s1a2.c" \
        >"$work/p36s1a2.log" 2>&1; then
    bad "p36 E36-2 (drop order product)" "ct-ast failed: $(head -3 "$work/p36s1a2.log")"
else
    if ! "$CC" -o "$work/p36s1a2.bin" "$work/p36s1a2.c" 2>"$work/p36s1a2.cc"; then
        bad "p36 E36-2 (build)" "$(cat "$work/p36s1a2.cc")"
    else
        n="$(nm "$work/p36s1a2.bin" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ [Tt] _?Box_int_Drop_drop$/ { c++ } END { print c + 0 }')"
        if [ "$n" = "1" ]; then
            ok "p36 E36-2 (Box_int drop: one definition, impl-after-use binds)"
        else
            bad "p36 E36-2 (Box_int drop count)" "got $n"
        fi
        n="$(nm "$work/p36s1a2.bin" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ [Tt] _?Pair_Probe_Drop_drop$/ { c++ } END { print c + 0 }')"
        if [ "$n" = "1" ]; then
            ok "p36 E36-2 (Pair_Probe glue: one definition)"
        else
            bad "p36 E36-2 (Pair_Probe drop count)" "got $n"
        fi
    fi
fi

# Phase 36 S1a (E36-3): a container whose element type has a lifecycle releases
# each live element. The fixture loop checks that `Vec<Probe>` calls
# `Probe_release` three times; here we pin that the `Vec<Str>` product binds the
# element helper to `Str_release` (not a no-op).
if ! "$work/ct-ast" test/ast/227_vec_element_release/prog.ct -o "$work/p36s1a3.c" \
        >"$work/p36s1a3.log" 2>&1; then
    bad "p36 E36-3 (element release product)" "ct-ast failed: $(head -3 "$work/p36s1a3.log")"
else
    if grep -q 'Vec_Str__elem_release' "$work/p36s1a3.c" \
       && grep -q 'Str_release' "$work/p36s1a3.c"; then
        ok "p36 E36-3 (Vec<Str> element helper calls Str_release)"
    else
        bad "p36 E36-3 (Vec<Str> element helper shape)" \
            "$(grep 'elem_release' "$work/p36s1a3.c" | head -3)"
    fi
fi

# Phase 36 S4c (E36-4): `Option<T> use Drop` makes the glue drop the payload.
# The fixture loop checks that both a present and a none Option drop the
# payload (none on the zero-initialised value); here we pin that the glue
# emits exactly one `Option_Probe_Drop_drop` definition and that it calls
# `Probe_Drop_drop` on the field (not a no-op).
if ! "$work/ct-ast" test/ast/233_option_probe_drop/prog.ct -o "$work/p36s4c.c" \
        >"$work/p36s4c.log" 2>&1; then
    bad "p36 E36-4 (Option drop product)" "ct-ast failed: $(head -3 "$work/p36s4c.log")"
else
    if ! "$CC" -o "$work/p36s4c.bin" "$work/p36s4c.c" 2>"$work/p36s4c.cc"; then
        bad "p36 E36-4 (build)" "$(cat "$work/p36s4c.cc")"
    else
        n="$(nm "$work/p36s4c.bin" 2>/dev/null | awk '$0 ~ /^[0-9a-fA-F]+ [Tt] _?Option_Probe_Drop_drop$/ { c++ } END { print c + 0 }')"
        if [ "$n" = "1" ]; then
            ok "p36 E36-4 (Option_Probe_Drop_drop: one definition)"
        else
            bad "p36 E36-4 (Option_Probe_Drop_drop count)" "got $n"
        fi
        if grep -q 'Probe_Drop_drop(&_self->value)' "$work/p36s4c.c"; then
            ok "p36 E36-4 (Option glue drops the payload field)"
        else
            bad "p36 E36-4 (Option glue shape)" \
                "$(grep 'Option_Probe_Drop_drop' "$work/p36s4c.c" | head -3)"
        fi
    fi
fi

echo
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
