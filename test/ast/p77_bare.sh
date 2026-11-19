#!/bin/sh
# PH-77-S1: the official pin table and the three name shapes.
#
# A bare name resolves the built-in official pins only -- never an index, never
# CT_REGISTRY -- and any other bare name is a hard error that asks for
# `<publisher>/<name>`. `ct/<name>` prefers an index row with `publisher = ct`
# and falls back to the pin. The pin itself is exercised offline by rewriting
# the official URL to a local repository (git insteadOf), so the test needs no
# network; the pinned digest mismatch is what proves the pin answered.
#
# Usage: sh test/ast/p77_bare.sh <ct-ast>
set -u
ctast=${1:?usage: p77_bare.sh <ct-ast>}
# Probes cd into throwaway projects, so pin the compiler down absolutely.
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p77bare.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/bare: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

if ! command -v git >/dev/null 2>&1; then
    echo "FAIL p77/bare: git is required for the offline fixtures" >&2
    exit 1
fi

pin_sha="sha256:432086f0ec6c9ef3cdce5e24d465924d207e81d04f97595518d6e7d584ddaa79"

mkrepo() { # <dir> <name> <publisher> <version> <tag>
    mkdir -p "$1"
    (
        cd "$1" || exit 1
        git init -q
        printf 'name = %s\npublisher = %s\nversion = %s\nns-root = .\n' \
            "$2" "$3" "$4" >ct.pkg
        printf 'pub int %s_value(void);\nint %s_value(void) { return 1; }\n' \
            "$2" "$2" >"$2.c"
        git add -A
        git -c user.email=p77@test -c user.name=p77 commit -qm one
        git tag "$5"
    )
}

digest_of() { # <dir> -> sha256:... of its tree
    d="$work/dig.$$.$(basename "$1")"
    mkdir -p "$d/home" "$d/proj"
    printf 'name = demo\nversion = 0.1.0\n' >"$d/proj/ct.pkg"
    ( cd "$d/proj" && HOME="$d/home" CT_HOME="$d/home" "$ctast" get "$1" \
        >/dev/null 2>&1 ) || return 1
    awk 'NR>1 { print $NF }' "$d/proj/ct.lock" | tail -1
}

proj() { # <dir> [dep]
    mkdir -p "$1"
    printf 'name = demo\nversion = 0.1.0\n%s\n' "${2:-}" >"$1/ct.pkg"
}

mkrepo "$work/repo_off" std ct 0.19.0 v0.19.0 || exit 1
mkrepo "$work/repo_acme" std acme 0.9.9 v0.9.9 || exit 1
mkrepo "$work/repo_hal" hal acme 0.2.0 v0.2.0 || exit 1
d_off=$(digest_of "$work/repo_off") || { echo "FAIL p77/bare: cannot digest the official fixture" >&2; exit 1; }
d_acme=$(digest_of "$work/repo_acme") || { echo "FAIL p77/bare: cannot digest the acme fixture" >&2; exit 1; }
d_hal=$(digest_of "$work/repo_hal") || { echo "FAIL p77/bare: cannot digest the hal fixture" >&2; exit 1; }
cat >"$work/index" <<EOF
std 0.19.0 ct file://$work/repo_off v0.19.0 $d_off
std 0.9.9 acme file://$work/repo_acme v0.9.9 $d_acme
hal 0.2.0 acme file://$work/repo_hal v0.2.0 $d_hal
EOF

# Rewrite the pinned official URL to the local fixture: a bare `std` still
# clones "https://github.com/ct-pkg/std", but the tree cannot match the pin,
# so the failure names the pinned digest.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0="url.file://$work/repo_off.insteadOf"
export GIT_CONFIG_VALUE_0="https://github.com/ct-pkg/std"

# --- E77-3a: a bare name ignores the index, even a `ct`-less one -----------
mkdir -p "$work/h1" "$work/p1"
proj "$work/p1"
( cd "$work/p1" && HOME="$work/h1" CT_HOME="$work/h1" \
    "$ctast" get --index "$work/index" std >"$work/a.out" 2>"$work/a.err" )
if [ $? -eq 0 ]; then
    bad "bare std with an index" "expected the pinned source, got exit 0"
elif grep -Fq "'std' does not match the pinned digest" "$work/a.err" \
     && grep -Fq "$pin_sha" "$work/a.err" \
     && ! grep -Fq "is ambiguous" "$work/a.err"; then
    ok "bare std resolves the built-in pin and ignores the index"
else
    bad "bare std with an index" "$(cat "$work/a.err")"
fi
[ -f "$work/p1/ct.lock" ] && bad "pinned digest refusal" "a refused get wrote ct.lock"

# --- E77-3b: a qualified third party is reachable through the index --------
mkdir -p "$work/h2" "$work/p2"
proj "$work/p2"
( cd "$work/p2" && HOME="$work/h2" CT_HOME="$work/h2" \
    "$ctast" get --index "$work/index" acme/std >"$work/b.out" 2>"$work/b.err" )
if [ $? -eq 0 ] \
   && grep -q '^acme/std 0\.9\.9 git ' "$work/p2/ct.lock" \
   && [ -f "$work/h2/pkg/acme/std/0.9.9/ct.pkg" ]; then
    ok "ct get acme/std stores the third-party identity"
else
    bad "ct get acme/std" "$(cat "$work/b.err"; cat "$work/p2/ct.lock" 2>/dev/null)"
fi

# --- E77-3c: a non-official bare name is a hard error ----------------------
mkdir -p "$work/h3" "$work/p3"
proj "$work/p3"
if ( cd "$work/p3" && HOME="$work/h3" CT_HOME="$work/h3" CT_REGISTRY="file://$work" \
        "$ctast" get --index "$work/index" hal >"$work/c.out" 2>"$work/c.err" ); then
    bad "bare hal" "a third-party bare name was accepted"
elif grep -Fq "'hal' is not an official package" "$work/c.err" \
     && grep -Fq "<publisher>/<name>" "$work/c.err"; then
    ok "bare hal is refused with the qualified spelling hint"
else
    bad "bare hal" "$(cat "$work/c.err")"
fi
[ -f "$work/p3/ct.lock" ] && bad "bare hal lock" "a refused bare name wrote ct.lock"

# --- a qualified third party is not a new bare name ------------------------
mkdir -p "$work/h4" "$work/p4"
proj "$work/p4"
if ( cd "$work/p4" && HOME="$work/h4" CT_HOME="$work/h4" \
        "$ctast" get --index "$work/index" acme/hal >"$work/d.out" 2>"$work/d.err" ) \
   && grep -q '^acme/hal 0\.2\.0 git ' "$work/p4/ct.lock"; then
    ok "ct get acme/hal uses the index"
else
    bad "ct get acme/hal" "$(cat "$work/d.err"; cat "$work/p4/ct.lock" 2>/dev/null)"
fi

# --- a qualified official name without an index fails with guidance --------
mkdir -p "$work/h5" "$work/p5"
proj "$work/p5"
if ( cd "$work/p5" && HOME="$work/h5" CT_HOME="$work/h5" \
        "$ctast" get ct/hal >"$work/e.out" 2>"$work/e.err" ); then
    bad "ct get ct/hal" "expected a non-zero exit"
elif grep -Fq "no index resolver for 'ct/hal'" "$work/e.err" \
     && grep -Fq "ct get --index <file> ct/hal" "$work/e.err"; then
    ok "ct/hal is not pinned and asks for an index"
else
    bad "ct get ct/hal" "$(cat "$work/e.err")"
fi

# --- E77-2 (resolution half): bare std and ct/std pick the same pin --------
mkdir -p "$work/h6" "$work/h7" "$work/p6" "$work/p7"
proj "$work/p6"
proj "$work/p7"
( cd "$work/p6" && HOME="$work/h6" CT_HOME="$work/h6" \
    "$ctast" get std >"$work/f1.out" 2>"$work/f1.err" )
( cd "$work/p7" && HOME="$work/h7" CT_HOME="$work/h7" \
    "$ctast" get ct/std >"$work/f2.out" 2>"$work/f2.err" )
if [ -s "$work/f1.err" ] && cmp -s "$work/f1.err" "$work/f2.err" \
   && grep -Fq "$pin_sha" "$work/f1.err"; then
    ok "bare std and ct/std resolve the same (url, tag, sha256)"
else
    bad "E77-2 resolution" "$(diff "$work/f1.err" "$work/f2.err" | head -4)"
fi

# --- a range outside the pin is a hard error with a URL hint ---------------
mkdir -p "$work/h8" "$work/p8"
proj "$work/p8"
if ( cd "$work/p8" && HOME="$work/h8" CT_HOME="$work/h8" \
        "$ctast" get std@0.3.2 >"$work/g.out" 2>"$work/g.err" ); then
    bad "ct get std@0.3.2" "a range outside the pin was accepted"
elif grep -Fq "no official version of 'std' satisfies '0.3.2'" "$work/g.err" \
     && grep -Fq "use a URL" "$work/g.err"; then
    ok "a range outside the pin points at a URL"
else
    bad "ct get std@0.3.2" "$(cat "$work/g.err")"
fi

# --- E77-1 shape: the official identity lands on ct/std and its store ------
mkdir -p "$work/h9" "$work/p9"
proj "$work/p9"
if ( cd "$work/p9" && HOME="$work/h9" CT_HOME="$work/h9" \
        "$ctast" get --index "$work/index" ct/std@0.19.0 >"$work/i.out" 2>"$work/i.err" ) \
   && grep -Eq '^ct/std 0\.19\.0 git ' "$work/p9/ct.lock" \
   && [ -f "$work/h9/pkg/ct/std/0.19.0/ct.pkg" ]; then
    ok "ct/std locks as ct/std and stores under pkg/ct/std/<ver>"
else
    bad "ct/std identity" "$(cat "$work/i.err"; cat "$work/p9/ct.lock" 2>/dev/null)"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/bare (pin table, bare-name rule, official identity)"
