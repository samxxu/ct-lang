#!/bin/sh
# PH-83 / S83c: run the versioned package conformance data against both the CT
# binary and the independent shell reference, then against the expected rows.
#
#   bash test/conformance/pkg/run.sh [--ct <binary>] [--data <dir>]
#
# The same data (test/conformance/pkg/v1/) feeds both implementations:
#   manifests/cases.tsv        legal/illegal ct.pkg (PK-1/2/5/8 categories)
#   index/{legal,illegal}.index index rows + cases.tsv (IV-1..IV-6)
#   digest/vector{1,2,3}/      the three contract §3.3 trees
#   digest/expect.tsv          the published digests
#
# A difference between CT and the reference is a failure unless it is listed in
# differences.md (wording only is already normalised away: the runner compares
# exit codes and categories, not diagnostic sentences). The data is versioned;
# a new format lands as v2 beside this one.
#
# Exit: 0 every case agrees, 1 at least one mismatch, 2 usage/prerequisite.
set -u
LC_ALL=C
export LC_ALL

here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../../.." && pwd)
data="$here/v1"
ct=${CT_BIN:-}

while [ $# -gt 0 ]; do
    case "$1" in
        --ct) [ $# -ge 2 ] || { echo "run.sh: --ct needs a path" >&2; exit 2; }
              ct=$2; shift 2 ;;
        --data) [ $# -ge 2 ] || { echo "run.sh: --data needs a path" >&2; exit 2; }
                data=$2; shift 2 ;;
        -h | --help) sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "run.sh: unknown argument '$1'" >&2; exit 2 ;;
    esac
done

if [ -z "$ct" ]; then
    if command -v ct >/dev/null 2>&1; then ct=ct
    elif command -v ct-ast >/dev/null 2>&1; then ct=ct-ast
    else echo "run.sh: no ct/ct-ast on PATH (use --ct)" >&2; exit 2
    fi
fi
case "$ct" in
    /*) ;;
    *)
        if [ -f "$ct" ]; then
            ct=$(cd -- "$(dirname -- "$ct")" && pwd)/$(basename -- "$ct")
        else
            ct=$(command -v "$ct" 2>/dev/null || printf '%s' "$ct")
        fi
        ;;
esac
[ -x "$ct" ] || { echo "run.sh: not executable: $ct" >&2; exit 2; }
[ -d "$data" ] || { echo "run.sh: no data directory: $data" >&2; exit 2; }

tmp=$(mktemp -d "${TMPDIR:-/tmp}/pkgconf.XXXXXX") || exit 1
trap 'rm -rf "$tmp"' EXIT HUP INT TERM
tab=$(printf '\t')
pass=0
fail=0
ok()  { pass=$((pass + 1)); printf 'ok   %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf 'FAIL %s: %s\n' "$1" "$2"; }

# --- CT side: map diagnostics to the shared categories --------------------
ct_manifest() {
    dir=$1
    out=$("$ct" pkg check "$dir" 2>&1)
    rc=$?
    case "$out" in
        *"ok: 4 criteria"*) printf 'ok\n'; return 0 ;;
        *"cannot read"*"ct.pkg"*) printf 'missing-manifest\n'; return 0 ;;
        *"missing 'name'"*) printf 'missing-name\n'; return 0 ;;
        *placeholder*) printf 'local-publisher\n'; return 0 ;;
        *"missing 'publisher'"*) printf 'missing-publisher\n'; return 0 ;;
        *"missing 'version'"*) printf 'missing-version\n'; return 0 ;;
        *"missing 'ns-root'"*) printf 'missing-nsroot\n'; return 0 ;;
        *"must be a relative path without '..'"*)
            v=$(printf '%s\n' "$out" | sed -n "s/.*ns-root '\\([^']*\\)'.*/\\1/p" | head -1)
            case "$v" in
                /*) printf 'nsroot-absolute\n' ;;
                *..*) printf 'nsroot-dotdot\n' ;;
                *) printf 'nsroot-shape\n' ;;
            esac
            return 0 ;;
        *"is not a directory"*) printf 'nsroot-not-dir\n'; return 0 ;;
        *"contains an absolute -I"*) printf 'absolute-I\n'; return 0 ;;
    esac
    printf 'other(rc=%s): %s\n' "$rc" "$out"
    return 1
}

ct_index() {
    "$ct" index verify "$1" 2>/dev/null |
        sed -n 's/^line \([0-9][0-9]*\): \([a-z][a-z-]*\):.*/\1'"$tab"'\2/p'
}

ct_digest() {
    dir=$1
    rm -rf "$tmp/proj" "$tmp/home"
    mkdir -p "$tmp/proj" "$tmp/home"
    if ! ( cd "$tmp/proj" && HOME="$tmp/home" CT_HOME="$tmp/home/.ct" \
            "$ct" get "$dir" ) >"$tmp/get.out" 2>"$tmp/get.err"; then
        printf 'ct get failed: %s\n' "$(tr '\n' ' ' <"$tmp/get.err")" >&2
        return 1
    fi
    awk '!/^#/ { print $NF; exit }' "$tmp/proj/ct.lock"
}

# --- 1. manifests --------------------------------------------------------
echo "== manifests ($data/manifests) =="
man_cases="$data/manifests/cases.tsv"
[ -f "$man_cases" ] || { echo "run.sh: missing $man_cases" >&2; exit 2; }
while IFS="$tab" read -r id expect category; do
    case "$id" in '' | '#'*) continue ;; esac
    dir="$data/manifests/$id"
    got_ct=$(ct_manifest "$dir") || got_ct="classifier-error"
    got_ref=$(sh "$here/reference.sh" manifest "$dir")
    if [ "$got_ct" = "$category" ] && [ "$got_ref" = "$category" ]; then
        ok "manifest $id ($category)"
    else
        bad "manifest $id" "expected '$category'; ct='$got_ct'; reference='$got_ref'"
    fi
done <"$man_cases"

# --- 2. index rows -------------------------------------------------------
echo "== index ($data/index) =="
"$ct" index verify "$data/index/legal.index" >"$tmp/legal.out" 2>&1
if [ "$?" -eq 0 ] && sh "$here/reference.sh" index "$data/index/legal.index" >"$tmp/legal.ref"; then
    if [ -s "$tmp/legal.ref" ]; then
        bad "legal index" "reference reported rows: $(cat "$tmp/legal.ref")"
    else
        ok "legal index (3 rows, both sides clean)"
    fi
else
    bad "legal index" "ct=$(cat "$tmp/legal.out")"
fi
: >"$tmp/expected"
while IFS="$tab" read -r line expect kind note; do
    case "$line" in '' | '#'*) continue ;; esac
    [ "$expect" = err ] && printf '%s\t%s\n' "$line" "$kind" >>"$tmp/expected"
done <"$data/index/cases.tsv"
ct_index "$data/index/illegal.index" >"$tmp/illegal.ct"
sh "$here/reference.sh" index "$data/index/illegal.index" >"$tmp/illegal.ref"
if diff -u "$tmp/expected" "$tmp/illegal.ct" >"$tmp/d1"; then
    ok "index illegal rows: CT matches the expected line/kind map"
else
    bad "index CT" "$(sed -n '1,12p' "$tmp/d1" | tr '\n' '|')"
fi
if diff -u "$tmp/expected" "$tmp/illegal.ref" >"$tmp/d2"; then
    ok "index illegal rows: shell reference matches the expected map"
else
    bad "index reference" "$(sed -n '1,12p' "$tmp/d2" | tr '\n' '|')"
fi
if diff -u "$tmp/illegal.ref" "$tmp/illegal.ct" >"$tmp/d3"; then
    ok "index: CT and shell reference agree row by row"
else
    bad "index drift" "$(sed -n '1,12p' "$tmp/d3" | tr '\n' '|')"
fi

# --- 3. digest vectors ---------------------------------------------------
echo "== digest ($data/digest) =="
expect_file="$data/digest/expect.tsv"
[ -f "$expect_file" ] || { echo "run.sh: missing $expect_file" >&2; exit 2; }
while IFS="$tab" read -r vector expected; do
    case "$vector" in '' | '#'*) continue ;; esac
    src="$data/digest/$vector"
    [ -d "$src" ] || { bad "digest $vector" "no tree"; continue; }
    work="$tmp/digest-$vector"
    rm -rf "$work"
    mkdir -p "$work"
    cp -R "$src/." "$work/"
    # Only vector2 has excluded paths: git cannot track a nested .git/, so the
    # data lists them and the runner materializes them here.
    ex="$data/digest/$vector.excluded.tsv"
    if [ -f "$ex" ]; then
        while IFS="$tab" read -r p content; do
            case "$p" in '' | '#'*) continue ;; esac
            mkdir -p "$work/$(dirname "$p")"
            printf '%b' "$content" >"$work/$p"
        done <"$ex"
    fi
    got_ref=$(sh "$here/reference.sh" digest "$work")
    if got_ct=$(ct_digest "$work"); then :; else got_ct="<ct get failed>"; fi
    if [ "$got_ct" = "$expected" ] && [ "$got_ref" = "$expected" ]; then
        ok "digest $vector ($expected)"
    else
        bad "digest $vector" "expected $expected; ct=$got_ct; reference=$got_ref"
    fi
done <"$expect_file"

echo
echo "conformance: $pass passed, $fail failed (data: $(basename "$data"))"
[ "$fail" -eq 0 ] || exit 1
exit 0
