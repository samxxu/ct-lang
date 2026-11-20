#!/bin/sh
# PH-82 / S82d: the written leak-guard contract and the release sync
# (E82-6 wording, E82-7 docs, E82-8 version/goldens).
#
#   - spec §4.72 records `leaks`, the direct-cycle scope/depth, the
#     allow-cycle rule and the "may leak ... unless broken by hand" wording;
#     §4.71's boundary now points at it;
#   - package-guide §2 lists the `leaks` key; patterns §5 is the tree pattern
#     (owning `box<Node>` down, raw `Node *parent` up, allow-cycle marker);
#   - the phase card carries the §7 closeout table with E82-1…8;
#   - the five CTC_VERSION sites, README/docs/README, roadmap and the card
#     agree on v0.82.0;
#   - `--debug-leaks` is still not implemented and is not renamed as a cycle
#     detector (D-011 J-4c).
#
# Usage: sh test/ast/p82_docs.sh <ct-ast>
set -u
ctast=${1:?usage: p82_docs.sh <ct-ast>}
case "$ctast" in
    /*) ;;
    *) ctast=$(cd -- "$(dirname -- "$ctast")" && pwd)/$(basename -- "$ctast") ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/p82doc.XXXXXX") || exit 1
trap 'rm -rf "$work"' EXIT HUP INT TERM
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p82/docs: $1" >&2; [ $# -gt 1 ] && printf '  %s\n' "$2" >&2; fail=1; }
cd "$root" || exit 1

for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
         selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
    if grep -q '#define CTC_VERSION "0.82.0"' "$f"; then
        ok "$f CTC_VERSION 0.82.0"
    else
        bad "$f CTC_VERSION is not 0.82.0"
    fi
done

if grep -q 'v0\.82\.0' README.md && grep -q 'v0\.82\.0' docs/README.md; then
    ok "README / docs/README carry v0.82.0"
else
    bad "README version"
fi
if grep -q '^| Phase 82 |' docs/roadmap.md && grep -q 'v0\.82\.0' docs/roadmap.md \
        && sed -n '/^| Phase 82 |/p' docs/roadmap.md | grep -q '✅'; then
    ok "roadmap lists Phase 82 done with v0.82.0"
else
    bad "roadmap Phase 82 row"
fi

spec=docs/language-spec.md
[ -f "$spec" ] || { bad "$spec missing"; exit 1; }
if grep -q '^### 4\.72 ' "$spec"; then
    ok "spec has the leak-guard section (4.72)"
else
    bad "spec section 4.72 missing"
fi
for needle in 'leaks = warn|error' 'allow-cycle' '3 条边' '可能泄漏' '会泄漏' \
              '--debug-leaks' 'c-boundary' 'unless the cycle is broken by hand' \
              '§4.72'; do
    if grep -qF -e "$needle" "$spec"; then ok "spec mentions $needle"; else bad "spec does not mention $needle"; fi
done

guide=docs/package-guide.md
if grep -q '| `leaks` |' "$guide" && grep -q '§4.72' "$guide"; then
    ok "package-guide lists the leaks key and points at §4.72"
else
    bad "package-guide leaks key"
fi

pat=docs/patterns.md
if grep -q '^## 5 父子结构' "$pat" && grep -qF 'allow-cycle' "$pat" \
        && grep -qF 'Node *parent' "$pat" && grep -qF 'first_child' "$pat"; then
    ok "patterns §5 is the tree pattern with allow-cycle and a raw parent pointer"
else
    bad "patterns tree section"
fi

card=docs/design/phase82.md
[ -f "$card" ] || { bad "$card missing"; exit 1; }
if grep -q '^## 7 ' "$card"; then ok "phase card has the §7 closeout"; else bad "card §7 missing"; fi
for id in E82-1 E82-2 E82-3 E82-4 E82-5 E82-6 E82-7 E82-8; do
    if grep -q "| $id |" "$card"; then ok "card rule row $id"; else bad "card missing $id"; fi
done
if grep -q '状态：完成' "$card" && grep -q 'E82-8 ✅' "$card"; then
    ok "card records the closeout (完成 / E82-8 ✅)"
else
    bad "card closeout status"
fi

# `--debug-leaks` is still a pending item, never a cycle detector.
printf 'int main(void) { return 0; }\n' >"$work/x.ct"
"$ctast" --debug-leaks "$work/x.ct" -o "$work/x.c" >"$work/dl.log" 2>&1
if grep -Fq "unknown option '--debug-leaks'" "$work/dl.log" \
        && ! grep -qi "cycle" "$work/dl.log"; then
    ok "--debug-leaks is still unknown (not renamed as cycle detection, D-011 J-4c)"
else
    bad "--debug-leaks contract" "$(head -2 "$work/dl.log")"
fi

[ "$fail" -eq 0 ] && echo "p82_docs: OK"
exit "$fail"
