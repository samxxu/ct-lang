#!/bin/sh
# DOC-87 Stage 2 probe: the built-in layer's source namespace `core`.
#
# The five lib/core units declare `namespace core;`, the canonical source
# spelling is `core::Vec` / `core::String` / `core::box` / ..., and the root
# spelling stays a compatibility alias for one MINOR. During the window the C
# symbols stay in the root namespace, so `core::` and the bare spelling emit
# byte-identical C (the banner line names the input, so it is excluded).
#
# Boundary: external `std::*` is not claimed by the built-in layer.
#
# Usage: sh test/ast/doc87_core.sh <ct-ast>
set -u
ctast=${1:?usage: doc87_core.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/doc87core.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
export CT_C_BOUNDARY=allow
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL doc87/core: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=$((fail + 1)); }

# 1. Every built-in unit declares the namespace.
for u in Vec Option Result Str Box; do
    if grep -qx 'namespace core;' "lib/core/$u.h.ct"; then
        ok "$u.h.ct declares namespace core"
    else
        bad "$u.h.ct has no 'namespace core;'"
    fi
done

# 2. The canonical `core::` spellings compile and run.
cat > "$work/core.ct" <<'CT'
#include <stdio.h>
int main() {
    core::Vec<int> v;
    v.h = 0;
    v.push(3);
    core::Option<int> o = { 1, 4 };
    core::Result<int, int> r = { 1, 8, 0 };
    core::String s = "hi";
    core::Str t = s.as_str();
    printf("%d %d %d %s %d\n", v.get(0), o.value, r.value, s.cstr(), t.len);
    return 0;
}
CT
if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$work/core.ct" -o "$work/core.c" ) \
        >"$work/core.log" 2>&1; then
    bad "core:: fixture did not compile" "$(head -3 "$work/core.log")"
elif ! cc -std=c99 "$work/core.c" -o "$work/core.bin" 2>"$work/core.cc"; then
    bad "core:: product did not build" "$(head -3 "$work/core.cc")"
elif ! "$work/core.bin" >"$work/core.out" 2>&1; then
    bad "core:: product exited non-zero"
elif ! grep -qx '3 4 8 hi 2' "$work/core.out"; then
    bad "core:: product output drifted: $(cat "$work/core.out")"
else
    ok "core::Vec/Option/Result/String/Str compile and run"
fi

# `core::Map` and `core::box` are the other two shapes; compile-only (the box
# fixture would need a runtime owner for a stable run).
cat > "$work/shapes.ct" <<'CT'
struct P { int x; };
int main() {
    core::Map<char *, int> m;
    m.h = 0;
    core::box<P> b = new P { 7 };
    return b.at()->x;
}
CT
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$work/shapes.ct" -o "$work/shapes.c" ) \
        >"$work/shapes.log" 2>&1; then
    ok "core::Map and core::box compile"
else
    bad "core::Map / core::box did not compile" "$(head -3 "$work/shapes.log")"
fi

# 3. The bare spelling still compiles (compatibility window) and emits the same
#    C apart from the banner's input path.
sed 's/core:://g' "$work/core.ct" > "$work/bare.ct"
if ! ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$work/bare.ct" -o "$work/bare.c" ) \
        >"$work/bare.log" 2>&1; then
    bad "bare spelling stopped compiling" "$(head -3 "$work/bare.log")"
elif ! tail -n +2 "$work/core.c" > "$work/core.body" \
        || ! tail -n +2 "$work/bare.c" > "$work/bare.body"; then
    bad "cannot strip the banner"
elif ! cmp -s "$work/core.body" "$work/bare.body"; then
    bad "core:: and the bare spelling emit different C"
else
    ok "core:: and the bare spelling emit identical C (banner excluded)"
fi

# 4. One instance, not two: the two spellings name the same `Vec<int>`.
if [ -f "$work/core.c" ] && [ "$(grep -c 'struct Vec_int {' "$work/core.c")" -eq 1 ]; then
    ok "core::Vec<int> and Vec<int> share one instance"
else
    bad "core::Vec<int> created a second instance"
fi

# 5. `core` stays an ordinary namespace for user code.
cat > "$work/userns.ct" <<'CT'
namespace core;
struct Thing { int x; };
int main() { core::Thing t; t.x = 2; return t.x; }
CT
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" "$work/userns.ct" -o "$work/userns.c" ) \
        >"$work/userns.log" 2>&1 \
   && grep -q 'struct core_Thing' "$work/userns.c"; then
    ok "user 'namespace core' is not reserved"
else
    bad "user 'namespace core' was rejected or mismangled" "$(head -3 "$work/userns.log")"
fi

# 6. The built-in layer does not claim the external `std::*` namespace: with no
#    std package installed the import stays unresolved even though core:: works.
cat > "$work/stdimp.ct" <<'CT'
import std::str;
int main() { core::String s = "x"; return 0; }
CT
if ( cd "$root" && CT_CORE_DIR="$root/lib/core" "$ctast" build "$work/stdimp.ct" -o "$work/stdimp.out" ) \
        >"$work/stdimp.log" 2>&1; then
    bad "import std::str resolved without a std package"
elif grep -Eq "cannot resolve import 'std[:/]str'" "$work/stdimp.log"; then
    ok "external std::* stays separate from core::*"
else
    bad "std::str failed for the wrong reason" "$(head -3 "$work/stdimp.log")"
fi

echo "doc87/core: $fail failure(s)"
[ "$fail" -eq 0 ]
