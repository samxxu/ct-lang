#!/bin/sh
set -u
ctast=${1:?usage: p45_contract.sh <ct-ast>}
fail=0
for d in p45_init p45_assign p45_return p45_container p45_depth; do
  "$ctast" check --types "test/ast/errors/$d/prog.ct" >/tmp/p45.out 2>/tmp/p45.err
  rc=$?
  if [ "$rc" -eq 0 ]; then echo "FAIL $d: rc=0"; fail=$((fail+1)); continue; fi
  if ! grep -Eq "expected '.*', got '.*'|argument [0-9]+: expected" /tmp/p45.err; then
    echo "FAIL $d: wrong diagnostic"; sed 's/^/  /' /tmp/p45.err; fail=$((fail+1))
  fi
done
"$ctast" check --types test/ast/p45_contract/prog.ct >/tmp/p45.out 2>/tmp/p45.err
if [ $? -ne 0 ] || [ -s /tmp/p45.err ]; then
  echo "FAIL p45_contract: legal void* conversion"; cat /tmp/p45.err; fail=$((fail+1))
fi
"$ctast" check --types examples/18_generic_string_table/generic_string_table.ct >/tmp/p45.out 2>/tmp/p45.err
if [ $? -ne 0 ] || [ -s /tmp/p45.err ]; then
  echo "FAIL p45_closure: example 18 false positive"; cat /tmp/p45.err; fail=$((fail+1))
fi
echo "p45/contract: $((6 - fail))/6 negative + legal skip + closure"
[ "$fail" -eq 0 ]
