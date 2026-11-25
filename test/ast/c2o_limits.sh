#!/usr/bin/env bash
# v1-PH-2 S1a-0 C2o probe: hard-coded lengths are gone; the only token/text
# limit is the formal TEXT_LIMIT (65536 bytes).
#
# Covers the old constants this slice removed:
#   * lexer/parser single identifier and one string literal: 2000 bytes usable,
#     > 65536 an explicit error (never truncated);
#   * import alias: 2000 bytes, and a 20-segment import path;
#   * exported type rows: more than the old 128-row table;
#   * qualified value/call path: more than the old 8 segments;
#   * namespace path longer than the old 160-byte buffer;
#   * `offsetof` field name: 2000 bytes;
# plus the generated C carrying every full name byte for byte.
#
# Usage: bash test/ast/c2o_limits.sh <ct-ast>
set -u
CT=${1:?usage: c2o_limits.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
work=$(mktemp -d "${TMPDIR:-/tmp}/c2o.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL c2o: $1" >&2; }
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

# ---- 1) 2000-byte identifier: global, function and local, in every position -
longid=$(printf '%*s' 2000 '' | tr ' ' a)
longfn=$(printf '%*s' 2000 '' | tr ' ' f)
longloc=$(printf '%*s' 2000 '' | tr ' ' l)
cat >"$work/id.ct" <<CT
int $longid = 7;
int $longfn(void) { int $longloc = 3; return $longloc; }
int main(void) { return ($longfn() + $longid == 10) ? 0 : 1; }
CT
if run_product id "$work/id.ct"; then
    if [ "$(grep -c "$longid" "$work/id.c")" -ge 1 ] \
       && [ "$(grep -c "$longfn" "$work/id.c")" -ge 2 ] \
       && [ "$(grep -c "$longloc" "$work/id.c")" -ge 1 ]; then
        ok; printf '  2000-byte identifier: global/function/local kept whole\n'
    else
        bad "the generated C cut one of the 2000-byte identifiers"
    fi
fi

# ---- 2) one 2000-byte string literal ---------------------------------------
str=$(printf '%*s' 2000 '' | tr ' ' x)
cat >"$work/str.ct" <<CT
int main(void)
{
    const char *p = "$str";
    return (p[0] == 'x' && p[1999] == 'x' && p[2000] == 0) ? 0 : 1;
}
CT
if run_product str "$work/str.ct"; then
    if [ "$(grep -c "$str" "$work/str.c")" -ge 1 ]; then
        ok; printf '  2000-byte string literal: kept whole\n'
    else
        bad "the generated C cut the 2000-byte string literal"
    fi
fi

# ---- 3) 20-segment import path + 2000-byte import alias --------------------
alias=$(printf '%*s' 2000 '' | tr ' ' A)
mkdir -p "$work/imp/src" "$work/imp/out"
segs=""
rel=""
fdir="$work/imp/src"
for i in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18; do
    if [ -n "$segs" ]; then segs="$segs::n$i"; else segs="n$i"; fi
    fdir="$fdir/n$i"
done
segs="$segs::n19"
mkdir -p "$fdir"
# the unit file is the last segment; its namespace is the directory prefix
ns=${segs%::n19}
cat >"$fdir/n19.h.ct" <<CT
namespace $ns;
pub struct Thing { int n; };
CT
cat >"$work/imp/src/main.ct" <<CT
import $segs::Thing as $alias;
int main(void)
{
    $alias t;
    t.n = 42;
    return t.n == 42 ? 0 : 1;
}
CT
if "$CT" build --emit-c -I "$work/imp/src" "$work/imp/src/main.ct" -o "$work/imp/out" \
        >"$work/imp/build.log" 2>&1; then
    if "$CC" -std=c99 "$work/imp/out"/*.c -o "$work/imp/run" >"$work/imp/cc.log" 2>&1 \
       && "$work/imp/run"; then
        ok; printf '  20-segment import path + 2000-byte alias: resolved and ran\n'
    else
        bad "the 20-segment/2000-byte-alias program did not build and run: $(head -2 "$work/imp/cc.log" | tr '\n' ' ')"
    fi
else
    bad "the 20-segment/2000-byte-alias program did not compile: $(head -3 "$work/imp/build.log" | tr '\n' ' ')"
fi

# ---- 4) more than the old 128 exported type rows ---------------------------
mkdir -p "$work/exp/src" "$work/exp/out"
: >"$work/exp/src/many.h.ct"
i=0
while [ "$i" -lt 200 ]; do
    printf 'pub struct S%d { int n; };\n' "$i" >>"$work/exp/src/many.h.ct"
    i=$((i + 1))
done
cat >"$work/exp/src/main.ct" <<'CT'
import many;
int main(void)
{
    struct S199 s;
    s.n = 42;
    return s.n == 42 ? 0 : 1;
}
CT
if "$CT" build --emit-c -I "$work/exp/src" "$work/exp/src/main.ct" -o "$work/exp/out" \
        >"$work/exp/build.log" 2>&1 \
   && "$CC" -std=c99 "$work/exp/out"/*.c -o "$work/exp/run" >"$work/exp/cc.log" 2>&1 \
   && "$work/exp/run"; then
    ok; printf '  200 exported type rows: beyond the old 128-row table\n'
else
    bad "the 200-exported-type program failed: $(head -3 "$work/exp/build.log" "$work/exp/cc.log" 2>/dev/null | tr '\n' ' ')"
fi

# ---- 5) a qualified call with 24 segments ---------------------------------
mkdir -p "$work/q/src" "$work/q/out"
qs=""
qdir="$work/q/src"
for i in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22; do
    if [ -z "$qs" ]; then qs="q$i"; else qs="$qs::q$i"; fi
    qdir="$qdir/q$i"
done
unit_ns="$qs"
qs="$qs::q23"
mkdir -p "$qdir"
cat >"$qdir/q23.h.ct" <<CT
namespace $unit_ns;
pub int bump(void) { return 7; }
CT
cat >"$work/q/src/main.ct" <<CT
import $qs;
int main(void) { return $unit_ns::bump() == 7 ? 0 : 1; }
CT
if "$CT" build --emit-c -I "$work/q/src" "$work/q/src/main.ct" -o "$work/q/out" \
        >"$work/q/build.log" 2>&1 \
   && "$CC" -std=c99 "$work/q/out"/*.c -o "$work/q/run" >"$work/q/cc.log" 2>&1 \
   && "$work/q/run"; then
    ok; printf '  24-segment qualified call: beyond the old 8-segment cap\n'
else
    bad "the 24-segment qualified call failed: $(head -3 "$work/q/build.log" "$work/q/cc.log" 2>/dev/null | tr '\n' ' ')"
fi

# ---- 6) a namespace longer than the old 160-byte buffer --------------------
mkdir -p "$work/ns/root" "$work/ns/out"
nsegs=""
ndir="$work/ns/root"
for i in $(seq -w 0 28); do
    if [ -z "$nsegs" ]; then nsegs="ns$i"; else nsegs="$nsegs::ns$i"; fi
    ndir="$ndir/ns$i"
done
mkdir -p "$ndir"
cat >"$ndir/ns029.h.ct" <<CT
namespace $nsegs;
pub int bump(void) { return 7; }
int main(void) { return bump() == 7 ? 0 : 1; }
CT
if "$CT" build --emit-c --ns-root "$work/ns/root" -I "$work/ns/root" "$ndir/ns029.h.ct" -o "$work/ns/out" \
        >"$work/ns/build.log" 2>&1 \
   && "$CC" -std=c99 "$work/ns/out/ns029.c" -o "$work/ns/run" >"$work/ns/cc.log" 2>&1 \
   && "$work/ns/run"; then
    if grep -q "${nsegs//::/_}_bump" "$work/ns/out/ns029.c"; then
        ok; printf '  >200-byte namespace: kept whole and ran\n'
    else
        bad "the generated C cut the >200-byte namespace prefix"
    fi
else
    bad "the >200-byte-namespace program failed: $(head -3 "$work/ns/build.log" "$work/ns/cc.log" 2>/dev/null | tr '\n' ' ')"
fi

# ---- 7) a 2000-byte offsetof field name -----------------------------------
field=$(printf '%*s' 2000 '' | tr ' ' g)
cat >"$work/off.ct" <<CT
#include <stddef.h>
struct S { int $field; };
int main(void) { return offsetof(struct S, $field) == 0 ? 0 : 1; }
CT
if run_product off "$work/off.ct"; then
    if [ "$(grep -c "$field" "$work/off.c")" -ge 2 ]; then
        ok; printf '  2000-byte offsetof field: declared and referenced whole\n'
    else
        bad "the generated C cut the 2000-byte offsetof field name"
    fi
fi

# ---- 8) past TEXT_LIMIT is an explicit error, not a truncation -------------
over=$(printf '%*s' 65537 '' | tr ' ' z)
cat >"$work/over_id.ct" <<CT
int $over = 1;
int main(void) { return 0; }
CT
"$CT" "$work/over_id.ct" -o "$work/over_id.c" >"$work/over_id.out" 2>"$work/over_id.err"
if [ $? -ne 0 ] && grep -qF "identifier is too long (over the 65536-byte formal text limit)" "$work/over_id.err"; then
    ok
else
    bad "a 65537-byte identifier was not refused with the formal-limit message"
fi
cat >"$work/over_str.ct" <<CT
int main(void) { const char *p = "$over"; return p[0] == 'z' ? 0 : 1; }
CT
"$CT" "$work/over_str.ct" -o "$work/over_str.c" >"$work/over_str.out" 2>"$work/over_str.err"
if [ $? -ne 0 ] && grep -qF "string literal exceeds 65536 bytes; split it" "$work/over_str.err"; then
    ok
else
    bad "a 65537-byte string literal was not refused with the formal-limit message"
fi

echo "c2o: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
