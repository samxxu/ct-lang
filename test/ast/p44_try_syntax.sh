#!/bin/sh
# Phase 44 S1: suffix `?` disambiguation matrix (red until S2).
run() {
    name=$1; shift
    printf '%s\n' "$1" > /tmp/p44syntax.ct
    "$ctast" check /tmp/p44syntax.ct >/tmp/p44syntax.out 2>/tmp/p44syntax.err
    rc=$?
    if [ "$2" = "suffix" ]; then
        [ "$rc" -eq 0 ] || { echo "FAIL $name: suffix rc=$rc"; head -2 /tmp/p44syntax.err; return 1; }
    else
        [ "$rc" -eq 0 ] || { echo "FAIL $name: ternary rc=$rc"; head -2 /tmp/p44syntax.err; return 1; }
    fi
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
  "ternary|T|int main(void) { int a=1,b=2,c=3; return a ? b : c; }"; do
    name=${spec%%|*}; body=${spec#*|}; kind=${body%%|*}; code=${body#*|}
    if run "$name" "$code" "$([ "$kind" = S ] && echo suffix || echo ternary)"; then pass=$((pass+1)); else fail=$((fail+1)); fi
done
echo "p44/syntax: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
