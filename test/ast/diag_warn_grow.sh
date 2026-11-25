#!/bin/sh
# S1a-0 C1: the warning store grows past MAX_WARNINGS (32).
set -u
ct=${1:?usage: diag_warn_grow.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/warn.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
i=0
while [ "$i" -lt 40 ]; do printf 'int f%d(int a[]) { return a[0]; }\n' "$i"; i=$((i+1)); done >"$w/prog.ct"
printf 'int main(void) { return 0; }\n' >>"$w/prog.ct"
mkdir "$w/out"
if "$ct" build --emit-c --check-level=warn "$w/prog.ct" -o "$w/out" >"$w/log" 2>&1; then
    n=$(grep -c 'warning:' "$w/log")
    if [ "$n" -eq 40 ]; then echo "ok   40 warnings recorded (grew past 32)"; else echo "FAIL warning count $n"; exit 1; fi
else
    echo "FAIL build stopped at $(grep -c 'warning:' "$w/log") warnings: $(tail -1 "$w/log")"; exit 1
fi
