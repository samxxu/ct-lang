#!/bin/sh
#
# check-ast.sh - the AST compiler's behavioural gate (Phase 9.1-9.7, 10.x, 11.x, 12.1).
#
# Builds the bootstrap chain (L0 -> L1 -> L2), then builds the AST compiler
# (selfhost/ct-ast/main.ct, D30: a separate tree in parallel with the old
# pipeline), and runs every fixture under test/ast/*/:
#
#   prog.ct -> ct-ast -> <name>.c + <name>.h -> cc (warning-free) -> run
#           -> compare stdout with prog.expected.out
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
    if [ ! -f "$work/$name.h" ]; then
        bad "$name" "no header was emitted"
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
echo "== bindings (Phase 12: the fake HAL demo) =="
# A binding is plain CT - a pass-through include, a mirrored trait / struct, a
# declared global instance and a `map` - so no language feature is involved.
# Build mode must emit the wrappers and the vtable into the unit that declares
# the map (12.1 fixed a gap where they were only emitted in compile mode).
bd=bindings/mock-hal
rm -rf "$work/bind"
mkdir -p "$work/bind"
if ! "$work/ct-ast" build "$bd/demo.ct" -o "$work/bind" >"$work/bind.out" 2>"$work/bind.err"; then
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
if "$work/ct-ast" build test/modules/split/main.ct -o "$mod-split" \
        >"$work/msplit.out" 2>"$work/msplit.err" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-split"/*.c -o "$work/msplit.bin" 2>"$work/msplit.cc" \
   && "$work/msplit.bin" >"$work/msplit.stdout" 2>&1 \
   && cmp -s "$work/msplit.stdout" test/modules/split/expected.out; then
    ok "split (import + pub routing + cross-unit dispatch)"
else
    bad "split" "$(cat "$work/msplit.err" "$work/msplit.cc" "$work/msplit.stdout")"
fi

rm -rf "$mod-ns"
mkdir -p "$mod-ns"
if "$work/ct-ast" build --ns-root test/modules/ns_dir/src \
        test/modules/ns_dir/src/main.ct test/modules/ns_dir/src/plain/extra.ct \
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
if "$work/ct-ast" build --ns-root test/modules/alias/src \
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
if "$work/ct-ast" build --ns-root test/modules/ns_funcs/src \
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
if "$work/ct-ast" build --ns-root test/modules/ns_qual/src \
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
if "$work/ct-ast" build test/modules/inc/main.ct -I test/modules/inc/extra \
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
if "$work/ct-ast" build test/modules/hdr/main.ct -o "$mod-hdr" \
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
echo "== header prologue (build mode copies the source's #include lines) =="
rm -rf "$mod-pro"
mkdir -p "$mod-pro"
if "$work/ct-ast" build test/modules/hdr_prologue/main.ct -o "$mod-pro" \
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
if "$work/ct-ast" build test/modules/pub_global/main.ct -o "$mod-pg" \
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
if "$work/ct-ast" build test/modules/xunit_box/main.ct -o "$mod-xb" \
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
if "$work/ct-ast" build test/modules/extern_decl/main.ct -o "$mod-ex" \
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
if "$work/ct-ast" build test/modules/map_ns/main.ct -o "$mod-mn" \
        >"$work/mmn.out" 2>"$work/mmn.err" \
   && grep -q 'hal_uart1_hal_Writer_vtable' "$mod-mn/uart.c" \
   && "$CC" -Wall -Wextra -std=c99 "$mod-mn"/*.c -o "$work/mmn.bin" 2>"$work/mmn.cc" \
   && "$work/mmn.bin" >"$work/mmn.stdout" 2>&1 \
   && cmp -s "$work/mmn.stdout" test/modules/map_ns/expected.out; then
    ok "map_ns (a qualified instance name resolves to the declared name)"
else
    bad "map_ns" "$(cat "$work/mmn.err" "$work/mmn.cc" "$work/mmn.stdout" 2>/dev/null)"
fi

# Globals are mangled by their namespace, so two units may each export `h`.
# The consumer reads and writes both through the qualified form.
rm -rf "$mod-ng"
mkdir -p "$mod-ng"
if "$work/ct-ast" build test/modules/ns_globals/main.ct -o "$mod-ng" \
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
if "$work/ct-ast" build test/modules/ambig_global/main.ct -o "$work/mod-bad" \
        >"$work/mag.out" 2>"$work/mag.err"; then
    bad "ambig_global" "expected a non-zero exit"
elif grep -q "variable 'h' is exported by more than one namespace" "$work/mag.err"; then
    ok "ambig_global (a bare name that two namespaces export is refused)"
else
    bad "ambig_global" "no ambiguity diagnostic: $(cat "$work/mag.err")"
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
if "$work/ct-ast" build --emit-map "$work/m11b/prog.map" test/ast/11_map/prog.ct \
        -o "$work/m11b" >"$work/m11b.out" 2>"$work/m11b.err" \
   && grep -q '^#line 1 "test/ast/11_map/prog.ct"' "$work/m11b/prog.c" \
   && grep -q '"compiler": "ct v' "$work/m11b/prog.map"; then
    ok "build default (#line on, map to a file)"
else
    bad "build metadata" "$(cat "$work/m11b.err")"
fi

rm -rf "$work/m11n"
mkdir -p "$work/m11n"
if "$work/ct-ast" build --no-line test/ast/11_map/prog.ct -o "$work/m11n" \
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

echo
echo "== negative cases =="
rm -rf "$work/mod-bad"
mkdir -p "$work/mod-bad"
if "$work/ct-ast" build --ns-root test/modules/ns_dir_mismatch \
        test/modules/ns_dir_mismatch/a/uart.ct -o "$work/mod-bad" \
        >"$work/mnbad.out" 2>"$work/mnbad.err"; then
    bad "ns_dir_mismatch" "expected a non-zero exit"
elif grep -q "^ctc: " "$work/mnbad.err"; then
    ok "ns_dir_mismatch (namespace/directory check)"
else
    bad "ns_dir_mismatch" "no diagnostic on stderr"
fi
if "$work/ct-ast" build test/modules/inc_missing/main.ct -o "$work/mod-bad" \
        >"$work/mincm.out" 2>"$work/mincm.err"; then
    bad "inc_missing" "expected a non-zero exit"
elif grep -q "^ctc: " "$work/mincm.err"; then
    ok "inc_missing (unresolved import)"
else
    bad "inc_missing" "no diagnostic on stderr"
fi
if "$work/ct-ast" build --ns-root test/modules/alias_dup/src \
        test/modules/alias_dup/src/main.ct -o "$work/mod-bad" \
        >"$work/madup.out" 2>"$work/madup.err"; then
    bad "alias_dup" "expected a non-zero exit"
elif grep -q "one alias names two imports" "$work/madup.err"; then
    ok "alias_dup (one alias, two imports)"
else
    bad "alias_dup" "no alias diagnostic: $(cat "$work/madup.err")"
fi
if "$work/ct-ast" build --ns-root test/modules/alias_missing/src \
        test/modules/alias_missing/src/main.ct -o "$work/mod-bad" \
        >"$work/mamiss.out" 2>"$work/mamiss.err"; then
    bad "alias_missing" "expected a non-zero exit"
elif grep -q "does not export that name" "$work/mamiss.err"; then
    ok "alias_missing (by-name import of an unknown name)"
else
    bad "alias_missing" "no alias diagnostic: $(cat "$work/mamiss.err")"
fi
if "$work/ct-ast" build --ns-root test/modules/ns_scoped_mismatch/src \
        test/modules/ns_scoped_mismatch/src/app/unit.ct -o "$work/mod-bad" \
        >"$work/mnsm.out" 2>"$work/mnsm.err"; then
    bad "ns_scoped_mismatch" "expected a non-zero exit"
elif grep -q "does not match the directory" "$work/mnsm.err"; then
    ok "ns_scoped_mismatch (file-scoped namespace vs --ns-root)"
else
    bad "ns_scoped_mismatch" "no namespace diagnostic: $(cat "$work/mnsm.err")"
fi
if "$work/ct-ast" build test/modules/ns_block/src/main.ct -o "$work/mod-bad" \
        >"$work/mnsb.out" 2>"$work/mnsb.err"; then
    bad "ns_block" "expected a non-zero exit"
elif grep -q "a namespace is file-scoped" "$work/mnsb.err"; then
    ok "ns_block (the block form is rejected)"
else
    bad "ns_block" "no namespace diagnostic: $(cat "$work/mnsb.err")"
fi
if "$work/ct-ast" build --ns-root test/modules/ns_fn_ambiguous/src \
        test/modules/ns_fn_ambiguous/src/main.ct -o "$work/mod-bad" \
        >"$work/mnfa.out" 2>"$work/mnfa.err"; then
    bad "ns_fn_ambiguous" "expected a non-zero exit"
elif grep -q "exported by more than one namespace" "$work/mnfa.err"; then
    ok "ns_fn_ambiguous (an unqualified call to a doubly exported name is refused)"
else
    bad "ns_fn_ambiguous" "no ambiguity diagnostic: $(cat "$work/mnfa.err")"
fi

if "$work/ct-ast" build --ns-root test/modules/ns_qual_missing/src \
        test/modules/ns_qual_missing/src/main.ct -o "$work/mod-bad" \
        >"$work/mnqm.out" 2>"$work/mnqm.err"; then
    bad "ns_qual_missing" "expected a non-zero exit"
elif grep -q "no function of that name in that namespace" "$work/mnqm.err"; then
    ok "ns_qual_missing (a qualified call to a missing function is refused)"
else
    bad "ns_qual_missing" "no qualified-call diagnostic: $(cat "$work/mnqm.err")"
fi

if "$work/ct-ast" build --ns-root test/modules/ns_bare_call/src \
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
if "$work/ct-ast" build test/modules/dup_impl/main.ct -o "$work/mod-bad" \
        >"$work/mdup.out" 2>"$work/mdup.err"; then
    bad "dup_impl" "expected a non-zero exit"
elif grep -q "duplicate impl of trait 'Speak' for struct 'Dog'" "$work/mdup.err" \
     && grep -q "first at .*a\.ct:" "$work/mdup.err"; then
    ok "dup_impl (one impl per struct and trait, the first one is named)"
else
    bad "dup_impl" "no duplicate diagnostic: $(cat "$work/mdup.err")"
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

# SH-8: a missing impl method must be reported the way L0/L2 report it, and no
# artifact may be left behind (a NULL vtable slot would crash at run time).
if "$work/ct-ast" test/ast/errors/missing_method.ct -o "$work/mmethod.c" \
        >"$work/mmethod.out" 2>"$work/mmethod.err"; then
    bad "impl completeness" "expected a non-zero exit"
elif grep -q "trait method 'b' is not implemented for struct 'P'" "$work/mmethod.err" \
        && [ ! -f "$work/mmethod.c" ]; then
    ok "impl (every trait method must be implemented)"
else
    bad "impl completeness" "$(cat "$work/mmethod.err")"
fi

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
# Compile mode keeps the `.c` self-contained: it must not include the `.h` it
# writes next to itself (the header is a standalone type artifact).
if "$work/ct-ast" test/ast/02_expr/prog.ct -o "$work/contract.c" \
        >"$work/contract.out" 2>"$work/contract.err" \
   && [ -f "$work/contract.h" ] \
   && ! grep -q '^#include "contract.h"' "$work/contract.c"; then
    ok "compile mode: the .c does not include its own header"
else
    bad "output contract" "the .c includes its header, or the .h is missing: $(cat "$work/contract.err")"
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
if "$work/ct-ast" build --std=gnu99 test/ast/11_map/prog.ct -o "$work/cli-b" \
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
if "$work/ct-ast" build test/ast/02_expr/prog.ct --ns-root \
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
if "$work/ct-ast" build test/modules/split/main.ct \
        >"$work/cli-bo.out" 2>"$work/cli-bo.err"; then
    bad "build without -o" "expected a non-zero exit"
elif grep -q "build needs -o" "$work/cli-bo.err"; then
    ok "build without -o is rejected"
else
    bad "build without -o" "wrong diagnostic: $(cat "$work/cli-bo.err")"
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
if "$work/ct-ast" build --diagnostics=json test/modules/leak_build/prog.ct \
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
if "$work/ct-ast" build test/modules/multi_err_build/prog.ct -o "$rec-multi_err_build" \
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
if "$work/ct-ast" build "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>"$cac/ast.err" \
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
"$work/ct-ast" build "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>&1
if [ "$(mtime "$cac/ast/main.c")" = "$cached" ]; then
    ok "cache: a warm build reuses unchanged units"
else
    bad "cache warm" "main.c was regenerated although nothing changed"
fi
touch -t 201001010000 "$cac/src/shapes.h.ct"
"$work/ct-ast" build "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>&1
if [ "$(mtime "$cac/ast/main.c")" != "$cached" ] \
   && [ "$(mtime "$cac/ast/impl_dog.c")" != "$cached" ]; then
    ok "cache: a dependency change invalidates downstream units"
else
    bad "cache dep" "main.c/impl_dog.c were not rebuilt after shapes changed"
fi
rm -f "$cac/ast/shapes.c"
"$work/ct-ast" build "$cac/src/main.ct" -o "$cac/ast" >/dev/null 2>&1
if [ -f "$cac/ast/shapes.c" ]; then
    ok "cache: a missing artefact is regenerated"
else
    bad "cache artifact" "shapes.c was not restored"
fi

echo
echo "== self-hosting (9.6) =="
# The AST compiler builds its own source; the result must compile warning-free,
# and the rebuilt compiler must reproduce the same output byte for byte (a
# fixpoint: the compiler agrees with itself on its own subset). The source is a
# multi-unit tree now, so the build mode drives both halves and the whole output
# directory is compared.
mkdir -p "$work/self1" "$work/self2"
if "$work/ct-ast" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/self1" \
        >"$work/self1.out" 2>"$work/self1.err" \
   && "$CC" -Wall -Wextra -std=c99 "$work/self1"/*.c -o "$work/ct-ast2" 2>"$work/selfcc.log" \
   && "$work/ct-ast2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/self2" \
        >"$work/self2.out" 2>"$work/self2.err" \
   && diff -r -q -x .ctcache "$work/self1" "$work/self2" >/dev/null 2>&1; then
    ok "self-compile (fixpoint: ct-ast2 reproduces ct-ast's output)"
else
    bad "self-compile" "$(cat "$work/self1.err" "$work/selfcc.log" "$work/self2.err" 2>/dev/null | head -5)"
fi

echo
echo "== summary: $pass passed, $fail failed =="
rm -rf "$work"
[ "$fail" -eq 0 ]
