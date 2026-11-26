#!/bin/sh
#
# s7_mem2_probe.sh - REQ-MEM-2 (v1-PH-2 S7-c) acceptance probe.
#
# The generic fixture loops compile positives and reject negatives; this probe
# adds the cases the matrix in docs/planning/s7-evidence-baseline.md §5 pins but
# a single compile cannot express:
#   - D1: a `goto` that skips a `borrow` declaration stays deferred (no finding);
#   - D2: a cross-unit callee is conservatively passed;
#   - P1: a `borrow` parameter stored into a global adds no write-summary
#         finding (the pre-existing stage-one borrow-store rule still owns the
#         definition; see the note printed below);
#   - the build escape hatch: `--check-level=off` writes the product and
#     `--check-level=warn` keeps it with a warning.
#
# Usage: sh test/ast/s7_mem2_probe.sh <ct-ast-binary>
# Exit: 0 all assertions hold; 1 otherwise.
set -u

ct=${1:-}
[ -x "$ct" ] || { echo "s7_mem2_probe: need an executable ct-ast" >&2; exit 2; }
root=$(cd "$(dirname "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${CT_SHORT_TMP:-/tmp}/s7mem2.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

# D1 ------------------------------------------------------------------------
cat > "$work/d1.ct" <<'CT'
struct Conn { int fd; } use Handback;
impl Handback for Conn { void handback() { self->fd = 0; } }
static struct Conn g_c;
static struct Conn *acq(void) { return &g_c; }
void f(int k)
{
    if (k) goto L;
    borrow struct Conn *c = acq();
L: ;
}
int main(void) { f(1); return 0; }
CT
"$ct" check "$work/d1.ct" >"$work/d1.out" 2>"$work/d1.err"
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q "stored outside the call" "$work/d1.err"; then
    ok "D1 goto over a borrow declaration stays deferred"
else
    bad "D1 goto" "exit $rc; $(cat "$work/d1.err")"
fi

# D2 ------------------------------------------------------------------------
mkdir -p "$work/d2"
cat > "$work/d2/b.h.ct" <<'CT'
pub struct Conn { int fd; };
pub struct Conn *bg;
pub void sink(struct Conn *c) { bg = c; }
CT
cat > "$work/d2/main.ct" <<'CT'
import b;
int main(void)
{
    struct Conn local;
    local.fd = 1;
    sink(&local);
    return 0;
}
CT
"$ct" build "$work/d2/main.ct" -o "$work/d2/prog.bin" >"$work/d2.out" 2>"$work/d2.err"
rc=$?
if [ "$rc" -eq 0 ] && ! grep -q "stored outside the call" "$work/d2.err"; then
    ok "D2 cross-unit callee is conservatively passed"
else
    bad "D2 cross-unit" "exit $rc; $(cat "$work/d2.err")"
fi

# P1: the new judgement must not add a finding. The definition still trips the
# pre-existing stage-one borrow-store rule, so the probe records that known
# conflict separately instead of pretending the unit is clean end to end.
cat > "$work/p1.ct" <<'CT'
struct Conn { int fd; };
struct Conn *g;
void put(borrow struct Conn *c) { g = c; }
int main(void) { struct Conn local; local.fd = 1; put(&local); return 0; }
CT
"$ct" check "$work/p1.ct" >"$work/p1.out" 2>"$work/p1.err"
if ! grep -q "stored outside the call" "$work/p1.err"; then
    if grep -q "a borrowed pointer cannot be stored in 'g'" "$work/p1.err"; then
        printf '  note  P1: no write-summary finding; the stage-one borrow-store rule still rejects the definition\n'
    fi
    ok "P1 borrow parameter adds no write-summary finding"
else
    bad "P1 borrow parameter" "$(cat "$work/p1.err")"
fi

# --check-level escape ------------------------------------------------------
cat > "$work/n1.ct" <<'CT'
struct Conn { int fd; };
struct Conn *g;
void put(struct Conn *c) { g = c; }
int main(void) { struct Conn local; local.fd = 1; put(&local); return 0; }
CT
"$ct" build --check-level=off "$work/n1.ct" -o "$work/n1.off.bin" \
    >"$work/off.out" 2>"$work/off.err"
rc=$?
if [ "$rc" -eq 0 ] && [ -x "$work/n1.off.bin" ]; then
    ok "--check-level=off writes the product despite an unannotated escape"
else
    bad "--check-level=off" "exit $rc; $(cat "$work/off.err")"
fi
"$ct" build "$work/n1.ct" -o "$work/n1.err.bin" \
    >"$work/on.out" 2>"$work/on.err"
rc=$?
if [ "$rc" -ne 0 ] && grep -q "declare the parameter 'borrow'" "$work/on.err"; then
    ok "build default rejects the unannotated escape"
else
    bad "build default" "exit $rc; $(cat "$work/on.err")"
fi
"$ct" build --check-level=warn "$work/n1.ct" -o "$work/n1.warn.bin" \
    >"$work/warn.out" 2>"$work/warn.err"
rc=$?
if [ "$rc" -eq 0 ] && [ -x "$work/n1.warn.bin" ] \
        && grep -q "warning: call to 'put'" "$work/warn.err"; then
    ok "--check-level=warn keeps the build and warns"
else
    bad "--check-level=warn" "exit $rc; $(cat "$work/warn.err")"
fi

if [ "$fail" -ne 0 ]; then
    printf 's7_mem2_probe: FAIL (%d passed, %d failed)\n' "$pass" "$fail"
    exit 1
fi
printf 's7_mem2_probe: OK (%d assertions)\n' "$pass"
exit 0
