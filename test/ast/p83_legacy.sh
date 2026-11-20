#!/bin/sh
# PH-83 / S83b: the five-field (legacy) index row is a per-row hard error
# (D-014 #5, E83-2).
#
#   - a request that resolves to a legacy row exits 1 with the contract
#     message, and writes neither store nor ct.lock;
#   - a six-field row in the same file still installs (the legacy row is not
#     a file-wide failure);
#   - the decision is per requested row: the same package can resolve to a
#     six-field row for one range and a legacy row for another; MVS can pick a
#     legacy row even when a newer six-field row exists;
#   - `ct index verify` reports every legacy row in the file by line number
#     and leaves the six-field rows alone;
#   - a failed request leaves an existing ct.lock byte-identical.
#
# Usage: sh test/ast/p83_legacy.sh <ct-ast>
set -u
ctast=${1:?usage: p83_legacy.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p83legacy.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p83/legacy: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

if ! command -v git >/dev/null 2>&1; then
    echo "skip p83/legacy: git is not installed" >&2
    exit 77
fi

export GIT_AUTHOR_EMAIL=pkg@test GIT_AUTHOR_NAME=pkg
export GIT_COMMITTER_EMAIL=pkg@test GIT_COMMITTER_NAME=pkg
D=0000000000000000000000000000000000000000000000000000000000000000
mkdir -p "$work/home" "$work/bin"

# A real local repository stands in for the registry (file:// is offline).
mkdir -p "$work/repo/src"
printf 'name = util\npublisher = acme\nversion = 1.1.0\nns-root = src\n' >"$work/repo/ct.pkg"
printf 'pub int u(void) { return 1; }\n' >"$work/repo/src/util.h.ct"
( cd "$work/repo" && git init -q && git add -A && git commit -qm one && git tag v1.1.0 ) || {
    echo "skip p83/legacy: cannot create the local git fixture" >&2
    exit 77
}
mkdir -p "$work/seed"
( cd "$work/seed" && HOME="$work/home" CT_HOME="$work/home/.ct" \
    "$ctast" get "$work/repo" ) >"$work/seed.out" 2>"$work/seed.err" || {
    echo "skip p83/legacy: the compiler cannot read the local fixture: $(cat "$work/seed.err")" >&2
    exit 77
}
RD=$(tail -1 "$work/seed/ct.lock" | awk '{ print $NF }')
rm -rf "$work/home/.ct" "$work/seed/ct.lock" "$work/seed"

cat >"$work/legacy.index" <<EOF
old 1.0.0 https://example.invalid/acme/old v1.0.0 sha256:$D
EOF
cat >"$work/mixed.index" <<EOF
util 1.0.0 https://example.invalid/acme/util v1.0.0 sha256:$D
util 1.1.0 acme file://$work/repo v1.1.0 $RD
other 1.0.0 https://example.invalid/acme/other v1.0.0 sha256:$D
EOF
cat >"$work/latest.index" <<EOF
util 1.1.0 acme file://$work/repo v1.1.0 $RD
util 1.2.0 https://example.invalid/acme/util v1.2.0 sha256:$D
EOF
LEGACY_MSG="index row for 'acme/old 1.0.0' is legacy (five fields); a six-field row is required"

get() {   # get <proj> <index> <spec>
    ( cd "$work/$1" && HOME="$work/home" CT_HOME="$work/home/.ct" \
        env -u CT_INDEX "$ctast" get --index "$2" "$3" ) >"$work/g.out" 2>"$work/g.err"
}

# --- a legacy row is a hard error ----------------------------------------
mkdir -p "$work/p1"
if get p1 "$work/legacy.index" 'acme/old@1.0.0'; then
    bad "legacy hit" "expected a non-zero exit"
elif grep -Fq "$LEGACY_MSG" "$work/g.err"; then
    ok "a requested legacy row exits 1 with the contract message"
else
    bad "legacy hit" "wrong diagnostic: $(cat "$work/g.err")"
fi
if [ ! -f "$work/p1/ct.lock" ] && [ ! -d "$work/home/.ct/pkg/acme/old" ]; then
    ok "the legacy failure writes neither ct.lock nor store"
else
    bad "legacy side effects" "ct.lock or store appeared"
fi

# --- six-field rows in the same file are unaffected ----------------------
mkdir -p "$work/p2"
if get p2 "$work/mixed.index" 'acme/util@1.1.0'; then
    if grep -Eq "^acme/util 1\.1\.0 git .* $RD$" "$work/p2/ct.lock"; then
        ok "a six-field row installs even when the file has legacy rows"
    else
        bad "mixed lock" "unexpected row: $(cat "$work/p2/ct.lock")"
    fi
else
    bad "mixed six-field" "non-zero exit: $(cat "$work/g.err")"
fi

# --- the decision is per requested row -----------------------------------
mkdir -p "$work/p3"
if get p3 "$work/mixed.index" 'acme/util@1.0.0'; then
    bad "per-row legacy" "the requested 1.0.0 legacy row was accepted"
elif grep -Fq "index row for 'acme/util 1.0.0' is legacy" "$work/g.err"; then
    ok "the same package rejects @1.0.0 (legacy) while accepting @1.1.0"
else
    bad "per-row legacy" "wrong diagnostic: $(cat "$work/g.err")"
fi

# --- MVS picks the lowest satisfying row, legacy or not ------------------
mkdir -p "$work/p4"
if get p4 "$work/mixed.index" 'acme/util@>=1.1.0'; then
    ok "MVS skips the lower legacy row for a range that excludes it"
else
    bad "MVS six" "expected success: $(cat "$work/g.err")"
fi
mkdir -p "$work/p5"
if get p5 "$work/mixed.index" 'acme/util@>=1.0.0'; then
    bad "MVS legacy" "expected the lowest (legacy) row to fail"
elif grep -Fq "index row for 'acme/util 1.0.0' is legacy" "$work/g.err"; then
    ok "MVS selects the lowest satisfying row and rejects it when legacy"
else
    bad "MVS legacy" "wrong diagnostic: $(cat "$work/g.err")"
fi

# --- latest selects a legacy row when it is the highest ------------------
mkdir -p "$work/p6"
if get p6 "$work/latest.index" 'acme/util'; then
    bad "latest legacy" "expected the highest (legacy) row to fail"
elif grep -Fq "index row for 'acme/util 1.2.0' is legacy" "$work/g.err"; then
    ok "no range selects the highest row and rejects it when legacy"
else
    bad "latest legacy" "wrong diagnostic: $(cat "$work/g.err")"
fi

# --- verify sees all legacy rows, and only them --------------------------
if ( cd "$work" && "$ctast" index verify "$work/mixed.index" ) >"$work/v.out" 2>&1; then
    bad "verify mixed" "expected exit 1"
else
    n=$(grep -c 'legacy-five-field' "$work/v.out")
    if [ "$n" = "2" ] && grep -Fq 'line 1: legacy-five-field' "$work/v.out" \
            && grep -Fq 'line 3: legacy-five-field' "$work/v.out"; then
        ok "verify reports every legacy row by line and skips the six-field row"
    else
        bad "verify mixed" "$(cat "$work/v.out")"
    fi
fi

# --- a failed request leaves an existing ct.lock untouched ---------------
mkdir -p "$work/p7"
printf '# ct-lock 2\nacme/util 1.1.0 git file://%s deadbeef src %s\n' "$work/repo" "$RD" >"$work/p7/ct.lock"
before=$(cksum "$work/p7/ct.lock")
get p7 "$work/mixed.index" 'acme/util@1.0.0' || true
after=$(cksum "$work/p7/ct.lock")
[ "$before" = "$after" ] && ok "a failed legacy request leaves ct.lock byte-identical" \
    || bad "lock rewrite" "ct.lock changed"

[ "$fail" -eq 0 ] && echo "p83_legacy: OK"
exit "$fail"
