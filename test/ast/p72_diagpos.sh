#!/bin/sh
# PH-72-R4: diagnostics must not truncate preprocessor lines silently
# (LANG-17/DF-1) and the column after a multi-line block comment must be the
# real one (LANG-16), not an offset from the previous line.
#
# Usage: sh test/ast/p72_diagpos.sh <ct-ast>
set -u
ctast=${1:?usage: p72_diagpos.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p72dp.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

python3 - "$work/pp.ct" <<'PY'
import sys
macro = "#define LONG_MACRO(x) ((x)" + "".join(" + %d" % i for i in range(1, 12000)) + ")"
open(sys.argv[1], "w").write(macro + "\nint main(void) { return LONG_MACRO(1); }\n")
PY
mkdir -p "$work/ppout"
( cd "$root" && "$ctast" build --emit-c -o "$work/ppout" "$work/pp.ct" ) >"$work/pp.log" 2>&1
if [ $? -eq 0 ] || ! grep -q "preprocessor line exceeds 65536 bytes" "$work/pp.log"; then
    echo "FAIL p72/diagpos: long preprocessor line not refused" >&2
    sed 's/^/  /' "$work/pp.log" | head -4 >&2
    fail=1
fi

cat > "$work/cmt.ct" <<'CT'
struct J { int n; }
int main(void) {
  struct J j;
  j /* long
     comment */ [0];
  return 0;
}
CT
( cd "$root" && "$ctast" check --types "$work/cmt.ct" ) >"$work/cmt.log" 2>&1
if ! grep -q "cmt.ct:5:17: error: " "$work/cmt.log"; then
    echo "FAIL p72/diagpos: column after block comment is wrong" >&2
    sed 's/^/  /' "$work/cmt.log" | head -4 >&2
    fail=1
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p72/diagpos (pp length + comment column)"
