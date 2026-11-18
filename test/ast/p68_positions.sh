#!/bin/sh
# PH-68-R3: the four judged positions must diagnose on mismatch and stay
# silent on legal code. Each negative case is its own file: the parser stops
# at the first hard error, so mixing them would hide later positions.
#
# Usage: sh test/ast/p68_positions.sh <ct-ast>
set -u
ctast=${1:?usage: p68_positions.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p68pos.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
fail=0

cat > "$tmp/pos.ct" <<'CT'
int f(void) { return 1; }
void take(Vec<int> v) { v.release(); }
int main(void)
{
    int a = 1;
    int b;
    b = a;
    int *p = &b;
    Vec<int> v = {1, 2};
    take(v);
    return f() + *p;
}
CT

check_neg() {
    name=$1; pat=$2; file=$3
    out=$tmp/$name.out
    ( cd "$root" && "$ctast" check --types "$file" ) >"$out" 2>&1
    if ! grep -q "$pat" "$out"; then
        echo "FAIL p68/positions: $name missing '$pat'" >&2
        sed 's/^/  /' "$out" | head -4 >&2
        fail=1
    fi
}

cat > "$tmp/init.ct" <<'CT'
int main(void) { int *p = 1; return p != 0; }
CT
cat > "$tmp/assign.ct" <<'CT'
int main(void) { int *p; p = 2; return p != 0; }
CT
cat > "$tmp/ret.ct" <<'CT'
int f(void) { return "x"; }
int main(void) { return f(); }
CT
cat > "$tmp/carg.ct" <<'CT'
void take(Vec<int> v) { v.release(); }
int main(void) { Vec<Vec<int>> g = {}; take(g); return 0; }
CT

out=$tmp/pos.out
( cd "$root" && "$ctast" check --types "$tmp/pos.ct" ) >"$out" 2>&1 || {
    echo "FAIL p68/positions: positive fixture rejected" >&2
    sed 's/^/  /' "$out" | head -6 >&2
    fail=1
}
for pat in 'initializer:' 'assignment:' 'return:' 'argument 1:'; do
    if grep -q "$pat" "$out"; then
        echo "FAIL p68/positions: positive fixture diagnosed with '$pat'" >&2
        fail=1
    fi
done

check_neg init 'initializer:' "$tmp/init.ct"
check_neg assign 'assignment:' "$tmp/assign.ct"
check_neg ret 'return:' "$tmp/ret.ct"
check_neg carg 'argument 1:' "$tmp/carg.ct"

[ "$fail" -eq 0 ] || exit 1
echo "OK p68/positions (init/assign/return/container arg)"
