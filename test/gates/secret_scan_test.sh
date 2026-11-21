#!/bin/sh
# Negative fixture for G7 secret scan (8.3: a gate change ships with a failing
# fixture). A fake AWS key must turn the scan red; the clean tree stays green.
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
exe="$root/tools/gates/secret_scan.py"
if python3 "$exe" "$root" --dir "$here/secret_scan/clean" >/dev/null 2>&1; then :; else
    echo "FAIL g7: clean fixture rejected" >&2; exit 1
fi
if python3 "$exe" "$root" --dir "$here/secret_scan/leak" 2>"$here/secret_scan/leak.err"; then
    echo "FAIL g7: fake AWS key passed the scan" >&2; exit 1
fi
grep -q "aws-access-key" "$here/secret_scan/leak.err" || {
    echo "FAIL g7: wrong diagnostic for fake AWS key" >&2; cat "$here/secret_scan/leak.err" >&2; exit 1
}
rm -f "$here/secret_scan/leak.err"
echo "OK g7/secret-scan (clean + 1 negative)"
