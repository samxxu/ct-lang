#!/bin/sh
# Phase 42 R4: a method without pub is static and absent from the header.
set -u
ctast=$1
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/out"
cat > "$work/p.h.ct" <<'CT'
pub struct Counter {
    int n;
}
impl Counter {
    int secret() { return self.n; }
    pub int get() { return self.n; }
}
CT
if ! "$ctast" build --emit-c "$work/p.h.ct" -o "$work/out" >"$work/b.out" 2>"$work/b.err"; then
    echo "FAIL p42/private: build: $(cat "$work/b.err")"; exit 1
fi
hdr="$work/out/p.h"
src="$work/out/p.c"
fail=0
if grep -q 'Counter_secret' "$hdr"; then echo "FAIL p42/private: private prototype in header"; fail=1; fi
if ! grep -q 'Counter_get' "$hdr"; then echo "FAIL p42/private: public prototype missing"; fail=1; fi
if ! grep -q 'static .*Counter_secret' "$src"; then echo "FAIL p42/private: private definition not static"; fail=1; fi
if [ "$fail" -eq 0 ]; then echo "p42/private: 1 passed, 0 failed"; else echo "p42/private: 0 passed, 1 failed"; fi
[ "$fail" -eq 0 ]
