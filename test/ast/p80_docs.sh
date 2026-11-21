#!/bin/sh
# PH-80 S5b-2 (E80-8): the written `String` / `Str` contract does not drift.
#
#   - the five `CTC_VERSION` sites agree on 0.83.3;
#   - README / docs/README carry the release;
#   - docs/roadmap.md lists Phase 80 with its version;
#   - the language reference has the §4.70 contract (layout, literal, `.data`,
#     `cstr()`, UTF-16 factories, the explicit copy protocol);
#   - lib/std/README.md names the layer units and the compatibility window;
#   - the phase card carries the §7 closeout table with every E80 row, the
#     S5b deletion (E80-7 ✅) and the C-7 / external dry-run sections.
#
# Usage: sh test/ast/p80_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fail=0
ok()  { printf 'ok   %s\n' "$1"; }
bad() { echo "FAIL p80/docs: $1" >&2; fail=1; }
cd "$root" || exit 1

for f in selfhost/l0/ctc.c selfhost/l1/ctc.ct selfhost/l2/core.ct \
         selfhost/l2/driver.ct selfhost/ct-ast/main.ct; do
    if grep -q '#define CTC_VERSION "0.87.0"' "$f"; then
        ok "$f CTC_VERSION 0.87.0"
    else
        bad "$f CTC_VERSION is not 0.87.0"
    fi
done

if grep -q 'v0\.87\.0' README.md; then ok "README carries v0.87.0"; else bad "README version"; fi
if grep -q 'v0\.87\.0' docs/README.md; then ok "docs/README carries v0.87.0"; else bad "docs/README version"; fi
if grep -q 'Phase 80' docs/roadmap.md && grep -q 'v0\.80\.4' docs/roadmap.md \
   && grep -q 'Phase 81' docs/roadmap.md && grep -q 'v0\.81\.0' docs/roadmap.md; then
    ok "roadmap lists Phase 80 (v0.80.4) and Phase 81 (v0.81.0)"
else
    bad "roadmap Phase 80 / 81 rows"
fi

spec=docs/language-spec.md
[ -f "$spec" ] || { bad "docs/language-spec.md missing"; exit 1; }
if grep -q '^### 4\.70 .*`String` / `Str`' "$spec"; then
    ok "spec has the String/Str section (4.70)"
else
    bad "spec section 4.70 missing"
fi
for needle in 'const char \*' 'cstr()' 'immortal' 'U16String' '旧类型已删除' '不保证 NUL'; do
    if grep -q "$needle" "$spec"; then ok "spec mentions $needle"; else bad "spec does not mention $needle"; fi
done

std=lib/std/README.md
if grep -q 'S5b' "$std" && grep -q '旧 owning `Str` 已删除' "$std"; then
    ok "lib/std README records the S5b deletion"
else
    bad "lib/std README deletion note"
fi
if grep -q 'U16String' "$std"; then ok "lib/std README names the UTF-16 pair"; else bad "lib/std README UTF-16"; fi

card=docs/design/phase80.md
[ -f "$card" ] || { bad "docs/design/phase80.md missing"; exit 1; }
if grep -q '^## 7 ' "$card"; then ok "phase card has the §7 closeout"; else bad "phase card §7 missing"; fi
for id in E80-1 E80-2 E80-3 E80-4 E80-5 E80-6 E80-7 E80-8; do
    if grep -q "| $id |" "$card"; then ok "card rule row $id"; else bad "card missing $id"; fi
done
if grep -q 'E80-7 ✅ 通过' "$card" && grep -q '7.7 C-7 回滚演练' "$card" \
   && grep -q '7.8 外部消费者 dry-run' "$card"; then
    ok "card records E80-7 pass, the C-7 drill and the external dry-run"
else
    bad "card does not record the completed S5b (E80-7 / C-7 / dry-run)"
fi

[ "$fail" -eq 0 ] && echo "p80_docs: OK"
exit "$fail"
