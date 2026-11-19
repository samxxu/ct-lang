#!/bin/sh
# LANG-7: a static call whose receiver names a type must say so.
#
# `Type.name(args)` where `Type` is a declared type name but not a struct with
# static methods (a typedef, an enum) used to fall through to the ordinary
# variable path and report `use of an undeclared variable` at the dot -- which
# sends the reader looking for an import or a visibility problem. The probe
# pins the accurate diagnostic, the existing struct shapes, and the boundary:
# a name ct has never seen is still an undeclared variable (it may be a typo,
# and the compiler cannot claim it is a type).
#
# Usage: sh test/ast/p77_lang7_static_type.sh <ct-ast>
set -u
ctast=${1:?usage: p77_lang7_static_type.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p77l7.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/lang7: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

# reject <src> <grep-pattern> <label>
reject() {
    if ( cd "$root" && "$ctast" "$1" -o "$work/r.c" ) >"$work/r.out" 2>"$work/r.err"; then
        bad "$3" "exit 0; expected a compile-time diagnostic"
        return 1
    fi
    if ! grep -Eq "$2" "$work/r.err"; then
        bad "$3" "missing diagnostic /$2/: $(sed -n '1,2p' "$work/r.err")"
        return 1
    fi
    case "$(sed -n '1p' "$work/r.err")" in
        *:*:*:\ error:*) ;;
        *) bad "$3" "diagnostic has no file:line:col: $(sed -n '1p' "$work/r.err")"; return 1 ;;
    esac
    ok "$3"
}

# --- a typedef name is a type, not a variable -----------------------------
cat >"$work/typealias.ct" <<'CT'
typedef int MyInt;
int main(void) { return MyInt.make(1); }
CT
reject "$work/typealias.ct" \
    "static method 'make' cannot be resolved: 'MyInt' is a type name, not a variable" \
    "typedef receiver names the type"

# --- so is an enum name ---------------------------------------------------
cat >"$work/enum.ct" <<'CT'
enum Color { RED, GREEN };
int main(void) { return Color.make(1); }
CT
reject "$work/enum.ct" \
    "static method 'make' cannot be resolved: 'Color' is a type name, not a variable" \
    "enum receiver names the type"

# --- the shape that must keep working ------------------------------------
cat >"$work/ok.ct" <<'CT'
struct Box { int v; }
impl Box { static int make(int x) { return x + 2; } }
int main(void) { return Box.make(3); }
CT
if ! ( cd "$root" && "$ctast" "$work/ok.ct" -o "$work/ok.c" ) >"$work/ok.out" 2>"$work/ok.err"; then
    bad "struct static call" "rejected a legal call: $(sed -n '1,2p' "$work/ok.err")"
elif ! "${CC:-cc}" -std=c99 "$work/ok.c" -o "$work/ok" >"$work/cc.log" 2>&1; then
    bad "struct static call" "emitted C does not compile: $(sed -n '1,2p' "$work/cc.log")"
else
    "$work/ok"
    got=$?
    [ "$got" -eq 5 ] && ok "struct static call still works" || bad "struct static call" "ran with status $got"
fi

# --- a struct with no such static method keeps its own wording -----------
cat >"$work/nomethod.ct" <<'CT'
struct Box { int v; }
int main(void) { return Box.nope(1); }
CT
reject "$work/nomethod.ct" "'Box' has no static method 'nope'" \
    "declared struct with no such method keeps its message"

# --- an unknown name is not a type: do not overclaim ---------------------
cat >"$work/unknown.ct" <<'CT'
int main(void) { return Nope.make(1); }
CT
reject "$work/unknown.ct" "use of an undeclared variable" \
    "an undeclared name still reports an undeclared variable"

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/lang7 (type-name static call diagnostic)"
