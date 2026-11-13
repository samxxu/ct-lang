#!/bin/sh
#
# test/battle/run.sh - self-test for the battle workflow tooling (§7.14).
#
# Covers the four subcommands and their refusals:
#   start    writes the question package + seat briefs; H-1/H-2 are enforced
#   check    validates question fields, rounds<=3, claim/counter E1-E5,
#            verify.json (environment/evidence/anchors/checks) and anchors
#   verdict  drafts the criterion x evidence matrix
#   close    archives closed.md and refuses without a verdict
#
# Every fixture lives under a throwaway directory; the repository is not touched.
#
# Usage: bash test/battle/run.sh
# Exit code 0 means every assertion passed.

set -u

root="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$root" || exit 1

work="${TMPDIR:-/tmp}"
work="${work%/}/ct-battle-test.$$"
rm -rf "$work"
mkdir -p "$work" || exit 1

BATTLE="bash tools/battle.sh"
CHECK="python3 tools/check-battle.py"

pass=0
fail=0
ok()  { pass=$((pass + 1)); printf '  ok    %s\n' "$1"; }
bad() { fail=$((fail + 1)); printf '  FAIL  %s: %s\n' "$1" "$2"; }

# run <name> <expected-rc> <command...>; stdout+stderr land in $work/<name>.log
run() {
    name="$1"; want="$2"; shift 2
    "$@" >"$work/$name.log" 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then ok "$name"; else
        bad "$name" "expected rc=$want, got $got: $(tr '\n' ' ' <"$work/$name.log" | cut -c1-200)"
    fi
}

# --- fixtures -----------------------------------------------------------------

# A complete battle that check must accept. Written directly (not via start) so
# the checker is exercised even if start regresses.
mk_valid() {
    d="$1"; id="$2"
    mkdir -p "$d/$id" "$d/docs/design"
    printf '# Phase 39\n\nfixture anchor line\n' >"$d/docs/design/phase39-draft.md"
    cat >"$d/$id/question.md" <<EOF
---
id: $id
head: ac040d1
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**
---

## 争点

self-test fixture.

## 逐条判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | fixture criterion | command output |
EOF
    for side in claim counter; do
        {
            echo "# $side"
            echo
            echo "## E1 命令"
            echo
            echo '```console'
            echo '$ true'
            echo '```'
            echo
            echo "## E2 锚点"
            echo
            echo "- docs/design/phase39-draft.md:1（利于己方）"
            echo "- docs/design/phase39-draft.md:3（不利于己方）"
            echo
            echo "## E3 预测"
            echo
            echo "run X -> Y"
            echo
            echo "## E4 代价"
            echo
            echo "1 file / 2 lines / revert"
            echo
            echo "## E5 steelman"
            echo
            echo "quote + response"
        } >"$d/$id/$side.md"
    done
    cat >"$d/$id/verify.json" <<EOF
{
  "battle": "$id",
  "head": "ac040d1",
  "environment": {"os": "test", "cc": "test", "date": "2026-11-13"},
  "rounds": 2,
  "evidence": [
    {"id": "V1", "side": "claim", "ref": "claim.md#E1", "command": "true", "exit": 0,
     "output": "ok", "reproduced": true}
  ],
  "anchors": [
    {"file": "docs/design/phase39-draft.md", "line": 1, "text": "# Phase 39", "supports": "claim", "checked": true}
  ],
  "checks": [
    {"id": "J-1", "claim": "x", "counter": "y", "evidence": ["V1"], "fact": "z"}
  ]
}
EOF
}

echo "work: $work"
echo

# --- start / H-1 / H-2 -------------------------------------------------------

run start-ok 0 $BATTLE start t-start --proposer REQ --opposition REVIEW --judge EDITOR --head ac040d1
if [ -f battle/t-start/question.md ] && [ -f battle/t-start/seats/claim.md ]; then
    ok start-artifacts
else
    bad start-artifacts "question.md or seats/claim.md missing"
fi
rm -rf battle/t-start

run start-h1 1 $BATTLE start t-h1 --proposer REQ --opposition REQ --judge EDITOR --head ac040d1
[ -d battle/t-h1 ] && bad start-h1-clean "refused start left battle/t-h1 behind" || ok start-h1-clean

run start-h2 1 $BATTLE start t-h2 --proposer EDITOR --opposition REVIEW --judge EDITOR --head ac040d1
[ -d battle/t-h2 ] && bad start-h2-clean "refused start left battle/t-h2 behind" || ok start-h2-clean

# --- check: positive and negative fixtures -----------------------------------

mkdir -p "$work/repo/battle"
mk_valid "$work/repo/battle" b-ok

check_one() { # <name> <expected> <battle-dir>
    name="$1"; want="$2"; dir="$3"
    ( cd "$work/repo" && python3 "$root/tools/check-battle.py" "$(basename "$dir")" ${4:-} ) \
        >"$work/$name.log" 2>&1
    got=$?
    if [ "$got" -eq "$want" ]; then ok "$name"; else
        bad "$name" "expected rc=$want, got $got: $(tr '\n' ' ' <"$work/$name.log" | cut -c1-240)"
    fi
}

check_one check-ok 0 "$work/repo/battle/b-ok"

# missing E5 in counter
cp -r "$work/repo/battle/b-ok" "$work/repo/battle/b-noe5"
python3 - "$work/repo/battle/b-noe5/counter.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read().replace("## E5 steelman", "## E-other")
open(p, "w").write(s)
PY
check_one check-noe5 1 "$work/repo/battle/b-noe5"

# broken anchor under --strict
cp -r "$work/repo/battle/b-ok" "$work/repo/battle/b-anchor"
sed -i.bak 's#docs/design/phase39-draft.md:1#docs/design/no-such-file.md:1#' \
    "$work/repo/battle/b-anchor/claim.md"
rm -f "$work/repo/battle/b-anchor/claim.md.bak"
check_one check-anchor 1 "$work/repo/battle/b-anchor" --strict

# verdict without verify.json
cp -r "$work/repo/battle/b-ok" "$work/repo/battle/b-noverify"
rm -f "$work/repo/battle/b-noverify/verify.json"
printf '# verdict\n\nupheld\n' >"$work/repo/battle/b-noverify/verdict.md"
check_one check-noverify 1 "$work/repo/battle/b-noverify"

# round 4 is over the H-4 cap
cp -r "$work/repo/battle/b-ok" "$work/repo/battle/b-r4"
cp "$work/repo/battle/b-r4/claim.md" "$work/repo/battle/b-r4/claim-r4.md"
cp "$work/repo/battle/b-r4/counter.md" "$work/repo/battle/b-r4/counter-r4.md"
check_one check-r4 1 "$work/repo/battle/b-r4"

# question with no criteria is not a case
cp -r "$work/repo/battle/b-ok" "$work/repo/battle/b-nocrit"
python3 - "$work/repo/battle/b-nocrit/question.md" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
s = s.split("## 逐条判据")[0] + "## 逐条判据\n\n（空）\n"
open(p, "w").write(s)
PY
check_one check-nocrit 1 "$work/repo/battle/b-nocrit"

# --- verdict / close ---------------------------------------------------------

# verdict needs a writable battle dir under the repository; the fixture lives in
# $work, so these two run against a real (temporary) repository battle.
mkdir -p battle/t-flow
cp -r "$work/repo/battle/b-ok/." battle/t-flow/
sed -i.bak 's/^id: b-ok/id: t-flow/' battle/t-flow/question.md
sed -i.bak 's/"battle": "b-ok"/"battle": "t-flow"/' battle/t-flow/verify.json
rm -f battle/t-flow/question.md.bak battle/t-flow/verify.json.bak
run verdict-ok 0 $BATTLE verdict t-flow
[ -f battle/t-flow/verdict.matrix.md ] && ok verdict-matrix || bad verdict-matrix "matrix missing"

# close refuses without verdict.md
rm -f battle/t-flow/verdict.md
run close-noverdict 1 $BATTLE close t-flow

# close accepts with a verdict and writes closed.md
printf '# verdict\n\nverdict: upheld\n' >battle/t-flow/verdict.md
run close-ok 0 $BATTLE close t-flow
[ -f battle/t-flow/closed.md ] && ok close-archive || bad close-archive "closed.md missing"
rm -rf battle/t-flow

# --- summary -----------------------------------------------------------------

echo
echo "battle self-test: $pass passed, $fail failed"
[ "$fail" -eq 0 ] || exit 1
exit 0
