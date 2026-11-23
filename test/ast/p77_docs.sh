#!/bin/sh
# PH-77-S0: the consumption contract is written down -- the official identity is
# `ct/std` with `publisher = ct`, a bare name only resolves the built-in pins,
# and the AGENTS package table points at the same store layout.
#
# Usage: sh test/ast/p77_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
guide="$root/docs/package-guide.md"
agents="$root/AGENTS.md"
decision="$root/docs/decisions/D-010.md"
fail=0

ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p77/docs: $1" >&2; fail=1; }

for f in "$guide" "$agents" "$decision"; do
    [ -f "$f" ] || { echo "FAIL p77/docs: missing $f" >&2; exit 1; }
done

if grep -Fq 'publisher = ct' "$guide" && grep -Fq '内置' "$guide" \
   && grep -Fq 'pin 表' "$guide"; then
    ok "package-guide documents the official identity and the built-in pins"
else
    bad "package-guide official identity/pin"
fi

if grep -Fq '只查内置 pin 表' "$guide" && grep -Fq '硬错' "$guide" \
   && grep -Fq '必须索引' "$guide"; then
    ok "package-guide states the three name shapes"
else
    bad "package-guide name shapes"
fi

if grep -Fq 'ct get ct/std@0.20.0' "$guide"; then
    ok "package-guide names the pinned std version"
else
    bad "package-guide pinned version"
fi

if grep -Fq "\$CT_HOME/pkg/ct/std/<version>/" "$agents" \
   && grep -Fq '内置 pin 表' "$agents" && grep -Fq 'ct/std' "$agents"; then
    ok "AGENTS package table uses ct/std and the pin table"
else
    bad "AGENTS package table"
fi

if grep -Fq 'publisher = ct' "$decision" && grep -Fq 'D-010' "$guide"; then
    ok "D-010 is linked from the guide"
else
    bad "D-010 link"
fi

if grep -Fq '裸名仅在索引唯一时可用' "$guide"; then
    bad "package-guide still documents the removed bare-name index fallback"
fi

[ "$fail" -eq 0 ] || exit 1
echo "OK p77/docs (official identity, bare-name rule, pin table documented)"
