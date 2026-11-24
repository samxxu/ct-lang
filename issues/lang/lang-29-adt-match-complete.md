# LANG-29 · ADT / `match` 完整化（B1/B2/B3/B4/B5，v1.1）

| 项 | 值 |
| --- | --- |
| 模块 | lang / selfhost（parser、Symbols、Emitter、语义、容量） |
| 定性 | **语言能力补全**（所有者 2026-11-24 裁定：v1.1 必做） |
| 严重度 | **High** |
| 锚点 | `4eb1e4e0`（2026-11-24） |
| 依据 | [D-021](../../docs/decisions/D-021.md) B1–B8；[P-4 重评](../../docs/reviews/2026-11-24-json-tree-b-reeval.md)；[LANG-28](lang-28-json-tree-b.md)（树存储结论：维持 A） |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者：完整 ADT/match 是 v1.1 必做项，扫清障碍）** |

## 1. 与 LANG-28 / P-4 的关系

- **JSON 存储仍维持 A**（arena + 索引）：P-4 的 `rejected` 结论不翻案，不重开 PKG-24；
- 本条接管 LANG-28 里的 **B1/B2/B3/B4/B5 语言面**：它们不只为 JSON 服务，是 ADT/match
  完整能力的一部分；
- **B7（只读视图 / 子树跨文档）** 与 **B6（`ct-gen` 外部）** 不在本条；
- 重提条件（LANG-28 里写的“B1+B3 落地后重评”）由本条直接承担 B1/B3 的实现；
- **语言能力与包解耦**：JSON 是外部 ct-pkg 包，不在本仓；本条不引用任何包类型做验收，
  夹具一律用中性的 `Node` / `Tree` / `Result<T, E>`。包侧是否采用这些能力由包自己决定。

## 2. 现在的障碍（v1.0.0 实测）

| # | 代码 | 现状 |
| --- | --- | --- |
| B1 | `enum N { Nil(), Arr(Vec<N> v) }` | 生成 C 里 `struct Vec_N;` 前置声明在 `struct N` 之后 → `field has incomplete type` |
| B2 | `enum N { … } impl N { int value() { … } }` | `error: impl of an unknown trait` |
| B5 | `return match (n) { N.Leaf(v) => v, N.Nil() => 0 };` | `error: unexpected token`（只有语句形态） |
| B3 | `enum M { Text(String s) }` + 工厂返回 | 能编译，但 payload 直接拷贝指针、**无 retain**；ASan `heap-use-after-free` |
| B4 | `map binding` 作为绑定点转换第三查找源 | 未实现 |

> P-4 报告明确：B1 的“预发射壳”是**可闭合路径**，只是尚未实现。

## 3. 范围与顺序

| 阶段 | 内容 | 依赖 |
| --- | --- | --- |
| S1 B1 | 在 ADT 之前**预发射**其用到的具体泛型实例壳（`struct Vec_N` / `Map_String_N`），实例体仍在后；递归按拓扑序、防环；`bool` 统一 `_Bool` | 无 |
| S2 B3 | ADT payload 的 `retain` / `release` / drop glue；`match` 绑定给 retain 副本；浅共享；禁止裸 `Str` payload | S1 |
| S3 B2 | enum ADT 的固有方法、自定义下标、多级链（含字段 / 方法 / 写形态）；临时量只求值一次，不落 C 指针算术 | S2 |
| S4 B4 + B5 | `map binding` 作为 D-020 第三查找源（编译期、import 可见、一跳、歧义硬错）；表达式 `match`（`yield` 语义）与语句形态共存 | S3 |

B8（`Int(long long)` / `Double(double)` / `Result<T, E>` / `_Bool` ABI）随 S1 一起定，
但**不引入任何外部包**。

## 4. 验收

- 递归 `enum J { Arr(Vec<J> v), Obj(Map<String, J> v) }` 生成的 C 可编译；深度 1000 用例 ASan 无泄漏/双释放；
- `doc["user"]["age"]` 读写、`doc["user"].field`、`doc["user"].method()` 均可用；
- 表达式 `match` 与语句 `match` 共存，`yield` 规则有负例（漏 `yield`、多 `yield`、类型不一致）；
- `match` 绑定 owning payload 时不产生 UAF（ASan 正例）；
- `map binding` 未 import 有可行动诊断；歧义硬错；未使用零成本；
- 全量 `--check-level=warn` FP=0 不回退；生成物变化按 golden 更新并单独提交；
- `check-all` 13 门绿；容量用 SH-109 动态增长，不受 512 限制。

## 5. 风险

| # | 风险 | 处置 |
| --- | --- | --- |
| R29-1 | 布局变化波及既有 golden | 生成物差异单独提交，逐字节对照；新增用例进 J-6 |
| R29-2 | `match` 绑定 retain 的语义边界（借用 vs 拥有） | 先写 ADR 增补（D-021 已有 B3 方向），再实现 |
| R29-3 | 与 v1.1 冻结冲突 | 必须在 `stable-subset` 把 ADT/`match` 转“已冻结”**之前**完成 |
| R29-4 | 递归实例的拓扑序/防环做错 | 专项负例：自引用、互引用、深度上限 |
| R29-5 | `Map` 键深拷贝成本 | 沿用 P-4 的量级基准（约 14–15 ns），超阈值再评估 |

## 6. 非目标

- 不切 JSON 存储到 B（维持 A）；不重开 PKG-24；
- 不做 B7 只读视图 / 子树跨文档；
- 不做 COW、可变树、运行时反射；
- 不做泛型 ADT、or 模式、嵌套模式（仍按 D3-A 留后续）。

## 7. 关联

- [D-021](../../docs/decisions/D-021.md)（B1–B8 设计）
- [P-4 重评](../../docs/reviews/2026-11-24-json-tree-b-reeval.md)（障碍实测）
- [LANG-28](lang-28-json-tree-b.md)（树存储 rejected；语言面由本条承接）
- [LANG-27](lang-27-container-cascade.md)（容器级联，已 verified）
- [v1-PH-1](../../docs/phases/v1-PH-1/card.md)（S2b）
