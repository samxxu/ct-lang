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
# 12.1 adds the bindings section: `bindings/mock-hal/` is a declarative binding
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
# touching of the shim header; bindings/posix-socket is the real-library demo
# (a header-only shim over socketpair / write / read / errno). A shim source
# without its header is rejected by name, a shim header that is not a regular
# file is rejected too, a static map's JSON carries the shim files, and two
# mapping units that share a base name are an error rather than a silent pick.
#
# batch 40 adds raw pass-through (17.3): `#ct-raw` at column 1 opens a block
# whose lines are copied verbatim into the generated C (never tokenised), and
# `#ct-endraw` closes it; the emitted text is re-anchored with a `#line` on the
# line after the block. test/ast/65_raw pins the verbatim copy and the anchor,
# and four negatives pin the column-1 rule, the unclosed block, the stray
# `#ct-endraw` and trailing text. The cap is 32768 bytes, and the compiler's
# own sources must stay free of raw blocks.
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

echo
echo "== behavioural cases (compile -> cc -> run -> compare) =="
for d in test/ast/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    name="$(basename "$d")"
    src="$d/prog.ct"
    [ -f "$src" ] || continue
    out="$work/$name.c"
    exe="$work/$name.bin"

    if ! "$work/ct-ast" "$src" -o "$out" >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name" "ct-ast failed: $(cat "$work/$name.err")"
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
bd=bindings/mock-hal
rm -rf "$work/bind"
mkdir -p "$work/bind"
if ! "$work/ct-ast" build --emit-c "$bd/demo.ct" -o "$work/bind" >"$work/bind.out" 2>"$work/bind.err"; then
    bad "bindings/mock-hal" "ct-ast failed: $(cat "$work/bind.err")"
elif ! grep -q "uart1_Controller_vtable" "$work/bind/uart.c"; then
    bad "bindings/mock-hal" "the map vtable was not emitted into the declaring unit"
elif ! "$CC" -Wall -Wextra -std=c99 -I "$bd" "$work/bind"/*.c "$bd/mock_hal_impl.c" \
        -o "$work/bind.bin" 2>"$work/bind.cc"; then
    bad "bindings/mock-hal" "generated C did not build warning-free: $(cat "$work/bind.cc")"
elif ! "$work/bind.bin" >"$work/bind.stdout" 2>&1; then
    bad "bindings/mock-hal" "the program exited non-zero"
elif ! cmp -s "$work/bind.stdout" "$bd/demo.expected.out"; then
    bad "bindings/mock-hal" "program output differs: $(cat "$work/bind.stdout")"
else
    ok "bindings/mock-hal"
fi

echo
echo "== corpus equivalence (9.7: test/cases + examples) =="
# D34: exit status + a warning-free build + identical program output. Golden
# `.c` / `.h` files are not compared; a case without `expected.out` is judged
# compile-only (`03_passthrough` / `04_signatures` have no `main`). A dialect
# demo is expanded by its plugins first: ct-ast, like ct, never sees the DSL.
# A file may mix several dialects, so every distinct marker is routed in
# first-appearance order (each plugin passes foreign blocks through).
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
            plugin="$dir/ct-dialects/$(printf '%s' "$dialect" | tr / -).sh"
            if [ -z "$dialect" ] || [ ! -f "$plugin" ]; then
                bad "$label" "no plugin for dialect '$dialect' (expected $plugin)"
                broken=1
                break
            fi
            if ! sh "$plugin" "$src" >"$work/corp-$ci.step.ct" 2>"$work/corp-$ci.err"; then
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

rm -rf "$mod-hdr"
mkdir -p "$mod-hdr"
if "$work/ct-ast" build --emit-c test/modules/hdr/main.h.ct -o "$mod-hdr" \
        >"$work/mhdr.out" 2>"$work/mhdr.err" \
   && grep -q '^#include <stdio.h>$' "$mod-hdr/main.h" \
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
   && grep -qF '((void)(a), strlen(""));' "$mod-mut/main.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-mut"/*.c -o "$work/mmut.bin" 2>"$work/mmut.cc" \
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

# `sizeof p` is not an evaluation (spec §6.3): a side-effecting actual is still
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
if "$work/ct-ast" build --emit-c bindings/posix-socket/demo.ct -o "$work/mpsock" \
        >"$work/mpsock.out" 2>"$work/mpsock.err" \
   && grep -qF '#include "socket.shim.h"' "$work/mpsock/demo.c" \
   && grep -qF -- '-I bindings/posix-socket/posix' "$work/mpsock.out" \
   && ! grep -qF '.shim.c' "$work/mpsock.out" \
   && "$CC" -Wall -Wextra -std=c99 -I bindings/posix-socket/posix "$work/mpsock"/*.c \
        -o "$work/mpsock.bin" 2>"$work/mpsock.cc" \
   && "$work/mpsock.bin" >"$work/mpsock.stdout" 2>&1 \
   && cmp -s "$work/mpsock.stdout" bindings/posix-socket/demo.expected.out; then
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
        bad "batch 38: $label" "expected a non-zero exit"
    elif grep -qF "$want" "$work/mb/err.txt"; then
        ok "batch 38 ($label)"
    else
        bad "batch 38: $label" "$(head -2 "$work/mb/err.txt")"
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
    'a .m.ct unit allows only #include and #define in its prologue'
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
# mean `sizeof((actual))`; the recipe must spell it without parentheses (§6.3).
mapbad sizeof_paren \
    'pub trait T { int m(); }\nmap trait T for type char * { m(s) -> malloc(sizeof(s)); }\n' \
    "map recipe takes 'sizeof s', not 'sizeof(s)'" \
    'import lib::lib;\n\nint main(void) { return 0; }\n'

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
echo "== negative cases (test/ast/errors/*.ct) =="
# Every source diagnostic now carries the full position (`file:line:col: error:`);
# driver-level failures (an unreadable input, a limit) keep the `ctc:` prefix and
# are asserted where they are produced.
for f in test/ast/errors/*.ct; do
    [ -f "$f" ] || continue
    b="$(basename "$f" .ct)"
    if "$work/ct-ast" "$f" -o "$work/bad-$b.c" \
            >"$work/bad-$b.out" 2>"$work/bad-$b.err"; then
        bad "$b" "expected a non-zero exit"
    elif grep -Eq '^[^:]+:[0-9]+:[0-9]+: error: ' "$work/bad-$b.err"; then
        ok "$b (rejected with a positioned diagnostic)"
    else
        bad "$b" "no positioned diagnostic on stderr: $(cat "$work/bad-$b.err")"
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
        >"$work/cli-i.out" 2>"$work/cli-i.err"; then
    ok "compile accepts -I (no imports to resolve)"
else
    bad "compile -I" "$(cat "$work/cli-i.err")"
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
cap_check params "too many parameters" "$work/cap_params.ct"
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
cap_check funcs "too many functions" "$work/cap_funcs.ct"
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
cap_check vars "too many variables" "$work/cap_vars.ct"
{
    printf 'struct Big {\n'
    i=0
    while [ "$i" -lt 65 ]; do printf '    int f%d;\n' "$i"; i=$((i + 1)); done
    printf '};\nint main(void) { return 0; }\n'
} >"$work/cap_fields.ct"
cap_check fields "too many fields in struct 'Big' (limit 64)" "$work/cap_fields.ct"

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
elif grep -q "not supported in compile mode" "$work/cli-im.err"; then
    ok "compile mode rejects 'import'"
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
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
