#!/bin/sh
# LANG-25: the stable diagnostic-code registry, wired through text and JSON.
#
#   - `--diag-codes` appends `[E-...]` / `[W-...]` to a diagnostic line;
#     without the flag the bytes stay exactly what they were before the change;
#   - `--diagnostics=json` carries the same code in every record;
#   - a representative batch across parse / driver / lower / type / trait /
#     name / mem / lang is exercised; docs/diagnostics/codes.md is the registry
#     and test/docs/check-docs.py enforces uniqueness and source equality.
#
# Usage: sh test/ast/p_lang25.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p_lang25.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/plang25.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
CT_CORE_DIR="$root/lib/core"
export CT_CORE_DIR
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p_lang25: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

cat >"$work/clean.ct" <<'EOF'
int main(void) { return 0; }
EOF
cat >"$work/pe.ct" <<'EOF'
int main(void) { return 1 + ; }
EOF
cat >"$work/tok.ct" <<'EOF'
int main(void) { return 0 }
EOF
cat >"$work/und.ct" <<'EOF'
int main(void) { return x; }
EOF
cat >"$work/br.ct" <<'EOF'
int main(void) { break; }
EOF
cat >"$work/co.ct" <<'EOF'
int main(void) { continue; }
EOF
cat >"$work/unr.ct" <<'EOF'
int main(void) { return 0; int x = 1; }
EOF
cat >"$work/imp.ct" <<'EOF'
import nope::Thing;
int main(void) { return 0; }
EOF
cat >"$work/arity.ct" <<'EOF'
int add(int a, int b) { return a + b; }
int main(void) { return add(1); }
EOF
cat >"$work/atype.ct" <<'EOF'
struct P { int n; }
struct Q { int n; }
int setp(struct P *p) { return p->n; }
int main(void) { struct Q q; q.n = 1; return setp(&q); }
EOF
cat >"$work/amb.ct" <<'EOF'
trait A { void f(); }
trait B { void f(); }
struct S { int n; } use A, B;
impl A for S { void f() {} }
impl B for S { void f() {} }
int main(void) { struct S s; s.n = 1; s.f(); return 0; }
EOF
cat >"$work/sig.ct" <<'EOF'
trait T { int f(int x); }
struct S { int n; } use T;
impl T for S { int f(char *x) { return 0; } }
int main(void) { return 0; }
EOF
cat >"$work/leak.ct" <<'EOF'
#include <stdlib.h>
struct S { int n; };
int main(void) {
    S *p = malloc(sizeof(struct S));
    return 0;
}
EOF
cat >"$work/leakpath.ct" <<'EOF'
#include <stdlib.h>
struct S { int n; };
int main(void) {
    S *p = malloc(sizeof(struct S));
    if (p) return 0;
    return 1;
}
EOF
cat >"$work/slice.ct" <<'EOF'
int[] f(void)
{
    int a[] = { 1, 2 };
    int[] s = a;
    return s;
}
int main(void) { int[] r = f(); return r[0] - 1; }
EOF
cat >"$work/loop.ct" <<'EOF'
#include <stdio.h>
int main(void)
{
    loop(2) {
        loop(2) {
            printf("x\n");
        }
    }
    return 0;
}
EOF
cat >"$work/ret.ct" <<'EOF'
#include <stdlib.h>
struct R { int n; } use Drop;
impl Drop for R { void drop() { } }
int f(void)
{
    own struct R *r = malloc(sizeof(struct R));
    r->n = 1;
    defer { }
    return 0;
}
int main(void) { return f(); }
EOF
cat >"$work/err.ct" <<'EOF'
Result<int, char *> fail(void) { return err: (Result<int, char *>){0, 0, "e"}; }
Result<int, char *> run(void)
{
    defer { }
    errdefer { }
    int v = fail()?;
    return (Result<int, char *>){1, v, 0};
}
int main(void) { return run().ok - 1; }
EOF
cat >"$work/chain.ct" <<'EOF'
trait H { H tap(int n); int get(); }
struct R { int s; } use H;
impl H for R {
    H tap(int n) { self->s = self->s + n; return self; }
    int get() { return self->s; }
}
int main(void)
{
    R x; x.s = 1; H h = x;
    int got = h.tap(2)->tap(3)->get();
    return got - 6;
}
EOF
cat >"$work/chainnest.ct" <<'EOF'
#include <stdio.h>
trait H { H tap(int n); int get(); }
struct R { int s; } use H;
impl H for R {
    H tap(int n) { self->s = self->s + n; return self; }
    int get() { return self->s; }
}
int main(void)
{
    R x; x.s = 1; H h = x;
    printf("%d\n", h.tap(2)->tap(3)->get());
    return 0;
}
EOF
# ---- text: one code per diagnostic ---------------------------------------

expect_text() {
    name=$1
    code=$2
    shift 2
    "$@" >"$work/$name.out" 2>"$work/$name.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        bad "$name" "exit 0; expected a diagnostic with $code"
        return
    fi
    if ! grep -Fq "[$code]" "$work/$name.err"; then
        bad "$name" "missing [$code]: $(sed -n '1,2p' "$work/$name.err")"
        return
    fi
    if ! grep -Eq ':[0-9]+:[0-9]+: (error|warning): |^ctc: ' "$work/$name.err"; then
        bad "$name" "the code landed without a diagnostic line: $(sed -n '1,2p' "$work/$name.err")"
        return
    fi
    ok "$name ($code)"
}

expect_text parse-001 E-PARSE-001 "$ctast" --diag-codes "$work/tok.ct" -o "$work/x.c"
expect_text parse-002 E-PARSE-002 "$ctast" --diag-codes "$work/pe.ct" -o "$work/x.c"
expect_text parse-004 E-PARSE-004 "$ctast" --diag-codes "$work/und.ct" -o "$work/x.c"
expect_text parse-006 E-PARSE-006 "$ctast" --diag-codes test/ast/errors/p38_defer_control.ct -o "$work/x.c"
expect_text parse-007 E-PARSE-007 "$ctast" --diag-codes test/ast/errors/p40_errdefer_control/prog.ct -o "$work/x.c"
expect_text parse-008 E-PARSE-008 "$ctast" check --semantics --diag-codes "$work/br.ct"
expect_text parse-009 E-PARSE-009 "$ctast" check --semantics --diag-codes "$work/co.ct"
expect_text parse-010 E-PARSE-010 "$ctast" check --semantics --diag-codes "$work/unr.ct"
expect_text parse-012 E-PARSE-012 "$ctast" --diag-codes test/ast/errors/p38_goto_cross.ct -o "$work/x.c"
expect_text parse-013 E-PARSE-013 "$ctast" --diag-codes test/ast/errors/p40_errdefer_own/prog.ct -o "$work/x.c"
expect_text parse-014 E-PARSE-014 "$ctast" --diag-codes test/ast/errors/closure_escape_return.ct -o "$work/x.c"
expect_text parse-999 E-PARSE-999 "$ctast" --diag-codes test/ast/errors/raw_unclosed.ct -o "$work/x.c"
expect_text driver-001 E-DRIVER-001 "$ctast" check --diag-codes "$work/imp.ct"
expect_text driver-002 E-DRIVER-002 "$ctast" --diag-codes "$work/does-not-exist.ct" -o "$work/x.c"
expect_text driver-003 E-DRIVER-003 "$ctast" --diag-codes test/ast/67_type_alias/lib/lib.m.ct -o "$work/x.c"
expect_text driver-004 E-DRIVER-004 "$ctast" --diag-codes "$work/clean.ct" -o "$work/no/such/x.c"
expect_text lower-001 E-LOWER-001 "$ctast" --diag-codes "$work/chainnest.ct" -o "$work/x.c"
expect_text lower-I1 E-LOWER-004 env CT_EMIT_INVARIANT_FAULT=cleanup-jump "$ctast" --diag-codes "$work/ret.ct" -o "$work/x.c"
expect_text lower-I2 E-LOWER-005 env CT_EMIT_INVARIANT_FAULT=cleanup-drop-first "$ctast" --diag-codes "$work/ret.ct" -o "$work/x.c"
expect_text lower-I3 E-LOWER-006 env CT_EMIT_INVARIANT_FAULT=errdefer-normal "$ctast" --diag-codes "$work/err.ct" -o "$work/x.c"
expect_text lower-I4 E-LOWER-007 env CT_EMIT_INVARIANT_FAULT=temp-missing "$ctast" --diag-codes "$work/chain.ct" -o "$work/x.c"
expect_text type-001 W-TYPE-001 "$ctast" check --types --diag-codes "$work/arity.ct"
expect_text type-002 W-TYPE-002 "$ctast" check --types --diag-codes "$work/atype.ct"
expect_text trait-001 W-TRAIT-001 "$ctast" check --diag-codes "$work/amb.ct"
expect_text trait-002 W-TRAIT-002 "$ctast" check --diag-codes "$work/sig.ct"

cat >"$work/borrow.ct" <<'EOF'
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
EOF

# A warning keeps compile mode's exit 0 (LANG-25 does not change severities);
# only the diagnostic line carries the code.
expect_warn_text() {
    name=$1
    code=$2
    shift 2
    "$@" >"$work/$name.out" 2>"$work/$name.err"
    if ! grep -Fq "[$code]" "$work/$name.err"; then
        bad "$name" "missing [$code]: $(sed -n '1,2p' "$work/$name.err")"
        return
    fi
    ok "$name ($code)"
}

expect_warn_text name-001 W-NAME-001 "$ctast" --diag-codes "$work/loop.ct" -o "$work/x.c"
expect_warn_text mem-001 W-MEM-001 "$ctast" --diag-codes "$work/leak.ct" -o "$work/x.c"
expect_warn_text mem-002 W-MEM-002 "$ctast" --diag-codes "$work/leakpath.ct" -o "$work/x.c"
expect_warn_text mem-004 W-MEM-004 "$ctast" --diag-codes "$work/slice.ct" -o "$work/x.c"
expect_warn_text mem-006 W-MEM-006 "$ctast" --diag-codes test/ast/p106_str_escape/ret_local.ct -o "$work/x.c"
expect_warn_text mem-003 W-MEM-003 "$ctast" --diag-codes "$work/borrow.ct" -o "$work/x.c"
mkdir -p "$work/shadow/vendor"
: >"$work/shadow/vendor/std"
cat >"$work/shadow/p.ct" <<'EOF'
struct A { Map<char *, int> *m; };
int main(void) { return 0; }
EOF
if ( cd "$work/shadow" && CT_CORE_DIR="$CT_CORE_DIR" "$ctast" --diag-codes p.ct -o p.c ) \
        >"$work/shadow.out" 2>"$work/shadow.err" \
   && grep -Fq "[W-DRIVER-001]" "$work/shadow.err"; then
    ok "std-shadow (W-DRIVER-001)"
else
    bad "std-shadow" "$(sed -n '1,3p' "$work/shadow.err")"
fi

# ---- JSON: the same code, no text channel --------------------------------

expect_json_rec() {
    name=$1
    code=$2
    expect_rc=$3
    shift 3
    "$@" >"$work/$name.json" 2>"$work/$name.err"
    rc=$?
    if [ "$expect_rc" = "nonzero" ] && [ "$rc" -eq 0 ]; then
        bad "$name" "exit 0; expected a JSON diagnostic with $code"
        return
    fi
    if ! python3 - "$work/$name.json" "$code" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
records = doc.get("errors", doc.get("warnings", []))
assert records, "empty diagnostic document"
assert records[0].get("code") == sys.argv[2], records[0]
PY
    then
        bad "$name" "JSON code mismatch: $(sed -n '1,2p' "$work/$name.json")"
        return
    fi
    ok "$name (JSON $code)"
}

expect_json_rec json-parse E-PARSE-002 nonzero "$ctast" --diagnostics=json "$work/pe.ct" -o "$work/x.c"
expect_json_rec json-mem W-MEM-001 zero "$ctast" --diagnostics=json "$work/leak.ct" -o "$work/x.c"
expect_json_rec json-trait W-TRAIT-001 nonzero "$ctast" check --diagnostics=json "$work/amb.ct"

# ---- text/JSON agreement for one warning ---------------------------------

"$ctast" --diag-codes "$work/leak.ct" -o "$work/x.c" 2>"$work/agree.text" || true
"$ctast" --diagnostics=json "$work/leak.ct" -o "$work/x.c" >"$work/agree.json" 2>/dev/null || true
if grep -Fq "[W-MEM-001]" "$work/agree.text" \
        && python3 - "$work/agree.json" <<'PY'
import json, sys
doc = json.load(open(sys.argv[1]))
assert doc["warnings"][0]["code"] == "W-MEM-001", doc
PY
then
    ok "text and JSON agree on W-MEM-001"
else
    bad "text/JSON code agreement" "$(sed -n '1,2p' "$work/agree.text")"
fi

# ---- registry presence ----------------------------------------------------

if [ -f docs/diagnostics/codes.md ] && grep -q '| E-PARSE-001 |' docs/diagnostics/codes.md \
        && grep -q '| W-MEM-001 |' docs/diagnostics/codes.md; then
    ok "docs/diagnostics/codes.md is present"
else
    bad "docs/diagnostics/codes.md missing or unregistered"
fi

echo "p_lang25: $fail failure(s)"
[ "$fail" -eq 0 ] || exit 1
exit 0
