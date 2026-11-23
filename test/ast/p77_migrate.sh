#!/bin/sh
# PH-77-S3: `ct update` migrates a legacy `std/std` lock to the official
# `ct/std` identity at the pinned version, prints the before/after line, keeps
# the old store, and never lets `ct install` / `ct build` rewrite the lock.
# `ct verify` only warns about the legacy publisher. Everything runs offline:
# the new target comes from an explicit index row (which overrides the pin).
#
# Usage: sh test/ast/p77_migrate.sh <ct-ast>
set -u
ctast=${1:?usage: p77_migrate.sh <ct-ast>}
ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast")
work=$(mktemp -d "${TMPDIR:-/tmp}/p77mig.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/migrate: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }

if ! command -v git >/dev/null 2>&1; then
    echo "FAIL p77/migrate: git is required for the fixtures" >&2
    exit 1
fi

digest_of() {
    d="$work/dig.$$.$(basename "$1")"
    mkdir -p "$d/home" "$d/proj"
    printf 'name = demo\nversion = 0.1.0\n' >"$d/proj/ct.pkg"
    ( cd "$d/proj" && HOME="$d/home" CT_HOME="$d/home" "$ctast" get "$1" \
        >/dev/null 2>&1 ) || return 1
    awk 'NR>1 { print $NF }' "$d/proj/ct.lock" | tail -1
}

mkrepo() { # <dir> <publisher> <version> <tag>
    mkdir -p "$1"
    (
        cd "$1" || exit 1
        git init -q
        printf 'name = std\npublisher = %s\nversion = %s\nns-root = .\n' "$2" "$3" >ct.pkg
        mkdir -p std
        printf 'pub int add(int a, int b);\nint add(int a, int b) { return a + b; }\n' >std/math.h.ct
        git add -A
        git -c user.email=p77@test -c user.name=p77 commit -qm one
        git tag "$4"
    )
}

mkrepo "$work/old" std 0.3.2 v0.3.2 || exit 1
mkrepo "$work/new" ct 0.20.0 v0.20.0 || exit 1
d_old=$(digest_of "$work/old") || { echo "FAIL p77/migrate: cannot digest the old fixture" >&2; exit 1; }
d_new=$(digest_of "$work/new") || { echo "FAIL p77/migrate: cannot digest the new fixture" >&2; exit 1; }
printf 'std 0.3.2 std file://%s v0.3.2 %s\n' "$work/old" "$d_old" >"$work/old.index"
printf 'std 0.20.0 ct file://%s v0.20.0 %s\n' "$work/new" "$d_new" >"$work/new.index"

# A project that pinned the old official identity through the old index.
mkdir -p "$work/home" "$work/proj"
printf 'name = demo\nversion = 0.1.0\ndep = std@>=0.3.2\n' >"$work/proj/ct.pkg"
printf 'import std::math;\nint main(void) { return add(1, 2) == 3 ? 0 : 1; }\n' >"$work/proj/main.ct"
( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
    "$ctast" get --index "$work/old.index" std/std >/dev/null 2>"$work/seed.err" ) \
    || { echo "FAIL p77/migrate: cannot seed the legacy lock: $(cat "$work/seed.err")" >&2; exit 1; }

# --- ct verify warns, does not fail ---------------------------------------
( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
    "$ctast" verify >"$work/v1.out" 2>"$work/v1.err" )
if [ $? -eq 0 ] && grep -Fq "legacy publisher 'std'" "$work/v1.err" \
   && grep -Fq "verified 1 package(s)" "$work/v1.out"; then
    ok "ct verify only warns on the legacy publisher"
else
    bad "ct verify legacy" "$(cat "$work/v1.out" "$work/v1.err")"
fi

# --- the old lock still builds offline ------------------------------------
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" build main.ct -o app_old >"$work/b1.out" 2>"$work/b1.err" ) \
   && [ -x "$work/proj/app_old" ]; then
    ok "the legacy lock and store still build offline"
else
    bad "legacy build" "$(cat "$work/b1.err")"
fi
cp "$work/proj/ct.lock" "$work/lock.before"

# --- ct install never rewrites the lock -----------------------------------
( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
    "$ctast" install >"$work/i1.out" 2>"$work/i1.err" )
if cmp -s "$work/lock.before" "$work/proj/ct.lock"; then
    ok "ct install leaves the legacy lock byte-identical"
else
    bad "ct install lock" "$(diff "$work/lock.before" "$work/proj/ct.lock" | head -4)"
fi

# --- ct update migrates ----------------------------------------------------
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        CT_INDEX="$work/new.index" "$ctast" update >"$work/u.out" 2>"$work/u.err" ); then
    :
else
    bad "ct update migration" "$(cat "$work/u.out" "$work/u.err")"
fi
if grep -Fq "migrate std/std 0.3.2 -> ct/std 0.20.0" "$work/u.out"; then
    ok "ct update prints the before/after migration line"
else
    bad "migration line" "$(cat "$work/u.out")"
fi
if grep -q '^ct/std 0\.20\.0 git ' "$work/proj/ct.lock" \
   && ! grep -q '^std/std ' "$work/proj/ct.lock"; then
    ok "the lock writes one ct/std row and no std/std row"
else
    bad "migrated lock" "$(cat "$work/proj/ct.lock")"
fi
if [ -f "$work/home/pkg/std/std/0.3.2/std/math.h.ct" ] \
   && [ -f "$work/home/pkg/ct/std/0.20.0/std/math.h.ct" ]; then
    ok "the old store stays and the new one is added"
else
    bad "stores after migration" "$(find "$work/home/pkg" -maxdepth 4 -type d | sort)"
fi

# --- the migrated project verifies and builds -----------------------------
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" verify >"$work/v2.out" 2>"$work/v2.err" ) \
   && ! grep -Fq "legacy" "$work/v2.err" \
   && ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" build main.ct -o app_new >"$work/b2.out" 2>"$work/b2.err" ) \
   && [ -x "$work/proj/app_new" ]; then
    ok "the migrated lock verifies without a warning and builds"
else
    bad "migrated verify/build" "$(cat "$work/v2.out" "$work/v2.err" "$work/b2.err")"
fi
cp "$work/proj/ct.lock" "$work/lock.after"
if ( cd "$work/proj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" build main.ct -o app_new2 >/dev/null 2>&1 ) \
   && cmp -s "$work/lock.after" "$work/proj/ct.lock"; then
    ok "ct build never rewrites the migrated lock"
else
    bad "ct build lock" "the lock changed after a build"
fi

# --- a lock carrying both identities is refused, not silently doubled -----
mkdir -p "$work/dual"
printf 'name = demo\nversion = 0.1.0\n' >"$work/dual/ct.pkg"
{
    printf '# ct-lock 2\n'
    grep '^std/std ' "$work/lock.before"
    grep '^ct/std ' "$work/lock.after"
} >"$work/dual/ct.lock"
if ( cd "$work/dual" && HOME="$work/home" CT_HOME="$work/home" \
        CT_INDEX="$work/new.index" "$ctast" update >"$work/d.out" 2>"$work/d.err" ); then
    bad "dual identity" "a lock with both identities was migrated"
elif grep -Fq "pins both 'std/std' and 'ct/std'" "$work/d.err" \
     || grep -Fq "package 'std' is required twice" "$work/d.err"; then
    ok "a lock with both identities is refused"
else
    bad "dual identity" "$(cat "$work/d.err")"
fi

# --- ct get refuses to merge a second identity beside the legacy row ------
mkdir -p "$work/getproj"
printf 'name = demo\nversion = 0.1.0\n' >"$work/getproj/ct.pkg"
cp "$work/lock.before" "$work/getproj/ct.lock"
if ( cd "$work/getproj" && HOME="$work/home" CT_HOME="$work/home" \
        "$ctast" get --index "$work/new.index" ct/std >"$work/g.out" 2>"$work/g.err" ); then
    bad "ct get on a legacy lock" "a second official identity was merged in"
elif grep -Fq "run 'ct update'" "$work/g.err"; then
    ok "ct get refuses to double-write and points at ct update"
else
    bad "ct get on a legacy lock" "$(cat "$work/g.err")"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/migrate (std/std -> ct/std, old store kept, lock never rewritten by install/build)"
