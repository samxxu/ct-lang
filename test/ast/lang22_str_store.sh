#!/usr/bin/env bash
# LANG-22: a non-immortal `Str` / `U16Str` view stored in a container element,
# an ADT payload or a global / static is a warning in compile/build and an
# error under `ct check` (the SH-106 severity policy). Immortal literals, views
# of an owner that outlives the frame (parameter / global / static / `self`)
# and owning `String` values are silent.
#
# Usage: bash test/ast/lang22_str_store.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
CT=${1:?usage: lang22_str_store.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
export CT_CORE_DIR="$root/lib/core"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/lang22.XXXXXX")
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL lang22: %s\n' "$1" >&2; }
msg="storing a non-immortal 'Str' view; the owner must outlive the container"

# A positive program: an immortal literal table, an immortal owner, an
# owning String and a caller-owned parameter are all safe.
cat >"$tmp/ok.ct" <<'CT'
Str gp = "global";
String go = "global-owner";
Str gv = go.as_str();
void use(Str p) { Vec<Str> v; v.push(p); }
int main(void) {
    Str a = "uart0";
    Str b = "uart1";
    Vec<Str> names = { a, b };
    Option<Str> o = Option<Str>::none();
    o.set(a);
    return names.len + o.is_some() + gp.len + gv.len;
}
CT
"$CT" check --types "$tmp/ok.ct" >"$tmp/ok.chk" 2>&1
if [ $? -eq 0 ] && [ ! -s "$tmp/ok.chk" ]; then ok "positive: immortal / outliving owners are silent"; else bad "positive check: $(cat "$tmp/ok.chk")"; fi
"$CT" "$tmp/ok.ct" -o "$tmp/ok.c" >"$tmp/ok.cmp" 2>&1
if [ $? -eq 0 ] && [ ! -s "$tmp/ok.cmp" ]; then ok "positive: compile is silent"; else bad "positive compile: $(cat "$tmp/ok.cmp")"; fi

neg() { # name, source
    name=$1
    printf '%s\n' "$2" >"$tmp/$name.ct"
    "$CT" check --types "$tmp/$name.ct" >"$tmp/$name.chk" 2>&1
    chk=$?
    if [ "$chk" -eq 1 ] && grep -Fq "error: $msg" "$tmp/$name.chk"; then
        ok "$name: check --types is an error"
    else
        bad "$name: check --types (exit $chk): $(head -1 "$tmp/$name.chk")"
    fi
    "$CT" "$tmp/$name.ct" -o "$tmp/$name.c" >"$tmp/$name.cmp" 2>&1
    cmp=$?
    if [ "$cmp" -eq 0 ] && grep -Fq "warning: $msg" "$tmp/$name.cmp"; then
        ok "$name: compile is a warning"
    else
        bad "$name: compile (exit $cmp): $(head -1 "$tmp/$name.cmp")"
    fi
}

neg vec_push 'int main(void) {
    String a = "hello";
    String s = a.to_string();
    Vec<Str> v;
    v.push(s.as_str());
    return v.len;
}'
neg vec_brace 'int main(void) {
    String a = "hello";
    String s = a.to_string();
    Str local = s.as_str();
    Vec<Str> v = { local };
    return v.len;
}'
neg option_set 'int main(void) {
    String a = "hello";
    String s = a.to_string();
    Option<Str> o = Option<Str>::none();
    o.set(s.as_str());
    return o.is_some();
}'
neg adt_payload 'enum Msg { Text(Str s), None() }
int main(void) {
    String a = "hello";
    String s = a.to_string();
    Msg m = Msg.Text(s.as_str());
    return s.len;
}'
neg global_assign 'Str gv;
int main(void) {
    String a = "hello";
    String s = a.to_string();
    gv = s.as_str();
    return gv.len;
}'
neg global_decl 'String make(void) { return "x"; }
Str gv = make().as_str();
int main(void) { return gv.len; }'

# `ct build` keeps the warning and still succeeds (the issue's acceptance).
mkdir -p "$tmp/bneg/out"
printf '%s\n' 'int main(void) {
    String a = "hello";
    String s = a.to_string();
    Vec<Str> v;
    v.push(s.as_str());
    return v.len;
}' >"$tmp/bneg/main.ct"
( cd "$tmp/bneg" && "$CT" build --emit-c -o out main.ct ) >"$tmp/bneg.out" 2>"$tmp/bneg.err"
brc=$?
if [ "$brc" -eq 0 ] && grep -Fq "warning: $msg" "$tmp/bneg.err"; then
    ok "build: warning keeps the run green"
else
    bad "build (exit $brc): $(head -1 "$tmp/bneg.err")"
fi

printf 'lang22_str_store: %d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
