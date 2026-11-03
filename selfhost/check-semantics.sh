#!/usr/bin/env bash
#
# check-semantics.sh - the semantic entry's gate (Phase 19.4).
#
# Builds the bootstrap chain and the AST compiler, then asserts the behaviour
# of `ct check` (D19-4):
#
#   - a clean unit exits 0 and prints nothing;
#   - each finding class (arity, argument type, ambiguous method, impl/trait
#     parameter drift) exits 1 and reads `error:` in text mode;
#   - `--diagnostics=json` is one parseable document whose records carry
#     `"severity":"error"`;
#   - the same unit through `ct compile` still exits 0 with `warning:` lines
#     and still writes its `.c`, so the 19.1-19.3 policy is unchanged.
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
if "$work/ct-ast" check "$work/clean.ct" >"$work/clean.out" 2>"$work/clean.err" \
        && [ ! -s "$work/clean.out" ] && [ ! -s "$work/clean.err" ]; then
    ok "check: a clean unit exits 0 and prints nothing"
else
    bad "check: clean unit" "exit $?; $(cat "$work/clean.err")"
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

# -- compile is unchanged --------------------------------------------------

"$work/ct-ast" compile "$work/amb.ct" -o "$work/amb.c" >"$work/comp.out" 2>"$work/comp.err"
rc=$?
if [ "$rc" -eq 0 ] && [ -s "$work/amb.c" ] \
        && grep -q "warning: ambiguous method: 'f' declared by 'A' and 'B'; 'A' is used" "$work/comp.err" \
        && ! grep -q 'error: ambiguous method' "$work/comp.err"; then
    ok "compile: same unit still exits 0, warns, and writes its C"
else
    bad "compile: unchanged policy" "exit $rc; $(cat "$work/comp.err")"
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
