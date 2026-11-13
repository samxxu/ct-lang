#!/usr/bin/env bash
# Phase 37 O2 probe: --runtime-checks adds a null-vtable guard, off stays
# byte-compatible (no guard text), and the guarded program aborts with a
# source position instead of segfaulting.
# Usage: bash test/ast/p37_rt_probe.sh <ct-ast-binary>
set -u
CT=${1:?usage: p37_rt_probe.sh <ct-ast>}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/p37-rt.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
src="$root/test/ast/219_runtime_guard/prog.ct"
off="$tmp/off"
on="$tmp/on"
bld="$tmp/build"
bin="$tmp/prog"
mkdir -p "$off" "$on" "$bld"
fail=0

if ! "$CT" build --emit-c "$src" -o "$off" >"$tmp/off.out" 2>"$tmp/off.err"; then
    echo "FAIL runtime off: build failed" >&2
    sed 's/^/  /' "$tmp/off.err" >&2
    fail=1
elif grep -Rq 'runtime check' "$off"; then
    echo "FAIL runtime off: guard text leaked into the off build" >&2
    fail=1
fi

if ! "$CT" build --runtime-checks --emit-c "$src" -o "$on" >"$tmp/on.out" 2>"$tmp/on.err"; then
    echo "FAIL runtime on: build failed" >&2
    sed 's/^/  /' "$tmp/on.err" >&2
    fail=1
elif ! grep -q '__ct_vt_guard' "$on/prog.c"; then
    echo "FAIL runtime on: prog.c has no guard" >&2
    fail=1
fi

if ! "$CT" build --runtime-checks --outdir "$bld" "$src" -o "$bin" >"$tmp/bin.out" 2>"$tmp/bin.err"; then
    echo "FAIL runtime bin: build failed" >&2
    sed 's/^/  /' "$tmp/bin.err" >&2
    fail=1
else
    "$bin" >"$tmp/run.out" 2>"$tmp/run.err"
    rc=$?
    if [ "$rc" -eq 0 ]; then
        echo "FAIL runtime run: expected abort, got 0" >&2
        fail=1
    elif ! grep -Eq 'prog\.ct:[0-9]+' "$tmp/run.err"; then
        echo "FAIL runtime run: no source position" >&2
        sed 's/^/  /' "$tmp/run.err" >&2
        fail=1
    elif ! grep -Fq 'runtime check: null vtable' "$tmp/run.err"; then
        echo "FAIL runtime run: missing null-vtable message" >&2
        sed 's/^/  /' "$tmp/run.err" >&2
        fail=1
    fi
fi

# battle p38-1 B′: an unstable receiver is rejected on (and accepted off).
unstable="$root/test/ast/219_runtime_guard/unstable.ct"
rm -rf "$tmp/unstable"
mkdir -p "$tmp/unstable"
if "$CT" build --runtime-checks --emit-c "$unstable" -o "$tmp/unstable" \
        >"$tmp/unstable.out" 2>"$tmp/unstable.err"; then
    echo "FAIL unstable: expected a rejection" >&2
    fail=1
elif ! grep -Fq 'runtime checks need a stable receiver' "$tmp/unstable.err"; then
    echo "FAIL unstable: missing stable-receiver message" >&2
    sed 's/^/  /' "$tmp/unstable.err" >&2
    fail=1
elif [ -f "$tmp/unstable/unstable.c" ]; then
    echo "FAIL unstable: rejection left a .c" >&2
    fail=1
fi
rm -rf "$tmp/unstable-off"
mkdir -p "$tmp/unstable-off"
if ! "$CT" build --emit-c "$unstable" -o "$tmp/unstable-off" >"$tmp/unstable-off.out" 2>"$tmp/unstable-off.err"; then
    echo "FAIL unstable off: expected acceptance" >&2
    sed 's/^/  /' "$tmp/unstable-off.err" >&2
    fail=1
fi
# A stable subscript stays accepted and guarded.
safe="$root/test/ast/219_runtime_guard/safe_index.ct"
rm -rf "$tmp/safe" "$tmp/safe-bin"
mkdir -p "$tmp/safe"
if ! "$CT" build --runtime-checks --outdir "$tmp/safe" "$safe" -o "$tmp/safe-bin" \
        >"$tmp/safe.out" 2>"$tmp/safe.err"; then
    echo "FAIL safe_index: build failed" >&2
    sed 's/^/  /' "$tmp/safe.err" >&2
    fail=1
else
    "$tmp/safe-bin" >"$tmp/safe.run" 2>&1
    if [ "$?" -ne 5 ]; then
        echo "FAIL safe_index: expected rc=5" >&2
        fail=1
    fi
fi

# A warm cache must not reuse an artefact produced with the other flag: the
# switch is a safety contract, so both directions are asserted.
cache="$tmp/cache"
rm -rf "$cache"
mkdir -p "$cache"
if ! "$CT" build --emit-c "$src" -o "$cache" >"$tmp/cache-off.out" 2>"$tmp/cache-off.err"; then
    echo "FAIL cache: off build failed" >&2
    fail=1
elif grep -q '__ct_vt_guard' "$cache/prog.c"; then
    echo "FAIL cache: off build unexpectedly guarded" >&2
    fail=1
elif ! "$CT" build --runtime-checks --emit-c "$src" -o "$cache" >"$tmp/cache-on.out" 2>"$tmp/cache-on.err"; then
    echo "FAIL cache: on build after off failed" >&2
    fail=1
elif ! grep -q '__ct_vt_guard' "$cache/prog.c"; then
    echo "FAIL cache: on after off reused the unguarded artefact" >&2
    fail=1
fi
cache="$tmp/cache2"
rm -rf "$cache"
mkdir -p "$cache"
if ! "$CT" build --runtime-checks --emit-c "$src" -o "$cache" >"$tmp/cache2-on.out" 2>"$tmp/cache2-on.err"; then
    echo "FAIL cache: on build failed" >&2
    fail=1
elif ! grep -q '__ct_vt_guard' "$cache/prog.c"; then
    echo "FAIL cache: on build has no guard" >&2
    fail=1
elif ! "$CT" build --emit-c "$src" -o "$cache" >"$tmp/cache2-off.out" 2>"$tmp/cache2-off.err"; then
    echo "FAIL cache: off build after on failed" >&2
    fail=1
elif grep -q '__ct_vt_guard' "$cache/prog.c"; then
    echo "FAIL cache: off after on reused the guarded artefact" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "p37_rt_probe: OK"
fi
exit "$fail"
