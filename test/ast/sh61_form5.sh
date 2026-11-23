#!/bin/sh
# SH-61: form 5 (Trait::method(recv, ...)) must read the trait method's
# variadic flag, like form 3/4 do via map_arity.
set -u
ct=${1:?usage: sh61_form5.sh <ct-ast>}
tmp=$(mktemp -d "${TMPDIR:-/tmp}/sh61.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
mkdir -p "$tmp/var"
cat >"$tmp/var/var.m.ct" <<'CT'
namespace var;
#include <string.h>
pub trait Log { int f(char *s, int n, ...); }
map trait Log for type char * { f(recv, s, n, ...) -> strlen(s); }
pub trait Fixed { int g(char *s, int n); }
map trait Fixed for type char * { g(recv, s, n) -> strlen(s); }
CT
cat >"$tmp/varonly.ct" <<'CT'
import var::var;
int main(void) { char *s = "abc"; return var::Log::f(s, s, 1, 2, 3); }
CT
cat >"$tmp/fixed.ct" <<'CT'
import var::var;
int main(void) { char *s = "abc"; return var::Fixed::g(s, s, 1, 2, 3); }
CT
vout=$("$ct" build -I "$tmp" "$tmp/varonly.ct" -o "$tmp/vout" 2>&1)
vrc=$?
case "$vout" in
*"arity mismatch"*) echo "FAIL p61: variadic form 5 still reports arity"; echo "$vout"; exit 1;;
esac
[ "$vrc" -eq 0 ] || { echo "FAIL p61: variadic build rc=$vrc"; echo "$vout"; exit 1; }
fout=$("$ct" build -I "$tmp" "$tmp/fixed.ct" -o "$tmp/fout" 2>&1)
case "$fout" in
*"arity mismatch: 'g'"*) :;;
*) echo "FAIL p61: non-variadic form 5 did not report arity"; echo "$fout"; exit 1;;
esac
echo "ok p61/form5 (variadic accepted, non-variadic rejected)"
