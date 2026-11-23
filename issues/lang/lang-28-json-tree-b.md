# LANG-28 · JSON 树方案 B（无 arena）实施

| 项 | 值 |
| --- | --- |
| 模块 | lang / selfhost（ADT 方法、下标链、表达式 match、ADT glue）+ 少量 docs |
| 定性 | 语言面特性集合（设计已定；不是 `ct/json` 包工作） |
| 严重度 | High（涉及 parser / Symbols / Emitter / 语义 / 容量） |
| 锚点 | v0.88.3（2026-11-23） |
| 依据 | [D-021](../../docs/decisions/D-021.md)、[JSON v1.1 提案评估](../../docs/reviews/2026-11-23-json-v11-proposal-eval.md) |
| 状态 | deferred |
| blocked-by | **LANG-27 先落地**；B2/B4/B5 各自 ADR 通过；SH-109 动态增长在当前 pre 窗口先落地（不再受 512 限制） |
| 处置证据 | **accepted（设计）**：所有者 2026-11-23 逐项裁定 B1–B8；实现待 LANG-27 后按 §阶段执行 |

## 范围（按 D-021）

1. **B1**：ADT 前预发射泛型实例壳；`_Bool`；`Int(long long)` / `Double(double)`；
   `Result<JsonNode, JsonError>`。
2. **B3**：ADT `retain` / `release` / drop glue；浅共享、`match` 绑定 retain 副本；
   无裸 `Str` payload。
3. **B2**：enum ADT 固有方法、ADT 自定义下标、多级链（含字段/方法/写形态）；
   临时量只求值一次，不落 C 指针算术。
4. **B4**：`map binding` 注册表作为 D-020 第三查找源；编译期、import 可见、一跳、歧义硬错。
5. **B5**：表达式 `match`（`yield` 语义）+ ct-gen 先走语句改写的 A 路径。
6. **B7**：`JsonArray` / `JsonObject` 只读视图；子树可跨文档；深度上限/迭代释放；
   与 arena 的基准对比。
7. **B6**：`ct-gen` 外部；生成物显式 `import`；`ct build` 不 glob、不调外部工具。

## 阶段

| 阶段 | 内容 | 前置 |
| --- | --- | --- |
| S0 | LANG-27 容器级联 | 已完成设计（D-021） |
| S1 | B1 + B3 + B8（布局、ADT glue、ABI/错误） | S0 |
| S2 | B2 + B4 + B5（语言面，各自 ADR） | S1 |
| S3 | B7（视图/子树/基准） | S2 |
| S4 | 外部 `ct/json` / `ct/tree` / `ct-gen` | 不在 Ct 计划 |

## 验收

- 递归 `Vec<JsonNode>` / `Map<String,JsonNode>` 生成 C 可编译，深度用例 ASan 无泄漏/双释放；
- `doc["user"]["age"]` 读写、`doc["user"].field`、`doc["user"].method()` 均可用；
- `map binding` 未 import 时有可行动诊断，歧义硬错，未用零代码；
- 表达式 `match` 与语句 `match` 共存，`yield` 规则有负例；
- 只读视图不可变；子树跨文档 retain/release 正确；
- SH-109 动态增长已落地（固定 512 不再作预算）；`check-all` / `check-docs` 绿。

## 非目标

- 不在本卡实现 `ct/json` 包、schema 生成器或外部排期；
- 不回到 arena + 索引作为默认；
- 不做 COW、可变树、运行时反射。

## 处置（REQ，2026-11-23）：deferred 到 v1.1 S1

LANG-27 容器级联已落地（本卡 blocked-by S0 解除），但 B1/B3/B4/B5 各自仍需 ADR 与
parser/Emitter 改造，属 v1.1 阶段 S1–S3；不阻塞 v1.0。触发：`v1-PH-1` 开卡且 B1/B3 ADR 通过。

## 任务描述（P-4，2026-11-24；30 天重评）

> 归属：[DOC-99](../docs/doc-99-v11-prework-tracker.md) P-4。**只出评估文档，不写实现、不 bump 版本。**

### 触发与截止

[LANG-27](lang-27-container-cascade.md) 已 verified（2026-11-23），唤醒条件第一项触发；
按“触发后 30 天内重评估”，**截止 2026-12-23**。过期未评，则本卡保持 `deferred` 并在
[DOC-99](../docs/doc-99-v11-prework-tracker.md) 记一次逾期原因。

### 输入

- [D-021](../../docs/decisions/D-021.md) 的 B1–B8 设计；
- [LANG-27](lang-27-container-cascade.md) §唤醒条件的 5 条判据与 `p_lang27_cascade` 的 17 项证据；
- 现行 A 方案（arena + 索引）的契约与 PKG-24（rejected，外部仓）记录；
- v1.0.0 实际编译器（`bootstrap/ct-ast` 可直接 `cc` 出 `ct`）。

### 必须做的五项（对应 LANG-27 判据）

| # | 判据 | 做法 |
| --- | --- | --- |
| 1 | 递归 ADT 布局闭合 | 最小例 `enum N { Nil(), Arr(Vec<N> v) }` 编译并 `cc -c`；记录错误原文（v1.0.0 实测：`field has incomplete type 'struct Vec_N'`，见下） |
| 2 | 级联无泄漏/双释放 | 复用 `p_lang27_cascade`；补嵌套容器、空句柄、越界 `get`，ASan/UBSan 零报告 |
| 3 | 子树跨文档语义 | 给出 B 下的契约（允许跨文档 retain/release，或仍禁止）；与 A 的“子树不跨文档”逐条对照 |
| 4 | `Map` 键深拷贝 / `Str` owner 成本 | 最小基准：构造、查找、释放各一组；给出量级与是否可接受 |
| 5 | 产出评估文档 | 落 `docs/reviews/`，回链 LANG-27 / 本卡 / D-021 / PKG-24 |

判据 1 的现状（v1.0.0 实测，可直接复现）：

```console
$ cc -std=c99 -I bootstrap/ct-ast bootstrap/ct-ast/*.c -o /tmp/ct
$ printf 'enum N { Nil(), Arr(Vec<N> v) }\nint main(void) { N n = N.Nil(); return 0; }\n' > /tmp/r.ct
$ /tmp/ct compile /tmp/r.ct -o /tmp/r.c && cc -std=c99 -c /tmp/r.c
/tmp/r.c:20:26: error: field has incomplete type 'struct Vec_N'
```

### 结论只有三种

1. **维持 A**（arena + 索引）——B 仍有判据不满足，写明是哪条、可复跑证据；
2. **切 B**——五条全满足，给出切换步骤与回滚点（B1/B3 ADR 才可开）；
3. **B 限定子集**——例如只做只读树或只做单文档，写明放弃哪一段。

### 验收

- 五条判据逐条“满足 / 不满足 + 证据”，不许写“预计通过”；
- 不改代码、不改 PKG-24 结论、不 bump 版本；`check-docs` 绿；
- 结论文档落 `docs/reviews/` 并回链；本卡的 `blocked-by` 按结论更新
  （切 B 才需要 B1/B3 ADR；维持 A 则本卡转 `rejected` 并记理由与重提条件）。

### 非目标

- 不在本项实现 B、不写 `ct/json`、不做性能承诺；
- 不重开 PKG-24 的外部排期；
- 不改 D-021 的 B1–B8 设计本身（如需改，另开 ADR 修订）。

