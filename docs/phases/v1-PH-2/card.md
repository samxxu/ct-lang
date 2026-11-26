---
phase-id: v1-PH-2
version-minor: 2
---

# v1-PH-2 — v1.2：LIR 先行，欠账清零

> **状态：规划中**（2026-11-25 开卡）。所有者 2026-11-25 裁定：**不再单开 v1.3/v1.4/v1.5**；
> **IR/LIR 先行**以省掉一次迁回 AST 的成本；存量欠账全部折进本卡；整卡只 bump 一次 MINOR
> （`v1.2.0`）。
> **前置**：`v1-PH-1` 收口（`v1.1.0`）；[D-026](../../decisions/D-026.md) 设计阶段验收。
> **编号**：`v1-PH-2`，`version-minor = 2` ↔ `v1.2.0`。
> **设计来源**：[typed-lowered-ir](../../proposals/typed-lowered-ir.md)、
> [requirements-pool](../../planning/requirements-pool.md)。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | `v1-PH-2`（`MINOR = 2`） |
| 目标 | 先把 LIR + 清理 CFG 落成唯一发射底座，再在同一底座上补完下标协议、函子、ADT 模式、检查器，把 **全局默认 strict** 作为 V1 欠账补齐，并用最新特性压缩 selfhost 源码 |
| 范围 | S0 小欠账 → S1a-0 容量上限动态化 → S1a-1 单元收敛（SH-94 剩余）→ S1b IR-1（闸）→ S2–S7 功能 → S8 IR-2 收尾切换 → **S8b 源码狗粮化** → **S8c 样例与文档去指针化** → S9 全局默认 strict 迁移 → S10 收口；见 §2 |
| 非目标 | 优化器、SSA、C ABI 破坏性变更、未列明的用户语法、真板硬件（`HW-*`）、外部包排期；**不要求生成 C 变短/逐字节不变、不做 minify、不把节点池 `kind` 改 ADT** |
| 交付物 | ABI-3/4 修复、CI 两个 job、LANG-25 码表；**容量上限动态化（49 个 Limits + 8 个本地 + 14 处硬编码）**；**SH-94 剩余方法组拆分**；TIR 视图 + LIR + 清理 CFG + 验证器；REQ-JSACCESS-1 / REQ-INDEX-1；函子 `(A,B) => R`；ADT 模式扩展；REQ-TYPE-1 / REQ-MEM-2 / P-1.3；**源码狗粮化报告**；**特性样例矩阵 + examples/docs 去指针化**；**全局默认 strict（in-repo 迁移 + 默认翻转）**；`v1.2.0` |
| 任务清单 | §2（S0–S10，四列齐全） |
| 退出判据 | E-V3-1…E-V3-11（§3） |
| version-minor | 2 |
| 已知风险 | R-V3-1…R-V3-12（§4） |

## 1 入口与闸

> **1.0 所有者裁定（2026-11-25）**：**全局默认 strict 是 V0 阶段已定项，不是 v1.2 新增的颠覆性变更。**
> [v0-PH-65](../v0-PH-65/card.md) 的“Ct 仓内四目录豁免”只是 pre-1.0 临时安排；selfhost 已不再以
> L2 语法为基础，不应直接 `#include` C 库。spec 的“不再自称 C 超集”不等于“Ct 仓永久 allow”。
> 因此 v1.2 把默认翻转为 strict，并迁移 `selfhost/`、`lib/core/`、`examples/`、`test/`；C 互操作
> 用例保留，但必须显式 allow（manifest / CLI / shim）。

| 闸 | 内容 | 现状 |
| --- | --- | --- |
| 前置 | `v1.1.0` 已发布；D-026 只完成设计验收 | 已完成 |
| 总闸 | **S1a-0 → S1a-1 → S1b**：S1a-0 放开容量上限；S1a-1 纯搬移收敛单元（SH-94 剩余）；S1b 落 LIR；未过闸，S2–S9 不开工 | 未开工 |
| 例外 | S0 不依赖 S1a/S1b，可先做并独立切 `v1.1.1` | 未开工 |
| stage 闸 | 每 stage 独立红证 → 独立合入 → 独立回滚；未过闸不进入下一 stage | 未开工 |
| 收口闸 | E-V3-* 全绿；`check-all`；seed 两轮逐字节；`v1.2.0` 由所有者手工打 tag | 未开工 |

### 1.1 真实依赖矩阵

| stage | 真实前置 | 说明 |
| --- | --- | --- |
| S0 小欠账 | 无 | 缺陷与 CI 可立即开工；可独立切 `v1.1.1` |
| S1a-0 容量上限动态化 | 无 | 33 个计数上限 + 7 个文本/路径 + 8 个本地常量 + 14 处硬编码；全部收到形式上限（`CAP_LIMIT` / `TEXT_LIMIT` / `NODE_LIMIT`）；C3 同批改 spec |
| S1a-1 单元收敛（SH-94 剩余） | S1a-0 | 纯搬移；`ExprOps` 已在 `MAX_METHODS=64` 上限，放开容量并拆新 trait 后不再受限 |
| S1b IR-1 | S1a-1 | 本卡总闸；TIR 只做现有 AST 的 typed 视图，不新建前端/优化器/SSA |
| S2 下标协议 | S1b | 在 LIR 上实现，避免 AST→LIR 二次迁移 |
| S3 函子 | S1b | 签名糖在 LIR 类型/发射层落地 |
| S4 ADT 模式 A | S1b | 只扩模式文法与穷尽框架 |
| S5 ADT 模式 B | S4 | or / 守卫复用 S4 的模式文法 |
| S6 泛型 ADT | S4 | 只依赖模式基础设施，不依赖 S5 |
| S7 检查器 | S1b | `REQ-MEM-2` 直接用 S1b 的清理 CFG；`REQ-TYPE-1` 用现有检查器 |
| S8 IR-2 | S1b | emitter 契约 + 语义图 + 自举切换；建议在 S2–S7 之后，避免反复搬发射逻辑 |
| S8b 源码狗粮化 | S8 | 用最新特性压缩 selfhost 源码；**用户语料生成 C 逐字节不变**，编译器自身 C 允许差异；详见 [dogfooding](../../planning/dogfooding.md) |
| S8c 样例与文档去指针化 | S2–S6（特性）、S8b（可并行）、**LANG-30（打印 API，v1.2 必做）** | 特性样例矩阵清零；examples/docs 用新写法；C 互操作例外逐条登记（[TEST-27](../../../issues/testing/test27-feature-examples-pointer-free.md)）；E3 类 26 个文件假删算未完成 |
| S9 全局默认 strict | S8c | 默认翻转 + in-repo 迁移；依赖 S7 的类型检查证据与 S1b 的 LIR |
| S10 收口 | S0–S9 | — |

> **约束（N-1…N-6）**
> N-1：S1a-0 → S1a-1 → S1b 是唯一总闸；S1b 未过，S2–S9 不开工。S1a 两段只做容量与纯搬移，不改语义/生成物。
> N-2：S1b 范围封顶——TIR 是现有 AST 的 typed 视图；LIR 只覆盖现有发射形态；不做新前端、SSA、优化器。
> N-3：S0 独立于 S1a/S1b；缺陷修复不因 IR 延期。
> N-4：S8 不得反向阻塞 S2–S7；功能先落在 LIR，切换最后做。
> N-5：外部/触发式条目（`REQ-PKG-1`、`REQ-ABI-2`、`TEST-22`、`PKG-16`）不进入本卡判据。
> N-6：C3 语言上限（ADT 形态、泛型元数）与 C1/C2 同批收到形式上限；spec §8 / stable-subset 的改写必须与实现同一提交，不允许实现先行。
> N-7：S1a-1 内 **Expr（A/B 组）与 Stmt（C 组）文件集不重叠，可并行**；Emitter D 组可与其并行；但都必须等 S1a-0 收口（C2n 驻留池是单写者阶段）。

## 1.5 并行轨道（2026-11-26）

> 原则：**同一时刻只有一个 `selfhost/**` 写入者**；`bootstrap/**`、`gen-seed.sh`、golden 只归 A 轨道。
> B/C/D 轨道不改编译器源码，不触发 seed，可与 A 并行。

| 轨道 | 负责 | 文件集 | 当前内容 | 依赖 | 冲突 |
| --- | --- | --- | --- | --- | --- |
| **A 编译器代码** | DEV | `selfhost/**`、`bootstrap/**` | S1a-0 剩余 `MAX_TEXT` 数组 → C4；之后 S1b | 无 | **独占 seed/golden**；不得与其它 A 类写入者并行 |
| **B 样例与文档** | TEST / REVIEW（[TEST-27](../../../issues/testing/test27-feature-examples-pointer-free.md)） | `examples/**`、`README.md`、`docs/tutorial.md`、guide、idioms、snippets | 特性样例矩阵已落（[feature-examples-matrix](../../planning/feature-examples-matrix.md)，23 行）；按缺口清单 B-1…B-6 补样例、去指针、改写文档；S2–S6 新特性落地后再补对应样例 | 新特性部分等 S2–S6 | 不碰 `selfhost` |
| **C 设计包** | REQ / REVIEW（[DESIGN-1](../../../issues/selfhost/design-1-v12-design-pack.md)） | `docs/design/**`、`docs/decisions/**`、`docs/diagnostics/**`、`issues/**` | TIR/LIR 契约与夹具清单已落（[tir-lir-contract](../../design/tir-lir-contract.md)、[tir-lir-fixtures](../../design/tir-lir-fixtures.md)）；剩 S2/S3 ADR、S4–S6 模式规范 | 无 | 不写代码 |
| **D 证据与审计** | TEST | `docs/reviews/**`、`issues/**`、只读脚本 | S7 的 FP=0 基线与 MEM-2 用例矩阵已落（[s7-evidence-baseline](../../planning/s7-evidence-baseline.md)）；S9 的 `#include` 分类已落（[strict-include-audit](../../planning/strict-include-audit.md)，819 文件 / 1,078 行）；C4 的 TEST-9 契约草稿待写 | 无 | 只读，不改 `selfhost`；报告入库，暂不单开卡 |

- B 的“已有特性”部分现在就能做；下标/函子/ADT 模式样例必须等 S2–S6 语法落地，不得提前写错语法；
- C 的结论必须经 REVIEW 复核，未复核不作为 S1b 输入；
- D 的产出是报告与清单，供 S7/S9 直接引用；
- 合入顺序：B/C/D 可在 A 收口前后独立合入，但**不得修改 A 的文件集**；A 收口后释放单写者，S1b 才开工。

## 2 任务（stage）

| stage | 交付 | 对应条目 | 验收 | effort |
| --- | --- | --- | --- | --- |
| S0 小欠账与基线 | 枚举形参 / `union *` 形参的 `.abi.h` 前置声明；nightly 补 TSan 与 ASAN 栈逃逸 job；诊断码 registry 完整化；文档纠偏（AGENTS pin、需求池过期字段） | [SH-121](../../../issues/selfhost/sh121-abi-enum-forward.md)、[SH-122](../../../issues/selfhost/sh122-abi-union-forward.md)、[REQ-CI-1](../../planning/requirements-pool.md#L279-L293)、[REQ-CI-2](../../planning/requirements-pool.md#L295-L309)、[LANG-25](../../../issues/lang/lang-25-diagnostic-code-registry.md)、[DOC-100](../../../issues/docs/doc-100-upstream-ct-cr.md) | 两个缺陷各有 issue 与正负例；两个 nightly job 绿；码表与源码一致；文档门禁绿；生成物零变化 | M |
| S1a-0 容量上限动态化 | C1：33 个计数上限 + 8 个本地常量 + 第 4 节 A 类字面量 → 动态倍增到 `CAP_LIMIT=65536`；C2a–C2m 已落（路径/命令/键/锁/行/初始化文本）；**C2n：剩余 `MAX_TEXT` 改字符串驻留池（791 处一次替换）**；C2o：硬编码 159/158/24/128；C2p：按单元簇合批，每提交 4–6 单元；C3：ADT 形态与泛型元数同批收到形式上限并改 spec / stable-subset；`MAX_NODES` 改动态 arena（`NODE_LIMIT=16M`）；只保留深度/错误恢复保护 | [capacity-limits](../../planning/capacity-limits.md)、[SH-109](../../../issues/selfhost/sh109-max-funcs-capacity.md) | 旧上限负例改为“可增长并通过”；长名/长路径用例；形式上限只由 OOM/注入自测触发；生成物逐字节；seed 两轮 | L |
| S1a-1 单元收敛（SH-94 剩余） | 纯搬移，按 [design §4](../../design/sh94-m1-core-layout.md#4-剩余拆分计划2026-11-25)：**Phase A** Expr 七个小组（A1–A7）→ **Phase B** 拆 `ExprOps`（B1–B5：CallCheck / Closure / Instantiate / TypeParse / StaticType）→ **Phase C** 拆 `StmtOps`（C1–C5：Match / Loop / Switch / Control / Uninit）→ **Phase D1–D3** 只拆 Emitter 的 `hoist` / `invariant` / `init`（执行序 D2→D1→D3）；**Expr/Stmt 可并行（N-7）**；`em_*` 76 个 kind 切片沿用既有自由函数工具 | [SH-94](../../../issues/selfhost/sh94-giant-units-duplicate-constants.md)、[sh94-m1-core-layout](../../design/sh94-m1-core-layout.md) | 每片 `tools/sh94_split_check.py` 函数体多重集不变；生成物逐字节；seed 两轮；单元名全局唯一；环数 0；A1 为 spike | L |
| S1b IR-1（总闸） | TIR typed 视图；LIR 覆盖现有发射形态；scope 树 + 清理条目栈 + 每条出口清理集；`return` / `break` / `continue` / 合法 `goto` / `?` 失败 / errdefer 清理边；TIR/LIR 两处不变量检查点（`E-IR-1xx`）；AST 路径保留为 oracle 双跑 | [SH-112](../../../issues/selfhost/sh112-typed-ir-architecture.md)、typed-lowered-ir §2–§5 | 全语料生成 C 逐字节不变；六类清理边夹具；验证器负例不产出 C；IR 覆盖清单 | L |
| S2 下标协议完整化 | REQ-JSACCESS-1（名 + 参数类型匹配）→ REQ-INDEX-1（读/写/借写；`+=` / `++` / `&x[k]` 二值化） | [REQ-JSACCESS-1](../../planning/requirements-pool.md#L71-L103)、[REQ-INDEX-1](../../planning/requirements-pool.md#L105-L142) | 两条 A1–A7 全绿；无匹配硬错并列候选；`p52_*` 零回归；`ct-json` / `rill` 冒烟 | L |
| S3 函子签名糖 | `(A,B) => R`：先 ADR（与 trait/闭包关系、类型语法、ABI、IDE 展开），再在 LIR 上实现 | [REQ-FUNCTOR-1](../../planning/requirements-pool.md)、[pointer-free-v2 §2.5](../../proposals/pointer-free-v2.md) | ADR 通过；正负例；零运行期成本；spec 新节 + IDE 语法高亮 | M |
| S4 ADT 模式 A | 字面量模式、嵌套模式、结构体模式 | [REQ-ADT-PATTERN-1](../../planning/requirements-pool.md)、[v0-PH-84 非目标](../v0-PH-84/card.md) | 三种模式正负例；穷尽性覆盖；`spec §4.73` 改口径 | L |
| S5 ADT 模式 B | or 模式 + 守卫；穷尽算法扩展（或分支计数、守卫不可穷尽） | 同上 | `A | B` 双臂；守卫不穷尽负例；漏分支负例 | M |
| S6 泛型 ADT | 泛型 ADT（`enum Option<T>` / `Result<T,E>`）；布局、实例化、与 `Box`/`Vec` 交互 | 同上 | 泛型实例夹具；`Box`/`Vec` 互操作；golden；sized 上限复核 | L |
| S7 检查器与证据 | REQ-TYPE-1（`--types` 三类判定进 `build/compile` 默认，先 FP=0 再分切片）；REQ-MEM-2（用 S1b 的 CFG 做单元内写入摘要）；REQ-MEM-1 只复评；P-1.3 迁移 lint | [REQ-TYPE-1](../../planning/requirements-pool.md#L229-L243)、[REQ-MEM-2](../../planning/requirements-pool.md#L261-L277)、[J-6 台账](../../planning/j6-evidence/ledger.md) | FP=0 证据；`--check-level=off` 逃生；写入摘要正负例；迁移 lint 三档 dry-run；`check-all` 绿 | L |
| S8 IR-2 | emitter 契约（类型/实例化/生命周期判定移出 emitter）；内建层/泛型实例语义依赖图；golden 差异清单后重基线；自举切换；**切换后按 [design §4.5](../../design/sh94-m1-core-layout.md#45-phase-demitter分两段避免与-ir-重复劳动) 做 Emitter D4–D6（EmitHeader / EmitDecl / EmitExpr）** | typed-lowered-ir §4、§6–§8、[SH-113](../../../issues/selfhost/sh113-builtin-live-boundary.md)、[SH-94](../../../issues/selfhost/sh94-giant-units-duplicate-constants.md) | emitter 无类型/实例化/生命周期判定（评审签字）；全语料等价或差异清单签字；自举 2 轮（tag 前 3 轮）逐字节；D4–D6 生成物逐字节；旧路径一提交可回滚 | L |
| S8b 源码狗粮化 | D1 方法化（329 个 `struct X *self` 自由函数）→ D2 容器化（82 处手写 realloc / 并行数组）→ D5 错误路径（`?` / `errdefer`）→ D3 命名构建（选域 `snprintf` → `String`）→ D4 判别式（已 ADT 域用 `match`，节点池不动）→ D6 函子签名；**按片交付**：D1/D2/D5 的 `tool/`、`runtime/`、`frontend/sym/` 域不等 S8，emitter / lowerer 域等 S8（[dogfooding §2.1](../../planning/dogfooding.md)） | [dogfooding](../../planning/dogfooding.md)、[REQ-ADT-PATTERN-1](../../planning/requirements-pool.md)、[REQ-FUNCTOR-1](../../planning/requirements-pool.md) | 用户语料生成 C 逐字节不变；`check-ast` fixpoint；seed 两轮；每片报告前后 LOC/计数；生成 C 可读性 REVIEW 签字 | L |
| S8c 样例与文档去指针化 | A：`docs/planning/feature-examples-matrix.md` 每个特性一行（example / test / doc / 状态）；B：examples 补齐缺失样例，非 C 互操作样例去掉 `char *` / `->` / `malloc`；C：README / tutorial / guide / idioms / snippets 改写；D：examples 全量构建 + 矩阵一致性断言（先 warn，收口转硬） | [TEST-27](../../../issues/testing/test27-feature-examples-pointer-free.md)、[LANG-30](../../../issues/lang/lang-30-str-print-api.md)（v1.2 必做）、[dogfooding](../../planning/dogfooding.md)、[pointer-free-v2](../../proposals/pointer-free-v2.md) | 矩阵无 missing；新特性（S2–S6）各有 ≥1 样例；非 C 互操作样例指针清零（例外逐条有理由）；**E3 类 26 个文件清零（依赖 LANG-30）**；snippets 可编译；`check-ast` / `check-docs` 绿 | L |
| S9 全局默认 strict（V1 欠账） | ① 审计 `#include`（2026-11-26 实测 **819 文件 / 1,078 行**：`selfhost` 56/183、`lib/core` 8/14、`examples` 180/218、`test` 575/663，见 [strict-include-audit](../../planning/strict-include-audit.md)），按 M1–M5 分三类推进：边界单元、C 互操作用例、待清理；② `selfhost/` 与 `lib/core/` 迁到边界单元（`.m.ct` / shim），**零 allow**；③ `examples/`、`test/` 能迁则迁，C 互操作/负例显式 allow（589 个文件可直删冗余 `<stdio.h>`，生成 C 逐字节不变）；④ `c_boundary_for` 去掉五目录豁免，默认 strict；manifest 无键改为 strict，`ct migrate` 为旧包写 `c-boundary = allow`；⑤ spec §1.2 / §4.66 与 README 更新；⑥ 自举与 seed 重生成 | [REQ-STRICT-1](../../planning/requirements-pool.md)、[v0-PH-65](../v0-PH-65/card.md) | 默认 strict 下 `check-all` 绿；`selfhost/`、`lib/core/` 零 allow；普通 `.ct` 无 include 不受影响；显式 allow 仍可用；`ct migrate` 旧包夹具通过；自举 2 轮 + seed 两轮逐字节 | L |
| S10 收口 | `stable-subset` 分档更新；冷/热构建各测一次并记录（不立项）；`CTC_VERSION 1.2.0` 与 dist；**tag 与 release 不自动创建**，由所有者手工验证后执行；seed 重生成 | — | E-V3-11 | M |

> **S6 的命名未决（2026-11-27）**：卡上写的是 `enum Option<T>` / `Result<T,E>`，但 `lib/core`
> 已把两者定义为普通泛型 struct（`has` / `value` / `ok` / `err`），且 `?` 的 lowering 依赖这套布局。
> S6 先按 [adt-patterns §10.5](../../design/adt-patterns.md) 的**方案 A** 落地机制（验收名
> `Maybe<T>` / `Either<T,E>`）；是否把内置名升级为 ADT 由单独 ADR（拟 `D-031`）在所有者的裁定下决定，
> 不与机制切片混做。
>
> **S8c 的前置（2026-11-27，所有者裁定）**：`Str.print()` / `println()`（[LANG-30](../../../issues/lang/lang-30-str-print-api.md)，
> 施工卡 [lang30-str-print-construction](../../design/lang30-str-print-construction.md)）**在 v1.2 内必须实现，不顺延**。
> E3 类 26 个样例的打印依赖它；API 未落地前可以先做 H1–H4 中不依赖 E3 的部分，但 S8c **不得据此宣称收口**，
> 也不得用 `cstr()` + `free` 假装去指针。
>
> **S9 的边界（重要）**：这不是“加一个显式开关”，而是把 [v0-PH-65](../v0-PH-65/card.md) 的
> pre-1.0 四目录豁免收回，**默认翻转为 strict**。C 互操作不删除：`.m.ct` / shim、manifest
> `c-boundary = allow`、CLI `--c-boundary=allow` 继续可用，但必须显式。1,078 行 `#include` 是
> **待迁移清单**，不是保留默认 allow 的理由；`examples` / `test` 中确实在测 C 互操作的用例保留并标注 allow。
> **S10 的版本纪律（所有者 2026-11-26）**：`v1.2.0` **禁止自动打 tag**。S10 只提交
> `CTC_VERSION`、dist 与收口证据；annotated tag 与 GitHub release 由所有者手工验证后执行。
> `release.yml` 仅在 tag push / `workflow_dispatch` 时运行，仓库内不存在自动打 tag 的步骤。
>
> **stage 纪律**：每个 stage 独立提交、独立回滚；同一时刻只有一个会话持有施工分支。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E-V3-1 | S0：[SH-121](../../../issues/selfhost/sh121-abi-enum-forward.md) / [SH-122](../../../issues/selfhost/sh122-abi-union-forward.md) verified；nightly TSan、ASAN 栈逃逸 job 绿；LANG-25 码表与源码一致；文档纠偏无死链 |
| E-V3-2a | S1a-0：旧上限负例变为“增长成功”；长名/长路径用例；只余形式上限（`CAP_LIMIT=65536` / `TEXT_LIMIT=65536` / `NODE_LIMIT=16777216`）与深度保护；生成物逐字节；seed 两轮 |
| E-V3-2b | S1a-1：A1–A7、B1–B5、C1–C5、D1–D3 每片函数体多重集不变、生成物逐字节、`check-ast` fixpoint、seed 两轮；`ExprOps` 不再顶 `MAX_METHODS`；环数 0 |
| E-V3-2 | IR-1：TIR 视图 + LIR 覆盖现有发射形态；全语料双跑逐字节；六类清理边夹具；`E-IR-1xx` 负例不产出 C |
| E-V3-3 | 下标协议：JSACCESS-1 A1–A5、INDEX-1 A1–A7 全绿；`p52_*` 零回归；下游冒烟通过 |
| E-V3-4 | 函子：ADR 通过；正负例；`(A,B) => R` 零运行期成本；spec + IDE 同步 |
| E-V3-5 | ADT 模式 A：字面量 / 嵌套 / 结构体模式正负例；穷尽性覆盖 |
| E-V3-6 | ADT 模式 B：or 模式 + 守卫；守卫不穷尽与漏分支负例 |
| E-V3-7 | 泛型 ADT：`Option<T>` / `Result<T,E>` 夹具；布局与实例化稳定；与 `Box`/`Vec` 互操作 |
| E-V3-8 | 检查器：REQ-TYPE-1 FP=0 + 分切片；REQ-MEM-2 写入摘要；P-1.3 迁移 lint；`off` 逃生 |
| E-V3-9 | IR-2：emitter 不再做类型/实例化/生命周期判定；语义图替换文本判活；golden 差异清单签字；自举 2 轮（tag 前 3 轮）逐字节；D4–D6 逐片生成物逐字节 |
| E-V3-9b | 狗粮化：D1–D6 各片用户语料生成 C 逐字节；源码 LOC/自由函数/realloc/snprintf/判别式前后报告入库；生成 C 可读性 REVIEW 签字 |
| E-V3-9c | 样例与文档：矩阵无 missing；新特性各有 ≥1 样例；非 C 互操作用例指针清零（例外有理由）；**E3 类打印受阻的 26 个文件清零，依赖 LANG-30 在 v1.2 内落地**；README/tutorial/guide/idioms/snippets 同步；`check-ast` / `check-docs` 绿 |
| E-V3-10 | 全局默认 strict：默认下 `check-all` 绿；`selfhost/` 与 `lib/core/` 零 allow；普通无 include 的 `.ct` 逐字节不变；显式 allow（manifest / CLI / shim）正负例；`ct migrate` 旧包夹具通过 |
| E-V3-11 | 收口：`CTC_VERSION 1.2.0`、dist 与发布流程同 v1.1；**不自动打 tag / 不自动发 release**——所有者手工验证后才创建 annotated tag；`check-all` 全绿、seed 两轮逐字节 |

## 4 风险与回滚

| # | 风险 | 处置 |
| --- | --- | --- |
| R-V3-1 | S1b 成为总闸，IR 拖延会挡住全部功能 | S1b 范围封顶（N-2）；接受标准全为机械判据；S0 先独立交付；每 stage 不可静默延期，未过闸就地停并改卡 |
| R-V3-2 | LIR 先行导致功能需在 LIR 上重写发射 | 这正是选此顺序的原因：只写一次；禁止为赶进度回写 AST 发射路径 |
| R-V3-3 | IR 范围扩张（优化器/SSA/新前端） | N-2；超出范围的提案一律进池，不加进 S1b/S8 |
| R-V3-4 | 泛型 ADT 波及布局、实例化与 `Box`/`Vec` 互操作 | 放 S6，单独 golden 与容量复核；可独立回滚 |
| R-V3-5 | `--types` 默认化打破语料 | 先复用 v1.0/v1.1 的 FP=0 证据；分切片推进；`--check-level=off` 保留 |
| R-V3-6 | 默认 strict 翻转使 in-repo 用例/旧包大面积变红 | 先审计再迁移；`examples`/`test` 的 C 互操作显式 allow；旧包用 `ct migrate` 写 `c-boundary = allow`；E-V3-10 用 `check-all` 兜底 |
| R-V3-7 | 改 `lib/core` 或内置层却忘重生成 seed | 任何内置层改动同批重生成；gate 13 两轮逐字节 + 手改负例 |
| R-V3-8 | 外部项被误当本卡前置 | N-5；`REQ-PKG-1` / `REQ-ABI-2` / 硬件项不进 E-V3-* |
| R-V3-9 | SH-94 剩余拆分与 LIR 同文件冲突 | S1a-1 先合入，S1b 只在拆分后的单元上改；单写者；每切片独立回滚 |
| R-V3-10 | 文本容量动态化触及 31 个单元、791 处定长数组 | C2 独立切片、独立回滚；先做 C1；长名/长路径夹具先行；`Limits.h.ct` 只留 `CAP_LIMIT` / `TEXT_LIMIT` / `NODE_LIMIT` 与 D 类 |
| R-V3-11 | 狗粮化改动面大、易与 IR/严格迁移冲突 | 放在 S8 之后、S9 之前；一域一片；用户语料逐字节；生成 C 只记录不设门禁；REVIEW 签字可读性 |
| R-V3-12 | 去指针化扭曲 C 互操作或硬件样例 | 例外清单（`55_c_boundary_shim` / `c-superset` / `54_freestanding_alloc` / `.m.ct` / shim）逐条登记；只改非边界样例 |

回滚：S0–S10 各自独立提交；`v1.2.0` 的版本/tag 单独回滚；不改已发布 tag。

## 5 关联

- [v1-PH-1](../v1-PH-1/card.md)（v1.1 收口）、[v1-PH-0](../v1-PH-0/card.md)（v1.0 收口）
- [D-026](../../decisions/D-026.md)（IR 设计裁定）、[typed-lowered-ir](../../proposals/typed-lowered-ir.md)
- [SH-112](../../../issues/selfhost/sh112-typed-ir-architecture.md)、[SH-111](../../../issues/selfhost/sh111-lowering-invariants.md)、[SH-113](../../../issues/selfhost/sh113-builtin-live-boundary.md)
- [requirements-pool](../../planning/requirements-pool.md)、[pointer-free-v2](../../proposals/pointer-free-v2.md)、[pointer-free-phase-plan](../../planning/pointer-free-phase-plan.md)
- [LANG-25](../../../issues/lang/lang-25-diagnostic-code-registry.md)、[LANG-29](../../../issues/lang/lang-29-adt-match-complete.md)
- [DESIGN-1](../../../issues/selfhost/design-1-v12-design-pack.md)（C 轨道设计包）、[TEST-27](../../../issues/testing/test27-feature-examples-pointer-free.md)（B 轨道样例/文档）
- [dogfooding](../../planning/dogfooding.md)（S8b）、[capacity-limits](../../planning/capacity-limits.md)（S1a-0）
- [J-6 证据台账](../../planning/j6-evidence/ledger.md)（P-1.3）
