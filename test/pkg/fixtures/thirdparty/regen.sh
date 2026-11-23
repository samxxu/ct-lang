#!/bin/sh
# PKG-17 fixture regeneration.
#
# `pkg/**` is the only source of truth. This script rebuilds the vendored bare
# git snapshots under `git/**` and the plain-text index rows under `index/**`
# from those sources, using the same tree-digest algorithm as the package
# contract (docs/planning/ct-pkg-get-contract.md section 3.3).
#
# Usage:
#   bash test/pkg/fixtures/thirdparty/regen.sh          # rewrite git/** + index/**
#   bash test/pkg/fixtures/thirdparty/regen.sh --check  # verify, write nothing
#
# The commit metadata is pinned so a regeneration produces the same commit id:
# fixed author/committer, fixed date, fixed branch and SHA-1 object format.
# README.md is deliberately not rewritten: update its table from the values
# printed here, then run --check.

set -eu

here=$(cd "$(dirname "$0")" && pwd)
cd "$here" || exit 1

if command -v shasum >/dev/null 2>&1; then
    hash_stdin() { shasum -a 256 | awk '{print "sha256:" $1}'; }
elif command -v sha256sum >/dev/null 2>&1; then
    hash_stdin() { sha256sum | awk '{print "sha256:" $1}'; }
else
    echo "regen.sh: need shasum or sha256sum" >&2
    exit 1
fi

# Contract section 3.3: paths sorted byte-wise, each file contributes
# "<relative path>\n" followed by its bytes, one SHA-256 over the stream.
digest_dir() {
    (
        cd "$1" || exit 1
        find . -type d \( -name .git -o -name vendor -o -name .ctcache \) -prune \
            -o -type f -print |
            sed 's#^\./##' |
            LC_ALL=C sort |
            while IFS= read -r f; do
                printf '%s\n' "$f"
                cat "$f"
            done
    ) | hash_stdin
}

version_of() {
    sed -n 's/^version *= *//p' "$1/ct.pkg" | head -1
}

# Rebuild one bare snapshot from a package directory. The temporary work tree
# contains exactly the files of the package (no .git), so the tagged tree and
# the digest of `pkg/<...>` are the same input.
make_repo() {
    pkgdir=$1
    repo=$2
    ver=$(version_of "$pkgdir")
    pub=$(sed -n 's/^publisher *= *//p' "$pkgdir/ct.pkg" | head -1)
    name=$(sed -n 's/^name *= *//p' "$pkgdir/ct.pkg" | head -1)
    tmp="$work/mk"
    rm -rf "$tmp" "$repo"
    mkdir -p "$tmp"
    cp -R "$pkgdir/." "$tmp/"
    (
        cd "$tmp" || exit 1
        git init -q --object-format=sha1 -b main
        git add -A
        env \
            GIT_AUTHOR_NAME="PKG-17 fixture" \
            GIT_AUTHOR_EMAIL="fixture@example.invalid" \
            GIT_AUTHOR_DATE="2026-11-23T00:00:00 +0000" \
            GIT_COMMITTER_NAME="PKG-17 fixture" \
            GIT_COMMITTER_EMAIL="fixture@example.invalid" \
            GIT_COMMITTER_DATE="2026-11-23T00:00:00 +0000" \
            git commit -q -m "PKG-17 fixture: $pub/$name $ver"
        git tag "v$ver"
    )
    git clone -q --bare --template= "$tmp" "$repo"
    # A vendored snapshot must not record the machine-local path it was built
    # from (and the macOS-only core.* hints would make the config drift).
    git --git-dir="$repo" remote remove origin 2>/dev/null || true
    git --git-dir="$repo" config --unset core.ignorecase 2>/dev/null || true
    git --git-dir="$repo" config --unset core.precomposeunicode 2>/dev/null || true
    rm -rf "$tmp"
}

repo_commit() {
    git --git-dir="$1" rev-parse "refs/tags/v$2^{commit}"
}

# The tagged tree must produce the same digest as the source directory: the
# index vouches for what `ct get` will check out.
repo_digest() {
    repo=$1
    ver=$2
    d="$work/checkout"
    rm -rf "$d"
    mkdir -p "$d"
    git --git-dir="$repo" archive --format=tar "refs/tags/v$ver" | tar -x -C "$d"
    digest_dir "$d"
}

check_row() {
    file=$1
    expected=$2
    actual=$(cat "$file")
    if [ "$actual" != "$expected" ]; then
        echo "regen.sh: $file is stale" >&2
        printf '  expected: %s\n' "$expected" >&2
        printf '  actual:   %s\n' "$actual" >&2
        return 1
    fi
}

check_readme() {
    needle=$1
    label=$2
    if ! grep -Fq -- "$needle" README.md; then
        echo "regen.sh: README.md does not record $label ($needle)" >&2
        return 1
    fi
}

work=$(mktemp -d "${TMPDIR:-/tmp}/ct-pkg17-regen.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

mode=regen
if [ "${1:-}" = "--check" ]; then
    mode=check
elif [ "$#" -ne 0 ]; then
    echo "usage: regen.sh [--check]" >&2
    exit 2
fi

if [ "$mode" = regen ]; then
    mkdir -p git
    make_repo pkg/hello git/hello.git
    make_repo pkg/acme/hello git/acme-hello.git
    make_repo pkg/ct/hello git/ct-hello.git
fi

dig_hello=$(digest_dir pkg/hello)
dig_acme=$(digest_dir pkg/acme/hello)
dig_ct=$(digest_dir pkg/ct/hello)
commit_hello=$(repo_commit git/hello.git 0.1.0)
commit_acme=$(repo_commit git/acme-hello.git 0.1.0)
commit_ct=$(repo_commit git/ct-hello.git 0.1.0)

row_six="hello 0.1.0 demo ../git/hello.git v0.1.0 $dig_hello"
row_five="hello 0.1.0 ../git/hello.git v0.1.0 $dig_hello"
row_bad="hello 0.1.0 demo ../git/hello.git v0.1.0 sha256:0000000000000000000000000000000000000000000000000000000000000000"
row_ct="hello 0.1.0 ct ../git/ct-hello.git v0.1.0 $dig_ct"
row_acme="hello 0.1.0 acme ../git/acme-hello.git v0.1.0 $dig_acme"
row_two="$row_six
$row_acme"

if [ "$mode" = regen ]; then
    printf '%s\n' "$row_six" > index/six
    printf '%s\n' "$row_five" > index/five
    printf '%s\n' "$row_bad" > index/bad-digest
    printf '%s\n' "$row_two" > index/two-publishers
    printf '%s\n' "$row_ct" > index/ct-row

    cat <<EOF
regenerated:
  pkg/hello         -> git/hello.git         $commit_hello  $dig_hello
  pkg/acme/hello    -> git/acme-hello.git    $commit_acme  $dig_acme
  pkg/ct/hello      -> git/ct-hello.git      $commit_ct  $dig_ct
  index/six, index/five, index/bad-digest, index/two-publishers, index/ct-row

Update README.md's table with these values, then run:
  bash test/pkg/fixtures/thirdparty/regen.sh --check
EOF
    exit 0
fi

fail=0
check_row index/six "$row_six" || fail=1
check_row index/five "$row_five" || fail=1
check_row index/bad-digest "$row_bad" || fail=1
check_row index/two-publishers "$row_two" || fail=1
check_row index/ct-row "$row_ct" || fail=1

for pair in \
    "git/hello.git 0.1.0 $dig_hello" \
    "git/acme-hello.git 0.1.0 $dig_acme" \
    "git/ct-hello.git 0.1.0 $dig_ct"
do
    set -- $pair
    got=$(repo_digest "$1" "$2")
    if [ "$got" != "$3" ]; then
        echo "regen.sh: $1 tag v$2 has digest $got, expected $3" >&2
        fail=1
    fi
done

check_readme "$dig_hello" "demo/hello digest" || fail=1
check_readme "$dig_acme" "acme/hello digest" || fail=1
check_readme "$dig_ct" "ct/hello digest" || fail=1
check_readme "$commit_hello" "demo/hello commit" || fail=1
check_readme "$commit_acme" "acme/hello commit" || fail=1
check_readme "$commit_ct" "ct/hello commit" || fail=1

if [ "$fail" -ne 0 ]; then
    echo "regen.sh --check: FAIL" >&2
    exit 1
fi
echo "regen.sh --check: OK (3 packages, 5 index files)"
