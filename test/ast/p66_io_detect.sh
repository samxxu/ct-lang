#!/usr/bin/env bash
# PH-66 R1 probe: the libc I/O set is detected from DIRECT calls only.
#   printf -> <stdio.h>;  wprintf -> <wchar.h>;  none -> nothing;
#   syslog -> nothing (not in D-008's set); a name in a string/comment -> nothing.
# `--show-io-headers` is the internal debug entry that prints the deduped set.
# Usage: bash test/ast/p66_io_detect.sh <ct-ast>
set -u
CT=${1:?usage: p66_io_detect.sh <ct-ast>}
case "$CT" in
    /*) ;;
    *) CT=$(cd -- "$(dirname -- "$CT")" && pwd)/$(basename -- "$CT") ;;
esac
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p66det.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

cat >"$tmp/stdio.ct" <<'CT'
int main(void) { printf("hi\n"); return 0; }
CT
cat >"$tmp/mixed.ct" <<'CT'
int main(void) { puts("a"); fprintf(stdout, "b"); return 0; }
CT
cat >"$tmp/wchar.ct" <<'CT'
int main(void) { wprintf("x"); return 0; }
CT
cat >"$tmp/none.ct" <<'CT'
int main(void) { return 0; }
CT
cat >"$tmp/syslog.ct" <<'CT'
int main(void) { syslog(1, "x"); return 0; }
CT
cat >"$tmp/text.ct" <<'CT'
/* printf( in a comment must not count */
int main(void)
{
    const char *s = "printf(";
    return s[0] == 'p';
}
CT

run() {   # run <file>  -> header lines
    ( cd "$tmp" && env -u CT_C_BOUNDARY "$CT" --show-io-headers "$1" ) 2>"$tmp/err"
}

check() {   # check <label> <file> <want>
    local label=$1 file=$2 want=$3 got
    got=$(run "$file")
    if [ "$got" != "$want" ]; then
        echo "FAIL p66/io-detect: $label: want '$want', got '$got'" >&2
        sed 's/^/  /' "$tmp/err" | head -3 >&2
        fail=1
    fi
}

check "printf" stdio.ct "stdio.h"
check "puts+fprintf" mixed.ct "stdio.h"
check "wprintf" wchar.ct "wchar.h"
check "no call" none.ct ""
check "syslog is not in the set" syslog.ct ""
check "text is not a call" text.ct ""

[ "$fail" -eq 0 ] && echo "OK p66/io-detect"
exit "$fail"
