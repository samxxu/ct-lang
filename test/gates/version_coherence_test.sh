#!/bin/sh
# Negative fixture for the G8 version gate (8.3: a gate change ships with a
# failing fixture). Builds a throwaway repo, drifts a card and a tag, and
# asserts the gate fails; the coherent/ledgered variants pass.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/g8ver.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM

mkdir -p "$work/docs/design" "$work/docs/planning"
cd "$work" || exit 1
git init -q .
git config user.email t@example.com
git config user.name t
printf '# Phase 99\n\n| version-minor | 98 |\n\n状态：完成\n' > docs/design/phase99.md
printf '# legacy offsets\n' > docs/planning/version-legacy-offsets.tsv
git add -A && git commit -qm base

if python3 "$root/tools/gates/version_coherence.py" "$work" 2>"$work/a.err"; then
    echo "FAIL g8: drifting card version-minor=98 passed" >&2
    exit 1
fi
grep -q "card version-minor=98 != 99" "$work/a.err" || {
    echo "FAIL g8: wrong diagnostic for card drift" >&2
    cat "$work/a.err" >&2
    exit 1
}

sed 's/| 98 |/| 99 |/' docs/design/phase99.md > docs/design/phase99.new && mv docs/design/phase99.new docs/design/phase99.md
if ! python3 "$root/tools/gates/version_coherence.py" "$work" >/dev/null 2>&1; then
    echo "FAIL g8: coherent card rejected" >&2
    exit 1
fi

git tag -a v0.97.0 -m "PH-99 closeout (deadbee)"
if python3 "$root/tools/gates/version_coherence.py" "$work" 2>"$work/b.err"; then
    echo "FAIL g8: drifting tag v0.97.0 for PH-99 passed" >&2
    exit 1
fi
grep -q "not in the legacy ledger" "$work/b.err" || {
    echo "FAIL g8: wrong diagnostic for tag drift" >&2
    cat "$work/b.err" >&2
    exit 1
}

printf '99\tv0.97.0\t97\tfixture legacy row\n' >> docs/planning/version-legacy-offsets.tsv
git add -A && git commit -qm ledger
if ! python3 "$root/tools/gates/version_coherence.py" "$work" >/dev/null 2>&1; then
    echo "FAIL g8: ledgered legacy tag still rejected" >&2
    exit 1
fi

echo "OK g8/version (card + tag drift, ledger)"
