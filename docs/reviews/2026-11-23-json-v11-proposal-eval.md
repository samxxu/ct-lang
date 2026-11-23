# 对《ct/json 包与 JSON 原生体验提案（v1.1）》的评估

> 评估对象：2026-11-23 提案（USER 签字），v1.1 一步到位。
> 核对基线：本仓 `main`（v0.88.3，DOC-87 Stage 2 / LANG-23 / SH-115 已合入）。
> 方法：逐条对照 spec §4.51/§4.56/§4.70/§4.73/§4.74，并用本仓 `.temp/verify-current/ct-ast`
> 跑最小探针；不改代码。
> 结论先行：**北极星（格式无关、无 as/to、整树自动释放）合理，但提案按现稿不可实现**。
> 它把 4 个“尚不存在”当成已存在：递归 ADT 布局、ADT 方法、ADT drop glue、`map binding`；
> 另有 3 处语法/语义与现行语言直接冲突。建议改写成“arena/struct 包装”的低风险版，
> 或先落 LANG-27 + 递归布局 + ADT glue 再谈一步到位。

## 1. 硬阻断（按证据排序）

| # | 提案断言 | 实测 | 结论 |
| --- | --- | --- | --- |
| 1 | `enum JsonNode { Null; Bool(...); … }` | ADT 变体用**逗号**；`Null;` 与带负载成员混用报 `unexpected token` | 语法不成立；改逗号 + `Null()` |
| 2 | `Arr(Vec<JsonNode>)` / `Obj(Map<String,JsonNode>)` 是定长句柄，尺寸层无环 | 修正语法后生成 C 仍是 `struct Vec_JsonNode` / `Map_String_JsonNode` 前向声明，`cc` 报 `field has incomplete type` | **递归 payload 仍不能值内嵌**；需要指针/间接或 arena |
| 3 | `impl JsonNode { pub JsonNode at(...) }` | `impl` 只接受 struct/trait；enum 报 `impl for undefined struct` / `impl of an unknown trait` | ADT 目前**没有任何方法宿主** |
| 4 | `pub trait ScalarBridge` + 编译器直接路由 | ADT 不能 `impl` trait，也不生成 vtable；内核也没有“按名字直接路由某 trait”的机制 | 需要新的内建特例或改用 struct 节点 |
| 5 | `map binding JsonNode -> int { from(...) }` | parser 在 `map binding` 处报 `expected 'trait'`；现行 `map` 只接 `trait` | 新语法不存在，且与 D-020 的查找规则冲突 |
| 6 | `self.email match { some(s) => … }` 作表达式 | `match` 只有语句形式；表达式位置报 `unexpected token` | 语法不成立 |
| 7 | `some(s)` / `none` 匹配 `Option` | `Option` 是普通 struct（`has` + `value`），不是 ADT 变体 | 模式不成立 |

补充：`Bool(bool b)` 的生成 C 字段是裸 `bool`，当前产物没有 `<stdbool.h>`，
`cc` 报 `unknown type name 'bool'`；这条是 ADT 布局之外的第二个编译阻断。

## 2. 设计冲突

1. **“JSON 进门后就是普通 Map/Vec 树”不成立**：`json_parse` 返回 `JsonNode`（ADT），
   `doc["user"]` 仍是 `JsonNode`；消费端要判别时仍 `match` 五个 JSON 变体，
   格式知识没有消失，只是从“Map/Vec”挪到了“ADT 变体”。
2. **`doc["user"]["age"]` 不是绑定点**：中间 `doc["user"]` 要作下一跳接收者，
   需要 ADT 自定义下标 + 临时接收者链；两者当前都不存在（`[]` 只覆盖内置容器/单层自定义，
   `impl JsonNode` 又不成立）。`foreach (root["items"])` 同理——foreach 源不是绑定点，
   不能靠“绑定点转换”把 `JsonNode` 变成容器。
3. **ADT drop glue 被标成“可选加速”，实际是必需项**：spec §4.73 明确 ADT 不生成 drop glue；
   `Str(String s)`、`Arr(Vec<JsonNode>)`、`Obj(Map<...>)` 的 owning payload 不会自动释放。
   LANG-27 只解决 `Vec/Map` 字段级联，不解决 ADT payload；没有 ADT glue，“整树自动释放”不成立。
4. **提案反转了已定的 arena + 索引**：2026-11-22 所有者裁决是 arena + 索引；
   LANG-27 的唤醒条件写的是“容器级联落地/递归布局通过后 30 天再评估”，提案直接跳到
   无 arena 一步到位，缺少新的决策记录。
5. **`map binding` 与 D-020 冲突**：D-020 只定义“固有方法 + 已 import 映射 trait”的查找；
   提案新增第三套注册表。要么改 ADR，要么用现有 `map trait` 表达。
6. **`*.json.ct` 自动包含 + `.gitignore`**：`ct build` 当前靠 import/单元解析；
   自动 glob 生成文件是新的构建规则；生成物不入库又要求 clone 后先跑外部 `ct-gen`，
   否则 `ct build` 直接缺单元。可复现性需要另定契约。

## 3. 可保留的部分

- **语言层零格式知识**、core 不出现 json/xml 字样：方向正确，应作为验收；
- **绑定点转换**（D-020）作为唯一隐式入口，表达式内禁转：正确，继续用；
- **schema 生成器**（ct-gen）不引入运行时反射：正确，但它属外部工具，不占 CT 计划；
- **Option 表示 null、缺字段/类型错的 warning/default/strict 三档**：可保留为包契约；
- **`ct/tree` 只提供契约、不预演 trait**：克制，合理。

## 4. 与仓库现状的依赖核对

| 提案依赖 | 实际状态 | 结论 |
| --- | --- | --- |
| 通用绑定点扩展协议（`map binding`） | 只有 D-020 的 `as<T>` / `.to<T>`；没有 `map binding` | 需新 ADR，或改用 `map trait` |
| ScalarBridge（lib/core） | ADT 不能 impl 任何 trait；没有内建路由 | 不成立 |
| LANG-27 容器级联 | `deferred`，唤醒条件未触发 | 不能当作 v1.1 已交付 |
| ADT drop glue | 非目标（spec §4.73） | 必需但未立项 |
| 递归 ADT 布局 | 当前不能闭合 | 未解决 |
| ct/json、ct/tree、ct-gen | 外部包/工具 | 不进 CT 路线 |

## 5. 处置建议

**不按现稿批准 v1.1 一步到位。** 两条可行路线：

- **路线 A（低风险，推荐先做）**：保留 arena + 索引；把“节点”做成 **struct 包装**
  （`JsonDoc` / `JsonNode` struct 持有 arena 与下标），`at` 用固有 impl（struct 支持），
  `doc["user"]` 走自定义下标，最终绑定用 D-020 转换。这样不需要递归 ADT、ADT 方法、
  ADT drop glue；`ScalarBridge` 也可做成普通 trait（struct 可 impl）。
- **路线 B（真树）**：先落地 LANG-27（容器级联）+ 递归 ADT 的指针/间接布局 + ADT drop glue，
  并满足 LANG-27 的唤醒判据后，再评估“无 arena”方案；在此之前不承诺 v1.1 一步到位。

**所有者裁决（2026-11-23）**：顺序固定为 **先落地 LANG-27，再评估方案 B**；
本提案不按 v1.1 一步到位批准，LANG-27 合入前不启动“无 arena”树存储方案。

同时：
1. `map binding` 与 `ScalarBridge` 若要保留，先立语言 ADR，不要与 JSON 包捆绑；
2. `ct-gen` 的 `*.json.ct` 自动包含规则另立构建契约（含 clone 后可复现）；
3. 文档层面把“JSON 树存储”的决策与 LANG-27 唤醒条件保持单一来源，避免两份口径。

## 6. 结论

提案的**用户体验目标**值得保留；但当前文本把 4 个不存在的语言能力写成了既定事实，
并反转了已定的 arena 决策。按仓库现状，`enum` 语法、递归布局、ADT 方法、ADT drop glue、
`map binding`、`match` 表达式六项都过不了编译/规范检查。建议按路线 A 改写，或先把
LANG-27 + 布局 + ADT glue 做成前置里程碑，再谈“无 arena 一步到位”。
