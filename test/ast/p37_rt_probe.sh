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
elif ! grep -q '__CT_VT_GUARD' "$on/prog.c"; then
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

# A warm cache must not reuse an artefact produced with the other flag: the
# switch is a safety contract, so both directions are asserted.
cache="$tmp/cache"
rm -rf "$cache"
mkdir -p "$cache"
if ! "$CT" build --emit-c "$src" -o "$cache" >"$tmp/cache-off.out" 2>"$tmp/cache-off.err"; then
    echo "FAIL cache: off build failed" >&2
    fail=1
elif grep -q '__CT_VT_GUARD' "$cache/prog.c"; then
    echo "FAIL cache: off build unexpectedly guarded" >&2
    fail=1
elif ! "$CT" build --runtime-checks --emit-c "$src" -o "$cache" >"$tmp/cache-on.out" 2>"$tmp/cache-on.err"; then
    echo "FAIL cache: on build after off failed" >&2
    fail=1
elif ! grep -q '__CT_VT_GUARD' "$cache/prog.c"; then
    echo "FAIL cache: on after off reused the unguarded artefact" >&2
    fail=1
fi
cache="$tmp/cache2"
rm -rf "$cache"
mkdir -p "$cache"
if ! "$CT" build --runtime-checks --emit-c "$src" -o "$cache" >"$tmp/cache2-on.out" 2>"$tmp/cache2-on.err"; then
    echo "FAIL cache: on build failed" >&2
    fail=1
elif ! grep -q '__CT_VT_GUARD' "$cache/prog.c"; then
    echo "FAIL cache: on build has no guard" >&2
    fail=1
elif ! "$CT" build --emit-c "$src" -o "$cache" >"$tmp/cache2-off.out" 2>"$tmp/cache2-off.err"; then
    echo "FAIL cache: off build after on failed" >&2
    fail=1
elif grep -q '__CT_VT_GUARD' "$cache/prog.c"; then
    echo "FAIL cache: off after on reused the guarded artefact" >&2
    fail=1
fi

if [ "$fail" -eq 0 ]; then
    echo "p37_rt_probe: OK"
fi
exit "$fail"
