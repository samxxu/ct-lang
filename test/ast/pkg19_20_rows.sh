#!/bin/sh
# PKG-19 / PKG-20: `ct get` and `ct index verify` must agree on index rows.
#
# Before this fix `pkg_index_lookup` accepted every row with at least five
# fields and only matched on name/publisher, so a seven-field row, a tag that
# is not `v<version>`, or a `local` publisher row all reached `git clone`.
# The probe pins the shared parse/validate contract:
#
#   - a selected row with a field count other than six exits 1 with
#     `line <n>: field-count: ...` (the five-field legacy row keeps its own
#     D-014 error), before any git call;
#   - a selected six-field row whose name / publisher / version / tag breaks
#     the contract exits 1 with the same `identity` / `tag-version` text that
#     `ct index verify` prints;
#   - `ct index verify` keeps reporting the same categories (the oracle);
#   - a failed `ct get` writes neither `ct.lock` nor the shared store;
#   - a legal six-field row still installs, with the same lock row and digest;
#   - an unselected bad row does not block a legal request (per-request scope,
#     unlike verify's file-wide scan).
#
# The bad-row probes put a fake `git` first on PATH. If the resolver reaches
# the fetch step the marker file appears and the probe fails even if the
# diagnostic happened to be right.
#
# Usage: sh test/ast/pkg19_20_rows.sh <ct-ast>
set -u
ctast=${1:?usage: pkg19_20_rows.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/pkg1920.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL pkg19_20: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

if ! command -v git >/dev/null 2>&1; then
    echo "skip pkg19_20: git is not installed" >&2
    exit 77
fi

export GIT_AUTHOR_EMAIL=pkg@test GIT_AUTHOR_NAME=pkg
export GIT_COMMITTER_EMAIL=pkg@test GIT_COMMITTER_NAME=pkg
D=0000000000000000000000000000000000000000000000000000000000000000
mkdir -p "$work/bin"

# A real local repository stands in for the registry; the seed `ct get` gives
# us the digest a legal six-field row must carry.
mkdir -p "$work/repo/src"
printf 'name = util\npublisher = acme\nversion = 1.1.0\nns-root = src\n' >"$work/repo/ct.pkg"
printf 'pub int u(void) { return 1; }\n' >"$work/repo/src/util.h.ct"
( cd "$work/repo" && git init -q && git add -A && git commit -qm one && git tag v1.1.0 ) || {
    echo "skip pkg19_20: cannot create the local git fixture" >&2
    exit 77
}
mkdir -p "$work/seed"
( cd "$work/seed" && HOME="$work/seed/home" CT_HOME="$work/seed/home/.ct" \
    env -u CT_INDEX "$ctast" get "$work/repo" ) >"$work/seed.out" 2>"$work/seed.err" || {
    echo "skip pkg19_20: the compiler cannot read the local fixture: $(cat "$work/seed.err")" >&2
    exit 77
}
RD=$(tail -1 "$work/seed/ct.lock" | awk '{ print $NF }')

# Fixtures. `EXTRA` is the seventh field; the other four break one identity
# rule each while keeping six fields.
cat >"$work/seven.index" <<EOF
foo 0.1.0 pub file://$work/nope v0.1.0 sha256:$D EXTRA
EOF
cat >"$work/badtag.index" <<EOF
foo 0.1.0 pub file://$work/nope v9.9.9 sha256:$D
EOF
cat >"$work/badpub.index" <<EOF
foo 0.1.0 local file://$work/nope v0.1.0 sha256:$D
EOF
cat >"$work/badname.index" <<EOF
Foo 0.1.0 acme file://$work/nope v0.1.0 sha256:$D
EOF
cat >"$work/badver.index" <<EOF
foo 1.0 acme file://$work/nope v1.0 sha256:$D
EOF

git_fake() { # <n>: a `git` that answers --version and records a real call
    {
        printf '#!/bin/sh\n'
        printf 'case "$1" in --version) echo "git version 2.99.0"; exit 0 ;; esac\n'
        printf ': >"%s/git-called%s"\nexit 1\n' "$work" "$1"
    } >"$work/bin/git"
    chmod +x "$work/bin/git"
}

run_verify() { # <n> <index>
    ( cd "$work" && HOME="$work/h$1" CT_HOME="$work/h$1/.ct" \
        env -u CT_INDEX "$ctast" index verify "$2" ) >"$work/v$1.out" 2>"$work/v$1.err"
}

run_get_fake() { # <n> <index> <spec>
    ( cd "$work/p$1" && HOME="$work/h$1" CT_HOME="$work/h$1/.ct" \
        PATH="$work/bin:$PATH" env -u CT_INDEX "$ctast" get --index "$2" "$3" ) \
        >"$work/g$1.out" 2>"$work/g$1.err"
}

run_get_real() { # <n> <index> <spec>
    ( cd "$work/p$1" && HOME="$work/h$1" CT_HOME="$work/h$1/.ct" \
        env -u CT_INDEX "$ctast" get --index "$2" "$3" ) \
        >"$work/g$1.out" 2>"$work/g$1.err"
}

bad_row() { # <n> <label> <index> <spec> <kind> <needle> <store>
    n=$1 label=$2 idx=$3 spec=$4 kind=$5 needle=$6 store=$7
    mkdir -p "$work/p$n" "$work/h$n"
    rm -f "$work/git-called$n"
    git_fake "$n"

    run_verify "$n" "$idx"; rc=$?
    if [ "$rc" -eq 1 ] && grep -Fq "line 1: $kind:" "$work/v$n.out" \
            && grep -Fq "$needle" "$work/v$n.out"; then
        ok "$label: verify reports $kind"
    else
        bad "$label verify" "rc=$rc $(cat "$work/v$n.out")"
    fi

    run_get_fake "$n" "$idx" "$spec"; rc=$?
    if [ "$rc" -ne 0 ] && grep -Fq "line 1: $kind:" "$work/g$n.err" \
            && grep -Fq "$needle" "$work/g$n.err"; then
        ok "$label: get reports $kind before fetch"
    else
        bad "$label get" "rc=$rc $(cat "$work/g$n.err")"
    fi

    if [ -e "$work/git-called$n" ]; then
        bad "$label no git" "the resolver reached git"
    else
        ok "$label: get does not invoke git"
    fi
    if [ -e "$work/p$n/ct.lock" ] || [ -e "$work/h$n/.ct/pkg/$store" ]; then
        bad "$label side effects" "ct.lock or store appeared"
    else
        ok "$label: get leaves ct.lock and store untouched"
    fi
}

bad_row seven "a seven-field row" "$work/seven.index" 'pub/foo@0.1.0' field-count \
    'index row has 7 fields; six are required' 'pub/foo'
bad_row badtag "a tag that is not v<version>" "$work/badtag.index" 'pub/foo@0.1.0' tag-version \
    "index tag 'v9.9.9' must be 'v0.1.0'" 'pub/foo'
bad_row badpub "publisher = local" "$work/badpub.index" 'local/foo@0.1.0' identity \
    "index publisher 'local' must be non-empty, not 'local', without '/'" 'local/foo'
bad_row badname "a name outside [a-z0-9][a-z0-9-]*" "$work/badname.index" 'acme/Foo@0.1.0' identity \
    "index package name 'Foo' must match" 'acme/Foo'
bad_row badver "a version that is not x.y.z" "$work/badver.index" 'acme/foo' identity \
    "index version '1.0' must be x.y.z" 'acme/foo'

# --- a legal six-field row is unchanged ----------------------------------
cat >"$work/good.index" <<EOF
util 1.1.0 acme file://$work/repo v1.1.0 $RD
EOF
mkdir -p "$work/pgood" "$work/hgood"
run_get_real good "$work/good.index" 'acme/util@1.1.0'; rc=$?
if [ "$rc" -eq 0 ] \
        && grep -Eq "^acme/util 1\.1\.0 git .* $RD$" "$work/pgood/ct.lock"; then
    ok "a legal six-field row still installs with the same lock row and digest"
else
    bad "legal six-field row" "rc=$rc lock=$(cat "$work/pgood/ct.lock" 2>/dev/null) $(cat "$work/ggood.err" 2>/dev/null)"
fi
run_verify good "$work/good.index"
if [ "$?" -eq 0 ] && grep -Fq 'index verify: OK (1 rows)' "$work/vgood.out"; then
    ok "verify still accepts the legal six-field row"
else
    bad "verify legal" "$(cat "$work/vgood.out")"
fi

# --- an unselected bad row does not block the request --------------------
cat >"$work/mixed.index" <<EOF
util 1.1.0 acme file://$work/repo v1.1.0 $RD
util 1.2.0 acme https://example.invalid/acme/util v1.2.0 sha256:$D EXTRA
EOF
mkdir -p "$work/pmix" "$work/hmix"
run_get_real mix "$work/mixed.index" 'acme/util@1.1.0'; rc=$?
if [ "$rc" -eq 0 ] \
        && grep -Eq "^acme/util 1\.1\.0 git .* $RD$" "$work/pmix/ct.lock"; then
    ok "an unselected seven-field row does not block a legal request"
else
    bad "mixed get" "rc=$rc $(cat "$work/gmix.err" 2>/dev/null)"
fi
run_verify mix "$work/mixed.index"; rc=$?
if [ "$rc" -eq 1 ] && grep -Fq 'line 2: field-count:' "$work/vmix.out"; then
    ok "verify still scans the whole file and reports the unselected bad row"
else
    bad "mixed verify" "rc=$rc $(cat "$work/vmix.out")"
fi

[ "$fail" -eq 0 ] && echo "pkg19_20: OK"
exit "$fail"
