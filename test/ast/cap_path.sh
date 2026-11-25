#!/bin/sh
# S1a-0 C2l: the diagnostic file path and the cache directory / key path are
# owned blocks, not 1024-byte `MAX_PATH` buffers.
#
# Two white-box cases (both run on every host):
#   diag   a `Warn.file` of 1500 logical bytes prints whole; the old
#          `char file[MAX_PATH]` truncated it to 1023 and the test read the
#          cut line back.
#   cache  `Cache.paths` returns owned blocks for a 1406-byte logical output
#          path; the old API took two `char[MAX_PATH]` buffers and its fixed
#          signature cannot express the case at all (the probe fails to build
#          against it, which is the red evidence).
#
# A real >1024-byte path cannot be created on Darwin (PATH_MAX is 1024), so
# the end-to-end filesystem case lives in cap_path_real.sh, which skips there
# and runs on Linux CI.
#
# Usage: sh test/ast/cap_path.sh <ct-ast>
set -u
ct=${1:?usage: cap_path.sh <ct-ast>}
ct=$(cd "$(dirname "$ct")" && pwd)/$(basename "$ct")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
cd "$root" || exit 1
w=$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/cappath.XXXXXX") || exit 1
trap 'rm -rf "$w"' EXIT HUP INT TERM
cc=${CC:-cc}
fail=0

# The probes include one generated unit and link the real unit objects, so the
# C tree has to come from the compiler under test.
gen="$w/gen"
mkdir -p "$gen" || exit 1
if ! "$ct" build --emit-c -I selfhost/ct-ast selfhost/ct-ast/main.ct -o "$gen" \
        >"$w/gen.log" 2>&1; then
    echo "FAIL path: the compiler could not emit its own C tree: $(tail -1 "$w/gen.log")"
    echo "cap_path: FAIL"
    exit 1
fi

# --- diag: a 1500-byte logical unit path survives in the record and the line.
if ! $cc -Wall -Wextra -std=c99 -I "$gen" test/ast/cap_path_diag.c "$gen/Diag.c" \
        -o "$w/diag" 2>"$w/diag.build"; then
    echo "FAIL diag: the probe did not build: $(head -3 "$w/diag.build" | tr '\n' ' ')"
    fail=1
elif ! "$w/diag" 2>"$w/diag.out"; then
    sed 's/^/    /' "$w/diag.out"
    fail=1
else
    len=$(head -n 1 "$w/diag.out" | sed 's/:1: warning:.*//' | tr -d '\n' | wc -c | tr -d ' ')
    if [ "$len" -eq 1500 ] && grep -Fq ':1: warning: signature mismatch:' "$w/diag.out"; then
        echo "ok   diag file path (1500-byte path printed whole)"
    else
        echo "FAIL diag: the unit path is $len bytes (want 1500)"
        fail=1
    fi
    if grep -Fq 'a/b.ct:2: warning: signature mismatch:' "$w/diag.out"; then
        echo "ok   diag file path (short record keeps its own path)"
    else
        echo "FAIL diag: the short record lost its path"
        fail=1
    fi
fi

# --- cache: owned directory / key path for a 1406-byte logical output path.
if ! $cc -Wall -Wextra -std=c99 -I "$gen" test/ast/cap_path_cache.c \
        "$gen/Cache.c" "$gen/Sh.c" -o "$w/cache" 2>"$w/cache.build"; then
    echo "FAIL cache: the generated Cache unit cannot compose a long logical path:"
    sed 's/^/    /' "$w/cache.build" | head -3
    fail=1
elif ! "$w/cache"; then
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "cap_path: OK (diag file path, cache directory and key path)"
    exit 0
fi
echo "cap_path: FAIL"
exit 1
