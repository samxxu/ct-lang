#!/bin/sh
# Phase 44 S1: the postfix `?` disambiguation matrix (design §3.1).
#
# Kinds:
#   S  a suffix `?` (rc=0)
#   T  the conditional operator, not a suffix (rc=0)
#   E  a conditional operator whose `:` is missing, because the token after
#      `?` starts an expression -- the user gets a syntax error, not a
#      silently shifted operator (rc!=0)
run() {
    name=$1
    code=$2
    kind=$3
    printf '%s\n' "$code" > /tmp/p44syntax.ct
    "$ctast" check /tmp/p44syntax.ct >/tmp/p44syntax.out 2>/tmp/p44syntax.err
    rc=$?
    case "$kind" in
    S|T)
        [ "$rc" -eq 0 ] || { echo "FAIL $name: expected rc=0, got $rc"; head -2 /tmp/p44syntax.err; return 1; }
        ;;
    E)
        [ "$rc" -ne 0 ] || { echo "FAIL $name: expected a syntax error (missing ':')"; return 1; }
        ;;
    esac
    return 0
}
ctast=${1:?usage: p44_try_syntax.sh <ct-ast>}
pass=0
fail=0
for spec in \
  "semi|S|Result<int, char *> f(void) { return err: (Result<int, char *>){0,0,0}; } int main(void) { f()?; return 0; }" \
  "comma|S|void g(int x) { (void)x; } int main(void) { g(1)?; return 0; }" \
  "paren|T|int main(void) { int a=1,b=2,c=3; return a ? b : c; }" \
  "unary|T|int main(void) { int a=1,b=2; return a ? -b : 0; }" \
  "ternary|T|int main(void) { int a=1,b=2,c=3; return a ? b : c; }" \
  "assign|S|int main(void) { int a=1, b=0; b = a?; return b; }" \
  "arg|S|void g(int x) { (void)x; } int main(void) { int a=1; g(a?); return 0; }" \
  "args2|S|void g(int x, int y) { (void)x; (void)y; } int main(void) { int a=1; g(a?, a?); return 0; }" \
  "plus|S|int main(void) { int a=1; return a?+1; }" \
  "parenpost|S|int main(void) { int a=1; return (a?)+1; }" \
  "arrow|S|struct S { int x; }; int main(void) { struct S s = {1}; struct S *p = &s; return p?->x; }" \
  "commaexpr|S|int main(void) { int a=1; return (a?, a); }" \
  "str|T|int main(void) { int a=1; char *s = a ? \"x\" : \"y\"; return s[0] == 'x'; }" \
  "preinc|T|int main(void) { int a=1,b=2,c=3; return a ? ++b : c; }" \
  "nested|T|int main(void) { int a=1,b=2,c=3,d=4,e=5; return a ? b ? c : d : e; }" \
  "star|T|int main(void) { int a=1,x=2; int *p=&x; return a ? *p : 0; }" \
  "comment|T|int main(void) { int a=1,b=2,c=3; return a ? /*why*/ b : c; }" \
  "sub|E|int main(void) { int a=1; return a? - 1; }" \
  "mul|E|int main(void) { int a=1,x=2; int *p=&x; return a? *p; }" \
  "andand|E|int main(void) { int a=1,b=0; return a? && b; }" \
  "preinc_e|E|int main(void) { int a=1,b=2; b = a? ++b; return b; }" \
  "predec_e|E|int main(void) { int a=1,b=2; int c = a? --b; return c; }"; do
    name=${spec%%|*}; body=${spec#*|}; kind=${body%%|*}; code=${body#*|}
    if run "$name" "$code" "$kind"; then pass=$((pass+1)); else fail=$((fail+1)); fi
done
echo "p44/syntax: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
