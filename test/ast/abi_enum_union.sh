#!/bin/sh
# REQ-ABI-3/4: enum and union parameters in --lib exports need tag forwards.
#
# Build a library whose exported signatures use `enum E` / `union U` from a C
# header. The generated `.abi.h` must carry `enum E;` / `union U;`, and a
# consumer that includes only the ABI header + the type header must compile
# with -Werror and run.
set -u
ct=${1:?usage: abi_enum_union.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
work=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/abi.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
pass=0; fail=0
ok()  { pass=$((pass+1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail+1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

cat >"$work/types.h" <<'HDR'
#ifndef ABI_TYPES_H
#define ABI_TYPES_H
enum E { E_A, E_B };
union U { int i; long l; };
#endif
HDR
cat >"$work/lib.h.ct" <<CT
#include "$work/types.h"
pub int take_enum(enum E e) { return (int)e; }
pub int take_union(union U *u) { return u->i; }
CT
cd "$work" || exit 1
if ! CT_C_BOUNDARY=allow "$ct" build --lib lib.h.ct -o lib.a >"$work/build.log" 2>&1; then
    bad "lib build" "$(head -3 "$work/build.log")"
    echo "abi_enum_union: FAIL"; exit 1
fi
abi=$work/.ctbuild/lib.abi.h
[ -n "$abi" ] || { bad "abi header" "lib.abi.h not found"; echo "abi_enum_union: FAIL"; exit 1; }
for want in 'enum E;' 'union U;'; do
    if grep -qxF "$want" "$abi"; then ok "abi header has '$want'"; else bad "abi header" "missing '$want'"; fi
done
cp "$abi" "$work/lib.abi.h"
cat >"$work/consumer.c" <<'C'
#include "types.h"
#include "lib.abi.h"
int main(void)
{
    enum E e = E_B;
    union U u;
    u.i = 3;
    return take_enum(e) == 1 && take_union(&u) == 3 ? 0 : 1;
}
C
if cc -std=c99 -Wall -Wextra -Werror -I "$work" "$work/consumer.c" "$work/lib.a" -o "$work/consumer" >"$work/cc.log" 2>&1 \
   && "$work/consumer"; then
    ok "consumer compiles (-Werror) and runs"
else
    bad "consumer" "$(head -4 "$work/cc.log")"
fi
echo "abi_enum_union: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
