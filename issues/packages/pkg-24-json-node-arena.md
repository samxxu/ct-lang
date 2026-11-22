# PKG-24 · JSON 节点包：arena + 索引、NodeVec/NodeMap、schema 生成

| 项 | 值 |
| --- | --- |
| 模块 | packages（std 包 / 外部仓；不在 CT 仓计划） |
| 定性 | **新特性（包侧）**（所有者 2026-11-22 裁定） |
| 严重度 | Medium |
| 锚点 | v0.88.3（2026-11-22） |
| 依据 | [REQ 卡评估](../../docs/reviews/2026-11-22-req-node-conversion-protocol-eval.md)、[LANG-26](../lang/lang-26-binding-site-conversion.md) |
| 状态 | open |
| 处置证据 | **accepted（外部工作；外部目标 v1.0 前；不进入 CT `v1-release-plan`、roadmap 或门禁；不占编译器容量、不碰冻结）** |

> **归属**：本卡在 CT 仓**只作接口依赖记录**。JSON 库、NodeVec/NodeMap、schema 生成器的
> 交付、排期与验收由 std 包 / 外部仓负责；CT 仓只维护 LANG-26 的绑定点转换 ADR，
> 以及包需要的 `map trait` / 容器接口。外部包的进展不写进 CT 发布路线。

## 定位

JSON 库 + NodeVec/NodeMap 寄生映射 + schema 生成器放在 **std 包/外部仓**，
以包形态交付；编译器只提供 `map trait` 与既有容器能力。

## 节点模型（已定）

- **arena + 索引**：节点 = `(arena, 下标)` 对；`JsonNode` 子节点用整数索引：
  `Arr(Vec<int>)`、`Obj(Map<String,int>)`；不再用递归值内嵌。
- **所有权**：节点绑定 arena；**子树不跨文档**。arena 统一释放，绕开 ADT 无 drop glue
  与递归布局两个问题。
- **Map 键**：`Map<String,int>`（`Str` 不能作键）；键深拷贝成本在契约中明示。
- `Str` payload 若保留视图，必须由 arena 持有底层 `String`，生命周期覆盖整棵树。

## 交付

### W2 · NodeVec / NodeMap 寄生映射

- `nodevec.m.ct`：trait NodeVec（`to_int_vec` / `to_str_vec` / `sum` 等），宿主 `Vec<JsonNode>`；
- `nodemap.m.ct`：trait NodeMap（`to_int_map` / `sum_values` 等），宿主 `Map<String, JsonNode>`；
- 映射单元零 `.c/.h` 发射；**未 import 时零代码零体积**（`--emit-c` 产物无相关符号）；
- 未 import 调用 = 编译错，文案指向 nodevec/nodemap 单元。

### W3 · JSON 库本体

- 解析器 + 序列化器：字符串转义（fuzz，与解析共用向量）、double 最短往返、
  compact/pretty 两档；
- 泛型入口 `decode<T>(Str)` / `encode<T>(T)`；每 struct 的映射代码由
  **schema → ct 生成器**承担，不引入运行时反射；
- 手写 impl 作为无 schema 时的逃生层；
- 契约硬条款（DOC-91 格式，每条带负例）：读宽容 / 写严格 / `as`·`to` 分工 /
  键深拷贝成本 / 子树不跨文档 / 与其他格式互转预留。

## 与编译器的接口

- 裸写绑定点转换（`Vec<int> v = node;`）依赖 [LANG-26](../lang/lang-26-binding-site-conversion.md)；
  在 LANG-26 ADR 通过前，包侧只提供显式 `.to<T>()` / `decode<T>` 路径。
- 不新增编译器关键字、不改生成 C 语义、不占 `v1-PH-0` 的顶层函数预算。

## 验收

- 两个可跑示例：`User u = decode<User>(text)` 全字段往返、NodeVec/NodeMap 取值；
- 未 import 零体积；契约条款数 = 负例数；
- 包测试独立于编译器门禁；
- v1.0 前交付；失败不阻塞 v1.0（包侧独立回滚）。
