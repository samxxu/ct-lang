#!/bin/sh
# SH-110 / SH-73: dynamic-dispatch chains.
#
#   - a trait method's result may be the next hop's receiver, one or two hops;
#   - an inherent method returning an interface value may start a chain;
#   - each hop is evaluated exactly once and left to right;
#   - forms that cannot be materialised (compound literal, function pointer,
#     array) keep a hard, positioned error.
#
# Usage: sh test/ast/p110_dispatch_chain.sh <ct-ast>
set -u
export CT_C_BOUNDARY=allow
ctast=${1:?usage: p110_dispatch_chain.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p110chain.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
[ -d "$root/lib" ] && ln -s "$root/lib" "$work/lib"

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p110/chain: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

chain="$work/chain.ct"
cat >"$chain" <<'CT'
trait HttpRequest {
    int status();
    HttpRequest tap(int n);
    HttpRequest bump();
    int get_hits();
}

struct Req { int s; int hits; } use HttpRequest;

impl HttpRequest for Req {
    int status() { return self->s; }
    HttpRequest tap(int n) { self->s = self->s + n; return self; }
    HttpRequest bump() { self->hits = self->hits + 1; return self; }
    int get_hits() { return self->hits; }
}

impl Req {
    HttpRequest tuned(int n) { self->s = self->s + n; return self; }
}

int seq = 0;
int tick(int n) { seq = seq * 10 + n; return n; }

int chain_one(HttpRequest h) { return h.tap(1)->status(); }
int chain_two(HttpRequest h) { return h.tap(2)->tap(3)->status(); }
int chain_inherent(Req *x) { return x->tuned(4).status(); }
int chain_bumps(HttpRequest h) { return h.bump()->bump()->get_hits(); }
int chain_order(HttpRequest h) { return h.tap(tick(1))->tap(tick(2))->status(); }

int main(void)
{
    Req x;
    x.s = 1;
    x.hits = 0;
    HttpRequest h = x;
    printf("%d\n", chain_one(h));
    printf("%d\n", chain_two(h));
    printf("%d\n", chain_inherent(&x));
    printf("%d\n", chain_bumps(h));
    printf("%d\n", chain_order(h));
    printf("%d\n", seq);
    return 0;
}
CT
cat >"$work/chain.expected" <<'EOF'
2
7
11
2
14
12
EOF

if ( cd "$work" && "$ctast" chain.ct -o chain.c ) >"$work/chain.log" 2>&1; then
    if "${CC:-cc}" -Wall -Wextra -std=c99 "$work/chain.c" -o "$work/chain.bin" \
            >>"$work/chain.log" 2>&1; then
        if "$work/chain.bin" >"$work/chain.out" 2>&1; then
            if cmp -s "$work/chain.out" "$work/chain.expected"; then
                ok "three chain forms compile, run, and keep the evaluation order"
            else
                bad "chain output differs" "$(cat "$work/chain.out")"
            fi
        else
            bad "the chain program exited non-zero" "$(cat "$work/chain.out")"
        fi
    else
        bad "generated C did not build warning-free" "$(sed -n '1,4p' "$work/chain.log")"
    fi
else
    bad "the three chain forms were refused" "$(sed -n '1,4p' "$work/chain.log")"
fi

# Exactly one temporary per hop: `bump` runs twice, so `get_hits()` is 2.
if grep -q '__ct_tmp' "$work/chain.c" 2>/dev/null; then
    ok "the chain is materialised into temporaries"
else
    bad "the chain was not materialised" "no __ct_tmp in the generated C"
fi

expect_error() {
    name="$1"
    msg="$2"
    src="test/ast/errors/$name.ct"
    if ( cd "$root" && "$ctast" "$src" -o "$work/$name.c" ) >"$work/$name.log" 2>&1; then
        bad "$name is refused" "exit 0; expected a positioned diagnostic"
    elif grep -Fq "$msg" "$work/$name.log"; then
        ok "$name keeps its diagnostic"
    else
        bad "$name is refused" "$(sed -n '1,3p' "$work/$name.log")"
    fi
}

expect_error dispatch_chain_compound_recv \
    "method receiver must be a variable, an element, a call or a field chain"
expect_error dispatch_chain_fnptr_recv "no method 'val' for type 'Fn'"
expect_error dispatch_chain_array_recv "no method 'val' for type 'int *'"

exit $fail
