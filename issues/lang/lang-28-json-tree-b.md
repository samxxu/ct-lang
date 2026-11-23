# LANG-28 · JSON 树方案 B（无 arena）实施

| 项 | 值 |
| --- | --- |
| 模块 | lang / selfhost（ADT 方法、下标链、表达式 match、ADT glue）+ 少量 docs |
| 定性 | 语言面特性集合（设计已定；不是 `ct/json` 包工作） |
| 严重度 | High（涉及 parser / Symbols / Emitter / 语义 / 容量） |
| 锚点 | v0.88.3（2026-11-23） |
| 依据 | [D-021](../../docs/decisions/D-021.md)、[JSON v1.1 提案评估](../../docs/reviews/2026-11-23-json-v11-proposal-eval.md) |
| 状态 | open |
| blocked-by | **LANG-27 先落地**；B2/B4/B5 各自 ADR 通过；`MAX_FUNCS` 容量复核或 v1.1 S0 |
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
- `MAX_FUNCS` 复算或 S0 已落地；`check-all` / `check-docs` 绿。

## 非目标

- 不在本卡实现 `ct/json` 包、schema 生成器或外部排期；
- 不回到 arena + 索引作为默认；
- 不做 COW、可变树、运行时反射。
