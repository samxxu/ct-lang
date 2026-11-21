#!/usr/bin/env bash
# PH-84 S84d probe: the ADT / `match` documentation.
#
# The three user-facing documents must agree with the implementation: the spec
# freezes the syntax, the layout and the C-enum invariant; the tutorial shows a
# runnable example; the patterns document carries the `kind` discriminator
# rewrite that the v1-pre train will apply. The freeze list lives with the spec
# section (the global stable-subset list remains DOC-79 / REQ).
#
# Usage: bash test/ast/p84_docs.sh
set -u
root=$(cd -- "$(dirname -- "$0")/../.." && pwd)
fail=0

need() {   # need <file> <needle>
    if ! grep -qF -- "$2" "$root/$1"; then
        echo "FAIL p84docs: $1 does not mention '$2'" >&2
        fail=1
    fi
}

spec=docs/language-spec.md
tut=docs/tutorial.md
pat=docs/patterns.md

# ---- the spec section and its frozen contents ------------------------------
need "$spec" "Shape.Circle(r) => { return 3 * r * r; }"
need "$spec" "两种形态不能混用"
need "$spec" "### 4.73 最小 ADT 与 \`match\`（Phase 84，仅 ct-ast）"
need "$spec" "#### 语法（冻结）"
need "$spec" "#### 布局与 ABI（冻结）"
need "$spec" "int tag;"
need "$spec" "_Static_assert"
need "$spec" "不引入 vtable"
need "$spec" "#### 冻结清单登记（PH-84 范围）"
need "$spec" "#### C enum 不变（E84-1 / E84-8）"
need "$spec" "缺分支、重复分支"
need "$spec" "match covers every variant of"
need "$spec" "### 4.73"
# the C-enum invariant is stated where a reader looks for the enum semantics
need "$spec" "无负载 \`enum\`"
need "$spec" "所有成员都不带负载"

# ---- the tutorial example --------------------------------------------------
need "$tut" "## 18. 最小 ADT 与 \`match\`（Phase 84，v0.84.0 起可用）"
need "$tut" "Shape.Empty() => { return 0; }"
need "$tut" "match does not cover variant 'Shape.Rect'"
need "$tut" "绑定是副本"
need "$tut" "pub enum"
need "$tut" "match needs an ADT value"

# ---- the patterns rewrite sample ------------------------------------------
need "$pat" "## 6. \`kind\` 判别改写成穷尽 \`match\`"
need "$pat" "Node.Num(v) => { return v; }"
need "$pat" "switch (n->kind)"
need "$pat" "case K_NUM:"
need "$pat" "test/ast/291_adt_kind_rewrite/prog.ct"
need "$pat" "language-spec §4.73"

# ---- the documents point at each other (no dangling section) ---------------
need "$tut" "patterns.md#6-kind-判别改写成穷尽-match"
if ! grep -qF "language-spec.md" "$root/$pat"; then
    echo "FAIL p84docs: patterns does not link the spec" >&2
    fail=1
fi

# ---- the probe's own fixtures exist (the tutorial claims a runnable sample) -
for d in 290_adt_match 291_adt_kind_rewrite 292_adt_pub_xunit; do
    if [ ! -f "$root/test/ast/$d/prog.ct" ] || [ ! -f "$root/test/ast/$d/prog.expected.out" ]; then
        echo "FAIL p84docs: the $d fixture is missing" >&2
        fail=1
    fi
done

[ "$fail" -eq 0 ] && echo "OK p84docs"
exit $([ "$fail" -eq 0 ] && echo 0 || echo 1)
