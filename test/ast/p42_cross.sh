#!/bin/sh
# Phase 42 R5: private methods are callable only from their own unit.
set -u
ctast=$1
work=$(mktemp -d) || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
cat > "$work/lib.h.ct" <<'CT'
pub struct Counter { int n; }
impl Counter {
    pub static Counter make(int n) { Counter c; c.n = n; return c; }
    int secret() { return self.n; }
    static int hidden() { return 7; }
}
CT
cat > "$work/main.ct" <<'CT'
import lib;
int main(void) { Counter c = Counter.make(1); return c.secret(); }
CT
cat > "$work/main2.ct" <<'CT'
import lib;
int main(void) { return Counter.hidden(); }
CT
pass=0
fail=0
for spec in "main.ct|method is private to its unit" "main2.ct|static method is private to its unit"; do
    f=${spec%%|*}; want=${spec#*|}
    if "$ctast" build --emit-c "$work/$f" -o "$work/out" >/dev/null 2>"$work/e"; then
        echo "FAIL $f: expected error"; fail=$((fail + 1)); continue
    fi
    if ! grep -qF "$want" "$work/e"; then
        echo "FAIL $f: missing '$want'"; sed 's/^/  /' "$work/e"; fail=$((fail + 1)); continue
    fi
    pass=$((pass + 1))
done
echo "p42/cross-unit: $pass passed, $fail failed"
[ "$fail" -eq 0 ]
