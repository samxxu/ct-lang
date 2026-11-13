#!/bin/sh
# Phase 42 R6: a private method of a pub generic template stays static and
# out of the instance header; a pub one is exported.
set -u
ctast=$1
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/out"
cat > "$work/lib.h.ct" <<'CT'
pub struct Box<T> { T v; }
impl<T> Box<T> {
    T secret() { return self.v; }
    pub T get() { return self.v; }
}
CT
cat > "$work/main.ct" <<'CT'
import lib;
int main(void) { Box<int> b = {1}; return b.get(); }
CT
if ! "$ctast" build --emit-c "$work/main.ct" -o "$work/out" >"$work/b.out" 2>"$work/b.err"; then
    echo "FAIL p42/generic: build: $(cat "$work/b.err")"; exit 1
fi
hdr="$work/out/lib.h"
src="$work/out/lib.c"
fail=0
if grep -q 'Box_int_secret' "$hdr"; then echo "FAIL p42/generic: private instance prototype"; fail=1; fi
if ! grep -q 'Box_int_get' "$hdr"; then echo "FAIL p42/generic: public instance prototype missing"; fail=1; fi
if ! grep -q 'static .*Box_int_secret' "$src"; then echo "FAIL p42/generic: private instance not static"; fail=1; fi
if [ "$fail" -eq 0 ]; then echo "p42/generic: 1 passed, 0 failed"; else echo "p42/generic: 0 passed, 1 failed"; fi
[ "$fail" -eq 0 ]
