#!/usr/bin/env bash
# v1-PH-2 S1a-0 C2p probe: the remaining one-shot text scratches are gone.
#
# C2p runs in batches of 4-6 units; this file grows one section per batch.
#
#   C2p-1 qualified path: the qpath/cname output buffers were `char[160]`, so a
#          qualified name whose underscore form was longer than 159 bytes was
#          refused with "qualified name is too long" even though every segment
#          was short. A qualified variable and a qualified call are compiled and
#          run, and the generated C must carry the whole mangled spelling.
#
# Usage: bash test/ast/c2p_limits.sh <ct-ast>
set -u
CT=${1:?usage: c2p_limits.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/c2p.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL c2p: $1" >&2; }
CC=${CC:-cc}
export CT_C_BOUNDARY=allow

# run_product <name> <source> [extra ct args...]
# one unit -> emitted C -> cc -> run; the caller checks the C separately when
# it needs to pin a full spelling.
run_product() {
    name=$1; src=$2; shift 2
    if ! "$CT" "$src" -o "$work/$name.c" "$@" >"$work/$name.log" 2>&1; then
        bad "$name: compile failed: $(head -2 "$work/$name.log" | tr '\n' ' ')"
        return 1
    fi
    if ! "$CC" -std=c99 "$work/$name.c" -o "$work/$name.bin" >"$work/$name.cc" 2>&1; then
        bad "$name: cc failed: $(head -2 "$work/$name.cc" | tr '\n' ' ')"
        return 1
    fi
    if "$work/$name.bin"; then return 0; fi
    bad "$name: program returned non-zero"
    return 1
}

# ---- C2p-1.1) qualified variable whose underscore form is >160 bytes --------
# Three 60-byte namespace segments: the qualifier joins to 181 bytes, which the
# old qpath[160] refused before the symbol lookup could even run.
seg=$(printf '%*s' 60 '' | tr ' ' a)
ns="$seg::$seg::$seg"
mangled="${ns//::/_}"
cat >"$work/qv.ct" <<CT
namespace $ns;
int h = 7;
int main(void) { return $ns::h == 7 ? 0 : 1; }
CT
if run_product qv "$work/qv.ct"; then
    if grep -qF "${mangled}_h" "$work/qv.c"; then
        ok; printf '  >160-byte qualified variable: resolved and emitted whole\n'
    else
        bad "the generated C cut the >160-byte qualified variable spelling"
    fi
fi

# ---- C2p-1.2) qualified call whose underscore form is >160 bytes -----------
cat >"$work/qc.ct" <<CT
namespace $ns;
pub int bump(void) { return 7; }
int main(void) { return $ns::bump() == 7 ? 0 : 1; }
CT
if run_product qc "$work/qc.ct"; then
    if grep -qF "${mangled}_bump" "$work/qc.c"; then
        ok; printf '  >160-byte qualified call: resolved and emitted whole\n'
    else
        bad "the generated C cut the >160-byte qualified call spelling"
    fi
fi

# ---- C2p-1.3) 200/1000-byte literals stay byte-exact (guard) ----------------
lit200=$(printf '%*s' 200 '' | tr ' ' x)
lit1000=$(printf '%*s' 1000 '' | tr ' ' y)
cat >"$work/lit.ct" <<CT
int main(void)
{
    const char *p = "$lit200";
    const char *q = "$lit1000";
    return (p[0] == 'x' && p[199] == 'x' && p[200] == 0
            && q[0] == 'y' && q[999] == 'y' && q[1000] == 0) ? 0 : 1;
}
CT
if run_product lit "$work/lit.ct"; then
    if grep -qF "$lit200" "$work/lit.c" && grep -qF "$lit1000" "$work/lit.c"; then
        ok; printf '  200/1000-byte literals: kept whole\n'
    else
        bad "the generated C cut a 200/1000-byte literal"
    fi
fi

# ---- C2p-2.1) a diagnostic that embeds a 150-byte struct name ---------------
# The message is "trait method 'g' is not implemented for struct '<name>'":
# with the 150-byte name it is past 160 bytes, so the old Parser.emsg[160] cut
# the name itself off.
sname=$(printf '%*s' 150 '' | tr ' ' s)
cat >"$work/diagtrait.ct" <<CT
trait T { int f(); int g(); }
struct $sname { int n; } use T;
impl T for $sname { int f() { return 1; } }
int main(void) { return 0; }
CT
"$CT" check "$work/diagtrait.ct" >"$work/diagtrait.out" 2>"$work/diagtrait.err"
rc=$?
if [ "$rc" -eq 1 ] && grep -qF "$sname" "$work/diagtrait.err" \
   && grep -qF "trait method 'g' is not implemented for struct" "$work/diagtrait.err"; then
    ok; printf '  long diagnostic: the 150-byte struct name is kept whole\n'
else
    bad "diag-trait: the 150-byte struct name is missing from the diagnostic (the message was cut at 160 bytes)"
fi

# ---- C2p-2.2) an arity warning naming a 300-byte callee --------------------
# Warn.var was a 160-byte row, so the warning named a truncated function.
fname=$(printf '%*s' 300 '' | tr ' ' f)
cat >"$work/diagwarn.ct" <<CT
int $fname(int a) { return a; }
int main(void) { return $fname(1, 2); }
CT
"$CT" compile "$work/diagwarn.ct" -o "$work/diagwarn.c" >"$work/diagwarn.out" 2>"$work/diagwarn.err"
if grep -qF "warning: arity mismatch" "$work/diagwarn.err" \
   && grep -qF "$fname" "$work/diagwarn.err"; then
    ok; printf '  arity warning: the 300-byte callee name is kept whole\n'
else
    bad "diag-warn: the 300-byte callee name is missing from the arity warning (Warn.var was cut at 160 bytes)"
fi

printf 'c2p: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
