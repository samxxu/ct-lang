#!/usr/bin/env bash
# S1a-0 C2e: the package manager's command text grows past the old 2048-byte
# MAX_PKG_CMD. One `ct get` of a local git package with a *quoted* cache path
# over 2048 bytes exercises every composed command: the clone, the tag listing,
# the checkout, the rev-parse and the captured-stderr wrapper.
#
# macOS caps a raw path at PATH_MAX (1024), so a >2048-byte command is reached
# the way a real one is: shell quoting expands every `'` in a 440-byte HOME to
# four bytes. The cache path keeps every quote, so `git -C '<cache>' ...`
# (and the `> '<tags>'` redirect of the tag listing) is over the old 2048
# buffer while the unquoted path still fits MAX_PKG_PATH.
#
#   * `ct get` succeeds where the old compiler returned -1 from git_run with
#     no diagnostic (the composed line did not fit `char full[MAX_PKG_CMD]`);
#   * the lock row records the full package identity;
#   * a second `ct get --json` reuses the cache and prints the URL in JSON
#     (the old `char url[MAX_PKG_CMD]` / `char giterr[MAX_PKG_CMD]` fields).
#
# The fixture is staged under mktemp -d, so the worktree is never written.
# `CT_AST` is required and an absent binary is an explicit failure (D-010-C).
#
# Usage:
#   CT_AST=/path/to/ct-ast bash test/pkg/pkg29_long_cmd.sh

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
ct="${CT_AST:-}"

if [ -z "$ct" ] || [ ! -x "$ct" ]; then
    printf 'pkg29: CT_AST must name an executable ct-ast (got %s)\n' "${ct:-<empty>}" >&2
    exit 1
fi

work="$(mktemp -d "${CT_SHORT_TMP:-${TMPDIR:-/tmp}}/ct-pkg29.XXXXXX")" || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf '  ok    %s\n' "$*"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s\n' "$*"; }

printf 'ct: %s\n' "$ct"

gitc() {
    GIT_CONFIG_NOSYSTEM=1 GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t \
        GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t git "$@"
}

# --- fixture: a local git package ----------------------------------------
repo="$work/probe-repo"
mkdir -p "$repo" || exit 1
printf 'name = probe\npublisher = ct\nversion = 0.1.0\nns-root = .\n' >"$repo/ct.pkg"
printf 'pub int probe_value(void);\nint probe_value(void) { return 0; }\n' \
    >"$repo/probe.h.ct"
(
    cd "$repo" || exit 1
    gitc init -q . || exit 1
    gitc add . || exit 1
    gitc commit -q -m probe || exit 1
    gitc tag v0.1.0 || exit 1
) || { printf 'pkg29: cannot stage the git fixture\n' >&2; exit 1; }

# The index row carries the tree digest the fetch verifies; generate it with
# the same command the package manager ships (`index refresh`).
printf '%s %s v0.1.0\n' "$repo" "$repo" >"$work/packages.list"
if ! "$ct" index refresh --packages "$work/packages.list" \
        --out "$work/probe.index" >"$work/refresh.out" 2>&1; then
    printf 'pkg29: index refresh failed: %s\n' "$(tail -2 "$work/refresh.out" | tr '\n' ' ')" >&2
    exit 1
fi

# --- the long, quote-heavy HOME ------------------------------------------
# 32-quote path components: the raw path stays under MAX_PKG_PATH (512), the
# shell-quoted form of the cache path is over 2048 bytes.
chunk="''''''''''''''''''''''''''''''''"
home="$work/hh"
while [ ${#home} -lt 440 ]; do
    home="$home/$chunk"
done
mkdir -p "$home" || exit 1

nq=$(printf '%s' "$home" | tr -cd "'" | wc -c | tr -d ' ')
printf '  home: %d bytes, %d quote(s)\n' "${#home}" "$nq"
if [ ${#home} -ge 512 ]; then
    bad "home path is ${#home} bytes (want < 512 so the unquoted cache fits MAX_PKG_PATH)"
fi

proj="$work/proj"
cthome="$work/cthome"
mkdir -p "$proj" "$cthome" || exit 1
printf 'name = app\nversion = 0.1.0\n' >"$proj/ct.pkg"
printf 'int main(void) { return 0; }\n' >"$proj/main.ct"

run_ct() {
    ( cd "$proj" || exit 1
      env -u CT_INDEX -u CT_REGISTRY \
          HOME="$home" CT_HOME="$cthome" \
          GIT_TERMINAL_PROMPT=0 GIT_CONFIG_NOSYSTEM=1 GIT_ALLOW_PROTOCOL=file \
          "$ct" "$@" )
}

# --- ct get: every composed command is over the old 2048 buffer -----------
if run_ct get --index "$work/probe.index" ct/probe >"$work/get.out" 2>"$work/get.err"; then
    ok "ct get installs through a >2048-byte quoted command"
else
    bad "ct get failed: $(tail -2 "$work/get.err" | tr '\n' ' ')"
fi

cache="$home/.cache/ct-pkg/ct/probe"
if [ -d "$cache/.git" ]; then
    ok "the git cache was cloned at the long quoted path"
else
    bad "no git cache at the long path"
fi

if [ -f "$proj/ct.lock" ] && grep -Fq "ct/probe 0.1.0 git " "$proj/ct.lock"; then
    ok "ct.lock pins ct/probe 0.1.0"
else
    bad "ct.lock is missing the ct/probe row"
fi

# --- second run: cache hit + JSON carrying the package URL ----------------
if run_ct get --json --index "$work/probe.index" ct/probe \
        >"$work/json.out" 2>"$work/json.err"; then
    if grep -Fq "\"url\":\"$repo\"" "$work/json.out" \
            && grep -Fq '"name":"ct/probe"' "$work/json.out"; then
        ok "ct get --json prints the whole URL and identity"
    else
        bad "the JSON result is missing the URL or identity: $(head -1 "$work/json.out")"
    fi
else
    bad "the second ct get failed: $(tail -2 "$work/json.err" | tr '\n' ' ')"
fi

if [ "$fail" -eq 0 ]; then
    echo "pkg29: OK (long pkg command)"
    exit 0
fi
echo "pkg29: FAIL"
exit 1
