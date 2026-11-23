#!/bin/sh
# SH-108: a multi-dimensional array parameter's empty first dimension is legal C,
# not the deprecated `T a[]` slice spelling.
#
#   - `char x[][MAX]` as a parameter and as a field: no `T a[]` warning;
#   - a genuine single-dimension `int a[]`: still warns (parameter and field);
#   - `ct-ast build --check-level=warn` on the compiler's own tree: 0 hits.
#
# Usage: sh test/ast/p108_multidim_param.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p108_multidim_param.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p108multi.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p108/multidim: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
dep="'T a[]' is deprecated"

build() {
    rm -rf "$work/.ctbuild" "$work/.ctcache"
    ( cd "$work" && "$ctast" build --check-level=warn "$1.ct" -o "$work/$1.bin" ) \
        >"$work/$1.log" 2>&1
}
expect_silent() {
    if ! build "$1"; then bad "$2" "the fixture did not build: $(sed -n '1,4p' "$work/$1.log")"
    elif grep -Fq "$dep" "$work/$1.log"; then bad "$2" "unexpected T a[] warning"
    else ok "$2"; fi
}
expect_warn() {
    if ! build "$1"; then bad "$2" "the fixture did not build: $(sed -n '1,4p' "$work/$1.log")"
    elif grep -Fq "$dep" "$work/$1.log"; then ok "$2"
    else bad "$2" "warning missing: $(sed -n '1,3p' "$work/$1.log")"; fi
}

cat >"$work/multi_param.ct" <<'EOF'
#define MAX 4
void f(char x[][MAX]) { (void)x; }
int main(void) { return 0; }
EOF
expect_silent multi_param "a multi-dimensional parameter first dim is not T a[]"

cat >"$work/multi_field.ct" <<'EOF'
#define MAX 4
struct S { char x[][MAX]; };
int main(void) { return 0; }
EOF
expect_silent multi_field "a multi-dimensional field first dim is not T a[]"

cat >"$work/single_param.ct" <<'EOF'
int total(int xs[], int n) { return n; }
int main(void) { return total(0, 0); }
EOF
expect_warn single_param "a genuine int a[] parameter still warns"

cat >"$work/single_field.ct" <<'EOF'
struct S { int xs[]; };
int main(void) { return 0; }
EOF
expect_warn single_field "a genuine int a[] field still warns"

# Dogfood: the compiler's own 10 false positives must be 0.
rm -rf "$work/dogfood"
mkdir -p "$work/dogfood"
if ( cd "$root" && "$ctast" build --check-level=warn --emit-c -I selfhost/ct-ast \
        selfhost/ct-ast/main.ct -o "$work/dogfood" ) >"$work/dogfood.log" 2>&1; then
    hits=$(grep -cF "$dep" "$work/dogfood.log")
    if [ "$hits" -eq 0 ]; then
        ok "ct-ast's own --check-level=warn run has 0 T a[] hits"
    else
        bad "ct-ast dogfood still has T a[] hits" "$hits hit(s)"
    fi
else
    bad "ct-ast dogfood build failed" "$(sed -n '1,4p' "$work/dogfood.log")"
fi

exit $fail
