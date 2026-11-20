# battle/pointer-free-1 反对席（REVIEW）

- 立场：**现在不受理**整体提案；问题成立，但方案与当前版本窗口、语法/ABI 现状、证据门槛
  三处冲突。替代方案按 §7.10 另出（见 verdict 的 C）。
- 只证伪，不负责设计新语言。

## E1 — 冲突可机械复现

```console
$ grep -n "语言在 v1.0 冻结" docs/planning/v1-release-plan.md
23:- 语言在 v1.0 冻结，后续只做兼容性修复/明确版本化变更。
$ grep -n "行为保持" docs/planning/v1-release-plan.md | head -3
61:“全面用最新语法重写 ct-ast”是**大范围行为保持重构**；“A 全量类型/语义进编译路径”是**产品契约变更**。
64:- `v1-PH-1 / S1`：ct-ast 语法现代化（行为保持）；
107:| v1.1 语法现代化 | `v1-PH-1 / S1` | v1.1 train | 行为保持，不单独 bump |
$ grep -n "pub struct Str" lib/std/Str.h.ct
18:pub struct Str {
$ grep -n "\bout\b" examples/c-superset/s01_switch/exprs.ct | head -2
13:    int out;
15:    out = -1;
$ grep -n "int a\[\]" test/ast/132_foreach_array_values/prog.ct | head -1
3:   explicit length, a local `int a[] = {…}` whose length only the initialiser
```

四组事实：

1. v1.0 语言冻结、v1.1 只做**行为保持**的语法现代化；提案是用户可见的新语法/新类型。
2. `Str` 是 std 包里的普通 struct，不是编译器内建；字面量默认类型改 `Str` 需要编译器认识
   外部包类型或把 `Str` 迁进内建层，属 ABI 级变更。
3. `ref` / `out` 已是合法标识符（示例里就有 `int out;` / `time_t *ref;`），`new` 也不在
   关键字表里；提案只承认一个 `new` 关键字，低估了保留字迁移。
4. `T a[]` 已是现有定长数组/初始化器语法（`int a[] = {…}`），提案再把 `T[]` 定义为
   `{ptr,len}` 切片值类型，语义与解析都要重定义。

## E2 — 锚点（含不利于己方）

- 有利于 B：[v1-release-plan.md:23](../../docs/planning/v1-release-plan.md#L23)、
  [:61-64](../../docs/planning/v1-release-plan.md#L61-L64)（冻结/行为保持）；
  [Str.h.ct:18](../../lib/std/Str.h.ct#L18)（`Str` 属 std）；
  [exprs.ct:13](../../examples/c-superset/s01_switch/exprs.ct#L13)（`out` 是标识符）；
  [time_t.ct:26](../../examples/c-superset/s19_header_typenames/time_t.ct#L26)（`ref` 是标识符）；
  [test/ast/132_foreach_array_values/prog.ct:3](../../test/ast/132_foreach_array_values/prog.ct#L3)（`int a[]` 既有语法）；
  [Stmt.h.ct:1695-1697](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1695-L1697)（关键字表无 new/ref/out）。
- **不利于己方**：[Vec.h.ct:29-32](../../lib/std/Vec.h.ct#L29-L32) 证明句柄协议可行；
  [battle/pointer-free-1/proposal.md:161](battle/pointer-free-1/proposal.md#L161-L166) 的 S2/S4 确实复用了既有能力。
  这两点不能否认，但它们只支持「以后可做」，不支持「现在整体受理」。

## E3 — 可证伪预测

1. 若 B 对，`box<T>` 不可能满足提案 J1 的「与指针写法产物行为逐字节一致」：refs 头部、
   额外分配、release 时机都会改变生成物与生命周期；若 A 能用同一份 J1 语料证明逐字节
   一致，B 在 J-3/J-5 上失败。
2. 若 B 对，`Str` 字面量默认化不可能靠 `c-boundary: allow` 覆盖普通 `.ct` 单元；若 A 能
   在不改 649 个含字面量测试文件、且不改 C ABI 的情况下完成迁移，B 在 J-3 上失败。
3. 若 B 对，`ref/out` 在没有逃逸限制时会出现「被调用者保存指针」的悬挂路径；若 A 能给出
   一条不引入借用检查的闭合规则并通过探针，B 在 J-4 上失败。

## E4 — 代价与回归面

- 语料：含字符串字面量的 `.ct` 文件 **649** 个；含 `char *` 的 **494** 处；`ref`/`out`
  作为标识符的现存用例可直接举出。
- 提案 5 个切片 + std Wave 2；每个都要动 parser/typecheck/emitter/文档，且 S5 是 ABI 级。
- v1.1 已承诺「行为保持」的语法现代化 + A strict；再加这 5 项，等于把 v1.1 变成语言 MAJOR。

## E5 — 对 A 最强论点的 steelman

A 最强的是：**问题真实 + Vec 证明句柄可行 + v1 之后更难改**。B 接受这三点；但「现在整体
受理」仍不成立，因为提案没有原型、没有迁移数据，且与 v1 冻结/行为保持直接冲突。
正确回应是把目标保留、把方案降级为 v2 REQ 与证据任务，而不是在 v1 前硬塞。
