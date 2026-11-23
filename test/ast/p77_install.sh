#!/bin/sh
# PH-77-S4: install.sh, the tutorial, README and the package guide all recommend
# a command that works -- `ct get ct/std@0.20.0` -- and none of them keeps the
# removed `ct get std` bare form. The command is executed against a local index
# (the same `ct/std` override the pin allows) so the probe needs no network.
#
# Usage: sh test/ast/p77_install.sh <ct-ast>
set -u
ctast=${1:?usage: p77_install.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p77inst.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/install: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

# --- the documented command -------------------------------------------------
if [ "$(grep -c 'ct get ct/std' "$root/install.sh")" -ge 2 ]; then
    ok "install.sh recommends ct get ct/std (both places)"
else
    bad "install.sh" "$(grep -n 'ct get' "$root/install.sh")"
fi
if grep -Fq 'ct get ct/std@0.20.0' "$root/docs/tutorial.md" \
   && grep -Fq '`ct get ct/std`' "$root/README.md" \
   && grep -Fq 'ct get ct/std@0.20.0' "$root/docs/package-guide.md"; then
    ok "tutorial, README and package-guide agree on the official command"
else
    bad "documented command" "$(grep -n 'ct get ct/std' "$root/docs/tutorial.md" "$root/README.md" "$root/docs/package-guide.md")"
fi
if grep -nE 'ct get std([^/]|$)' "$root/install.sh" "$root/README.md" \
        "$root/docs/tutorial.md" "$root/docs/package-guide.md" >/dev/null 2>&1; then
    bad "removed bare form" "$(grep -nE 'ct get std([^/]|$)' "$root/install.sh" "$root/README.md" "$root/docs/tutorial.md" "$root/docs/package-guide.md")"
else
    ok "no document recommends the removed bare std form"
fi

# --- the command really resolves offline -----------------------------------
if ! command -v git >/dev/null 2>&1; then
    echo "FAIL p77/install: git is required for the fixture" >&2
    exit 1
fi
mkdir -p "$work/repo" "$work/proj" "$work/home"
(
    cd "$work/repo" || exit 1
    git init -q
    printf 'name = std\npublisher = ct\nversion = 0.20.0\nns-root = .\n' >ct.pkg
    printf 'pub int twice(int x);\nint twice(int x) { return 2 * x; }\n' >std.h.ct
    git add -A
    git -c user.email=p77@test -c user.name=p77 commit -qm one
    git tag v0.20.0
)
printf 'name = demo\nversion = 0.1.0\n' >"$work/proj/ct.pkg"
printf 'import std;\nint main(void) { return twice(21) == 42 ? 0 : 1; }\n' >"$work/proj/main.ct"
mkdir -p "$work/seed/home" "$work/seed/proj"
printf 'name = demo\nversion = 0.1.0\n' >"$work/seed/proj/ct.pkg"
( cd "$work/seed/proj" && HOME="$work/seed/home" CT_HOME="$work/seed/home" \
    "$ctast" get "$work/repo" >/dev/null 2>&1 ) \
    || { echo "FAIL p77/install: cannot digest the fixture" >&2; exit 1; }
dig=$(awk 'NR>1 { print $NF }' "$work/seed/proj/ct.lock" | tail -1)
printf 'std 0.20.0 ct file://%s v0.20.0 %s\n' "$work/repo" "$dig" >"$work/index"

if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" get --index "$work/index" ct/std@0.20.0 >"$work/g.out" 2>"$work/g.err" ) \
   && grep -q '^ct/std 0\.20\.0 git ' "$work/proj/ct.lock"; then
    ok "the documented ct get ct/std@0.20.0 succeeds"
else
    bad "documented command run" "$(cat "$work/g.err"; cat "$work/proj/ct.lock" 2>/dev/null)"
fi
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" build main.ct -o app >"$work/b.out" 2>"$work/b.err" ) \
   && [ -x "$work/proj/app" ] && "$work/proj/app"; then
    ok "the project builds and runs after the documented command"
else
    bad "documented command build" "$(cat "$work/b.err")"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/install (install.sh / tutorial / README / package-guide agree and run)"
