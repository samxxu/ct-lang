# 对《节点转换协议 + NodeVec/NodeMap 寄生映射》REQ 卡的评估

> 评估对象：`ct-req-node-conversion-protocol.md`（v1.0 一步到位 · 意图恢复）。
> 核对基线：v0.88.3（2026-11-22）。本评估只做可行性/一致性核对，不改代码。
> 结论先行：**不认可“v1.0 bugfix / 意图恢复”的定性**；这是一项新语言特性 + 大型库，
> 当前卡面有 3 个硬阻断，应先改设计再谈排期。
> **所有者已裁决（2026-11-22）**：改新特性、绑定点默认宽松、JSON 树 arena + 索引、
> W1 走 ADR 落 v1.1、W2/W3 移 std 包/外部仓（v1.0 前交付）。详见 §4。

## 1. 实测结果

| 探针 | 结果 | 说明 |
| --- | --- | --- |
| P1 泛型实例作映射宿主 | **通过（语法层）** | `map trait NodeVec for type Vec<int> { sum(v) -> ct_sum(v); }` 被接受，调用展开为 `ct_sum((v))`；只在 C 编译阶段因 helper 未定义报错 |
| P2 绑定点转换可见性 | **不成立（特性不存在）** | `Vec<int> v = node;` 在当前编译器没有隐式转换；这不是“可见性”问题，而是 W1 尚未实现 |
| 卡面 `JsonNode` 逐字编译 | **失败** | 三处：payload 缺字段名、`Null;` 与带负载成员混用、递归 `Vec<JsonNode>` 触发不完整类型/`offsetof` 静态断言 |
| `Map<Str, JsonNode>` | **硬错** | `Map key type 'Str' is a borrowed view; use 'String' (owning)`（[spec §4.70](../language-spec.md)） |

`JsonNode` 的逐字形态（卡面）与修正后形态都试过：修正 payload 名与 `Null()` 后，
递归 `Vec<JsonNode>` 仍过不了布局；说明问题不是笔误，而是**递归 ADT 的值内嵌表示**。

## 2. 硬冲突（不修不能批准）

| # | 卡面 | 实测/规则 | 必须改成 |
| --- | --- | --- | --- |
| 1 | `Obj(Map<Str, JsonNode>)` | `Map<Str,…>` 是硬错；`Str` 只能作借用视图 | `Map<String, JsonNode>`（键深拷贝），或自定义键驻留/arena |
| 2 | `Bool(bool)` / `Null;` | ADT 负载必须带字段名；混合形态用 `Null()` | `Bool(bool v)`、`Num(double v)`、`Str(Str s)`、`Null()` |
| 3 | `Arr(Vec<JsonNode>)` / `Obj(Map<…,JsonNode>)` | 递归 payload 以值内嵌，布局无法闭合（静态断言失败） | **arena + 索引**（`Vec<int>` / `Map<String,int>`），或指针包装 + 显式释放 |
| 4 | `Str(Str)` 作为 JSON 字符串 | `Str` 是借用视图；ADT 不生成 drop glue（PH-84 简化项） | 明确 owner：arena 持有 `String` + 视图，或 payload 用 `String` 并依赖 W4 级联 |
| 5 | “意图恢复 / bugfix” | 仓库内没有 `JsonNode` / 绑定点转换 / `as<T>` 的既定记录；卡面引用的“Vec/Map 句柄层补全”issue 不在本仓 | 补 ADR/决策记录，或改立新特性卡 |
| 6 | W1 放在 v1.0 | 冻结期、501/512 容量、`v1-PH-0` 新增顶层函数 ≤11；绑定点查找是新语义面 | 至少 v1.1；若坚持 v1.0，必须先过 `S0` 并证明容量 |

补充：`as<T>` 当前不是语言关键字；`to<T> -> Option<T>` 也需要新的泛型方法形态。
两者都属于语言面增量，不是“增量库”。

## 3. 可取之处

- **只在绑定点转换**（声明初始化 / 赋值 / `out` / `return`）这条原则是对的；表达式内不转换
  能避免把隐式语义扩散到所有运算。
- **`as<T>` 宽松 / `to<T>` 严格两档**成对存在，方向合理；**所有者裁定绑定点默认维持宽松档**，
  严格档由 `.to<T>()` 与 `decode<T>` 边界承担，fail-fast 在 schema/decode 层闭环。
- **NodeVec / NodeMap 寄生映射**：P1 已证明泛型宿主语法可行；“未 import 零代码零体积”
  与现有 `.m.ct` 的零发射一致。
- **schema 生成器、不引入运行时反射**：方向正确；但 `decode<T>`/`encode<T>` 如何分派到
  生成代码（trait bound 还是生成函数表）卡面没写，需要补。

## 4. 所有者裁决（2026-11-22）

| # | 裁决 | 落点 |
| --- | --- | --- |
| 1 | 定性改为**新特性**；不补签“原意图”ADR | [LANG-26](../../issues/lang/lang-26-binding-site-conversion.md) |
| 2 | 绑定点默认**维持宽松档**；严格档由 `.to<T>()` / `decode<T>` 边界承担 | LANG-26 协议条款 |
| 3 | JSON 树定稿 **arena + 索引**（`Arr(Vec<int>)` / `Obj(Map<String,int>)`），节点 = (arena, 下标)；子树不跨文档 | [PKG-24](../../issues/packages/pkg-24-json-node-arena.md) |
| 4 | W1 走 ADR 落 **v1.1**（501/512 容量硬约束）；W2/W3 移 **std 包/外部仓**，v1.0 前交付，包形态不占容量、不碰冻结 | LANG-26 + PKG-24 |
| 5 | 连带义务（J-6 / stable-subset / capabilities / idioms 第 11 条）随 W1 ADR 通过后再登记 | 时序 |

## 5. 落地卡

- [LANG-26](../../issues/lang/lang-26-binding-site-conversion.md)：v1.1，先 ADR；
- [PKG-24](../../issues/packages/pkg-24-json-node-arena.md)：**外部包工作**，由 std 包/外部仓交付；
  CT 仓只保留接口依赖记录，不进入 `v1-release-plan`。外部目标 v1.0 前。

## 6. 仍未闭合的设计项（不阻塞定性）

- `decode<T>` / `encode<T>` 如何分派到生成代码（trait bound 还是生成函数表）；
- 节点字符串 payload 的 owner（arena 持有 `String`，还是视图 + 输入寿命）；
- PKG-24 的 schema 子集边界与错误码。
