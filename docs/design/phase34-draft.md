# Phase 34 — 生态可用性：`pub` 泛型函数、非泛型固有方法、`Option`/`Result`

> **状态：规划中**（2026-11-11 立项草案；**不写实现**）。
> **基线**：**Phase 33 落地并推送后确定**（P33 是硬前置；不预钉 `v0.30.0` 或 `bd91bfe`）；S0 在**实现提交的父提交**上重建二进制并复跑 §2.2 探针，红证必须记录 `baseline: <sha>`，复跑结果与父提交不一致时不得开工。
> **文档形态**：`phase34-draft.md`；design window 12/12，**每次转正归档当时最老的一张**（32 → phase20，33 → phase21，34 → phase22，35 → phase23，36 → phase24）。
> **前置**：[phase31.md](phase31.md)（容器）、[phase33.md](phase33-draft.md)（泛型 struct 与跨单元实例归属）、[phase26.md](phase26.md)（L26-2 的来源）。**P33 是硬前置**：P33 未落地则本相暂停，不提供降级分支。
> **排序理由**：没有 `pub` 泛型函数与非泛型固有方法，`Option`/`Result` 只能停留在模板所属单元，Phase 31/33 的成果无法被包复用。

## 1 目标与范围

### 1.1 一句话目标

让泛型能力从单单元自用变成**可被包复用**：`pub` 泛型函数跨单元实例化、**新增非泛型固有 `impl Name { … }` 并支持跨单元调用**、`Option<T>`/`Result<T,E>` 进入 `lib/std`；编译器侧按 §10 的切片求和计。

### 1.2 范围（O1–O3）

| 编号 | 范围 | 交付 |
| --- | --- | --- |
| O1 | `pub` 泛型函数 | 解除 L26-2，模板体随 `.h.ct` 暴露，消费方单元按需发 `static` 实例 |
| O2 | 非泛型固有方法 | **新增 `impl Counter { … }` 语法**（今天只支持 `impl<T> Name<…>` 走固有分支，见 §2.2）；方法按 `<Struct>_<method>` 命名、静态派发，并支持 `pub` struct 的跨单元可见 |
| O3 | `Option`/`Result` 标准库 | `lib/std/Option.h.ct`、`Result.h.ct`：泛型 **struct** 的构造、查询、取值、释放；库代码单列，不占编译器预算 |

### 1.3 非目标（本相明确不做）

- 不做泛型 enum/union（承接项见 [phase35-draft.md](phase35-draft.md) 的 T35-6）；`Option`/`Result` 用泛型 struct + 标签实现。
- 不做 `Option` 的 pattern matching、`?`、异常、`match` 语法糖。
- 不做泛型 trait、supertrait、关联类型（Phase 35）。
- 不做泛型 `Drop`、拥有式 payload 的自动释放（Phase 36）；本相 `Option`/`Result` 对 payload 只提供显式 `release`。
- 不做方法级泛型、变参泛型、默认参数；不做跨单元重复方法定义的解析期检测（落到链接期，见 R34-4）。
- 不改变非泛型函数/结构体的已发布 ABI 与命名；不改 vtable 布局。
- 不放宽 L26-1/L26-3–L26-5；L26-2 的变更单独评审（§1.4）。
- 不新增 `MAX_*`；不触碰冻结层 `l0/l1/l2`。

### 1.4 L26-2 变更（独立提交、独立评审、可回滚）

当前判据（[phase26.md](phase26.md)）：**L26-2** `pub` 泛型函数 → `generic functions cannot be pub`。

变更内容：允许 `pub T name<T>(...)`；模板体必须写在 `.h.ct`（源码头）中；消费方为每个 `(模板, 具体类型)` 发 `static` 实例，实例名沿用 `<name>__ct<N>`；生成 `.h` 仍只放类型；定义单元与消费方各发同名 `static` 副本不产生重复全局符号；其他 L26 规则不变。

**影响面清单：代码 1 + 可执行断言 3 + 夹具 2 + 规范文档 6**（6 = 6 个影响点：language-spec 两处同改算 1 点，phase29 三处合并算 1 点）：

| 类别 | 位置 | 现状 / 处置 |
| --- | --- | --- |
| 代码 | `frontend/parse/Parser.h.ct:1110` | `return fail("generic functions cannot be pub")` |
| 可执行断言 | `selfhost/check-ast.sh:1397` | `p26_diag generic_pub 2:9 "…"` |
| 可执行断言 | `selfhost/check-ast.sh:1435` | `p26_chk generic_pub "…"` |
| 可执行断言 | `selfhost/check-ast.sh:5859` | E29-13/B6 期望旧文案 |
| 夹具 | `test/ast/errors/generic_pub.ct` | 位于 `errors/`，必须转正 |
| 夹具 | `test/modules/errors/generic_struct_pub_fn.ct` | 位于 `errors/`，必须转正 |
| 规范文档 | `docs/design/phase26.md:186` | 表格行不动；superseding 块加在 DOC-67 补充段之后、§2.6 之前 |
| 规范文档 | `docs/design/phase26.md:262-265` | TEST-18 的「`pub` 泛型已被 L26-2 拒绝」理由已假；改写理由，并在同一提交给 TEST-18 加 `test/modules/p34_*` 扫描钩子（否则 `tparam_residue` 扫不到新实例） |
| 规范文档 | `docs/design/phase26.md:537` | v0.25.0 vs v0.26.0 历史对照表：**只加脚注，不改写** |
| 规范文档 | `docs/language-spec.md:1913-1914`、`:4349-4350` | 两处 L26-2 码行与文案 |
| 规范文档 | `docs/design/phase29.md:912`、`:920`、`:987` | 三处合并计 1 个影响点；**Phase 29 文件一字不动**，只在 P34 卡内加「P34 覆盖」说明 |
| 规范文档 | `docs/modern-oo-gap.md:90` | 改为标注「已在 P34 关闭（`pub` 泛型 + 跨单元固有方法）」 |

`docs/history/reports/review-phase26.md:96` 是冻结的历史报告，**不参与回滚**。

**两个 `errors/` 夹具必须移出**：`test/ast/errors/` 的判据是「非零退出」，放开后退出 0 会挂门禁。`generic_pub.ct` 转正为 `test/ast/228_pub_generic_fn/prog.ct` 正例；`generic_struct_pub_fn.ct` 转正为 `test/modules/p34_pub_generic_export/` 正例，`check-ast.sh:5859` 改为断言其**编译运行成功**。

**E29-13/B6 只做纯增量，不自证批准**：`phase29.md:912`/`:920`/`:987` 原文一字不动，Phase 29 的任何判据都不改；只在**本卡**加一条「P34 覆盖：L26-2 已解禁，B6 的旧负例不再成立，P34 用 `p34_pub_generic_export` 正例覆盖」的说明。若实现时确认必须改 Phase 29 文件，标记 **blocked** 并删掉该改动，不得自行宣告批准。E34-2b 只做这条卡内说明，不触碰 phase29 文件。

回滚方式：恢复 `Parser.h.ct:1110`，恢复 **3 处可执行断言 + 2 个夹具的失败期望**；规范文档按上表逐项还原（`phase26.md:186` 去 superseding、`262-265` 恢复旧理由、`537` 去脚注、language-spec 两处、`phase29.md:912` 去覆盖条目、`modern-oo-gap.md:90`）。`phase26.md:537` 只是脚注，不属于「必须恢复的断言」。

### 1.5 依赖链

`Phase 31（容器）→ Phase 33（泛型 struct + 跨单元实例归属）→ Phase 34 → Phase 35 → Phase 36`。

- O1/O2 的跨单元实例化依赖 P33。
- O3 的 `Option<Point>`（Point 在消费方单元）依赖 P33；**P33 未落地时本相不开工**，不设降级分支。

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.30.0 发版）：`check-ast` 1073/0、`test/run` 141/0、`check-warnings` 353/0、`check-docs` 1070 links / 185 files、`design window 12/12`。这些数字**不是判据**；S0 必须在 **Phase 33 收口提交**上实测并替换本节，之后所有 E 判据只引用 S0 的实测值。

### 2.2 红证探针（2026-11-11 实测）

| 探针 | 命令 | 基线输出 |
| --- | --- | --- |
| `pub T id<T>(T x)` | `ct-ast test/ast/errors/generic_pub.ct` | `2:9: error: generic functions cannot be pub` |
| 非泛型固有 `impl Counter { … }` | `ct-ast /tmp/p34_inherent.ct` | `3:14: error: impl of an unknown trait` |
| `enum Option<T>` | `ct-ast /tmp/p34_enum.ct` | `1:12: error: unexpected token` |
| `Option<int>` / `Result<int, char *>` | `grep -r "struct Option" lib/std` | 无此文件/类型 |
| `Option<Show>` | `ct-ast /tmp/p34_opt_iface.ct` | **今天已可编译**，产物含 `struct Option_Show__iface`；本相**不记作新能力**，只锁 API 语义与产物形状 |

### 2.3 关键代码锚点

| 主题 | 位置 |
| --- | --- |
| L26-2 拒绝 | `frontend/parse/Parser.h.ct:1110` |
| `impl Trait for Struct` 入口 | `frontend/parse/Parser.h.ct:2419-2465`（名字后非 `<` 走 trait 路径） |
| `impl<T> Name<…>` 固有分支 | `frontend/parse/Parser.h.ct:2671-2760`（`use Drop` 也在 2756 校验） |
| 固有方法查找 | `frontend/parse/Expr.h.ct:2996-3015`（要求 `ct_inst_find(base) >= 0`，非泛型 struct 今天返回 -1） |
| 泛型实例编码 | `frontend/sym/Symbols.h.ct:1778-1808`（`ct_inst_encode`） |
| 生成 `.h` 只放类型 | `frontend/module/Module.h.ct:1541-1556`、`Emitter.h.ct:emit_unit_header` |
| `.h.ct` 才可被 import | `frontend/module/Module.h.ct:393`（`only a .h.ct unit can be imported`） |
| 标准库位置 | `lib/std/Vec.h.ct`、`lib/std/README.md` |

## 3 语义设计

### 3.1 O1 `pub` 泛型函数

- 解析：`pub` + `T name<T>(...)` 不再拒绝；模板标记与 Phase 26 相同。
- 可见性：模板体必须在 `.h.ct` 中。**不新增诊断**：`.ct` 单元的 `pub` 声明本来就不可被 import，既有 `only a .h.ct unit can be imported` 已覆盖。
- 实例化：消费方看到 `name<int>(...)` 时用模板体在本单元发 `static` 实例；生成 `.h` 仍只放类型，原型只在源码头。
- 与 Phase 33 的关系：泛型 struct 的实例方法仍按 P33 规则；本项只处理自由函数。

### 3.2 O2 非泛型固有方法（新增语法 + 新增派发）

今天只有 `impl<T> Box<T>` 这一形态进入固有分支；`impl Counter { … }` 报 `impl of an unknown trait`。因此 O2 不是"跨单元可见性"一项，而是三件事：

1. **语法**：`parse_impl` 在名字后既不是 `<`、也不是 `for` 时，按固有 impl 解析（需要与「trait 名后必须有 `for`」的既有错误区分）。
2. **派发**：`inst_inherent_method` / `inst_static_method` 今天要求 `ct_inst_find(base) >= 0`；非泛型 struct 没有实例行，查找必须回落到 struct 行与本地 impl 表。
3. **跨单元**：`pub struct` 的 `impl` 写在 `.h.ct` 中，方法以 `<Struct>_<method>` 发一个全局符号。生成 `.h` 仍只放类型，因此**消费方必须为自己的调用合成原型**：`c.get()` 展开为 `Counter_get(&c)` 后，消费方 `.c` 要在首次调用前写出 `int Counter_get(struct Counter *);`。**C99 已删除隐式函数声明**，clang `-std=c99` 直接报 `error: call to undeclared function 'Counter_get'; ISO C99 and later do not support implicit function declarations`；与 `-Werror` 无关。定义只由属主单元发一次，消费方只发原型。

- 冲突：同单元同名方法沿用既有重复定义诊断；**跨单元重复定义不作解析期检测**（impl 表按单元隔离），落到链接期重复符号，登记为 R34-4 的已知限制，不承诺硬错。
- 不做方法级类型参数；`impl<T> Box<T>` 的泛型方法仍是 P33 范围。

### 3.3 O3 `Option` / `Result`

- 表示（库代码，不占编译器预算）：`struct Option<T> { int has; T value; }`、`struct Result<T, E> { int ok; T value; E err; }`。
- API（最小集）：`option_some/option_none/is_some/is_none/unwrap_or/release`；`result_ok/result_err/is_ok/is_err/unwrap_or/release`。
- 构造/查询是 `pub` 泛型函数（O1），方法是非泛型固有方法（O2）——库本身不需要新编译器特性。
- `Option<Show>` 今天已编译为 `struct Option_Show__iface`（字段为 `struct Show_iface value;`），本相沿用该形状，不改名、不加新能力；`Option<Vec<int>>` 依 Phase 31 的容器值规则。
- **同名冲突不使用硬错**：用户自定义 `Option` 与 `import std/option` 同单元重名时，沿用既有「同单元重复类型定义」诊断；`vendor/std` 遮蔽维持 L29-W1 告警，避免误伤用户自定义类型。

## 4 决策表

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D34-1 | `pub` 泛型模板体放 `.h.ct`，消费方发 `static` 实例 | 单态化需要模板体；`static` 避免重复全局 |
| D34-2 | 生成 `.h` 仍只放类型 | 硬边界；原型只在源码头 |
| D34-3 | L26-2 变更独立提交、独立评审、可回滚 | 判据变更不得夹带；§1.4 列全影响面 |
| D34-4 | **新增 `impl Name { … }` 语法**，方法沿用 struct 的 `pub` | 今天不支持非泛型固有 impl；新增关键字会扩大语法面 |
| D34-5 | `Option`/`Result` 用泛型 struct，不做泛型 enum | 泛型 enum 需布局 + pattern，独立轴（T35-6） |
| D34-6 | `Option`/`Result` 放 `lib/std`，不计编译器预算 | 用户明确库部分不占预算 |
| D34-7 | `Option<消费方类型>` 依赖 P33，不设降级分支 | 两分支判据不可证伪 |
| D34-8 | `own` payload 的自动释放推迟到 P36 | 泛型 Drop 是 P36 的轴 |
| D34-9 | 同名类型冲突沿用既有诊断，不升级为硬错 | 硬错会误伤用户自定义 `Option` |
| D34-10 | 不改 L26-1/L26-3–L26-5 | 只放开 `pub` |
| D34-11 | 不新增 `MAX_*` | 控制结构体膨胀 |
| D34-12 | 不 bump、不打 tag | 与 31–33 纪律一致 |
| D34-13 | E29-13/B6：只做纯增量，Phase 29 文件与判据不动；必须改则标 blocked | 已收口判据不能由本卡自行宣告批准或改写 |

## 5 Battle 记录

### B34-1 头文件模板 vs 定义单元预实例化
采纳头文件模板。预实例化只能覆盖固定类型集，无法服务包消费者。

### B34-2 生成 `.h` 是否放函数原型
不放。硬边界「生成的 `.h` 只放类型」优先；若评审认为必须放原型，需单独改硬边界。

### B34-3 非泛型固有 impl：新增语法 vs 伪装成 trait
必须新增语法。实测 `impl Counter { … }` 今天报 `impl of an unknown trait`，把它映射到合成 trait 会让每个 struct 都多一个假 trait 行，且与 `MAX_TRAITS=64` 冲突。

### B34-4 `Option`/`Result`：泛型 enum vs 泛型 struct
泛型 struct。泛型 enum 需要布局单态化 + 标签 + pattern，属独立轴。

### B34-5 库放 `lib/std` vs ct-pkg
放 `lib/std`；ct-pkg 侧镜像由用户在其仓库决定，`lib/std/README.md` 记录去重清单。

### B34-6 L26-2 的影响面与回滚
见 §1.4。评审要求"旧判据 / 新判据 / 影响面 / 回滚方式"四件套；回滚必须覆盖代码 1 处、可执行断言 3 处、夹具 2 个、规范文档 6 处（其中 `phase26.md:537` 只是脚注，不属于必须恢复的断言），只恢复代码视为未回滚。

### B34-7 `Option<Show>` 是否算 P34 新能力
不算。实测今天已生成 `struct Option_Show__iface`；本相只锁 API 与产物形状，不重复计入 P31/P34 的能力清单。

## 6 实现切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 依赖落地后的父提交上重建、复跑 §2.2、归档 L26-2 旧判据原文 | 无源码改动 | 0 |
| S1a | `pub` 泛型解析解禁 + 泛型 enum 守卫（L34-3） | `Parser.h.ct` | 45–80 |
| S1b | 模板体归属 `.h.ct` + 消费方可见性 | `Parser.h.ct` / `Emitter.h.ct` | 50–90 |
| S2a | 消费方 `static` 实例发射 | `Expr.h.ct` / `Emitter.h.ct` | 60–110 |
| S2b | 实例去重与 `<name>__ct<N>` 命名 | `Emitter.h.ct` | 50–90 |
| S3a | L26-2 判据变更：断言改向、两个 `errors/` 夹具转正、TEST-18 加 `test/modules/p34_*` 钩子 + `p34_residue_dirty` 受控脏夹具（断言 `tparam_residue` 必失败） | `check-ast.sh` / `test/**` | 30–60 |
| S3b | 规范文档影响面：phase26 superseding 块、262-265、537 脚注、language-spec 两处、gap | `docs/**` | 20–50 |
| S4 | `impl Name { … }` 固有 impl 解析 | `Parser.h.ct` | 70–110 |
| S5a | 非泛型固有方法查找与静态派发 | `Expr.h.ct` | 60–100 |
| S5b | 跨单元 `<Struct>_<method>` 符号、消费方原型合成（拼写固定为 `int Counter_get(struct Counter *);`）与 `.h.ct` 可见 | `Emitter.h.ct` / `Module.h.ct` | 80–140 |
| S6 | 编译器回归：`.h` 类型-only + `nm` 无重复实例 + 双目录 cache key 方向性断言 | `check-ast.sh` | 60–110 |
| S7 | `Option`/`Result` 基本夹具 | `test/ast/**` | 100–150 |
| S8 | 跨单元夹具：`Option<Point>`、固有方法；`Option<Show>`/嵌套产物夹具 | `test/**` | 80–130 |
| S9a | `Option` 核心（表示/构造/查询/release），**库片** | `lib/std/Option.h.ct` | 70–140 |
| S9b | `Option` 其余 API，**库片** | `lib/std/Option.h.ct` | 60–110 |
| S9c | `Result` 核心，**库片** | `lib/std/Result.h.ct` | 70–140 |
| S9d | `Result` 其余 API，**库片** | `lib/std/Result.h.ct` | 50–110 |
| S10 | 样例 `examples/38_ecosystem_reuse`（两单元） | `examples/38_*` | 80–150 |
| S11a | 文档 | `docs/**` | 80–120 |
| S11b | 全量门禁与收口记录 | 无源码改动 | 20–40 |

依赖：S1a→S1b→S2a→S2b→S3a→S3b；S4→S5a→S5b；S9 依赖 S1/S4；S7–S8 依赖 S9；S10–S11 最后。

## 7 退出判据（E34-n）

| ID | 断言 | 夹具 | 门禁 | 红证 |
| --- | --- | --- | --- | --- |
| E34-1 | `.h.ct` 的 `pub T id<T>(T)` 在消费方 `id<int>(3)` 编译运行；实例为消费方 `static` | `test/modules/p34_pub_generic` | `check-ast` modules 段 | 当前 `generic functions cannot be pub` |
| E34-2a | L26-2 主提交：`check-ast.sh` 三处断言改向、两个 `errors/` 夹具转正、**`test/modules/p34_residue_dirty/` 受控脏夹具（产物故意留一个 `T`，断言 `tparam_residue` 必失败，证明钩子不是空操作）**、`phase26.md` 的 `262-265` 改写理由并接 `test/modules/p34_*` 钩子、`537` 只加脚注、language-spec 两处与 gap 更新 | 上述夹具 + `check-ast.sh` + 提交记录 | `check-ast` | 当前三处断言逐字匹配旧文案；TEST-18 不扫 modules |
| E34-2b | Phase 29 纯增量说明（**人工审查项，非门禁**）：Phase 34 卡内含且仅含一条 `P34 覆盖`；`phase29.md:912`/`:920`/`:987` 一字不动；若必须改 phase29 则标 blocked 并删除该改动 | `docs/design/phase34-draft.md` | 人工审查 | 当前无覆盖说明 |
| E34-3 | `pub` 泛型带 bound `T: Show` 跨单元实例化；`test/modules/errors/p34_bound_hidden/`（`main.ct` + `dep.h.ct`）触发既有 `unknown trait '<x>' in a generic bound` | `test/modules/p34_pub_bound` + `test/modules/errors/p34_bound_hidden/` | `check-ast` modules 段（正例与错误段） | 当前无法声明 `pub` |
| E34-4 | `pub struct Counter` 的非泛型固有方法从另一单元调用并运行。**主判据**：`nm -g --defined-only` 在属主 `.c` 恰 1 个 `T Counter_get`，`nm -g --undefined-only` 在消费方 `.c` 恰 1 个 `U Counter_get`；**辅助**：消费方原型 `grep -c '^int Counter_get(struct Counter \*);$' == 1`、属主定义 `grep -c '^int Counter_get(struct Counter \*.*) {' == 1`（重复定义先链接失败） | `test/modules/p34_inherent` + `nm` + 产物 grep | `check-ast` modules 段 | 当前 `impl of an unknown trait` |
| E34-5 | `Option<int>` 的 some/none/is_some/unwrap_or/release 输出逐字节正确 | `ast/215_option_basic` | `check-ast` | 当前无 `Option` |
| E34-6 | `Result<int, char *>` 的 ok/err/is_ok/unwrap_or/release 输出正确 | `ast/216_result_basic` | `check-ast` | 当前无 `Result` |
| E34-7 | `Option<Point>`（Point 在消费方单元）跨单元编译运行；产物含 `struct Option_Point` | `test/modules/p34_option_point` | `check-ast` modules 段 | 当前无 `Option` |
| E34-8 | `Option<Show>` 的 `is_some`/`unwrap_or` 正确；产物为 `struct Option_Show__iface { int has; struct Show_iface value; }` | `ast/217_option_iface` + 产物 grep | `check-ast` | 今天可编译，仅缺 API |
| E34-9 | `Option<Option<int>>` 可构造/查询/释放 | `ast/218_option_nested` | `check-ast` | 当前无 `Option` |
| E34-10 | `enum Option<T>` 给 `generic enums are not supported`（L34-3） | `errors/generic_enum.ct` | `check-ast` | 当前 `1:12: unexpected token` |
| E34-11 | 生成 `.h` 仅类型；`nm` 无重复 `<name>__ctN`；缓存键：用两个干净的 `-o` 目录分别构建 A/B，比较 `.ctcache/*.key` 字节一致；`touch -m -t 203001010000 a.h.ct` 后先 `stat -f %m` 断言 mtime 已变，再重建 B，**B 的 key 必须改变** | 全部跨单元夹具 + 产物检查 | `check-ast` | 当前无此路径 |
| E34-12 | 既有断言零回退；非泛型函数/结构体产物逐字节不变 | 全量 | `check-ast` | S0 实测计数 |
| E34-13 | 样例 `examples/38_ecosystem_reuse` 进入 `test/run.sh`，golden 人工核对 | `examples/38_*` | `test/run` | 当前不存在 |
| E34-14 | language-spec/tutorial/glossary/roadmap 写清 `pub` 泛型、跨单元固有方法、`Option`/`Result` 边界与 L26-2 变更 | `docs/**` | `check-docs` | 当前无表述 |
| E34-15 | `pub` 泛型缺类型实参 → L26-1；两个类型参数 → L26-3；两个夹具各自恰一条断言并钉住位置 | `errors/p34_pub_missing_arg.ct`、`errors/p34_pub_two_params.ct` | `check-ast` | 当前先被 L26-2 拦截 |

## 8 负例台账（L34-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L34-1 | `pub` 泛型缺类型实参 | `errors/p34_pub_missing_arg.ct` | 沿用 L26-1，恰一条 |
| L34-2 | `pub` 泛型两个类型参数 | `errors/p34_pub_two_params.ct` | 沿用 L26-3，恰一条 |
| L34-3 | 泛型 enum | `errors/generic_enum.ct` | `generic enums are not supported` |

三条负例均有夹具与 `check-ast` 断言。**只有 L34-3 是新诊断**；L34-1/L34-2 分别是既有 L26-1/L26-3 的用例，不新增文案。原先的「bound trait 在消费方不可见」不是新 L：它是 E34-3 的模块回归断言（`test/modules/errors/p34_bound_hidden/`），用的是既有诊断，故不列入 L 台账。

## 9 样例计划

- **`examples/38_ecosystem_reuse`**（两单元）：库单元提供 `pub` 泛型函数 + `Option`/`Result` + 非泛型固有方法；应用单元调用并输出确定结果。
- 覆盖：`pub` 泛型跨单元、`Option<int>`、`Result<int, char *>`、`Option<Point>`、非泛型固有方法。
- 编号：35 = P32，36–37 = P33，**38 = P34**。

## 10 估算（= 各切片求和）

| 区 | 组成 | 行数 | 文件数 |
| --- | --- | --- | --- |
| 编译器 | S1a+S1b+S2a+S2b+S4+S5a+S5b | **415–720** | 4–6 |
| 夹具与断言 | S3a+S6+S7+S8 | 270–450 | 12–20 |
| 文档 + 样例 | S3b+S10+S11a+S11b | 200–360 | 6–9 |
| **编译器外合计** | 夹具/断言 + 文档/样例 | **470–810** | 18–29 |
| 库代码（S9a+S9b+S9c+S9d，**不计编译器预算**） | `lib/std/Option.h.ct`、`Result.h.ct` | 250–500 | 2–4 |

编译器 415–720 = 45+50+60+50+70+60+80（下限）与 80+90+110+90+110+100+140（上限），与 §6 逐片一致；S6 是 `check-ast.sh` 断言，归入夹具/断言区，不冒充编译器代码。

## 11 风险与触发条件

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R34-1 | `pub` 泛型实例在多单元重复导致链接冲突 | 一律 `static`；E34-11 用 `nm` |
| R34-2 | `.h.ct` 模板体泄漏实现细节 | 文档写明；生成 `.h` 仍只放类型 |
| R34-3 | 非泛型固有 impl 与 trait impl 语法歧义 | S4 用「名字后是否为 `<` / `for`」区分；E34-4 用模块夹具 + 产物三断言（原型/定义/`nm`） |
| R34-4 | 跨单元重复方法定义 | impl 表按单元隔离，落到链接期；文档登记为已知限制 |
| R34-5 | `Option<Show>` 的 `__iface` 形状被误当作新能力 | B34-7 明确；E34-8 只锁形状 |
| R34-6 | L26-2 变更被夹带进其他切片 | D34-3 独立提交；E34-2a/E34-2b 是硬条件 |

### 开放项 / 触发条件

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T34-1 | `Option`/`Result` 的 `?`/pattern | 有值 pattern 语法设计卡 |
| T34-2 | payload 自动释放 | Phase 36 |
| T34-3 | 非泛型固有方法的生成 `.h` 原型 | 若硬边界调整，另立评审 |
| T34-4 | 泛型 enum | 由 [phase35-draft.md](phase35-draft.md) 的 T35-6 承接 |

## 12 交付物清单

- `selfhost/ct-ast/**`：S1–S6 的实现与诊断。
- `lib/std/Option.h.ct`、`Result.h.ct`、`lib/std/README.md` 去重说明。
- `test/modules/p34_*`、`test/ast/errors/*`、`test/ast/215–218_*`。
- `examples/38_ecosystem_reuse/` + golden。
- `docs/language-spec.md`、`tutorial.md`、`glossary.md`、`roadmap.md`。
- L26-2 变更评审记录（单独提交，附 §1.4 影响面）。

## 13 收口与纪律

- **T-7 先红后绿**：S0 在实现提交的父提交上复跑探针并提交 `test(ecosystem): P34 红`（含 `baseline: <sha>` 与原始输出）；L26-2 变更单独提交、单独评审。
- 每片 ≤3 文件、净增 ≤150 行；仓库任何时刻可构建。
- 不改判据宽度、不改 golden、不改版本号凑绿；不 bump、不打 tag、不 push。
- 只暂存本相文件；不碰其他会话文件。
