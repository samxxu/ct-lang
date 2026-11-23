#!/bin/sh
# PKG-23: a failed `ct get` git step must say what failed and what to do.
#
# The probe is offline. It drives real git against local repositories and a
# closed loopback port, plus one fake `git` for the authentication branch (a
# real 401 needs an HTTP server, and the point here is only that the captured
# stderr becomes a classified diagnostic). Every case asserts the *new*
# diagnostic wording, so it is red on a tree that still prints only
# `git fetch of '<url>' failed`.
#
# Usage: sh test/ast/pkg23_git_diag.sh <ct-ast>
set -u
ctast=${1:?usage: pkg23_git_diag.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
work=$(mktemp -d "${TMPDIR:-/tmp}/pkg23.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL pkg23: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

if ! command -v git >/dev/null 2>&1; then
    echo "skip: git is not installed" >&2
    exit 77
fi

# Bound the real-git probes and keep the closed loopback port off any proxy.
export CT_GIT_TIMEOUT=10
export NO_PROXY=127.0.0.1,localhost
export no_proxy=127.0.0.1,localhost

pin_url="https://github.com/ct-pkg/std"
pin_tag="v0.20.0"
pin_digest="sha256:60d2e7dd157facc775e80d45e6769c4f2bfe7273feed6af7ccba9676d8ae42a7"

# A local git package; the pinned digest is deliberately not reproduced -- the
# probe only needs fetch/checkout to run, not the official tree.
mkrepo() { # <dir> <tag>
    mkdir -p "$1"
    (
        cd "$1" || exit 1
        git init -q
        printf 'name = std\npublisher = ct\nversion = 0.20.0\nns-root = .\n' >ct.pkg
        printf 'pub int std_value(void);\nint std_value(void) { return 1; }\n' >std.c
        git add -A
        git -c user.email=pkg23@test -c user.name=pkg23 commit -qm one || exit 1
        git tag "$2"
    )
}

proj() { # <dir>
    mkdir -p "$1"
    printf 'name = demo\nversion = 0.1.0\n' >"$1/ct.pkg"
}

# seed_cache <home> <repo>: a valid cache whose origin is the pinned URL, so
# `ct get std` reaches the fetch path instead of cloning.
seed_cache() { # <home> <repo>
    cache="$1/.cache/ct-pkg/ct/std"
    mkdir -p "$1/.cache/ct-pkg/ct" || return 1
    git clone -q "$2" "$cache" || return 1
    git -C "$cache" remote set-url origin "$pin_url" || return 1
}

run_get() { # <home> <proj> <out-prefix> <path-prefix-or-empty> <args...>
    h=$1; p=$2; pre=$3; pp=$4
    shift 4
    if [ -n "$pp" ]; then
        ( cd "$p" && HOME="$h" CT_HOME="$h" PATH="$pp:$PATH" \
            "$ctast" get "$@" ) >"$work/$pre.out" 2>"$work/$pre.err"
    else
        ( cd "$p" && HOME="$h" CT_HOME="$h" "$ctast" get "$@" ) \
            >"$work/$pre.out" 2>"$work/$pre.err"
    fi
}

mkrepo "$work/good" "$pin_tag" || { echo "FAIL pkg23: cannot build the fixture repo" >&2; exit 1; }
mkrepo "$work/old" "v0.1.0" || { echo "FAIL pkg23: cannot build the old repo" >&2; exit 1; }

# --- network / proxy: a closed loopback port ---------------------------------
h="$work/h_net"; p="$work/p_net"
mkdir -p "$h" "$p"; proj "$p"
seed_cache "$h" "$work/good" || bad "network seed_cache"
( cd "$p" && HOME="$h" CT_HOME="$h" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0='url.http://127.0.0.1:1/x.git.insteadOf' \
    GIT_CONFIG_VALUE_0="$pin_url" \
    "$ctast" get std ) >"$work/net.out" 2>"$work/net.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    bad "network case succeeded against a closed port"
elif grep -q 'network/proxy' "$work/net.err" \
     && grep -q 'retry' "$work/net.err" \
     && grep -q 'ct get ct/std@0.20.0' "$work/net.err" \
     && grep -q 'git said' "$work/net.err"; then
    ok "an unreachable remote names network/proxy and gives a retry action"
else
    bad "network diagnostic" "$(cat "$work/net.err")"
fi
if [ -s "$work/net.err" ] && grep -q 'secret' "$work/net.err"; then
    bad "network diagnostic leaked credentials"
fi

# --- cache corruption: .git is not a repository ------------------------------
h="$work/h_bad"; p="$work/p_bad"
mkdir -p "$h" "$p" "$h/.cache/ct-pkg/ct/std/.git"; proj "$p"
cache="$h/.cache/ct-pkg/ct/std"
( cd "$p" && HOME="$h" CT_HOME="$h" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$work/good.insteadOf" \
    GIT_CONFIG_VALUE_0="$pin_url" \
    "$ctast" get std ) >"$work/bad.out" 2>"$work/bad.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    bad "corrupt cache was accepted"
elif grep -q "$cache" "$work/bad.err" \
     && grep -q "rm -rf '$cache'" "$work/bad.err" \
     && grep -q -- '--refresh' "$work/bad.err"; then
    ok "a corrupt cache names the cache path, rm -rf and --refresh"
else
    bad "corrupt-cache diagnostic" "$(cat "$work/bad.err")"
fi

# --- remote tag missing: fetch works, the pinned tag does not exist ----------
h="$work/h_tag"; p="$work/p_tag"
mkdir -p "$h" "$p"; proj "$p"
seed_cache "$h" "$work/old" || bad "tag seed_cache"
( cd "$p" && HOME="$h" CT_HOME="$h" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$work/old.insteadOf" \
    GIT_CONFIG_VALUE_0="$pin_url" \
    "$ctast" get std ) >"$work/tag.out" 2>"$work/tag.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    bad "a missing pinned tag was accepted"
elif grep -q 'remote tag/object missing' "$work/tag.err" \
     && grep -q "$pin_tag" "$work/tag.err"; then
    ok "a missing pinned tag is classified as remote tag/object missing"
else
    bad "missing-tag diagnostic" "$(cat "$work/tag.err")"
fi

# --- authentication: a git test double returns a 401-style message -----------
h="$work/h_auth"; p="$work/p_auth"
mkdir -p "$h" "$p" "$h/.cache/ct-pkg/ct/std/.git" "$work/fakebin"; proj "$p"
cat >"$work/fakebin/git" <<'EOF'
#!/bin/sh
for a in "$@"; do
    case "$a" in
        fetch)
            echo "fatal: Authentication failed for 'https://user:secret@example.test/ct-pkg/std/'" >&2
            exit 128 ;;
        --version)
            echo "git version 2.0.0"
            exit 0 ;;
    esac
done
case "$*" in
    *"config --get remote.origin.url"*)
        echo "https://github.com/ct-pkg/std"
        exit 0 ;;
esac
exit 0
EOF
chmod +x "$work/fakebin/git"
run_get "$h" "$p" auth "$work/fakebin" std
rc=$?
if [ "$rc" -eq 0 ]; then
    bad "authentication failure was accepted"
elif grep -q 'authentication/permission' "$work/auth.err" \
     && grep -q '\*\*\*@example.test' "$work/auth.err" \
     && ! grep -q 'secret' "$work/auth.err"; then
    ok "an authentication failure is classified and credentials are redacted"
else
    bad "authentication diagnostic" "$(cat "$work/auth.err")"
fi

# --- --refresh: rebuild the corrupt cache (then fail on the pin digest) ------
h="$work/h_ref"; p="$work/p_ref"
mkdir -p "$h" "$p" "$h/.cache/ct-pkg/ct/std/.git"; proj "$p"
cache="$h/.cache/ct-pkg/ct/std"
( cd "$p" && HOME="$h" CT_HOME="$h" \
    GIT_CONFIG_COUNT=1 \
    GIT_CONFIG_KEY_0="url.file://$work/good.insteadOf" \
    GIT_CONFIG_VALUE_0="$pin_url" \
    "$ctast" get --refresh std ) >"$work/ref.out" 2>"$work/ref.err"
rc=$?
if [ "$rc" -eq 0 ]; then
    bad "--refresh accepted a tree that does not match the pin"
elif grep -q "does not match the pinned digest" "$work/ref.err" \
     && [ -d "$cache/.git" ] \
     && [ "$(git -C "$cache" config --get remote.origin.url)" = "$pin_url" ]; then
    ok "--refresh discards the corrupt cache and fetches the pin again"
else
    bad "--refresh diagnostic" "$(cat "$work/ref.err"; ls -la "$cache" 2>/dev/null | head -4)"
fi
if ! grep -q "$pin_digest" "$work/ref.err"; then
    bad "--refresh did not reach the pinned-digest check" "$(cat "$work/ref.err")"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK pkg23 (network, corrupt cache, missing tag, auth, refresh)"
