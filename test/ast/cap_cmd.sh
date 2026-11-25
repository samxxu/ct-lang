#!/bin/sh
# S1a-0 C2f: the composed cc command line grows past the old 8192-byte MAX_CMD.
#
# Sixty units are enough: each unit adds
# `'<outdir>/<base>.c'` to the one link line, and a 180-byte output directory
# pushes the line past 8192 bytes while the unit table stays at its old
# 64-row initial size. The old compiler refused with
# "ctc: the cc command line is too long"; the new one grows the line to the
# formal TEXT_LIMIT and builds/runs the program.
#
# Usage: sh test/ast/cap_cmd.sh <ct-ast>
set -u
ct=${1:?usage: cap_cmd.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
# the fixture is host C / build input, not a package source
CT_C_BOUNDARY=allow
export CT_C_BOUNDARY
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/capcmd.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}

# A long output directory (nested, each component under NAME_MAX).
outdir="$w/o"
i=0
while [ ${#outdir} -lt 180 ]; do
    outdir="$outdir/ddddddddddddddddddddddddddddddddddd"
    i=$((i + 1))
done
mkdir -p "$outdir" || exit 1

# Sixty tiny units; the first owns `main`.
i=0
set -- "$w/u00.ct"
printf 'int main(void)\n{\n    return 0;\n}\n' >"$w/u00.ct"
while [ "$i" -lt 59 ]; do
    i=$((i + 1))
    n=$(printf '%02d' "$i")
    printf 'pub int f%s(void);\nint f%s(void) { return %d; }\n' "$n" "$n" "$i" \
        >"$w/u$n.ct"
    set -- "$@" "$w/u$n.ct"
done

if ! "$ct" build "$@" --outdir "$outdir" -o "$outdir/prog" >"$w/build.out" 2>"$w/build.err"; then
    echo "FAIL cc_line: ct-ast rejected a $((${#outdir} + 60)) * 60-byte link line:"
    sed 's/^/    /' "$w/build.err" | tail -3
    echo "cap_cmd: FAIL"
    exit 1
fi
if [ ! -x "$outdir/prog" ]; then
    echo "FAIL cc_line: no binary at the long output directory"
    echo "cap_cmd: FAIL"
    exit 1
fi
"$outdir/prog"
rc=$?
if [ "$rc" -ne 0 ]; then
    echo "FAIL cc_line: the linked program returned $rc"
    echo "cap_cmd: FAIL"
    exit 1
fi
echo "ok   cc_line (60-unit link line over 8192 bytes)"
echo "cap_cmd: OK (cc command text)"
exit 0
