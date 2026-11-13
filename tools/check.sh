#!/usr/bin/env bash
# tools/check.sh - governance gate entry (not part of selfhost/check-all.sh).
#
# Usage: tools/check.sh g0
#
# g0 is the methodology landing gate: spec block + full copy + session map +
# the three block-outside sections + the two signed deviations.  The project's
# eleven hard gates remain in selfhost/check-all.sh; this entry only makes G0
# runnable, because G0 is a precondition for opening a new phase (11.5 L-3).
set -euo pipefail

root="$(cd -- "$(dirname -- "$0")/.." && pwd)"
cd "$root"

fail() { echo "g0: FAIL: $*" >&2; exit 1; }

g0() {
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

case "${1:-}" in
  g0) g0 ;;
  *) echo "usage: tools/check.sh g0" >&2; exit 2 ;;
esac
