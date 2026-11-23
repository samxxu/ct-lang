#!/bin/sh
# PH-77-S5: the published side still agrees with the built-in pin.
#
# This is the only p77 probe that may touch the network. It needs git + curl and
# a reachable official index; without them it exits 77 (skip) and says why, so
# the hard gate stays offline-green. When it can run it proves E77-1 and E77-8:
# a clean HOME resolves the official pin with no index, both spellings write the
# same lock line, and the published index row matches the pin.
#
# Usage: sh test/ast/p77_external.sh <ct-ast>
set -u
ctast=${1:?usage: p77_external.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
work=$(mktemp -d "${TMPDIR:-/tmp}/p77ext.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/external: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

index_url="https://raw.githubusercontent.com/ct-pkg/index/master/index"
pin_sha="sha256:60d2e7dd157facc775e80d45e6769c4f2bfe7273feed6af7ccba9676d8ae42a7"

if ! command -v git >/dev/null 2>&1; then
    echo "skip: git is not installed" >&2
    exit 77
fi
if ! command -v curl >/dev/null 2>&1; then
    echo "skip: curl is not installed" >&2
    exit 77
fi
if ! curl -fsSL --retry 2 --retry-delay 1 --max-time 10 "$index_url" >"$work/index" 2>"$work/curl.err"; then
    echo "skip: cannot reach $index_url ($(sed -n '1p' "$work/curl.err"))" >&2
    exit 77
fi
row=$(grep -E '^std 0\.20\.0 ' "$work/index" | head -1)
if [ -z "$row" ]; then
    echo "skip: the official index has no std row yet" >&2
    exit 77
fi

# name version publisher url tag sha256
set -- $row
idx_ver=${2:-}
idx_pub=${3:-}
idx_url=${4:-}
idx_tag=${5:-}
idx_sha=${6:-}

mkdir -p "$work/h1" "$work/p1" "$work/h2" "$work/p2"
printf 'name = demo\nversion = 0.1.0\n' >"$work/p1/ct.pkg"
printf 'name = demo\nversion = 0.1.0\n' >"$work/p2/ct.pkg"

# The network is the only reason this probe may be inconclusive: a clone/fetch
# failure is a skip (77), never a failed assertion. Retry once -- GitHub is
# occasionally slow -- then hand the decision to the gate as `skip`.
network_skip() {
    echo "skip: $1" >&2
    exit 77
}
get_pkg() { # <proj> <home> <spec>
    ( cd "$1" && HOME="$2" CT_HOME="$2" "$ctast" get "$3" \
        >"$work/get.out" 2>"$work/get.err" )
    rc=$?
    [ "$rc" -eq 0 ] && return 0
    if grep -Eq 'git clone of|git fetch of|Cannot resolve|Could not resolve|unable to access|timed out|Connection (timed out|reset|refused)' \
            "$work/get.err"; then
        return 77
    fi
    return 1
}

# --- E77-1: clean HOME, no index, bare std ---------------------------------
get_pkg "$work/p1" "$work/h1" std
rc=$?
[ "$rc" -eq 77 ] && { sleep 2; get_pkg "$work/p1" "$work/h1" std; rc=$?; }
if [ "$rc" -eq 77 ]; then
    network_skip "cannot fetch the pinned source ($(sed -n '1p' "$work/get.err"))"
elif [ "$rc" -eq 0 ]; then
    ok "ct get std succeeds with a clean HOME and no index"
else
    bad "ct get std" "$(cat "$work/get.err")"
fi
if grep -q '^ct/std 0\.20\.0 git https://github\.com/ct-pkg/std ' "$work/p1/ct.lock" \
   && [ -f "$work/h1/pkg/ct/std/0.20.0/ct.pkg" ]; then
    ok "the lock is ct/std and the store is pkg/ct/std/<ver>"
else
    bad "official store/lock" "$(cat "$work/p1/ct.lock" 2>/dev/null)"
fi
lock_sha=$(awk '$1 == "ct/std" { print $NF }' "$work/p1/ct.lock")
if [ "$lock_sha" = "$pin_sha" ]; then
    ok "the fetched tree matches the pinned digest"
else
    bad "pinned digest" "lock $lock_sha / pin $pin_sha"
fi

# --- E77-2: both spellings write byte-identical lock lines -----------------
get_pkg "$work/p2" "$work/h2" ct/std
rc=$?
[ "$rc" -eq 77 ] && { sleep 2; get_pkg "$work/p2" "$work/h2" ct/std; rc=$?; }
if [ "$rc" -eq 77 ]; then
    network_skip "cannot fetch the pinned source for ct/std ($(sed -n '1p' "$work/get.err"))"
elif [ "$rc" -ne 0 ]; then
    bad "E77-2 get" "$(cat "$work/get.err")"
elif cmp -s "$work/p1/ct.lock" "$work/p2/ct.lock"; then
    ok "ct get std and ct get ct/std write the same lock"
else
    bad "E77-2 lock" "$(diff "$work/p1/ct.lock" "$work/p2/ct.lock" 2>/dev/null | head -4)"
fi

# --- E77-7/E77-8: the published row matches the pin -----------------------
if [ "$idx_ver" = "0.20.0" ] && [ "$idx_pub" = "ct" ] \
   && [ "$idx_url" = "https://github.com/ct-pkg/std" ] \
   && [ "$idx_tag" = "v0.20.0" ] && [ "$idx_sha" = "$pin_sha" ]; then
    ok "the official index row matches the built-in pin"
else
    bad "index/pin consistency" "index: $row"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/external (clean-HOME pin, both spellings, index row matches)"
