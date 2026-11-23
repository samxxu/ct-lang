#!/bin/sh
# DOC-74 / PN-8 negative fixture: under `window: W2` a bare `PH-<n>` card is
# red.  Before the migration gate exists the check cannot even run, so this
# fixture is the T-7 red evidence; after tools/gates/phase_id.py lands it is
# green.  Run: sh test/gates/phase_id_test.sh
set -u
here=$(cd -- "$(dirname -- "$0")" && pwd)
root=$(cd -- "$here/../.." && pwd)
exe="$root/tools/gates/phase_id.py"
work=$(mktemp -d "${TMPDIR:-/tmp}/phaseid.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0

mkdir -p "$work/docs/planning" "$work/docs/phases"
cat >"$work/docs/planning/phase-id-ledger.md" <<'LEDGER'
# phase-ID 编号账本（fixture）

window: W2

| 旧 ID | 新 ID | 旧路径 | 新路径 | 版本 | 状态 |
| --- | --- | --- | --- | --- | --- |
| PH-9 | PH-9 | docs/design/phase9.md | docs/phases/PH-9/card.md | v0.9.0 | migrated |
LEDGER
cp -R "$here/phase_id/bare_ph/PH-9" "$work/docs/phases/PH-9"

if python3 "$exe" "$work" >"$work/out" 2>&1; then
    echo "FAIL: window W2 accepted a bare PH-9 card" >&2
    cat "$work/out" >&2
    fail=1
elif ! grep -q '裸 PH-9' "$work/out"; then
    echo "FAIL: expected the bare-PH diagnostic, got:" >&2
    cat "$work/out" >&2
    fail=1
fi

# The same gate must accept the canonical v0-PH-9 layout.
rm -rf "$work/docs/phases/PH-9"
mkdir -p "$work/docs/phases/v0-PH-9"
sed 's/^phase-id: PH-9$/phase-id: v0-PH-9/' "$here/phase_id/bare_ph/PH-9/card.md" \
    >"$work/docs/phases/v0-PH-9/card.md"
sed 's/^| PH-9 | PH-9 |/| PH-9 | v0-PH-9 |/; s#docs/phases/PH-9/card.md#docs/phases/v0-PH-9/card.md#' \
    "$work/docs/planning/phase-id-ledger.md" >"$work/ledger.good"
cp "$work/ledger.good" "$work/docs/planning/phase-id-ledger.md"
if ! python3 "$exe" "$work" >"$work/out2" 2>&1; then
    echo "FAIL: canonical v0-PH-9 card rejected:" >&2
    cat "$work/out2" >&2
    fail=1
fi

[ "$fail" -eq 0 ] && echo "OK phase-id (W2 bare PH red, v0-PH green)"
exit "$fail"
