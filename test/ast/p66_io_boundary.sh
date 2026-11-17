#!/usr/bin/env bash
# PH-66 R4 probe: the edges of the libc I/O exception (D-008 §4).
#   1. a user-defined `printf` is not "stolen": no <stdio.h> is added;
#   2. `syslog` (outside the set) never pulls <stdio.h>;
#   3. `--freestanding` never adds the header; an undeclared `printf` is an
#      error naming the file:line and the shim way out.
# Usage: bash test/ast/p66_io_boundary.sh <ct-ast>
set -u
CT=${1:?usage: p66_io_boundary.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p66bnd.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

cat >"$tmp/user.ct" <<'CT'
int printf(const char *s)
{
    return 0;
}

int main(void)
{
    return printf("x");
}
CT
cat >"$tmp/syslog.ct" <<'CT'
int main(void) { syslog(1, "x"); return 0; }
CT
cat >"$tmp/fs.ct" <<'CT'
int main(void) { printf("x"); return 0; }
CT

got=$( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" --show-io-headers user.ct 2>"$tmp/e1" )
if [ "$got" != "" ]; then
    echo "FAIL p66/io-boundary: a user-defined printf pulled '$got'" >&2
    fail=1
fi

got=$( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" --show-io-headers syslog.ct 2>"$tmp/e2" )
if [ "$got" != "" ]; then
    echo "FAIL p66/io-boundary: syslog pulled '$got'" >&2
    fail=1
fi

( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" --freestanding fs.ct -o "$tmp/fs.c" ) \
    >"$tmp/fs.out" 2>"$tmp/fs.err"
rc=$?
if [ "$rc" -ne 1 ]; then
    echo "FAIL p66/io-boundary: --freestanding accepted printf (rc=$rc)" >&2
    fail=1
elif ! grep -q "is not declared in a freestanding build" "$tmp/fs.err"; then
    echo "FAIL p66/io-boundary: wrong freestanding diagnostic" >&2
    sed 's/^/  /' "$tmp/fs.err" | head -3 >&2
    fail=1
elif [ -f "$tmp/fs.c" ]; then
    echo "FAIL p66/io-boundary: a rejected freestanding build left a product" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK p66/io-boundary"
exit "$fail"
