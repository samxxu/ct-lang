#!/usr/bin/env bash
# SH-113: pin the current built-in-unit liveness boundary (no algorithm change).
#
# `builtin_live_for` is a whole-identifier text scan plus a layer-symbol scan,
# not a semantic reference graph. These six groups fix the boundary the code
# actually has today, so a future change is a visible diff rather than a silent
# widening. Group 6 is the known compile-mode miss: `--diagnostics` is unrelated;
# the compile-mode layer gate only matches `str_`/type words, so a lowercase
# non-`str_` export is not pulled in. That is SH-113's deferred item, not a
# regression this probe should hide.
#
# Usage: bash test/ast/sh113_builtin_live.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: sh113_builtin_live.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
export CT_CORE_DIR="$root/lib/core"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sh113.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL sh113: %s\n' "$1" >&2; }

build_case() { # name, source, must-have|none, needle...
    name=$1
    src=$2
    want=$3
    shift 3
    mkdir -p "$tmp/$name/out"
    printf '%s\n' "$src" >"$tmp/$name/main.ct"
    ( cd "$tmp/$name" && "$CT" build --emit-c -o out main.ct ) >"$tmp/$name/log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$name: build exit $rc ($(head -2 "$tmp/$name/log"))"
        return
    fi
    c="$tmp/$name/out/main.c"
    for needle in "$@"; do
        if [ "$want" = have ] && ! grep -Fq "$needle" "$c"; then
            bad "$name: expected '$needle' in the generated C"
            return
        fi
        if [ "$want" = none ] && grep -Fq "$needle" "$c"; then
            bad "$name: did not expect '$needle' in the generated C"
            return
        fi
    done
    ok "$name ($want)"
}

compile_case() { # name, source, must-have|none, needle...
    name=$1
    src=$2
    want=$3
    shift 3
    printf '%s\n' "$src" >"$tmp/$name.ct"
    "$CT" "$tmp/$name.ct" -o "$tmp/$name.c" >"$tmp/$name.log" 2>&1
    rc=$?
    if [ "$rc" -ne 0 ]; then
        bad "$name: compile exit $rc ($(head -2 "$tmp/$name.log"))"
        return
    fi
    c="$tmp/$name.c"
    for needle in "$@"; do
        if [ "$want" = have ] && ! grep -Fq "$needle" "$c"; then
            bad "$name: expected '$needle' in the generated C"
            return
        fi
        if [ "$want" = none ] && grep -Fq "$needle" "$c"; then
            bad "$name: did not expect '$needle' in the generated C"
            return
        fi
    done
    ok "$name ($want)"
}

# 1. a comment naming the containers must not pull the layer in (build mode).
build_case comment '/* Vec String Option Result Str */ int main(void){ return 0; }' \
    none '#include "Str.h"' '#include "Vec.h"'

# 2. a longer identifier is not the built-in name.
build_case prefix 'int MyVec; int Vecx; int Stringy; int Struct; int main(void){ return 0; }' \
    none '#include "Str.h"' '#include "Vec.h"'

# 3. a `String` struct field is a real use: Str is live, and Vec rides along
#    because the Str unit's `split` names `Vec<U16String>`.
build_case field 'struct S { String name; }; int main(void){ return 0; }' \
    have '#include "Str.h"' '#include "Vec.h"'

# 4. names inside a string literal are not identifiers.
build_case literal 'int main(void){ const char *s = "Option Result Vec"; return 0; }' \
    none '#include "Str.h"' '#include "Vec.h"'

# 5. a `str_` layer call is found by the symbol scan even when no `Str` word
#    appears in the source; compile mode also loads on the `str_` prefix.
build_case str_prefix 'int main(void){ return str_dup_len("hi", 2).len; }' \
    have '#include "Str.h"'
compile_case str_prefix_compile 'int main(void){ return str_dup_len("hi", 2).len; }' \
    have 'struct ct_str_hdr {'

# 6. known miss (SH-113): a lowercase layer export whose name does not start
#    with `str_` is invisible to the compile-mode word/prefix gate, so the
#    generated C keeps a bare call and the layer is absent. Build mode's symbol
#    scan does find it; the assertion is the current (documented) boundary.
compile_case lowercase_miss 'int main(void){ return ct_str_live_count(); }' \
    none 'struct ct_str_hdr {'
build_case lowercase_build 'int main(void){ return ct_str_live_count(); }' \
    have '#include "Str.h"'

printf 'sh113_builtin_live: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
