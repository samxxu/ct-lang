#!/bin/sh
# Negative fixture for G7 secret scan (8.3: a gate change ships with a failing
# fixture). The fake key is generated in a temp dir, never committed, so the
# real-tree scan cannot hit its own fixture. A clean dir passes; the leak dir
# must turn the scan red with the matching diagnostic.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
exe="$root/tools/gates/secret_scan.py"
work=$(mktemp -d "${TMPDIR:-/tmp}/g7secret.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
mkdir -p "$work/clean" "$work/leak"
printf 'no credentials here\n' > "$work/clean/readme.txt"
printf 'aws = "AKIA%s"\n' 'IOSFODNN7EXAMPLE' > "$work/leak/creds.txt"
if python3 "$exe" "$root" --dir "$work/clean" >/dev/null 2>&1; then :; else
    echo "FAIL g7: clean fixture rejected" >&2; exit 1
fi
if python3 "$exe" "$root" --dir "$work/leak" 2>"$work/err"; then
    echo "FAIL g7: fake AWS key passed the scan" >&2; exit 1
fi
grep -q "aws-access-key" "$work/err" || {
    echo "FAIL g7: wrong diagnostic for fake AWS key" >&2; cat "$work/err" >&2; exit 1
}
echo "OK g7/secret-scan (clean + 1 negative)"
