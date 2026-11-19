#!/bin/sh
# PH-77-S2: `ct get` shows the canonical source as `url@<package version>` in
# all three output shapes, with the tag on its own line (text) and a `spec`
# field (JSON). A local directory source follows the same rule.
#
# Usage: sh test/ast/p77_output.sh <ct-ast>
set -u
ctast=${1:?usage: p77_output.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
work=$(mktemp -d "${TMPDIR:-/tmp}/p77out.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/output: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

if ! command -v git >/dev/null 2>&1; then
    echo "FAIL p77/output: git is required for the git fixture" >&2
    exit 1
fi

digest_of() {
    d="$work/dig.$$"
    mkdir -p "$d/home" "$d/proj"
    printf 'name = demo\nversion = 0.1.0\n' >"$d/proj/ct.pkg"
    ( cd "$d/proj" && HOME="$d/home" CT_HOME="$d/home" "$ctast" get "$1" \
        >/dev/null 2>&1 ) || return 1
    awk 'NR>1 { print $NF }' "$d/proj/ct.lock" | tail -1
}

mkdir -p "$work/repo" "$work/proj" "$work/home" "$work/dirpkg"
(
    cd "$work/repo" || exit 1
    git init -q
    printf 'name = pkg\npublisher = ct\nversion = 1.0.0\nns-root = .\n' >ct.pkg
    printf 'pub int pkg_value(void);\nint pkg_value(void) { return 1; }\n' >pkg.c
    git add -A
    git -c user.email=p77@test -c user.name=p77 commit -qm one
    git tag v1.0.0
)
dig=$(digest_of "$work/repo") || { echo "FAIL p77/output: cannot digest the fixture" >&2; exit 1; }
printf 'pkg 1.0.0 ct file://%s v1.0.0 %s\n' "$work/repo" "$dig" >"$work/index"
printf 'name = demo\nversion = 0.1.0\n' >"$work/proj/ct.pkg"

run() { ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
          "$ctast" get --index "$work/index" "$@" ); }

if ! run ct/pkg >"$work/text.out" 2>"$work/text.err"; then
    bad "ct get ct/pkg" "$(cat "$work/text.err")"
fi
if grep -Fq "resolved   ct/pkg 1.0.0" "$work/text.out" \
   && grep -Fq "  source   file://$work/repo@1.0.0" "$work/text.out" \
   && grep -Fq "  tag      v1.0.0" "$work/text.out" \
   && ! grep -Fq "source   git" "$work/text.out"; then
    ok "text: source is url@version and the tag is on its own line"
else
    bad "text output" "$(cat "$work/text.out")"
fi

if run -q ct/pkg >"$work/quiet.out" 2>"$work/quiet.err" \
   && grep -Eq "^ct/pkg 1\.0\.0 file://$work/repo@1\.0\.0$" "$work/quiet.out"; then
    ok "quiet: name version url@version"
else
    bad "quiet output" "$(cat "$work/quiet.out" "$work/quiet.err")"
fi

if run --json ct/pkg >"$work/json.out" 2>"$work/json.err" \
   && grep -Fq "\"spec\":\"file://$work/repo@1.0.0\"" "$work/json.out" \
   && grep -Fq "\"tag\":\"v1.0.0\"" "$work/json.out" \
   && grep -Fq "\"version\":\"1.0.0\"" "$work/json.out"; then
    ok "json: a spec field carries url@version"
else
    bad "json output" "$(cat "$work/json.out" "$work/json.err")"
fi

# A local directory source: same url@version shape, no tag line.
printf 'name = dpkg\npublisher = ct\nversion = 2.0.0\nns-root = .\n' >"$work/dirpkg/ct.pkg"
printf 'pub int dpkg_value(void);\nint dpkg_value(void) { return 2; }\n' >"$work/dirpkg/dpkg.c"
printf 'name = demo2\nversion = 0.1.0\n' >"$work/proj2.ct.pkg"
mkdir -p "$work/proj2"
printf 'name = demo\nversion = 0.1.0\n' >"$work/proj2/ct.pkg"
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" get "$work/dirpkg" >"$work/dir.out" 2>"$work/dir.err" ) \
   && grep -Fq "  source   $work/dirpkg@2.0.0" "$work/dir.out"; then
    ok "text: a directory source is path@version"
else
    bad "directory source" "$(cat "$work/dir.out" "$work/dir.err")"
fi
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" get -q "$work/dirpkg" >"$work/dirq.out" 2>"$work/dirq.err" ) \
   && grep -Eq "^ct/dpkg 2\.0\.0 $work/dirpkg@2\.0\.0$" "$work/dirq.out"; then
    ok "quiet: a directory source is path@version"
else
    bad "directory quiet" "$(cat "$work/dirq.out" "$work/dirq.err")"
fi
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" get --json "$work/dirpkg" >"$work/dirj.out" 2>"$work/dirj.err" ) \
   && grep -Fq "\"spec\":\"$work/dirpkg@2.0.0\"" "$work/dirj.out"; then
    ok "json: a directory source has a spec field"
else
    bad "directory json" "$(cat "$work/dirj.out" "$work/dirj.err")"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/output (url@version in text, quiet and json)"
