# DOC-97 · C 程序员指引补「迁移适用面」一节

| 项 | 值 |
| --- | --- |
| 模块 | docs（`guide-for-c-programmers.md`） |
| 定性 | 文档补充（把“哪些新特性可用于既有 C 工程”写成判据） |
| 严重度 | Low（读者决策支持；不改语义） |
| 锚点 | `72c22173`（v0.88.3 + SH-60；2026-11-23） |
| 依据 | 外部评估“无需为新特性做迁移”的逐条核对；[language-spec §4.57](../../docs/language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast)、[§4.69](../../docs/language-spec.md#469-切片-tphase-79仅-ct-ast)、[§4.70](../../docs/language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast)、[§4.71](../../docs/language-spec.md#471-box--new单对象句柄phase-81仅-ct-ast)、[§4.73](../../docs/language-spec.md#473-最小-adt-与-matchphase-84仅-ct-ast)、[stable-subset](../../docs/stable-subset.md) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23 所有者同意开卡；只补文档，不改 API/ABI）** |

## 1. 背景

外部评估的判断是：在“公开头不动、ABI 不动、`char *` 字段不动”的前提下，新特性里能直接采用的是
`ref` 参数与方法可见性；`Str` / 切片 / `Box` / ADT / `own` 受“字段位置禁用、非 C ABI、冻结契约”
限制。这个结论方向正确，但表述容易被读成“这些特性不能用于真实工程”。需要一节把边界写成判据：

- **可直接用于 C 边界**：`ref` / `out`（发射即 `T *`）、`pub` 方法可见性、写法糖；
- **只能用于 Ct 内部实现**：`String` / `Vec` / `Map` / `Option` / `Result` / `Box<T>` / ADT；
- **边界必须转 C 形态**：`cstr()`、`(const char *, size_t)`、`T *`、opaque `struct`；
- **位置禁止**：借用视图（`Str` / `T[]`）不得进字段、全局、容器元素、`Box`、`Option`/`Result`、
  ADT 负载、泛型实参。

## 2. 落点

`docs/guide-for-c-programmers.md` 现已有 §3.3（三个迁移场景）、§6（特性与指针速查）、
§7.1（借用视图透传矩阵）、§10（C 互操作）。本条**不重写这些节**，在 §6 之后新增：

- **§6.1 迁移适用面**：三行主表（可直接用 / 仅内部用 / 边界必须转 C 形态），每行给最小示例与
  规范锚点；
- **§6.2 位置禁止表**：列 `Str` 与 `T[]` 的允许位置与禁止位置，并指向 §7.1，不重复其逐类矩阵。

篇幅控制在约 40 行：guide 已有 402 行，已超 G4 的 300 行要求（该缺口由
[DOC-96](doc-96-doc-freshness-followups.md) 统一处理，本条不扩写成长文）。

## 3. 必须写准的两句

1. **“非 C ABI”的准确含义**：这些类型**不能进入对 C 消费者承诺的导出面**，但在 Ct 内部单元里
   完全可用（`ct-ast` 自身就用 `String`/`Vec`/`Map`）。不得写成“不能用”。
2. **“全绿”的口径**：`test/run.sh` 160/0 是 **compile 模式**；`ct build` 对 `Box<T>` 目前有真实缺陷
   （[SH-116](../selfhost/sh116-build-mode-box-unit.md)）。引用“全绿”必须注明模式，避免读者把
   compile 全绿当成 build 全绿。

## 4. 验收

- guide 新增 §6.1 / §6.2；三行主表每行带至少一条 spec 锚点；
- 不重复 §7.1 的逐类矩阵，最多给一句指路；
- `check-docs` 绿；新增锚点可被 `#fragment` 解析；
- 不改 `language-spec`、`stable-subset`、编译器代码与生成物。

## 5. 非目标

- 不改任何 API / ABI 承诺，不改类型布局或拼写；
- 不改 `stable-subset` 的分档（`String`/`Str`/切片/`ref/out`/ADT/`Box` 仍是“冻结中”，v1.1 冻结）；
- 不把 SH-116 的代码修复写进文档（代码侧由 SH-116 承接）；
- 不重写 guide 的既有章节，也不处理 300 行超限（归 DOC-96）。

## 6. 关联

- [guide-for-c-programmers](../../docs/guide-for-c-programmers.md)（§3.3 / §6 / §7.1 / §10）
- [language-spec §4.57](../../docs/language-spec.md#457-c-abi-静态库ct-build---libphase-39仅-ct-ast)（`--lib` 导出面）、[§4.70](../../docs/language-spec.md#470-string--strutf-8-owning-与借用phase-80仅-ct-ast)（String/Str）、[§4.71](../../docs/language-spec.md#471-box--new单对象句柄phase-81仅-ct-ast)（Box 非 ABI）
- [stable-subset](../../docs/stable-subset.md)（三档）
- [SH-116](../selfhost/sh116-build-mode-box-unit.md)（build 模式缺陷）
- [DOC-96](doc-96-doc-freshness-followups.md)（g4 / 300 行）


## 复核（REV，2026-11-23）

按卡验收完成；`check-docs` 2971 links / 5 README snippet sources；`check-warnings` new-handle build 段
50–53 + 3 snippets 全 green；tutorial §14/§24、test/README 165/0 与实测一致。
