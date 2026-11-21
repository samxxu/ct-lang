#!/usr/bin/env bash
# tools/check.sh - governance gate entry (not part of selfhost/check-all.sh).
#
# Usage: tools/check.sh g0 | g1 | g2 | g4 | g5 | g6 | g7 | g8 | g9
#
# These are the AGENTS 6.4 governance gates.  The project's eleven hard gates
# remain in selfhost/check-all.sh; this entry makes every governance gate
# runnable by name.  check-all is deliberately left unchanged: it stays the
# end-to-end ratchet, while these entries are the per-gate judges used by REV
# and by the CI-10/CI-11 ledger work.
#
#   g0  methodology landing (block + full copy + session map + deviations)
#   g1  phase-card completeness (phase_card.py g1)
#   g2  ACC-* mapping - SKIP: deviation g2-acc-mapping, tracked by CI-16
#   g4  docs executable/timeliness (reuses test/docs/check-docs.py)
#   g5  criterion <-> case minimal subset (phase_card.py g5)
#   g6  issue-ledger closure (issue_ledger.py; 5 negative fixtures)
#   g7  security mechanicals (secret scan + check-warnings; G7_SANITIZERS=1
#       also runs selfhost/check-sanitizers.sh)
#   g8  version coherence (version_coherence.py)
#   g9  spec anchoring (spec_pin.py; master spec, else the in-repo copy)
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

fail() { echo "${gate:-g0}: FAIL: $*" >&2; exit 1; }

g0() {
  gate=g0
  [ -f AGENTS.md ] || fail "AGENTS.md missing"
  [ -f docs/session-map.md ] || fail "docs/session-map.md missing"
  [ -f docs/spec/ai-coding-workflow.md ] || fail "docs/spec/ai-coding-workflow.md missing"

  grep -q '^#### 0.1 本项目实例化' AGENTS.md || fail "0.1 missing"
  grep -q '^#### 0.2 话术路由' AGENTS.md || fail "0.2 missing"
  grep -q '^#### 0.3 偏离项' AGENTS.md || fail "0.3 missing"
  grep -q '^| 版本落点 |' AGENTS.md || fail "版本落点 row missing"
  grep -q 'deviation: single-session-workflow' AGENTS.md || fail "single-session deviation missing"
  grep -q 'deviation: version-minor-offset' AGENTS.md || fail "version-minor deviation missing"

  block_ver="$(sed -n 's/^<!-- spec:begin version=\([^ ]*\) sha256=\([0-9a-f]*\) -->$/\1/p' AGENTS.md | head -1)"
  block_sha="$(sed -n 's/^<!-- spec:begin version=\([^ ]*\) sha256=\([0-9a-f]*\) -->$/\2/p' AGENTS.md | head -1)"
  [ -n "$block_ver" ] && [ -n "$block_sha" ] || fail "spec block header missing"

  if command -v shasum >/dev/null 2>&1; then
    actual_sha="$(shasum -a 256 docs/spec/ai-coding-workflow.md | awk '{print $1}')"
  else
    actual_sha="$(sha256sum docs/spec/ai-coding-workflow.md | awk '{print $1}')"
  fi
  [ "$block_sha" = "$actual_sha" ] || fail "docs/spec sha256 does not match block header"

  sync_agents="${SYNC_AGENTS:-$HOME/trae-ws/.ai-engineering/bin/sync-agents.sh}"
  if [ -f "$sync_agents" ]; then
    bash "$sync_agents" --check AGENTS.md
  else
    echo "g0: warn: sync-agents.sh not found; block-body equality skipped" >&2
  fi

  echo "g0: OK (block $block_ver, session-map present)"
}

g1() { gate=g1; python3 "$root/tools/gates/phase_card.py" "$root" g1; }

g2() {
  echo "g2: SKIP (deviation: g2-acc-mapping; docs/design has no ACC-* map yet, tracked by CI-16)" >&2
}

g4() { gate=g4; python3 "$root/test/docs/check-docs.py"; }

g5() { gate=g5; python3 "$root/tools/gates/phase_card.py" "$root" g5; }

g6() { gate=g6; python3 "$root/tools/gates/issue_ledger.py" "$root"; }

g7() {
  gate=g7
  python3 "$root/tools/gates/secret_scan.py" "$root"
  local log
  log="$(mktemp "${TMPDIR:-/tmp}/g7warn.XXXXXX")"
  if ! bash "$root/selfhost/check-warnings.sh" >"$log" 2>&1; then
    tail -25 "$log" >&2
    rm -f "$log"
    fail "check-warnings.sh is red"
  fi
  rm -f "$log"
  if [ "${G7_SANITIZERS:-0}" = 1 ]; then
    bash "$root/selfhost/check-sanitizers.sh" || fail "check-sanitizers.sh is red"
  fi
  echo "g7: OK (secret scan 0 hits; check-warnings green${G7_SANITIZERS:+, sanitizers green})"
}

g8() { gate=g8; python3 "$root/tools/gates/version_coherence.py" "$root"; }

g9() { gate=g9; python3 "$root/tools/gates/spec_pin.py" "$root"; }

battle_selftest() { bash "$root/test/battle/run.sh"; }

case "${1:-}" in
  g0) g0 ;;
  g1) g1 ;;
  g2) g2 ;;
  g4) g4 ;;
  g5) g5 ;;
  g6) g6 ;;
  g7) g7 ;;
  g8) g8 ;;
  g9) g9 ;;
  battle-selftest) battle_selftest ;;
  *) echo "usage: tools/check.sh g0 | g1 | g2 | g4 | g5 | g6 | g7 | g8 | g9 | battle-selftest" >&2; exit 2 ;;
esac
