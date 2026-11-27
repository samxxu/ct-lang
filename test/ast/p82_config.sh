#!/bin/sh
# PH-82 / S82a: `leaks = warn|error` in `ct.pkg` (E82-1, E82-2, D-012).
#
#   - the key resolves from the input's package: an `-I` root's manifest for
#     `ct build`, and the unit's own directory for `ct compile` / `ct check`
#     (those modes ignore `-I`, so the fallback is what makes them work);
#   - `warn` / an old manifest without the key / no manifest at all keep the
#     pre-PH-82 `warning:` and exit 0;
#   - `error` turns the same `potential leak` record into an `error:` and the
#     run fails before a `.c` is written (build and compile, text and JSON);
#   - `leaks` is orthogonal: it does not make a package strict (`c-boundary`
#     unchanged), does not fail a clean unit, and does not escalate any other
#     warning class.
#
# Usage: sh test/ast/p82_config.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p82_config.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p82cfg.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p82/config: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

leaky='#include <stdlib.h>

struct S { int n; };

int main(void) {
    S *p = malloc(sizeof(struct S));
    return 0;
}
'
clean='int main(void) { return 0; }
'
arity='int add(int a, int b) { return a + b; }
int main(void) { return add(1); }
'

for d in warn err old strict none plain; do
    mkdir -p "$work/$d"
    printf '%s' "$leaky" > "$work/$d/prog.ct"
done
printf '%s' "$clean" > "$work/err/clean.ct"
printf '%s' "$arity" > "$work/err/arity.ct"
printf 'name = demo\nleaks = warn\n' > "$work/warn/ct.pkg"
printf 'name = demo\nleaks = error\n' > "$work/err/ct.pkg"
printf 'name = demo\n' > "$work/old/ct.pkg"
printf 'name = demo\nleaks = error\nc-boundary = strict\n' > "$work/strict/ct.pkg"
# `none` has no manifest at all; `plain` (arity fixture) gets an error manifest.

run_build() {   # run_build <dir> <outdir> [extra args...]
    local d=$1 out=$2
    shift 2
    rm -rf "$out"
    mkdir -p "$out"
    "$ctast" build "$@" -I "$work/$d" --emit-c -o "$out" \
        "$work/$d/prog.ct" >"$work/$d.log" 2>&1
}

# 1) no manifest, compile mode: default is warn, exit 0, a product is written.
"$ctast" compile --allow-c-boundary "$work/none/prog.ct" -o "$work/none/prog.c" \
    >"$work/none.log" 2>&1
if [ $? -eq 0 ] && [ -f "$work/none/prog.c" ] \
        && grep -Fq "warning: potential leak: 'p' (S*) allocated but never deleted" "$work/none.log"; then
    ok "no manifest: default warn, compile exits 0 and writes the C"
else
    bad "no manifest default" "$(head -2 "$work/none.log")"
fi

# 2) an explicit warn package behaves the same on the build path.
run_build warn "$work/warn/out"
if [ $? -eq 0 ] && [ -f "$work/warn/out/prog.c" ] \
        && grep -Fq "warning: potential leak" "$work/warn.log"; then
    ok "leaks = warn: build exits 0, warning, product written"
else
    bad "leaks = warn" "$(head -2 "$work/warn.log")"
fi

# 3) an old package without the key is unchanged.
run_build old "$work/old/out"
if [ $? -eq 0 ] && [ -f "$work/old/out/prog.c" ] \
        && grep -Fq "warning: potential leak" "$work/old.log"; then
    ok "old manifest (no leaks key): unchanged warning, exit 0"
else
    bad "old manifest" "$(head -2 "$work/old.log")"
fi

# 4) leaks = error: build fails with error: before writing the product.
run_build err "$work/err/out"
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq "error: potential leak: 'p' (S*) allocated but never deleted" "$work/err.log"; then
    ok "leaks = error: build exits 1 with error: on the same record"
else
    bad "leaks = error build" "exit $rc: $(head -2 "$work/err.log")"
fi
if [ -e "$work/err/out/prog.c" ]; then
    bad "leaks = error artifact" "a failed build still wrote prog.c"
else
    ok "leaks = error: no .c product is written"
fi

# 5) the compile entry honours the unit's own manifest (it ignores -I).
rm -f "$work/err/prog.compile.c"
"$ctast" compile --allow-c-boundary "$work/err/prog.ct" -o "$work/err/prog.compile.c" \
    >"$work/err.compile.log" 2>&1
rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$work/err/prog.compile.c" ] \
        && grep -Fq "error: potential leak" "$work/err.compile.log"; then
    ok "compile: error package fails before writing the C (no -I needed)"
else
    bad "compile error package" "exit $rc; $(head -2 "$work/err.compile.log")"
fi

# 6) JSON carries the escalated severity; warn JSON does not.
run_build err "$work/err/json" --diagnostics=json
if [ $? -eq 1 ] && grep -Fq '"severity":"error"' "$work/err.log" \
        && grep -Fq '"type":"potential_leak"' "$work/err.log"; then
    ok "JSON: leaks = error record carries \"severity\":\"error\""
else
    bad "JSON error severity" "$(head -2 "$work/err.log")"
fi
run_build warn "$work/warn/json" --diagnostics=json
if [ $? -eq 0 ] && ! grep -Fq '"severity"' "$work/warn.log" \
        && grep -Fq '"type":"potential_leak"' "$work/warn.log"; then
    ok "JSON: warn package keeps the pre-PH-82 shape"
else
    bad "JSON warn shape" "$(head -2 "$work/warn.log")"
fi

# 7) c-boundary: v1-PH-2 S9 flipped the no-key default to strict, so a
#    leaks-only manifest is strict too; an explicit key still wins.
got=$(env -u CT_C_BOUNDARY "$ctast" build -I "$work/err" --show-c-boundary "$work/err/prog.ct" 2>"$work/err.cb")
if [ "$got" = "strict" ]; then
    ok "c-boundary: a leaks-only manifest is strict by default (S9)"
else
    bad "c-boundary leaks-only" "want 'strict', got '$got' ($(head -1 "$work/err.cb"))"
fi
got=$(env -u CT_C_BOUNDARY "$ctast" build -I "$work/strict" --show-c-boundary "$work/strict/prog.ct" 2>"$work/strict.cb")
if [ "$got" = "strict" ]; then
    ok "c-boundary: an explicit c-boundary = strict still wins"
else
    bad "c-boundary strict" "want 'strict', got '$got'"
fi

# 8) a clean unit in the same error package still passes both entries.
"$ctast" check "$work/err/clean.ct" >"$work/err.clean.log" 2>&1
if [ $? -eq 0 ] && [ ! -s "$work/err.clean.log" ]; then
    ok "leaks = error: a clean unit still exits 0 with no findings"
else
    bad "clean unit" "$(head -2 "$work/err.clean.log")"
fi
"$ctast" build --c-boundary=allow --emit-c -o "$work/plain" "$work/err/clean.ct" \
    >"$work/plain.log" 2>&1
if [ $? -eq 0 ]; then
    ok "leaks = error: a clean build still succeeds"
else
    bad "clean build" "$(head -2 "$work/plain.log")"
fi

# 9) the key is narrow: a different warning class keeps its severity and the
#    build keeps its pre-PH-82 exit code. `--check-level=off` parks the B/type
#    level (v1-PH-1 S3 default `error` would escalate the arity record) so this
#    assertion stays about `leaks` alone.
mkdir -p "$work/err/arity"
"$ctast" build --check-level=off -I "$work/err" --emit-c -o "$work/err/arity" "$work/err/arity.ct" \
    >"$work/err.arity.log" 2>&1
rc=$?
if [ "$rc" -eq 0 ] && grep -Fq "warning: arity mismatch" "$work/err.arity.log" \
        && ! grep -Fq "error: arity mismatch" "$work/err.arity.log"; then
    ok "leaks = error does not escalate arity (still a warning, exit 0)"
else
    bad "narrow scope" "exit $rc; $(head -2 "$work/err.arity.log")"
fi

[ "$fail" -eq 0 ] && echo "p82_config: OK"
exit "$fail"
