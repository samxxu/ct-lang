#!/bin/sh
# PH-83 / S83c: the *shell* side of the package conformance pair.
#
# It implements the same read-only rules the CT binary implements, but from
# scratch and over the same versioned data under test/conformance/pkg/v1/:
#
#   reference.sh manifest <package-dir>   PK-1/2/5/8; prints ok|category
#   reference.sh index <index-file>       IV-1..IV-6; prints "<line>\t<kind>"
#   reference.sh digest <package-dir>     the §3.3 tree digest
#
# Exit: manifest/index 0 when valid, 1 when they report a category; digest 0.
# The runner (run.sh) compares this output with the CT binary's and with the
# expected rows in the data. Known, registered wording differences live in
# differences.md; categories are the shared contract.
set -u
LC_ALL=C
export LC_ALL

root=$(cd -- "$(dirname -- "$0")" && pwd)
tmp=$(mktemp -d "${TMPDIR:-/tmp}/pkgconf-ref.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM

ref_manifest() {
    dir=$1
    f="$dir/ct.pkg"
    name=
    publisher=
    version=
    nsroot=
    if [ ! -f "$f" ] || [ ! -r "$f" ]; then
        echo missing-manifest
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        line=${line%%#*}
        case "$line" in
            *=*) ;;
            *) continue ;;
        esac
        key=$(printf '%s' "${line%%=*}" | tr -d ' \t')
        val=$(printf '%s' "${line#*=}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
        case "$key" in
            name) name=$val ;;
            publisher) publisher=$val ;;
            version) version=$val ;;
            ns-root) nsroot=$val ;;
        esac
    done <"$f"
    [ -n "$name" ] || { echo missing-name; return 1; }
    [ -n "$publisher" ] || { echo missing-publisher; return 1; }
    [ "$publisher" = local ] && { echo local-publisher; return 1; }
    [ -n "$version" ] || { echo missing-version; return 1; }
    [ -n "$nsroot" ] || { echo missing-nsroot; return 1; }
    case "$nsroot" in
        /*) echo nsroot-absolute; return 1 ;;
        *..*) echo nsroot-dotdot; return 1 ;;
    esac
    [ -d "$dir/$nsroot" ] || { echo nsroot-not-dir; return 1; }
    # PK-8: no absolute -I in the tree; skip the same directories, *.md and
    # files above 262144 bytes that `ct pkg check` skips.
    re="(^|[[:space:]\"'])-I[[:space:]]*/"
    : >"$tmp/hits"
    find "$dir" \( -type d \( -name .git -o -name docs -o -name issues \
            -o -name battle -o -name test \) -prune \) -o \
        \( -type f -size -262145c -print \) 2>/dev/null |
        while IFS= read -r p; do
            case "$p" in *.md) continue ;; esac
            if grep -qE "$re" "$p" 2>/dev/null; then
                printf '%s\n' "$p" >>"$tmp/hits"
            fi
        done
    if [ -s "$tmp/hits" ]; then
        echo absolute-I
        return 1
    fi
    echo ok
    return 0
}

ref_index() {
    file=$1
    seen="$tmp/seen"
    : >"$seen"
    n=0
    if [ ! -r "$file" ]; then
        return 1
    fi
    while IFS= read -r line || [ -n "$line" ]; do
        n=$((n + 1))
        line=$(printf '%s' "$line" | sed 's/[[:space:]]*$//')
        case "$line" in
            '' | '#'*) continue ;;
        esac
        # shellcheck disable=SC2086
        set -- $line
        if [ $# -eq 5 ]; then
            printf '%s\tlegacy-five-field\n' "$n"
            continue
        fi
        if [ $# -ne 6 ]; then
            printf '%s\tfield-count\n' "$n"
            continue
        fi
        name=$1
        version=$2
        pub=$3
        tag=$5
        sha=$6
        case "$name" in
            [a-z0-9]*) ;;
            *) printf '%s\tidentity\n' "$n"; continue ;;
        esac
        case "$name" in
            *[!a-z0-9-]*) printf '%s\tidentity\n' "$n"; continue ;;
        esac
        if [ -z "$pub" ] || [ "$pub" = local ]; then
            printf '%s\tidentity\n' "$n"
            continue
        fi
        case "$pub" in
            */*) printf '%s\tidentity\n' "$n"; continue ;;
        esac
        if ! printf '%s' "$version" | grep -Eq '^[0-9]{1,9}\.[0-9]{1,9}\.[0-9]{1,9}$'; then
            printf '%s\tidentity\n' "$n"
            continue
        fi
        if [ "$tag" != "v$version" ]; then
            printf '%s\ttag-version\n' "$n"
            continue
        fi
        if ! printf '%s' "$sha" | grep -Eq '^sha256:[0-9a-f]{64}$'; then
            printf '%s\tdigest\n' "$n"
            continue
        fi
        key="$pub/$name $version"
        if grep -Fxq "$key" "$seen"; then
            printf '%s\tduplicate\n' "$n"
            continue
        fi
        printf '%s\n' "$key" >>"$seen"
    done <"$file"
    return 0
}

ref_digest() {
    d=$1
    if command -v sha256sum >/dev/null 2>&1; then
        hasher=sha256sum
    elif command -v shasum >/dev/null 2>&1; then
        hasher="shasum -a 256"
    else
        echo "reference: no sha256sum/shasum" >&2
        return 2
    fi
    (
        cd "$d" || exit 1
        find . -mindepth 1 \
            \( -type d \( -name .git -o -name vendor -o -name .ctcache \) -prune \) -o \
            \( -type f -print \)
    ) | sed 's|^\./||' | LC_ALL=C sort | {
        while IFS= read -r p; do
            printf '%s\n' "$p"
            cat "$d/$p"
        done
    } | {
        # shellcheck disable=SC2086
        $hasher
    } | awk '{ print "sha256:" $1 }'
}

cmd=${1:-}
[ $# -gt 0 ] && shift
case "$cmd" in
    manifest)
        [ $# -eq 1 ] || { echo "usage: reference.sh manifest <dir>" >&2; exit 2; }
        ref_manifest "$1"
        ;;
    index)
        [ $# -eq 1 ] || { echo "usage: reference.sh index <file>" >&2; exit 2; }
        ref_index "$1"
        rc=$?
        exit "$rc"
        ;;
    digest)
        [ $# -eq 1 ] || { echo "usage: reference.sh digest <dir>" >&2; exit 2; }
        ref_digest "$1"
        ;;
    *)
        echo "usage: reference.sh manifest|index|digest <path>" >&2
        exit 2
        ;;
esac
