# 对《节点转换协议 + NodeVec/NodeMap 寄生映射》REQ 卡的评估

> 评估对象：`ct-req-node-conversion-protocol.md`（v1.0 一步到位 · 意图恢复）。
> 核对基线：v0.88.3（2026-11-22）。本评估只做可行性/一致性核对，不改代码。
> 结论先行：**不认可“v1.0 bugfix / 意图恢复”的定性**；这是一项新语言特性 + 大型库，
> 当前卡面有 3 个硬阻断，应先改设计再谈排期。

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
- **`as<T>` 宽松 / `to<T>` 严格两档**成对存在，方向合理；但默认档建议反过来——
  绑定点默认严格、边界显式宽松，才符合当前 fail-fast 口径。
- **NodeVec / NodeMap 寄生映射**：P1 已证明泛型宿主语法可行；“未 import 零代码零体积”
  与现有 `.m.ct` 的零发射一致。
- **schema 生成器、不引入运行时反射**：方向正确；但 `decode<T>`/`encode<T>` 如何分派到
  生成代码（trait bound 还是生成函数表）卡面没写，需要补。

## 4. 处置建议

1. **改定性**：从“v1.0 bugfix / 意图恢复”改为“新特性提案（v1.1 起）”。
   没有 ADR 证据时，不能用“意图恢复”绕开冻结与容量。
2. **拆卡**：
   - W0：只保留探针结果（P1 通过、P2 证明特性不存在）；
   - W1：先出 ADR（绑定点转换的查找、默认档、表达式禁区），落 v1.1；
   - W2：在 `JsonNode` 所有权定稿后作为 v1.1 增量；宿主改 `Map<String, JsonNode>`；
   - W3：JSON 解析/序列化 + schema 生成器移到 **std 包/外部仓**，不进编译器 v1.0。
3. **重设计 JSON 树**：优先 **arena + 索引**——`Arr(Vec<int>)`、`Obj(Map<String,int>)`，
   节点由 arena 统一释放；这样同时绕开递归布局与 ADT 无 drop glue 两个问题。
4. **暂不登记连带义务**：J-6 行、stable-subset、capabilities、idioms 第 11 条都等到
   ADR 通过、特性立项后再加；现在加会把“未批准特性”写成既定事实。

## 5. 需所有者裁决

1. 是否有“节点转换是原意图”的 ADR/评审记录？若没有，是否接受改按新特性立卡？
2. JSON 树用 **arena + 索引**，还是“每节点 owning + 显式 Drop”？
3. W3 放本仓还是 std 包？
4. 绑定点默认选 **严格 `to<T>`** 还是卡面的宽松 `as<T>`？

在这四条定稿前，本卡不宜进入 v1.0 实施队列。
