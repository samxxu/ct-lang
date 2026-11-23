# LANG-27 · 容器级联释放（`Vec` / `Map` 进入 Drop 胶水）+ 树存储重评估

| 项 | 值 |
| --- | --- |
| 模块 | lang / selfhost（Drop 胶水）+ `lib/core`（Vec / Map） |
| 定性 | 语言 / 运行时能力（原节点协议 REQ 卡的 **B 项：Drop 级联**） |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-23） |
| 依据 | 外部 REQ 卡 W4/B 项；[节点协议评估](../../docs/reviews/2026-11-22-req-node-conversion-protocol-eval.md)；[spec §4.56](../../docs/language-spec.md) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23 所有者：先落地 LANG-27；方案 B 在 LANG-27 合入后按 §唤醒条件评估，不提前承诺 v1.1 一步到位）** |

## 现状（机制核实）

字段胶水的准入是 `uses_drop` 标志，不是“所有字段”：

- `Emitter` 只为 `uses_drop` 的 struct 生成 `<S>_Drop_drop` 体；字段递归时只对
  **基类型 struct 的 `uses_drop` 为真** 的字段发 `<Child>_Drop_drop`（指针字段带 `if (f)`，
  值字段传 `&field`）；显式 `impl Drop` 会整体关闭自动胶水。
- `Vec` / `Map` 是**普通泛型 struct**，没有 `use Drop`，因此不置 `uses_drop`；
  宿主 `use Drop` 的胶水会跳过它们（生成体退化为 `(void)_self;`）。
- 只有 `String` / `U16String`（`lib/core/Str.h.ct`）与 `Box`（`lib/core/Box.h.ct`）`use Drop`。
- 所以今天的结论是：**`Vec` / `Map` 字段无自动胶水，生命周期靠显式 `release()`**；
  这与 spec §4.56 / §4.70 的表述一致。

## 目标（B 项）

让容器级联释放成为语言/运行时的正式能力，而不是每处手写 `release()`：

1. `Vec<T>` / `Map<K,V>` 字段在宿主析构时按元素协议递归释放；
2. 元素释放走现有 `__ct_elem_release` 级联（含 `h == 0` 零句柄守卫），不改变
   `release()` 对零句柄仍 abort 的契约；
3. 显式 `impl Drop` 仍自负全责，不自动加胶水；
4. 无泄漏、无双释放；ASan 夹具覆盖嵌套容器、空句柄、越界 `get` 的零值。

## 唤醒条件（本卡核心）

**容器级联（本卡 B 项）落地，或递归 ADT 的布局方案（指针/间接）先通过布局断言，
以先发生者为准；触发后 30 天内重评估 JSON 树存储方案。**

**所有者裁决（2026-11-23）**：顺序固定为 **先落地 LANG-27，再评估方案 B**；
LANG-27 合入前不启动“无 arena”树存储方案，也不把 JSON v1.1 提案当作已批准。

重评估对象：

| 候选 | 形态 | 当前结论 |
| --- | --- | --- |
| A（现行） | arena + 索引：节点 = `(arena, 下标)`，`Arr(Vec<int>)` / `Obj(Map<String,int>)` | 已选；绕开递归布局与无 drop glue |
| B（本卡唤醒后重评） | 递归 ADT + `Vec<JsonNode>` / `Map<String,JsonNode>` + 自动容器级联 | 当前不可行；级联 + 布局闭合后才重新评估 |

重评估判据（缺一不可）：

1. 递归 ADT 生成的 C 能闭合布局（无 incomplete type / `offsetof` 失败）；
2. 容器级联无泄漏、无双释放，ASan 绿；
3. 子树跨文档语义仍明确（现行契约是“子树不跨文档”，B 若改变须给出新契约）；
4. `Map` 键深拷贝成本、`Str` 视图 owner 仍可接受；
5. 产出评估文档，再决定是否改 PKG-24 / 节点协议结论；**不自动切换**。

## 非目标

- 不在本卡实现 JSON 库或 NodeVec/NodeMap（PKG-24 已按用户裁定 rejected，属外部仓）；
- 不改 arena + 索引的现行结论，除非 §唤醒条件全部满足；
- 不把 `AutoDrop` 变成 trait（§4.9）。

## 验收

- 容器字段级联释放的生成 C 有正例/负例与 ASan 夹具；
- 嵌套容器、空句柄、越界 `get` 零值不 abort；
- 显式 `impl Drop` 仍不生成胶水；
- 唤醒条件触发后，评估文档落 `docs/reviews/` 并回链本卡。

## 关联

- [D-021](../../docs/decisions/D-021.md)：JSON 树方案 B 设计；
- [LANG-28](lang-28-json-tree-b.md)：B 方案实施（LANG-27 为前置）；
- [JSON v1.1 提案评估](../../docs/reviews/2026-11-23-json-v11-proposal-eval.md)：方案 B 的前置评估；
- [节点协议评估](../../docs/reviews/2026-11-22-req-node-conversion-protocol-eval.md)；
- [PKG-24](../../issues/packages/pkg-24-json-node-arena.md)（rejected，外部仓）；
- [LANG-26](lang-26-binding-site-conversion.md)（D-020，v1.1 实现）；
- [language-spec §4.56 / §4.70](../../docs/language-spec.md)。

## 复核（REV，2026-11-23）

`Vec`/`Map` by-value 字段在宿主 `use Drop` 胶水中按声明顺序级联 `release`；元素走
`__ct_elem_release`（h==0 守卫）；显式 `impl Drop` 仍不生成胶水；指针/数组字段不自动递归。
`p_lang27_cascade` 17 ok（生成 C 形状/负例/运行/ASan/UBSan/leaks 0）；check-all 12 门绿。
