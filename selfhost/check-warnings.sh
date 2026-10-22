#!/bin/sh
#
# check-warnings.sh - the generated code must compile warning-free.
#
# check-ast.sh already builds every generated file with -Wall -Wextra, but it
# only fails when the compiler errors out: warnings are ignored. This gate is
# the missing half. It compiles the output of the AST compiler (the installed
# entry) with `-Wall -Wextra -std=c99 -c` and fails if stderr is not empty.
#
# Coverage:
#   - the bootstrap chain's own artefacts (l1.c, l2/*.c, ast/*.c), so ct-ast
#     keeps emitting warning-free C for the compiler itself;
#   - test/ast/*/prog.ct            (one unit per fixture);
#   - test/cases/*.ct + examples/*/*.ct (compile mode; a dialect demo is
#     expanded by its plugins first, as in check-ast.sh);
#   - test/modules/*/main.ct        (build mode, all units);
#   - bindings/mock-hal/demo.ct     (build mode, with the binding's -I root).
#
# The gate is strict on purpose. `_self` / vtable / Drop helpers used to warn
# when unused (issue SH-10); the emitter now silences them at the source
# (`(void)self;`, referenced helpers), so there is no allow-list to maintain.
# A fixture that legitimately cannot compile warning-free does not belong here:
# fix the emitter or the fixture.
#
# Usage:  bash selfhost/check-warnings.sh
#         CC=clang bash selfhost/check-warnings.sh
#
# Exit code 0 means every generated file compiled without a single warning.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-warn-test.$$"

rm -rf "$work"
mkdir -p "$work" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

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
if ! "$work/ctc" selfhost/l1/ctc.ct -o "$work/l1.c" 2>"$work/l1.out"; then
    echo "  L0 could not compile L1:"; sed 's/^/    /' "$work/l1.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l1.c" -o "$work/l1" 2>"$work/l1b.log"; then
    echo "  L1 did not build:"; sed 's/^/    /' "$work/l1b.log"; exit 1
fi
mkdir -p "$work/l2src" "$work/astsrc"
if ! "$work/l1" build selfhost/l2/driver.ct -o "$work/l2src" >"$work/l2.out" 2>&1; then
    echo "  L1 could not build the split tree:"; sed 's/^/    /' "$work/l2.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/l2src"/*.c -o "$work/l2" 2>"$work/l2b.log"; then
    echo "  L2 did not build:"; sed 's/^/    /' "$work/l2b.log"; exit 1
fi
if ! "$work/l2" build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$work/astsrc" >"$work/ast.out" 2>&1; then
    echo "  L2 could not build the AST compiler:"; sed 's/^/    /' "$work/ast.out"; exit 1
fi
if ! "$CC" -Wall -Wextra -std=c99 "$work/astsrc"/*.c -o "$work/ct-ast" 2>"$work/astb.log"; then
    echo "  the AST compiler did not build:"; sed 's/^/    /' "$work/astb.log"; exit 1
fi
ok "the chain builds (L0 -> L1 -> L2 -> ct-ast)"

# scan_one <label> <generated.c> [extra cc flags...]
scan_one() {
    label="$1"
    src="$2"
    shift 2
    if ! "$CC" -Wall -Wextra -std=c99 -c "$@" "$src" -o "$work/one.o" 2>"$work/one.warn"; then
        bad "$label" "generated C does not compile: $(cat "$work/one.warn")"
        return
    fi
    if [ -s "$work/one.warn" ]; then
        bad "$label" "generated C warns: $(cat "$work/one.warn")"
        return
    fi
    ok "$label"
}

echo
echo "== the compiler's own artefacts =="
# The chain build above already puts -Wall -Wextra on these files; this repeats
# the check explicitly so a warning is attributed to the right layer.
scan_one "l1.c" "$work/l1.c"
for f in "$work"/l2src/*.c; do scan_one "l2/$(basename "$f")" "$f"; done
for f in "$work"/astsrc/*.c; do scan_one "ct-ast/$(basename "$f")" "$f"; done

echo
echo "== test/ast fixtures =="
for d in test/ast/*/; do
    [ -d "$d" ] || continue
    d="${d%/}"
    name="$(basename "$d")"
    [ -f "$d/prog.ct" ] || continue
    if ! "$work/ct-ast" "$d/prog.ct" -o "$work/$name.c" >"$work/$name.out" 2>"$work/$name.err"; then
        bad "$name" "ct-ast failed: $(cat "$work/$name.err")"
        continue
    fi
    scan_one "$name" "$work/$name.c"
done

echo
echo "== corpus (test/cases + examples, compile mode) =="
ci=0
for ct in test/cases/*.ct examples/*/*.ct; do
    dir=$(dirname "$ct")
    name=$(basename "$ct" .ct)
    label="$ct"
    src="$ct"
    ci=$((ci + 1))

    if [ -d "$dir/ct-dialects" ]; then
        dialects=$(sed -n 's|^//@ct-dialect:[[:space:]]*||p' "$ct" | tr -d ' ' | awk '!seen[$0]++')
        cp "$ct" "$work/dia-$ci.ct"
        src="$work/dia-$ci.ct"
        broken=0
        for dialect in $dialects; do
            plugin="$dir/ct-dialects/$(printf '%s' "$dialect" | tr / -).sh"
            if [ -z "$dialect" ] || [ ! -f "$plugin" ]; then
                bad "$label" "no plugin for dialect '$dialect' (expected $plugin)"
                broken=1
                break
            fi
            if ! sh "$plugin" "$src" >"$work/dia-$ci.step.ct" 2>"$work/dia-$ci.err"; then
                bad "$label" "the expander for '$dialect' failed: $(cat "$work/dia-$ci.err")"
                broken=1
                break
            fi
            mv "$work/dia-$ci.step.ct" "$src"
        done
        if [ "$broken" -ne 0 ]; then continue; fi
    fi

    if ! "$work/ct-ast" "$src" -o "$work/corp-$ci.c" >"$work/corp-$ci.out" 2>"$work/corp-$ci.err"; then
        bad "$label" "ct-ast failed: $(cat "$work/corp-$ci.err")"
        continue
    fi
    scan_one "$label" "$work/corp-$ci.c"
done

echo
echo "== modules (build mode) =="
for d in test/modules/*/; do
    d="${d%/}"
    name="$(basename "$d")"
    [ -f "$d/main.ct" ] || continue
    # dup_impl and ambig_global are negative fixtures: the compiler must refuse
    # them (check-ast.sh owns those assertions), so they have no generated C.
    [ "$name" = "dup_impl" ] && continue
    [ "$name" = "ambig_global" ] && continue
    rm -rf "$work/mod-$name"
    mkdir -p "$work/mod-$name" || continue
    if [ -d "$d/extra" ]; then
        if ! "$work/ct-ast" build "$d/main.ct" -I "$d/extra" -o "$work/mod-$name" >"$work/mod-$name.out" 2>"$work/mod-$name.err"; then
            bad "$name" "ct-ast failed: $(cat "$work/mod-$name.err")"
            continue
        fi
    else
        if ! "$work/ct-ast" build "$d/main.ct" -o "$work/mod-$name" >"$work/mod-$name.out" 2>"$work/mod-$name.err"; then
            bad "$name" "ct-ast failed: $(cat "$work/mod-$name.err")"
            continue
        fi
    fi
    for f in "$work/mod-$name"/*.c; do
        scan_one "modules/$name/$(basename "$f")" "$f" -I "$work/mod-$name"
    done
done

echo
echo "== bindings (Phase 12) =="
bd=bindings/mock-hal
rm -rf "$work/bind"
mkdir -p "$work/bind"
if ! "$work/ct-ast" build "$bd/demo.ct" -o "$work/bind" >"$work/bind.out" 2>"$work/bind.err"; then
    bad "bindings/mock-hal" "ct-ast failed: $(cat "$work/bind.err")"
else
    for f in "$work/bind"/*.c; do
        scan_one "bindings/mock-hal/$(basename "$f")" "$f" -I "$bd"
    done
fi

echo
printf 'check-warnings: %d ok, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
