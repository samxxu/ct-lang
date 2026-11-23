#!/bin/sh
# SH-118 / E-V1-5: full-corpus B false-positive gate.
#
# Corpus (P-1.1): every `.ct` under `examples/`, `test/` and `lib/`.
# Judged: `ct check --types` must report no B diagnostic -- the five words the
# B kernel emits for an initializer / assignment / return / argument / general
# type mismatch. A legal fixture that draws one is a false positive and fails
# this gate; it is never "fixed" by adding a skip.
#
# Skip table: test/ast/p118_skip.tsv, one `<path><TAB><reason>` row per file.
# Rows are only for files that are not part of the legal corpus (negative
# fixtures, diagnostic demos and the pre-B p32 baseline probes). The gate
# rejects a stale row, so the table can only shrink. A legal fixture must not
# appear in it.
#
# Usage: sh test/ast/p118_fp_all.sh <ct-ast> [--selftest]
#
# --selftest plants a known B diagnostic in a temporary corpus and requires
# the gate to turn red, so the judgement itself cannot silently rot.
set -u
ctast=${1:?usage: p118_fp_all.sh <ct-ast> [--selftest]}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd "$(dirname "$ctast")" && pwd)/$(basename "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p118fp.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
cd "$root" || exit 1
export CT_C_BOUNDARY=allow

# The five words B uses; a hit is a false positive on a legal fixture.
B_RE='initializer:|assignment:|return:|argument [0-9]+:|type mismatch'
skip_file=${P118_SKIP_FILE:-test/ast/p118_skip.tsv}
corpus=${P118_CORPUS:-"examples test lib"}

# A skip row's reason is mandatory; this is the "each row has a basis" check.
read_skips() {
    : > "$work/skip_paths"
    [ -f "$skip_file" ] || { echo "FAIL p118/skip: $skip_file missing" >&2; exit 1; }
    while IFS= read -r line; do
        case "$line" in
            ''|'#'*) continue ;;
        esac
        path=$(printf '%s\n' "$line" | cut -f1)
        reason=$(printf '%s\n' "$line" | cut -f2-)
        if [ -z "$path" ] || [ -z "$reason" ]; then
            echo "FAIL p118/skip: row without path/reason: $line" >&2
            exit 1
        fi
        printf '%s\n' "$path" >> "$work/skip_paths"
    done < "$skip_file"
}

# --selftest: one clean corpus row passes, one known B diagnostic turns red.
if [ "${2:-}" = "--selftest" ]; then
    : > "$work/empty.skip"
    mkdir -p "$work/corpus"
    cat > "$work/corpus/legal.ct" <<'CT'
int main(void)
{
    int x = 1;
    return x;
}
CT
    if ! P118_CORPUS="$work/corpus" P118_SKIP_FILE="$work/empty.skip" \
            sh "$0" "$ctast" >"$work/clean.out" 2>&1; then
        echo "FAIL p118/selftest: a clean legal file did not pass" >&2
        sed 's/^/  /' "$work/clean.out" >&2
        exit 1
    fi
    cat > "$work/corpus/legal.ct" <<'CT'
int main(void)
{
    int x = "s";
    return x;
}
CT
    if P118_CORPUS="$work/corpus" P118_SKIP_FILE="$work/empty.skip" \
            sh "$0" "$ctast" >"$work/bad.out" 2>&1; then
        echo "FAIL p118/selftest: a known B diagnostic was not detected" >&2
        exit 1
    fi
    if ! grep -q '^FAIL p118/fp:' "$work/bad.out"; then
        echo "FAIL p118/selftest: the red run did not name an FP" >&2
        sed 's/^/  /' "$work/bad.out" >&2
        exit 1
    fi
    echo "OK p118/selftest (clean corpus passes; injected B diagnostic turns red)"
    exit 0
fi

read_skips

# The corpus is fixed by P-1.1; an empty list is a broken scan, not a pass.
# shellcheck disable=SC2086
find $corpus -name '*.ct' | sort > "$work/corpus"
total=$(wc -l < "$work/corpus" | tr -d ' ')
[ "$total" -gt 0 ] || { echo "FAIL p118/fp: empty corpus ($corpus)" >&2; exit 1; }

checked=0
skipped=0
fp=0

while IFS= read -r f; do
    if grep -Fxq "$f" "$work/skip_paths"; then
        skipped=$((skipped + 1))
        # A row that no longer draws a B diagnostic is stale: legal fixtures
        # may not be parked here, and negatives must stay negatives.
        hits=$("$ctast" check --types "$f" 2>&1 | grep -E "$B_RE")
        if [ -z "$hits" ]; then
            echo "FAIL p118/skip: stale row (no B diagnostic): $f" >&2
            fp=$((fp + 1))
        fi
        continue
    fi
    checked=$((checked + 1))
    out=$("$ctast" check --types "$f" 2>&1)
    hits=$(printf '%s\n' "$out" | grep -E "$B_RE")
    if [ -n "$hits" ]; then
        fp=$((fp + 1))
        echo "FAIL p118/fp: $f" >&2
        printf '%s\n' "$hits" | sed 's/^/  /' | head -3 >&2
    fi
done < "$work/corpus"

# Every skip row must name a corpus file; a typo would silently weaken the gate.
while IFS= read -r p; do
    if ! grep -Fxq "$p" "$work/corpus"; then
        echo "FAIL p118/skip: row is not in the P-1.1 corpus: $p" >&2
        fp=$((fp + 1))
    fi
done < "$work/skip_paths"

if [ "$fp" -ne 0 ]; then
    echo "FAIL p118/fp: $fp finding(s); checked $checked legal .ct, skipped $skipped, corpus $total" >&2
    exit 1
fi
echo "OK p118/fp (0 B diagnostics; checked $checked legal .ct, skipped $skipped, corpus $total)"
