#!/usr/bin/env bash
# PH-65 R1 probe, flipped by v1-PH-2 S9, extended by D-032 (Q-2): the C
# boundary policy resolves to the right side.
#   every input          -> strict by default (the CT-tree exemption is gone)
#   the working dir      -> not an input (SH-93: an external unit stays strict
#                           even when ct runs from the repo root)
#   a package manifest   -> its `c-boundary` key; no key is strict too
#   the nearest manifest -> covers the whole subtree up to the unit's owning
#                           root (D-032): selfhost/ct-ast and lib/core are two
#                           internal manifests, lib/core covers utf16/, a
#                           child manifest wins over its parent, and a parent
#                           outside the owning root never leaks in
#   the command line     -> wins over all of the above
# Usage: bash test/ast/p65_policy.sh <ct-ast>
set -u
CT=${1:?usage: p65_policy.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p65pol.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

mkdir -p "$tmp/ext" "$tmp/allow" "$tmp/strict" "$tmp/old"
printf 'int main(void) { return 0; }\n' >"$tmp/ext/x.ct"
printf 'int main(void) { return 0; }\n' >"$tmp/allow/u.ct"
printf 'int main(void) { return 0; }\n' >"$tmp/strict/v.ct"
printf 'int main(void) { return 0; }\n' >"$tmp/old/w.ct"
printf 'name = demo\nc-boundary = allow\n'  >"$tmp/allow/ct.pkg"
printf 'name = demo\nc-boundary = strict\n' >"$tmp/strict/ct.pkg"
printf 'name = demo\n'                      >"$tmp/old/ct.pkg"

check() {   # check <label> <want> <cmd...>
    local label=$1 want=$2 got
    shift 2
    got=$( cd "$root" && "$@" 2>"$tmp/err" )
    if [ "$got" != "$want" ]; then
        echo "FAIL p65/policy: $label: want '$want', got '$got' ($(head -1 "$tmp/err"))" >&2
        fail=1
    fi
}

check_in() {   # check <label> <want> <dir> <cmd...>
    local label=$1 want=$2 dir=$3 got
    shift 3
    got=$( cd "$dir" && "$@" 2>"$tmp/err" )
    if [ "$got" != "$want" ]; then
        echo "FAIL p65/policy: $label: want '$want', got '$got' ($(head -1 "$tmp/err"))" >&2
        fail=1
    fi
}
check_in "external default" strict "$tmp" "$CT" --show-c-boundary "$tmp/ext/x.ct"
# SH-93 negative: running from the CT repo root must not relax an external
# unit; only the input path decides.
check "external from repo root" strict "$CT" --show-c-boundary "$tmp/ext/x.ct"
check_in "CLI allow"        allow  "$tmp" "$CT" --c-boundary=allow --show-c-boundary "$tmp/ext/x.ct"
check "CT tree default"  strict "$CT" --show-c-boundary test/ast/p65_policy/inside.ct
# D-032 (Q-2): the internal layers' allow is an ordinary manifest key, and one
# manifest covers the subtree -- no per-unit and no per-subdirectory manifest.
check "selfhost/ct-ast unit"        allow  "$CT" --show-c-boundary selfhost/ct-ast/main.ct
check "selfhost/ct-ast child unit"  allow  "$CT" --show-c-boundary selfhost/ct-ast/frontend/module/Module.h.ct
check "lib/core unit"               allow  "$CT" --show-c-boundary lib/core/Vec.h.ct
check "lib/core/utf16 subtree"      allow  "$CT" --show-c-boundary lib/core/utf16/U16Str.h.ct
check "examples default"            strict "$CT" --show-c-boundary examples/37_nested_pattern/nested_pattern.ct
check "CLI strict wins"  strict "$CT" --c-boundary=strict --show-c-boundary test/ast/p65_policy/inside.ct
check "package allow"    allow  "$CT" build -I "$tmp/allow" --show-c-boundary "$tmp/allow/u.ct"
check "package strict"   strict "$CT" build -I "$tmp/strict" --show-c-boundary "$tmp/strict/v.ct"
check "old package (no key)" strict "$CT" build -I "$tmp/old" --show-c-boundary "$tmp/old/w.ct"
check "CLI over package" allow "$CT" build -I "$tmp/strict" --c-boundary=allow --show-c-boundary "$tmp/strict/v.ct"

# D-032 negative: an allow manifest *outside* the unit's owning root (`-I`
# root here) must not reach inside it.
mkdir -p "$tmp/outer/inner"
printf 'name = demo\nc-boundary = allow\n' >"$tmp/outer/ct.pkg"
printf 'int main(void) { return 0; }\n'   >"$tmp/outer/inner/u.ct"
check "outside allow (-I inner)" strict "$CT" build -I "$tmp/outer/inner" --show-c-boundary "$tmp/outer/inner/u.ct"
check_in "outside allow (cwd outer)" strict "$tmp/outer" "$CT" build -I inner --show-c-boundary inner/u.ct

# D-032 negative: a child manifest is the nearer package and wins over an
# allow parent, so its strict subtree stays strict.
mkdir -p "$tmp/nest/sub"
printf 'name = demo\nc-boundary = allow\n'  >"$tmp/nest/ct.pkg"
printf 'name = demo\nc-boundary = strict\n' >"$tmp/nest/sub/ct.pkg"
printf 'int main(void) { return 0; }\n'     >"$tmp/nest/sub/u.ct"
check "child manifest wins" strict "$CT" build -I "$tmp/nest/sub" --show-c-boundary "$tmp/nest/sub/u.ct"

# D-032: `leaks` resolves from the same package root as `c-boundary`, so one
# `leaks = error` manifest covers its subtree. The leaky unit needs a C
# boundary allow only to make the include legal; the leak policy is separate.
leaky='#include <stdlib.h>

struct S { int n; };

int main(void) {
    S *p = malloc(sizeof(struct S));
    return 0;
}
'
mkdir -p "$tmp/leak/pkg/sub" "$tmp/leak/out"
printf 'name = demo\nleaks = error\n' >"$tmp/leak/pkg/ct.pkg"
printf '%s' "$leaky" >"$tmp/leak/pkg/sub/prog.ct"
( cd "$tmp/leak" && "$CT" build --c-boundary=allow --emit-c -o out pkg/sub/prog.ct \
    >"$tmp/leak.log" 2>&1 )
rc=$?
if [ "$rc" -eq 1 ] && grep -Fq "error: potential leak" "$tmp/leak.log"; then
    :
else
    echo "FAIL p65/policy: leaks = error covers the subtree (rc=$rc; $(head -1 "$tmp/leak.log"))" >&2
    fail=1
fi
# The parent's key does not overflow into a child package that has its own
# manifest without the key: warn, exit 0, product written.
mkdir -p "$tmp/leak2/parent/pkg/sub" "$tmp/leak2/out"
printf 'name = parent\nleaks = error\n' >"$tmp/leak2/parent/ct.pkg"
printf 'name = pkg\n' >"$tmp/leak2/parent/pkg/ct.pkg"
printf '%s' "$leaky" >"$tmp/leak2/parent/pkg/sub/prog.ct"
( cd "$tmp/leak2" && "$CT" build --c-boundary=allow --emit-c -o out parent/pkg/sub/prog.ct \
    >"$tmp/leak2.log" 2>&1 )
rc=$?
if [ "$rc" -eq 0 ] && grep -Fq "warning: potential leak" "$tmp/leak2.log" \
        && [ -f "$tmp/leak2/out/prog.c" ]; then
    :
else
    echo "FAIL p65/policy: a parent leaks key overflowed into the child package (rc=$rc; $(head -1 "$tmp/leak2.log"))" >&2
    fail=1
fi

# D-032: the built-in layer is not under `-I`; with `CT_CORE_DIR` set and a
# cwd outside the repo, its manifest still covers `utf16/`.
mkdir -p "$tmp/elsewhere"
got=$( cd "$tmp/elsewhere" && env -u CT_C_BOUNDARY CT_CORE_DIR="$root/lib/core" \
    "$CT" --show-c-boundary "$root/lib/core/utf16/U16Str.h.ct" 2>"$tmp/err" )
if [ "$got" != "allow" ]; then
    echo "FAIL p65/policy: CT_CORE_DIR utf16 subtree: want 'allow', got '$got' ($(head -1 "$tmp/err"))" >&2
    fail=1
fi

# D-032 M3 negative: a manifest placed directly under `lib/core/utf16` is the
# nearer package and makes that subtree strict again; the root sibling keeps the
# package root's allow. Copy the layer so the repo tree stays untouched.
cp -R "$root/lib/core" "$tmp/core-strict"
printf 'name = core\nc-boundary = strict\n' >"$tmp/core-strict/utf16/ct.pkg"
got=$( cd "$tmp/elsewhere" && env -u CT_C_BOUNDARY CT_CORE_DIR="$tmp/core-strict" \
    "$CT" --show-c-boundary "$tmp/core-strict/utf16/U16Str.h.ct" 2>"$tmp/err" )
if [ "$got" != "strict" ]; then
    echo "FAIL p65/policy: utf16 child manifest: want 'strict', got '$got' ($(head -1 "$tmp/err"))" >&2
    fail=1
fi
got=$( cd "$tmp/elsewhere" && env -u CT_C_BOUNDARY CT_CORE_DIR="$tmp/core-strict" \
    "$CT" --show-c-boundary "$tmp/core-strict/Vec.h.ct" 2>"$tmp/err" )
if [ "$got" != "allow" ]; then
    echo "FAIL p65/policy: root sibling after utf16 child manifest: want 'allow', got '$got' ($(head -1 "$tmp/err"))" >&2
    fail=1
fi

( cd "$root" && "$CT" --c-boundary=nope --show-c-boundary "$tmp/ext/x.ct" >"$tmp/bad.out" 2>"$tmp/bad.err" )
rc=$?
if [ "$rc" -eq 0 ] || ! grep -q "takes strict or allow" "$tmp/bad.err"; then
    echo "FAIL p65/policy: a bad --c-boundary value was not rejected (rc=$rc)" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p65/policy"
exit "$fail"
