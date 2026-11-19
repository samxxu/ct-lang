#!/bin/sh
# PH-70-R1: structured control-flow judgement. Code after an if/else whose
# both arms return is unreachable; an if without else is not.
#
# Usage: sh test/ast/p70_cfg.sh <ct-ast>
set -u
ctast=${1:?usage: p70_cfg.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p70c.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/both.ct" <<'CT'
int f(int c) { if (c) return 1; else return 2; int x = 3; return x; }
int main(void) { return f(1); }
CT
cat > "$work/one.ct" <<'CT'
int f(int c) { if (c) return 1; return 2; }
int main(void) { return f(1); }
CT
cat > "$work/loop.ct" <<'CT'
int f(void) { while (1) { } return 0; }
int main(void) { return f(); }
CT

out=$work/both.out
( cd "$root" && "$ctast" check --semantics "$work/both.ct" ) >"$out" 2>&1
if [ $? -eq 0 ] || ! grep -q "unreachable code after a jump" "$out"; then
    echo "FAIL p70/cfg: if/else both return not detected" >&2
    sed 's/^/  /' "$out" | head -4 >&2
    fail=1
fi

for c in one loop; do
    out=$work/$c.out
    ( cd "$root" && "$ctast" check --semantics "$work/$c.ct" ) >"$out" 2>&1 || {
        echo "FAIL p70/cfg: $c rejected" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    }
done

[ "$fail" -eq 0 ] || exit 1
echo "OK p70/cfg (structured termination)"
