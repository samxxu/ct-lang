#!/bin/sh
# PH-75-R1 (SH-65): a closure as a pair-form method argument is accepted,
# emitted as the (trampoline, env) pair, and the program runs correctly.
#
# Usage: sh test/ast/p75_closure.sh <ct-ast>
set -u
ctast=${1:?usage: p75_closure.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$ctast" in /*) ;; *) ctast=$root/$ctast ;; esac
work=$(mktemp -d "${TMPDIR:-/tmp}/p75c.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

cat > "$work/pos.ct" <<'CT'
trait Each { int each(int (*f)(void *env, int x), void *env); }
struct Box { int total; } use Each;
impl Each for Box {
    int each(int (*f)(void *env, int x), void *env) { return f(env, 3); }
}
int main(void) {
    struct Box b = { 7 };
    int r = b.each((int x) => b.total + x);
    return r == 10 ? 0 : 1;
}
CT

( cd "$work" && "$ctast" check --types pos.ct ) >"$work/chk.log" 2>&1 || {
    echo "FAIL p75/closure: pair-form check rejected" >&2
    sed 's/^/  /' "$work/chk.log" | head -4 >&2
    fail=1
}

( cd "$work" && "$ctast" build -o prog pos.ct ) >"$work/build.log" 2>&1 || {
    echo "FAIL p75/closure: pair-form build failed" >&2
    sed 's/^/  /' "$work/build.log" | head -4 >&2
    exit 1
}
"$work/prog" || {
    echo "FAIL p75/closure: program returned non-zero" >&2
    fail=1
}

[ "$fail" -eq 0 ] || exit 1
echo "OK p75/closure (pair-form method argument)"
