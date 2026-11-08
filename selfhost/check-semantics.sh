#!/usr/bin/env bash
#
# check-semantics.sh - the semantic entry's gate (Phase 19.4).
#
# Builds the bootstrap chain and the AST compiler, then asserts the behaviour
# of `ct check` (D19-4):
#
#   - a clean unit exits 0 and prints nothing;
#   - a `.m.ct` declaration unit is a valid input, an import-bearing unit is not;
#   - each finding class (arity, argument type, ambiguous method, impl/trait
#     parameter drift) exits 1 and reads `error:` in text mode at
#     `file:line:col:`;
#   - `--diagnostics=json` is one parseable document whose records carry
#     `"severity":"error"` and `"col"`;
#   - the same units through `ct compile` still exit 0 with `file:line:`
#     `warning:` lines and still write their `.c`, so the 19.1-19.3 policy is
#     unchanged.
#
# Exit code 0 means every assertion passed.

set -u

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root" || exit 1

CC="${CC:-cc}"
work="${TMPDIR:-/tmp}"
work="${work%/}/ct-semantics-test.$$"

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

# -- the probes ------------------------------------------------------------

cat > "$work/clean.ct" <<'EOF'
trait A { int f(int v); }
struct S { int n; } use A;
impl A for S { int f(int v) { return v + self->n; } }

int main(void)
{
    struct S s;
    s.n = 1;
    return s.f(2);
}
EOF
"$work/ct-ast" check "$work/clean.ct" >"$work/clean.out" 2>"$work/clean.err"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$work/clean.out" ] && [ ! -s "$work/clean.err" ]; then
    ok "check: a clean unit exits 0 and prints nothing"
else
    bad "check: clean unit" "exit $rc; $(cat "$work/clean.err")"
fi

cat > "$work/decl.m.ct" <<'EOF'
namespace m;
pub trait Shape { int area(int scale); }
EOF
"$work/ct-ast" check "$work/decl.m.ct" >"$work/map.out" 2>"$work/map.err"
rc=$?
if [ "$rc" -eq 0 ] && [ ! -s "$work/map.out" ] && [ ! -s "$work/map.err" ]; then
    ok "check: a .m.ct declaration unit is a valid input (SH-49)"
else
    bad "check: .m.ct input" "exit $rc; $(cat "$work/map.err")"
fi

"$work/ct-ast" compile "$work/decl.m.ct" -o "$work/decl.c" >"$work/mapc.out" 2>"$work/mapc.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq 'a .m.ct unit produces no output' "$work/mapc.err"; then
    ok "compile: .m.ct is still rejected as a build-only input"
else
    bad "compile: .m.ct guard" "exit $rc; $(cat "$work/mapc.err")"
fi

# `ct check` is a single-unit entry (DOC-62): an import-bearing unit is
# rejected by the compiler, and the message says why check cannot take it
# (SH-55). If check ever gains multi-unit support this assertion and the two
# docs tables must change together.
cat > "$work/import.ct" <<'EOF'
import other::Thing;

int main(void) { return 0; }
EOF
"$work/ct-ast" check "$work/import.ct" >"$work/import.out" 2>"$work/import.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && grep -Fq "'import' requires multi-file mode: use 'ct build' (ct check is single-unit)" \
            "$work/import.err"; then
    ok "check: an import-bearing unit is rejected with a check-specific reason (SH-55)"
else
    bad "check: import guard" "exit $rc; $(cat "$work/import.err")"
fi

# SH-54: `-I` cannot affect a single-unit mode, so it is reported instead of
# being dropped; the exit code is unchanged so scripts keep composing.
"$work/ct-ast" check -I /tmp "$work/clean.ct" >"$work/ign.out" 2>"$work/ign.err"
rc=$?
if [ "$rc" -eq 0 ] \
        && grep -Fq "ctc: warning: -I is ignored by check mode; imports require 'ct build'" \
            "$work/ign.err"; then
    ok "check: -I is reported as ignored and the exit code stays 0 (SH-54)"
else
    bad "check: -I warning" "exit $rc; $(cat "$work/ign.err")"
fi

cat > "$work/arity.ct" <<'EOF'
int add(int a, int b) { return a + b; }
int main(void) { return add(1); }
EOF
"$work/ct-ast" check "$work/arity.ct" >"$work/arity.out" 2>"$work/arity.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && grep -q 'error: arity mismatch: '"'"'add'"'"' takes 2 argument(s), 1 given' "$work/arity.err"; then
    ok "check: a call-site arity mismatch is an error (exit 1)"
else
    bad "check: arity probe" "exit $rc; $(cat "$work/arity.err")"
fi

# Phase 21 S4: closure escapes are hard errors on both entries, and the
# independent `note:` line neither becomes a second error nor changes the
# `ctc: N error(s) generated` count. `ct check` must keep its strict exit 1.
cat > "$work/cl_escape.ct" <<'EOF'
void *get(void)
{
    int n = 1;
    int (*c)(int x) = (int x) => x + n;
    return c;
}
int main(void) { return 0; }
EOF
"$work/ct-ast" check "$work/cl_escape.ct" >"$work/cl_escape.out" 2>"$work/cl_escape.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && grep -Fq "error: a closure cannot escape through 'return'" "$work/cl_escape.err" \
        && grep -Fq "note: use an explicit Callable struct + trait:" "$work/cl_escape.err" \
        && grep -Fq 'ctc: 1 error(s) generated' "$work/cl_escape.err"; then
    ok "check: a closure escape is one hard error plus its note (exit 1)"
else
    bad "check: closure escape probe" "exit $rc; $(cat "$work/cl_escape.err")"
fi

"$work/ct-ast" compile "$work/cl_escape.ct" -o "$work/cl_escape.c" \
    >"$work/cl_escape.comp.out" 2>"$work/cl_escape.comp.err"
rc=$?
if [ "$rc" -eq 1 ] && [ ! -e "$work/cl_escape.c" ] \
        && grep -Fq "error: a closure cannot escape through 'return'" "$work/cl_escape.comp.err"; then
    ok "compile: a closure escape is still a hard error and writes no C"
else
    bad "compile: closure escape probe" "exit $rc; $(cat "$work/cl_escape.comp.err")"
fi

"$work/ct-ast" check --diagnostics=json "$work/cl_escape.ct" \
    >"$work/cl_escape.json" 2>"$work/cl_escape.json.err"
rc=$?
if [ "$rc" -eq 1 ] && [ ! -s "$work/cl_escape.json" ] \
        && grep -Fq "note: use an explicit Callable struct + trait:" "$work/cl_escape.json.err"; then
    ok "check: the closure note adds no JSON key (still no warnings document)"
else
    bad "check: closure JSON" "exit $rc; $(cat "$work/cl_escape.json" "$work/cl_escape.json.err")"
fi

cat > "$work/atype.ct" <<'EOF'
struct P { int n; }
struct Q { int n; }
int setp(struct P *p) { return p->n; }
int main(void) { struct Q q; q.n = 1; return setp(&q); }
EOF
"$work/ct-ast" check "$work/atype.ct" >"$work/atype.out" 2>"$work/atype.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && grep -Fq "error: type mismatch: 'setp' argument 1: expected 'struct P *', got 'struct Q *'" "$work/atype.err"; then
    ok "check: an argument type mismatch is an error (exit 1)"
else
    bad "check: argument type probe" "exit $rc; $(cat "$work/atype.err")"
fi

cat > "$work/amb.ct" <<'EOF'
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
EOF
"$work/ct-ast" check "$work/amb.ct" >"$work/amb.out" 2>"$work/amb.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && grep -q "error: ambiguous method: 'f' declared by 'A' and 'B'; 'A' is used" "$work/amb.err"; then
    ok "check: an ambiguous trait method is an error (exit 1)"
else
    bad "check: ambiguity probe" "exit $rc; $(cat "$work/amb.err")"
fi

"$work/ct-ast" check --diagnostics=json "$work/amb.ct" >"$work/amb.json" 2>"$work/amb_json.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && python3 -m json.tool "$work/amb.json" >/dev/null 2>&1 \
        && grep -Fq '"severity":"error"' "$work/amb.json" \
        && grep -Fq '"col":' "$work/amb.json" \
        && grep -Fq '"type":"ambiguous_method"' "$work/amb.json"; then
    ok "check: --diagnostics=json is one document with severity and type"
else
    bad "check: json diagnostics" "exit $rc; $(cat "$work/amb.json")"
fi

# The trait lives in the same unit here; the imported-unit half of the check
# is exercised in check-ast.sh, this gate only pins the entry's behaviour.
cat > "$work/drift.ct" <<'EOF'
trait W { int put(int v); }
struct P { int n; } use W;
impl W for P { int put(struct P *v) { (void)v; return 0; } }

int main(void)
{
    struct P p;
    p.n = 1;
    return p.put(1);
}
EOF
"$work/ct-ast" check "$work/drift.ct" >"$work/drift.out" 2>"$work/drift.err"
rc=$?
if [ "$rc" -eq 1 ] \
        && grep -Fq "error: signature mismatch: 'put' in impl of 'W' for 'P': parameter 1 type 'struct P *' does not match the trait's 'int'" "$work/drift.err"; then
    ok "check: impl parameter drift is an error (exit 1)"
else
    bad "check: impl drift probe" "exit $rc; $(cat "$work/drift.err")"
fi

# SH-50: check findings carry the token's column, the location contract the
# parser errors already follow.
for name in arity atype amb drift; do
    if grep -Eq "$name.ct:[0-9]+:[0-9]+: error:" "$work/$name.err"; then
        ok "check: the $name finding carries file:line:col"
    else
        bad "check: $name location" "$(cat "$work/$name.err")"
    fi
done

# -- compile is unchanged --------------------------------------------------

# Every finding class stays a warning on the compile path (D19-4): exit 0,
# a written `.c`, `warning:` lines and no `error:` line. The ambiguity case
# additionally pins its exact wording.
for name in arity atype amb drift; do
    "$work/ct-ast" compile "$work/$name.ct" -o "$work/$name.c" \
        >"$work/$name.comp.out" 2>"$work/$name.comp.err"
    rc=$?
    if [ "$rc" -eq 0 ] && [ -s "$work/$name.c" ] \
            && grep -q 'warning:' "$work/$name.comp.err" \
            && ! grep -q 'error:' "$work/$name.comp.err" \
            && ! grep -Eq "$name.ct:[0-9]+:[0-9]+: warning:" "$work/$name.comp.err"; then
        ok "compile: the $name finding stays a warning, exits 0 and writes its C"
    else
        bad "compile: $name policy" "exit $rc; $(cat "$work/$name.comp.err")"
    fi
done

if grep -Fq "warning: ambiguous method: 'f' declared by 'A' and 'B'; 'A' is used" \
        "$work/amb.comp.err"; then
    ok "compile: the ambiguity wording is the pre-existing one"
else
    bad "compile: ambiguity wording" "$(cat "$work/amb.comp.err")"
fi

# `ct check` writes no C even when handed an output path.
rm -f "$work/none.c"
"$work/ct-ast" check "$work/clean.ct" -o "$work/none.c" >/dev/null 2>&1
if [ ! -e "$work/none.c" ]; then
    ok "check: no C artefact is written"
else
    bad "check: artefact" "$work/none.c exists"
fi

echo
if [ "$fail" -eq 0 ]; then
    printf 'check-semantics: OK (%d assertions)\n' "$pass"
    rm -rf "$work"
    exit 0
fi
printf 'check-semantics: FAIL (%d failed, %d passed; work left at %s)\n' "$fail" "$pass" "$work"
exit 1
