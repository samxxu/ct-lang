# Phase 34 — 生态可用性：`pub` 泛型函数、非泛型固有方法、`Option`/`Result`

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：`v0.30.0` @ `bd91bfe`；不 bump 版本、不打 tag。
> **文档形态**：`phase34-draft.md`；design window 12/12（phase20–31），32–36 共 5 张全部转正时按最老顺序归档 phase20–24。
> **deviation:** G4 `g4-size` 要求单份文档 ≤ 300 行；本卡约 300 行，需需求提出方签字保留单卡。
> **前置**：[phase31.md](phase31.md)（容器）、[phase33.md](phase33-draft.md)（泛型 struct / T31-2 消费方发射）、[phase26.md](phase26.md)（L26-2 的来源）。
> **排序理由**：它决定 Phase 31/33 的成果能否被包复用——没有 `pub` 泛型函数与跨单元固有方法，`Option`/`Result` 只能停留在模板所属单元。

## 1 目标与范围

### 1.1 一句话目标

让「泛型能力」从单单元自用变成**可被包复用**：`pub` 泛型函数跨单元实例化、非泛型固有方法跨单元调用、`Option<T>`/`Result<T,E>` 进入标准库；编译器侧 500–1,100 行，库代码不计入编译器预算。

### 1.2 范围（O1–O3）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | `pub` 泛型函数 | 解除 L26-2（`generic functions cannot be pub`，`Parser.h.ct:1110`），模板体随 `.h.ct` 暴露，消费方单元按需发 `static` 实例 |
| O2 | 非泛型固有方法跨单元 | `pub struct` 的 `impl` 方法（无方法级类型参数、接收者不是待单态化的泛型实例）由 `.h` 带原型、定义单元发符号，消费方直接调用 |
| O3 | `Option`/`Result` 标准库 | `lib/std/Option.h.ct`、`Result.h.ct`：泛型 **struct**（非泛型 enum）的构造、查询、取值、释放；库代码单列，不占编译器预算 |

### 1.3 非目标（本相明确不做）

- 不做泛型 enum/union；`Option`/`Result` 用泛型 struct + 标签实现，不新增语言构造。
- 不做 `Option` 的值 pattern matching、`?` 运算符、异常、`match` 语法糖。
- 不做泛型 trait（Phase 35）、supertrait、关联类型。
- 不做泛型 `Drop`、拥有式 payload 的自动释放（Phase 36）；本相 `Option`/`Result` 对 `own` payload 只提供显式 `release`。
- 不做方法级泛型、变参泛型、默认参数。
- 不改变非泛型函数/结构体的已发布 ABI 与命名；不改 vtable 布局。
- 不放宽 L26-1/L26-3–L26-5 的其他泛型诊断；L26-2 的变更单独评审（见 §1.4）。
- 不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 L26-2 变更（必须单独评审）

当前判据（[phase26.md](phase26.md)）：

> **L26-2** `pub` 泛型函数 → `generic functions cannot be pub`

变更内容：

- 允许 `pub T name<T>(...)`；模板体必须写在 `.h.ct`（源码头）中，消费方单元可见；
- 消费方单元为每个 `(模板, 具体类型)` 发 `static` 实例，实例名沿用 `<name>__ct<N>`；
- 生成 `.h` 仍只放类型，不放函数体/实例；
- 定义单元若也实例化同一组类型，允许存在同名的 `static` 副本（链接局部化），不产生重复全局符号；
- **其他 L26 规则不变**：忘记类型实参仍是 L26-1，多类型参数仍是 L26-3。

评审要求：本项必须独立提交、独立评审，卡内附「旧判据原文 / 新判据 / 影响面 / 回滚方式」；不得与其他切片混在一个提交。未通过评审前，O1 不实现。回滚方式：恢复 `Parser.h.ct:1110` 的拒绝与 `test/ast/errors/generic_pub.ct` 的期望文案。

### 1.5 依赖链

`Phase 31（容器）→ Phase 33（泛型 struct + T31-2 消费方发射）→ Phase 34 → Phase 35 → Phase 36`。

- O1/O2 的跨单元实例化依赖 P33 的消费方 `static` 发射机制；若 P33 的 T31-2 降级，O1 仍可做（函数体在 `.h.ct`），但 `Option<消费方类型>` 会受限。
- O3 的 `Option<Point>`（Point 在消费方单元）依赖 P33 的同一机制；P33 未落地时，`Option` 只保证 std/内建/同单元类型，跨单元用户类型给 L34-4。

## 2 现状与基线

### 2.1 门禁基线（`bd91bfe`）

`check-ast` 1073 / `test/run` 141 / `check-warnings` 353 / `check-docs` OK（1048 links，11 gates，window 12/12）。

### 2.2 红证探针

| 探针 | 命令 | 基线 |
| --- | --- | --- |
| `pub T id<T>(T x)` | `/tmp/ct-ast check /tmp/p34_pub.ct` | `generic functions cannot be pub`（`Parser.h.ct:1110`） |
| 跨单元调用非泛型固有方法 | 两单元 `ct build` 夹具（S0 建） | S0 记录当前错误/未定义符号；若已可用则转为回归锁，不重复实现 |
| `Option<int>` | `grep -r "struct Option" lib/std` | 无此文件/类型 |
| `Result<int, char *>` | 同上 | 无 |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| L26-2 拒绝 | `Parser.h.ct:1110` |
| 泛型实例命名 `<name>__ctN` | Phase 26 发射路径；`Parser.h.ct` 泛型解析 |
| `.h.ct` 模板可见性 | Phase 26 `/tmp` 审计与 `test/modules` 夹具 |
| 非泛型固有方法 | `Parser.h.ct:2694-2746`（impl 解析）、`ct_impl_add` `Symbols.h.ct:1620-1643` |
| 生成 `.h` 只放类型 | `test/run.sh` / `check-ast.sh` 的 `.h` 断言 |
| 标准库位置 | `lib/std/Vec.h.ct`、`lib/std/README.md` |

## 3 语义设计

### 3.1 O1 `pub` 泛型函数

- 解析：`pub` + `T name<T>(...)` 不再拒绝；模板标记与 Phase 26 相同（`N_FUNC.text3`）。
- 可见性：模板体必须在 `.h.ct` 中；若 `pub` 泛型函数定义在 `.ct` 实现单元，报 L34-1「pub generic function body must be in a header」。
- 实例化：消费方单元看到调用 `name<int>(...)` 时，用模板体在本单元发 `static` 实例 `<name>__ctN`；定义单元不重复发同一实例（若定义单元也调用，则各发各的 `static` 副本，链接允许）。
- 生成 `.h`：只放类型与函数**声明**？本项目硬边界是「生成的 `.h` 只放类型」，因此即使 `pub` 泛型函数也不把原型放进生成 `.h`；原型只在 `.h.ct`（源码层）中，消费方解析时可见。生成 `.c` 自包含。
- 与 Phase 33 的关系：泛型 struct 的实例方法仍按 P33 规则；本项只处理自由函数。

### 3.2 O2 非泛型固有方法跨单元

- 范围：方法自身无类型参数，且接收者是**非泛型 struct** 或**已具体化的泛型实例**（如 `Box<int>`）；`impl<T> Box<T>` 的泛型方法不在本项。
- 可见性：沿用 struct 的 `pub`；不为方法新增关键字。`pub struct` 的 `impl` 方法在 `.h.ct` 中可见，定义单元发一个全局符号 `<Struct>_<method>`；消费方直接调用。
- 生成 `.h`：只放类型；方法原型留在 `.h.ct` 源码头。若消费方只能看到生成 `.h` 而看不到 `.h.ct`，则本项不承诺——`ct build` 的单元输入是 `.h.ct`，与现有模块机制一致。
- 冲突：同一 struct 在两个单元各写 `impl` 同名方法 → L34-3 重复定义（现状诊断保持）。

### 3.3 O3 `Option` / `Result`

- 表示（库代码，不占编译器预算）：
  ```
  struct Option<T> { int has; T value; }
  struct Result<T, E> { int ok; T value; E err; }
  ```
- API（最小集）：`option_some<T>(T) -> Option<T>`、`option_none<T>() -> Option<T>`、`is_some`、`is_none`、`unwrap_or(T) -> T`、`release()`；`result_ok`、`result_err`、`is_ok`、`is_err`、`unwrap_or`、`release()`。
- 构造/查询函数是 `pub` 泛型函数（O1），方法是 `Option<T>` 上的非泛型固有方法（O2）——这正是本相两项编译器能力的消费者，库本身不需要新编译器特性。
- 布局：`Option<T>` 内联 `T`；`Option<Show>` 存接口值（Phase 31 的接口字段），`Option<Vec<int>>` 存容器值（Phase 31）。`Option<own T>` 的释放由 Phase 36 的泛型 Drop 接管；本相只提供显式 `release`。
- 不做 `Option` 的 `?`/pattern；库示例用 `is_some`/`unwrap_or`。
- 命名冲突：用户自定义 `Option` 与 std 同名 → 沿用 L29-W1 的 std 遮蔽告警；本相把它升级为**硬错**只在 `ct build` 的 std 预加载路径（L34-7），避免静默覆盖。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D34-1 | `pub` 泛型模板体放 `.h.ct`，消费方发 `static` 实例 | 消费者需要看到模板体才能单态化；`static` 避免重复全局 |
| D34-2 | 生成 `.h` 仍只放类型 | 硬边界；原型只在源码头 |
| D34-3 | L26-2 变更独立提交、独立评审、可回滚 | 用户明确要求；判据变更不得夹带 |
| D34-4 | 非泛型固有方法沿用 struct 的 `pub`，不新增方法关键字 | 最小语法面；与现有可见性模型一致 |
| D34-5 | `Option`/`Result` 用泛型 struct，不做泛型 enum | 泛型 enum 不在 Phase 29/33 范围；struct 版本可立即复用 |
| D34-6 | `Option`/`Result` 放 `lib/std`，不计编译器预算 | 用户明确库部分不占编译器预算 |
| D34-7 | `Option<消费方类型>` 依赖 P33 T31-2；未落地时 L34-4 | 泛型 struct 实例的归属单元与容器元素同构 |
| D34-8 | `own` payload 的自动释放推迟到 P36 | 泛型 Drop 是 P36 的轴 |
| D34-9 | std 同名遮蔽在 `ct build` 下硬错 | 生态复用需要确定性，不允许静默覆盖 |
| D34-10 | 不改 L26-1/L26-3–L26-5 | 只放开 `pub`，不放宽其他泛型诊断 |
| D34-11 | 不新增 `MAX_*` | 控制编译器结构体膨胀 |
| D34-12 | 不 bump、不打 tag | 与 31–33 纪律一致 |

## 5 Battle 记录

### B34-1 `pub` 泛型：头文件模板 vs 定义单元预实例化
采纳**头文件模板**。预实例化只能覆盖固定类型集，无法服务包消费者；头文件模板是 C++/Rust 泛型跨单元的标准做法。代价是 `.h.ct` 必须携带模板体，需在文档中写明。

### B34-2 生成 `.h` 是否放函数原型
不放。项目硬边界「生成的 `.h` 只放类型」优先；原型放源码头 `.h.ct`，消费方解析期可见。若评审认为必须放原型，需单独改硬边界，不在本相偷跑。

### B34-3 非泛型固有方法：新增 `pub` 方法关键字 vs 继承 struct 可见性
继承 struct 可见性。新增关键字会扩大语法面并影响所有 impl；本相只需要「`pub struct` 的方法可见」。

### B34-4 `Option`/`Result`：泛型 enum vs 泛型 struct
泛型 struct。泛型 enum 需要布局单态化 + 标签 + pattern，属于独立轴；struct 版本已能覆盖 `is_some`/`unwrap_or` 的生态用法。

### B34-5 库放 `lib/std` vs ct-pkg
放 `lib/std`（用户说“标准库”）；ct-pkg 侧是否镜像由用户在其仓库决定。`lib/std/README.md` 记录来源与去重清单。

## 6 实现切片

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | `bd91bfe` 重建二进制，复跑 §2.2 探针；L26-2 旧判据原文归档 | 无源码改动 | 0 |
| S1 | `pub` 泛型解析解禁 + `.h.ct` 模板体约束 + L34-1 | `Parser.h.ct` | 80–140 |
| S2 | 消费方 `static` 实例发射 + 去重 | `Emitter.h.ct` / `Parser.h.ct` | 100–180 |
| S3 | L26-2 判据变更独立提交 + 评审记录 | `docs/` + `test/ast/errors/generic_pub.ct` | 40–80 |
| S4 | 非泛型固有方法跨单元原型 + 符号 + L34-3 | `Parser.h.ct` / `Emitter.h.ct` | 80–150 |
| S5 | `Option.h.ct` + `Result.h.ct`（库，不计编译器预算） | `lib/std/**` | 250–500 |
| S6 | `Option`/`Result` 跨单元夹具 + L34-4 | `test/modules/**` | 100–180 |
| S7 | 编译器回归：既有 1073 条 + `.h` 类型-only 断言 | `check-ast.sh` | 60–120 |
| S8 | 样例 `examples/38_ecosystem_reuse`（两单元） | `examples/38_*` | 80–150 |
| S9 | 文档 + 全量门禁 | `docs/**` | 150–280 |

依赖：S1→S2→S3；S4 可与 S2 并行；S5 依赖 S1/S4；S6 依赖 S5；S7–S9 最后。

## 7 退出判据（E34-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E34-1 | `.h.ct` 中 `pub T id<T>(T)`，消费方调用 `id<int>(3)` 编译运行；实例为消费方 `static` | `test/modules/p34_pub_generic` | `check-ast` 跨单元块 | 当前 `generic functions cannot be pub` |
| E34-2 | L26-2 旧判据变更单独提交并附评审记录；`generic_pub.ct` 的期望被显式替换，其他 L26 诊断文案不变 | `errors/generic_pub.ct` + 评审记录 | `check-ast` | 当前文案逐字匹配 |
| E34-3 | `pub` 泛型函数带 bound `T: Show` 跨单元实例化；错误实参给 L33-1 同文案 | `test/modules/p34_pub_bound` | `check-ast` | 当前无法声明 `pub` |
| E34-4 | `pub struct Counter` 的非泛型固有方法从另一单元调用，运行正确 | `test/modules/p34_inherent` | `check-ast` 跨单元块 | S0 记录当前错误 |
| E34-5 | `Option<int>`：some/none/is_some/unwrap_or/release 输出逐字节正确 | `ast/211_option_basic` | `check-ast` + `test/run` | 当前无 `Option` |
| E34-6 | `Result<int, char *>`：ok/err/is_ok/unwrap_or/release 输出正确 | `ast/212_result_basic` | `check-ast` + `test/run` | 当前无 `Result` |
| E34-7 | `Option<Point>`（Point 在消费方单元）跨单元编译运行；ASAN 干净 | `test/modules/p34_option_owned` | `check-ast` + ASAN | 当前无 `Option`；P33 未落地时 L34-4 |
| E34-8 | `Option<Show>` 存接口值，`is_some`/`unwrap_or` 正确，无 vptr 读越界 | `ast/213_option_iface` | `check-ast` + ASAN | 当前无 `Option` |
| E34-9 | 嵌套 `Option<Option<int>>` 可构造/查询/释放 | `ast/214_option_nested` | `check-ast` | 当前无 `Option` |
| E34-10 | `enum Option<T>` 给出明确「泛型 enum 不支持」错误，不落到通用解析错 | `errors/generic_enum.ct` | `check-ast` | 当前通用解析错 |
| E34-11 | 生成 `.h` 仅类型；`nm` 无重复 `<name>__ctN` 全局；重复构建缓存键稳定 | 全部跨单元夹具 + 产物检查 | `check-ast` / CI | 当前无此路径 |
| E34-12 | 既有 1073 条断言零回退；非泛型函数/结构体产物逐字节不变 | 全量 | `check-ast` | 基线 1073 |
| E34-13 | 样例 `examples/38_ecosystem_reuse` 进入 `test/run.sh`，golden 人工核对 | `examples/38_*` | `test/run` | 当前不存在 |
| E34-14 | language-spec/tutorial/glossary/roadmap 写清 `pub` 泛型、跨单元固有方法、`Option`/`Result` 边界与 L26-2 变更 | `docs/**` | `check-docs` | 当前无表述 |

## 8 负例台账（L34-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L34-1 | `pub` 泛型函数体不在 `.h.ct` | `pub generic function body must be in a header` |
| L34-2 | `pub` 泛型函数的 bound trait 在消费方不可见 | `bound trait '<T>' is not visible in this unit` |
| L34-3 | 同一 struct 在两个单元定义同名固有方法 | 沿用重复定义诊断 |
| L34-4 | `Option<消费方类型>` 在 P33 T31-2 未落地时 | `this element type cannot cross a unit boundary yet` |
| L34-5 | `Option`/`Result` 与用户定义同名（`ct build` std 路径） | `std type '<name>' is shadowed by a user definition` |
| L34-6 | 泛型 enum 声明 | `generic enums are not supported` |
| L34-7 | `pub` 泛型函数缺少类型实参 | 沿用 L26-1 |
| L34-8 | `pub` 泛型函数多个类型参数 | 沿用 L26-3 |

## 9 样例计划

- **`examples/38_ecosystem_reuse`**（两单元）：库单元提供 `pub` 泛型函数 + `Option`/`Result` 包装 + 非泛型固有方法；应用单元调用并输出确定结果。
- 覆盖：`pub` 泛型跨单元、`Option<int>`、`Result<int, char *>`、`Option<Point>`（若 P33 落地）、非泛型固有方法。
- 编号：35 = P32，36–37 = P33，**38 = P34**。

## 10 估算

| 区 | 行数 | 文件数 |
| --- | --- | --- |
| 编译器（S1–S4、S7） | **500–1,100** | 4–6 |
| 夹具（S6–S7） | 250–450 | 10–18 |
| 文档 + 样例（S8–S9） | 150–280 + 样例 | 5–8 |
| 库代码（S5，**不计编译器预算**） | 250–500 | 2–4 |
| **编译器合计（不含库）** | **900–1,830** | **19–32** |

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R34-1 | `pub` 泛型实例在多个单元重复导致链接冲突 | 一律 `static`；E34-11 用 `nm` |
| R34-2 | `.h.ct` 模板体泄漏实现细节 | 文档明确「模板体必须可见」；生成 `.h` 仍只放类型 |
| R34-3 | 非泛型固有方法在 `.h.ct` 不可见 | 夹具同时覆盖 `.h.ct` 与生成 `.h` 的差异；不承诺生成 `.h` 可独立链接 |
| R34-4 | `Option<T>` 对接口/容器 payload 的布局 | 复用 Phase 31 的字段规则；E34-8 |
| R34-5 | std 同名遮蔽破坏既有项目 | L34-5 硬错 + L29-W1 迁移说明 |
| R34-6 | L26-2 变更被夹带进其他切片 | D34-3 独立提交；评审记录是 E34-2 的硬条件 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T34-1 | `Option`/`Result` 的 `?`/pattern | 有值 pattern 语法设计卡 |
| T34-2 | `own` payload 自动释放 | Phase 36 |
| T34-3 | 非泛型固有方法的生成 `.h` 原型 | 若硬边界调整，另立评审 |
| T34-4 | 泛型 enum | 独立轴，需布局单态化设计 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S4、S7 的实现与诊断。
- `lib/std/Option.h.ct`、`Result.h.ct`、`lib/std/README.md` 去重说明。
- `test/modules/p34_*`、`test/ast/errors/*`、`test/ast/211–214_*`。
- `examples/38_ecosystem_reuse/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。
- L26-2 变更评审记录（单独提交）。

## 13 收口与纪律

- **T-7 先红后绿**：S0 复跑探针并提交 `test(ecosystem): P34 红证`；L26-2 变更单独提交、单独评审。
- 每片 ≤3 文件、净增尽量 ≤150 行；仓库任何时刻可构建。
- 不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；不碰其他会话文件。
