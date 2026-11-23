#!/usr/bin/env bash
# PH-87 S87c probe: the A checker (`--check-level=warn`) on the compiler's own
# source.
#
# E87-5 asks for a dogfood run with no crash and a registered false-positive
# list. This probe builds ct-ast's own tree with `--check-level=warn`, requires
# the build to succeed, and compares the warnings with
# `test/probes/p87_dogfood.tsv`. PH-87 registered 10 findings, all one class
# (`'T a[]' is deprecated` on the first dimension of a multi-dimensional array
# parameter), as false positives. SH-108 fixed that class: the manifest is now
# empty and the run must report 0 warnings.
#
# Usage: bash test/ast/p87_dogfood.sh <ct-ast>
set -u
CT=${1:?usage: p87_dogfood.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p87dog.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT INT TERM
pass=0
fail=0
ok()  { pass=$((pass + 1)); }
bad() { fail=$((fail + 1)); echo "FAIL p87dogfood: $1" >&2; }

out="$tmp/emit"
mkdir -p "$out"
if "$CT" build --emit-c --check-level=warn -I selfhost/ct-ast \
        selfhost/ct-ast/main.ct -o "$out" >"$tmp/build.out" 2>"$tmp/build.err"; then
    ok
    echo "  p87dogfood: the compiler builds its own tree under --check-level=warn"
else
    bad "the compiler crashed or failed under --check-level=warn: $(head -3 "$tmp/build.err" | tr '\n' ' ')"
fi

warn=$(grep -c 'warning:' "$tmp/build.err" || true)
if [ "$warn" -eq 0 ]; then
    ok
    echo "  p87dogfood: 0 warnings after SH-108"
else
    bad "expected 0 warnings after SH-108, got $warn"
fi
if [ "$warn" -gt 0 ] && grep 'warning:' "$tmp/build.err" \
        | grep -vFq "warning: 'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array"; then
    bad "a warning outside the registered false-positive class appeared"
else
    ok
fi
if [ "$warn" -gt 0 ] && grep 'warning:' "$tmp/build.err" | grep -vq '^selfhost/ct-ast/'; then
    bad "a dogfood warning points outside the compiler tree"
else
    ok
fi

sort "$tmp/build.err" >"$tmp/sorted.err"
if diff -u test/probes/p87_dogfood.tsv "$tmp/sorted.err" >"$tmp/diff.txt" 2>&1; then
    ok
else
    bad "the dogfood warning set drifted from test/probes/p87_dogfood.tsv: $(head -4 "$tmp/diff.txt" | tr '\n' ' ')"
fi

doc=docs/design/p87_dogfood.md
if [ -s "$doc" ] && grep -Fq "SH-108" "$doc" \
   && grep -Fq "0 条 warning" "$doc" && grep -Fq "误报" "$doc"; then
    ok
else
    bad "$doc is missing the dogfood counts or the false-positive list"
fi

echo "p87dogfood: $pass passed, $fail failed"
if [ "$fail" -eq 0 ]; then echo "OK p87dogfood"; fi
[ "$fail" -eq 0 ]
