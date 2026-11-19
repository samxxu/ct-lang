#!/bin/sh
# LANG-5: a custom-subscript result used as a field receiver.
#
# `b["k"].v` is emitted literally as `Box_get(&b, "k").v`. When `get` answers a
# value that is valid C, but when it answers a pointer (or an interface value)
# the host cc rejects the member access -- the compiler itself said nothing.
# The probe pins the hard error and the shapes that already work:
#
#   * pointer-returning `get` + `.v`      -> rejected, `file:line:col` + `->`
#   * interface-returning `get` + `.v`    -> rejected (interfaces have methods)
#   * pointer-returning `get` + `->v`     -> accepted and runs
#   * value-returning `get` + `.v`        -> accepted and runs (valid C)
#   * value-returning `get` + `.m()`      -> accepted and runs (materialised)
#   * `f().m()` / `f().v` on a value       -> accepted and runs
#   * `p.v` on a pointer variable         -> same pointer guard
#
# Usage: sh test/ast/p77_lang5_field.sh <ct-ast>
set -u
ctast=${1:?usage: p77_lang5_field.sh <ct-ast>}
# Keep the compiler path absolute: every fixture runs from a throwaway dir.
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p77l5.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/lang5: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

# compile <src> -> generated C on stdout; exit code is the compiler's.
gen() { # <src> <cfile>
    ( cd "$root" && "$ctast" "$1" -o "$2" ) >"$work/gen.out" 2>"$work/gen.err"
}

build_run() { # <src> <label> <want-rc>
    if ! gen "$1" "$work/t.c"; then
        bad "$2" "ct-ast rejected a legal fixture: $(sed -n '1,2p' "$work/gen.err")"
        return 1
    fi
    if ! "${CC:-cc}" -std=c99 "$work/t.c" -o "$work/t" >"$work/cc.log" 2>&1; then
        bad "$2" "the emitted C does not compile: $(sed -n '1,3p' "$work/cc.log")"
        return 1
    fi
    "$work/t"
    got=$?
    if [ "$got" -ne "$3" ]; then
        bad "$2" "ran with status $got, want $3"
        return 1
    fi
    ok "$2"
}

# reject <src> <grep-pattern> <label>
reject() {
    if ( cd "$root" && "$ctast" "$1" -o "$work/r.c" ) >"$work/r.out" 2>"$work/r.err"; then
        bad "$3" "exit 0; expected a compile-time refusal (the emitted C is not checked by ct)"
        return 1
    fi
    if ! grep -Eq "$2" "$work/r.err"; then
        bad "$3" "missing diagnostic /$2/: $(sed -n '1,2p' "$work/r.err")"
        return 1
    fi
    # every diagnostic carries position and a stable prefix
    case "$(sed -n '1p' "$work/r.err")" in
        *:*:*:\ error:*) ;;
        *) bad "$3" "diagnostic has no file:line:col: $(sed -n '1p' "$work/r.err")"; return 1 ;;
    esac
    ok "$3"
}

# --- a pointer-returning `get` is not a value field base -------------------
cat >"$work/ptr.ct" <<'CT'
struct Inner { int v; }
struct Box { Inner i; }
impl Box { Inner *get(const char *k) { (void)k; return &self->i; } }
int main(void) { Box b; b.i.v = 5; return b["k"].v; }
CT
reject "$work/ptr.ct" "cannot access field 'v' through a pointer receiver; use '->v'" \
    "b[\"k\"].v with a pointer result is refused"

# --- an interface value has methods, not fields ---------------------------
cat >"$work/iface.ct" <<'CT'
trait Ref { int kind(void); }
struct Inner { int v; } use Ref;
impl Ref for Inner { int kind(void) { return 7; } }
struct Box { }
impl Box { Ref get(const char *k) { (void)k; Inner i = { 2 }; return i; } }
int main(void) { Box b; return b["k"].v; }
CT
reject "$work/iface.ct" "is an interface value; it has methods, not fields" \
    "b[\"k\"].v with an interface result is refused"

# --- the pointer spelling that works --------------------------------------
cat >"$work/ptrarrow.ct" <<'CT'
struct Inner { int v; }
struct Box { Inner i; }
impl Box { Inner *get(const char *k) { (void)k; return &self->i; } }
int main(void) { Box b; b.i.v = 5; return b["k"]->v; }
CT
build_run "$work/ptrarrow.ct" "b[\"k\"]->v compiles and runs" 5

# --- a value-returning `get` keeps the plain dot --------------------------
cat >"$work/valfield.ct" <<'CT'
struct Inner { int v; }
struct Box { }
impl Box { Inner get(const char *k) { (void)k; Inner i = { 4 }; return i; } }
int main(void) { Box b; return b["k"].v; }
CT
build_run "$work/valfield.ct" "b[\"k\"].v with a value result compiles and runs" 4

# --- the method form keeps its materialisation ----------------------------
cat >"$work/valmethod.ct" <<'CT'
struct Inner { int v; }
impl Inner { int twice(void) { return self->v * 2; } }
struct Box { Inner i; }
impl Box { Inner get(const char *k) { (void)k; return self->i; } }
int main(void) { Box b; b.i.v = 3; return b["k"].twice(); }
CT
build_run "$work/valmethod.ct" "b[\"k\"].m() still materialises and runs" 6

cat >"$work/fnmethod.ct" <<'CT'
struct Inner { int v; }
impl Inner { int twice(void) { return self->v * 2; } }
Inner mk(void) { Inner i = { 3 }; return i; }
int main(void) { return mk().twice(); }
CT
build_run "$work/fnmethod.ct" "f().m() still materialises and runs" 6

cat >"$work/fnfield.ct" <<'CT'
struct Inner { int v; }
Inner mk(void) { Inner i = { 3 }; return i; }
int main(void) { return mk().v; }
CT
build_run "$work/fnfield.ct" "f().v on a value compiles and runs" 3

# --- a pointer variable is the same defect --------------------------------
cat >"$work/ptrvar.ct" <<'CT'
struct Inner { int v; }
int main(void) { Inner i; i.v = 3; Inner *p = &i; return p.v; }
CT
reject "$work/ptrvar.ct" "cannot access field 'v' through a pointer receiver; use '->v'" \
    "p.v on a pointer variable is refused"

# --- a pointer-receiver method still gets its own arrow diagnostic --------
cat >"$work/ptrmethod.ct" <<'CT'
struct Inner { int v; }
impl Inner { int twice(void) { return self->v * 2; } }
struct Box { Inner i; }
impl Box { Inner *get(const char *k) { (void)k; return &self->i; } }
int main(void) { Box b; b.i.v = 3; return b["k"].twice(); }
CT
reject "$work/ptrmethod.ct" "cannot call method 'twice' through a pointer receiver; use '->twice\(\)'" \
    "b[\"k\"].m() pointer receiver keeps its diagnostic"

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/lang5 (field receiver: pointer/interface refused, value forms kept)"
