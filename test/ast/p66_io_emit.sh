#!/usr/bin/env bash
# PH-66 R2 probe: the detected headers reach the product, exactly once.
# Build mode is the discriminating case: an unused layer is pruned, so before
# R2 a `printf`-only unit had no <stdio.h> at all.
# Usage: bash test/ast/p66_io_emit.sh <ct-ast>
set -u
CT=${1:?usage: p66_io_emit.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p66emi.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0
mkdir -p "$tmp/o1" "$tmp/o2"

cat >"$tmp/io.ct" <<'CT'
int main(void) { printf("hi\n"); return 0; }
CT
cat >"$tmp/w.ct" <<'CT'
int main(void) { wprintf("x"); return 0; }
CT

count() {   # count <file> <pattern>
    grep -c -- "$2" "$1" 2>/dev/null || true
}

( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" build --emit-c io.ct -o "$tmp/o1" ) \
    >"$tmp/b1.log" 2>"$tmp/b1.err" || {
    echo "FAIL p66/io-emit: build of the printf unit failed" >&2
    sed 's/^/  /' "$tmp/b1.err" | head -3 >&2
    exit 1
}
n=$(count "$tmp/o1/io.c" '#include <stdio.h>')
[ "$n" = "1" ] || { echo "FAIL p66/io-emit: build mode has $n <stdio.h> (want 1)" >&2; fail=1; }
n=$(count "$tmp/o1/io.c" '#include <wchar.h>')
[ "$n" = "0" ] || { echo "FAIL p66/io-emit: build mode pulled <wchar.h> ($n)" >&2; fail=1; }

( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" build --emit-c w.ct -o "$tmp/o2" ) \
    >"$tmp/b2.log" 2>"$tmp/b2.err" || {
    echo "FAIL p66/io-emit: build of the wprintf unit failed" >&2
    sed 's/^/  /' "$tmp/b2.err" | head -3 >&2
    exit 1
}
n=$(count "$tmp/o2/w.c" '#include <wchar.h>')
[ "$n" = "1" ] || { echo "FAIL p66/io-emit: build mode has $n <wchar.h> (want 1)" >&2; fail=1; }

# Compile mode merges the layer into one translation unit; the header must not
# appear twice (the layer's own include is deduped).
( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" io.ct -o "$tmp/c.c" ) \
    >"$tmp/c.log" 2>"$tmp/c.err" || {
    echo "FAIL p66/io-emit: compile mode failed" >&2
    sed 's/^/  /' "$tmp/c.err" | head -3 >&2
    exit 1
}
n=$(count "$tmp/c.c" '#include <stdio.h>')
[ "$n" = "1" ] || { echo "FAIL p66/io-emit: compile mode has $n <stdio.h> (want 1)" >&2; fail=1; }

[ "$fail" -eq 0 ] && echo "OK p66/io-emit"
exit "$fail"
