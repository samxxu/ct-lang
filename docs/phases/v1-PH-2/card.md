---
phase-id: v1-PH-2
version-minor: 2
---

# v1-PH-2 — v1.2：LIR 先行，欠账清零

> **状态：实施中（v1.2.0 已提交、未打 tag；所有者 2026-11-28 追加 I1/I2，落地后再打 tag）**（2026-11-25 开卡）。所有者 2026-11-25 裁定：**不再单开 v1.3/v1.4/v1.5**；
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
| 范围 | S0 小欠账 → S1a-0 容量上限动态化 → S1a-1 单元收敛（SH-94 剩余）→ S1b IR-1（闸）→ S2–S7 功能 → S8 IR-2 收尾切换 → **S8a 常量键折叠（可砍）** → **S8b 源码狗粮化** → **S8c 样例与文档去指针化** → S9 全局默认 strict 迁移 → S10 收口；见 §2 |
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
| 总闸 | **S1a-0 → S1a-1 → S1b**：S1a-0 放开容量上限；S1a-1 纯搬移收敛单元（SH-94 剩余）；S1b 落 LIR；未过闸，S2–S9 不开工 | 已完成 |
| 例外 | S0 不依赖 S1a/S1b，可先做并独立切 `v1.1.1` | 已完成（随卡交付，未单切 `v1.1.1`） |
| stage 闸 | 每 stage 独立红证 → 独立合入 → 独立回滚；未过闸不进入下一 stage | 已完成（各 stage 独立提交） |
| 收口闸 | E-V3-* 全绿；`check-all`；seed 两轮逐字节；`v1.2.0` 由所有者手工打 tag | 已执行（E-V3-8/9b/9c 部分，见 §6；tag 待所有者） |

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
| S8a 常量键折叠（I1） | S8 | 在 S8 的 LIR 上实现，避免 AST/LIR 写两遍；**可砍**：若 S8 收口后窗口不足，整体降到 1.2 之后，不改任何退出判据 |
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
| S8a 常量键折叠（I1，**可砍**） | 字符串**字面量**键在编译期解析到结构体字段并折叠为字段访问（`p["x"]` → `p.x`）；未知字段 / 非字面量键 / 非结构体接收者硬错；**不做**映射表、不做接口值下标、不做运行期键折叠 | [REQ-INDEXFOLD-1](../../planning/requirements-pool.md)、[LANG-31](../../../issues/lang/lang-31-const-key-fold.md) | 折叠后生成 C 无 `get` 调用、无临时量；未知键与字段重命名负例；`check-goldens-ast` 25/25；**不阻塞 S8b/S9/S10** | M |
| S8b 源码狗粮化 | D1 方法化（329 个 `struct X *self` 自由函数）→ D2 容器化（82 处手写 realloc / 并行数组）→ D5 错误路径（`?` / `errdefer`）→ D3 命名构建（选域 `snprintf` → `String`）→ D4 判别式（已 ADT 域用 `match`，节点池不动）→ D6 函子签名；**按片交付**：D1/D2/D5 的 `tool/`、`runtime/`、`frontend/sym/` 域不等 S8，emitter / lowerer 域等 S8（[dogfooding §2.1](../../planning/dogfooding.md)） | [dogfooding](../../planning/dogfooding.md)、[剩余补完施工卡](../../design/s8b-remaining-construction.md)（`S8B-REM-1`，2026-11-28 方案 A）、[REQ-ADT-PATTERN-1](../../planning/requirements-pool.md)、[REQ-FUNCTOR-1](../../planning/requirements-pool.md) | 用户语料生成 C 逐字节不变；`check-ast` fixpoint；seed 两轮；每片报告前后 LOC/计数；生成 C 可读性 REVIEW 签字 | L |
| S8c 样例与文档去指针化 | A：`docs/planning/feature-examples-matrix.md` 每个特性一行（example / test / doc / 状态）；B：examples 补齐缺失样例，非 C 互操作样例去掉 `char *` / `->` / `malloc`；C：README / tutorial / guide / idioms / snippets 改写；D：examples 全量构建 + 矩阵一致性断言（先 warn，收口转硬） | [TEST-27](../../../issues/testing/test27-feature-examples-pointer-free.md)、[LANG-30](../../../issues/lang/lang-30-str-print-api.md)（v1.2 必做）、[dogfooding](../../planning/dogfooding.md)、[pointer-free-v2](../../proposals/pointer-free-v2.md) | 矩阵无 missing；新特性（S2–S6）各有 ≥1 样例；非 C 互操作样例指针清零（例外逐条有理由）；**E3 类 26 个文件清零（依赖 LANG-30）**；snippets 可编译；`check-ast` / `check-docs` 绿 | L |
| S9 全局默认 strict（V1 欠账） | ① 审计 `#include`（2026-11-26 实测 **819 文件 / 1,078 行**：`selfhost` 56/183、`lib/core` 8/14、`examples` 180/218、`test` 575/663，见 [strict-include-audit](../../planning/strict-include-audit.md)），按 M1–M5 分三类推进：边界单元、C 互操作用例、待清理；② `selfhost/` 与 `lib/core/` 迁到边界单元（`.m.ct` / shim），**零 allow**；③ `examples/`、`test/` 能迁则迁，C 互操作/负例显式 allow（589 个文件可直删冗余 `<stdio.h>`，生成 C 逐字节不变）；④ `c_boundary_for` 去掉五目录豁免，默认 strict；manifest 无键改为 strict，`ct migrate` 为旧包写 `c-boundary = allow`；⑤ spec §1.2 / §4.66 与 README 更新；⑥ 自举与 seed 重生成 | [REQ-STRICT-1](../../planning/requirements-pool.md)、[v0-PH-65](../v0-PH-65/card.md) | 默认 strict 下 `check-all` 绿；`selfhost/`、`lib/core/` 零 allow；普通 `.ct` 无 include 不受影响；显式 allow 仍可用；`ct migrate` 旧包夹具通过；自举 2 轮 + seed 两轮逐字节 | L |
| S10 收口 | `stable-subset` 分档更新；冷/热构建各测一次并记录（不立项）；`CTC_VERSION 1.2.0` 与 dist；**tag 与 release 不自动创建**，由所有者手工验证后执行；seed 重生成 | [s10-closeout](s10-closeout.md)（REQ 起草的收口清单） | E-V3-11 | M |

> **S6 的命名口径（2026-11-27 裁定，S6b 落地）**：卡上写的是 `enum Option<T>` / `Result<T,E>`，但 `lib/core`
> 已把两者定义为普通泛型 struct（`has` / `value` / `ok` / `err`），且 `?` 的 lowering 依赖这套布局。
> S6b 采用 [adt-patterns §10.5](../../design/adt-patterns.md) 的**方案 D：按 unit 遮蔽**——声明
> `enum Option<T>` / `Result<T,E>` 的 unit 内用户 ADT 优先，其他 unit 仍用内置 struct；`?` 的 lowering
> 与 spec §4.62 契约不变（提交 `ca3515ff`、`010a5318`，机制见
> [adt-generic §10](../../design/adt-generic.md#10-遮蔽内置-option--results6b)）。
> A/B/C 三案仅作历史分析，不再作为落地口径，也不另开 ADR。
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
| E-V3-9d（S8a，**必做**；2026-11-28 撤回 deferred） | 常量键折叠：`p["x"]` → `p.x`；未知字段 / 非字面量键 / 非结构体接收者硬错；折叠后生成 C 无 `get` 调用、无临时量；`check-goldens-ast` 25/25；`check-docs` 绿 | 前置 `D-031` + spec §4.79（施工卡已有）；与 E-V3-9e 共用 D-028 的下标解析表 |
| E-V3-9e（I2 阶段一，**必做**；2026-11-28 新立） | 接口值**只读**下标：trait 的 `get(K)` 标 `index` 后，`o[k]` 经 vtable 槽解析；未标 → 硬错；固有 impl 路径（D-028）零回归；`index` 为上下文修饰词；正负例 + `check-goldens-ast` 25/25 | 先出 ADR `D-034`（Q1 立项 / Q2 方法级 `index` / Q4 暂不承诺 ABI）；与 E-V3-9d 共用 D-028 解析表 |
| E-V3-9f（I2 阶段二，**必做**；同属 1.2） | 接口值**写入**：`set(K, V)` 标 `index` 后 `o[k] = v` 成立；定义只读实现、所有权、失败语义；不新增 vtable 槽 | 阶段一稳定后开工；不与阶段一同提交 |
| E-V3-10 | 全局默认 strict：默认下 `check-all` 绿；**`selfhost/ct-ast` 与 `lib/core` 各用一处 manifest 显式 allow（`c-boundary = allow`，包根覆盖子树）；仓库其它目录零 allow**（[CR-V3-1](#8-判据变更记录) 改写，2026-11-28）；普通无 include 的 `.ct` 逐字节不变；显式 allow（manifest / CLI / shim）正负例；`ct migrate` 旧包夹具通过 |
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

## 6 收口证据（2026-11-27，v1.2.0）

> 判据定义见 §3（未改动）。**「部分」不是「通过」**：未满足的部分在末列逐条登记；本表不把
> 剩余项并入「通过」。原始命令与输出见 §7.4。
> **本卡不自动打 tag / 不发 release**：`v1.2.0` 的 annotated tag 与 GitHub release 由所有者
> 按 §7.5 手工执行（所有者 2026-11-26 版本纪律）。

| 判据 | 结论 | 证据 | 剩余 / 边界 |
| --- | --- | --- | --- |
| E-V3-1 | 通过 | [SH-121](../../../issues/selfhost/sh121-abi-enum-forward.md)、[SH-122](../../../issues/selfhost/sh122-abi-union-forward.md) 状态 `verified`；LANG-25 码表 `docs/diagnostics/codes.md` 47 码由 `check-docs` 逐码比对（§7.4）；nightly `tsan` / `asan-stack` job 在 `.github/workflows/nightly.yml`；文档死链 0（`check-docs` 3423 links） | nightly 绿证以 CI 侧为准：本轮不 push、未触发 CI，只登记 job 定义与仓内探针 |
| E-V3-2a | 通过 | S1a-0 记录见 [capacity-limits](../../planning/capacity-limits.md) §2–§5；`test/ast/c2p_limits.sh` 58/58、`c2n/intern` 11/11、`c2o/limits` 9/9；`tools/limits_sync.py --check` 拒绝镜像漂移；生成物逐字节与 seed 两轮见 §7.2 | 无；深度/错误恢复保护（`MAX_ERRORS` 等）按设计保留，不属容量上限 |
| E-V3-2b | 通过 | SH-94 剩余拆分见 [sh94-m1-core-layout](../../design/sh94-m1-core-layout.md) §4；`tools/sh94_split_check.py` 校验函数体多重集；`check-ast` 0 失败（§7.4）；环数 0；`ExprOps` 不再顶 `MAX_METHODS` | 无 |
| E-V3-2 | 通过 | `bash test/ir/run.sh <ct>`：**82 corpus 0 byte-differences**、4 TIR negatives、6 LIR negatives、selfhost TIR shadow 78 units 逐字节、15 checks（§7.4）；`E-IR-1xx` 负例由 `test/ir` 覆盖 | 无 |
| E-V3-3 | 通过 | [D-028](../../decisions/D-028.md) 已 `accepted`；`test/ast/p52_index.sh`、`index_overload_both`、`jsaccess_overload_both` 覆盖读/写/借写与按实参类型分派；`check-ast` 0 失败；`p52_*` 零回归 | 无；接口值下标、`x[k].field`、多级连写按 D-028 非目标 |
| E-V3-4 | 通过 | [D-029](../../decisions/D-029.md) 已 `accepted`；`test/ast/p3_functor.sh`、`p3_functor_forms`、`p3_functor_header`；展开与 `R (*)(A,B)` 同型、零运行期成本；spec §4.77 | IDE 语法高亮随编辑器迁到 `samxxu/ct-vscode`（仓外），本轮只登记编译器与 spec 侧 |
| E-V3-5 | 通过 | `test/ast/303_adt_literal_pattern`、`304_adt_nested_pattern`、`305_adt_struct_pattern` 正例；穷尽性负例在 `p84/errors` 与 `test/ast/errors`（§7.4） | 无 |
| E-V3-6 | 通过 | `test/ast/306_adt_or_pattern`、`307_adt_guard`；守卫不穷尽、漏分支负例同批（p84/errors） | 无 |
| E-V3-7 | 通过 | `test/ast/308_adt_generic_option`…`314_adt_shadow_result`；`311_adt_generic_box_vec` 覆盖 `Box`/`Vec` 互操作；布局与实例化随 golden | 无；`enum Option<T>` / `Result<T,E>` 的 S6b unit 遮蔽口径见 §2 注 |
| E-V3-8 | 通过 | REQ-TYPE-1：`test/ast/p122_types_default.sh` 44/44、FP=0 基线 [s7-evidence-baseline](../../planning/s7-evidence-baseline.md)；`--check-level=off` 逃生保留。REQ-MEM-2：`315_mem2_literal`…`319_mem2_recursion` + `p111_invariants`；写入摘要正负例随 `check-ast`。**P-1.3 迁移 lint（2026-11-28 补）**：`tools/migrate_lint.py` 三档 dry-run，可自动 2.9% / 需人工 69.5% / 语义需确认 27.7%（596 个可迁移站点），[证据](../../planning/j6-evidence/p1_3_lint.md) + [清单](../../planning/j6-evidence/p1_3_lint_files.tsv)；J-6 台账 P-1.3 已从 `阻塞` 转 `已过` | 文本级 lint（非编译器内建、不自动改写）；边界见证据 §5 |
| E-V3-9 | 通过（带边界） | S8r2 默认 LIR、10 个 known-gap 清零：[差异清单](../../reviews/2026-11-27-s8-ir2-diff-list.md)（82 corpus、839 个 `test/ast` 夹具、自举 1638/1638、seed 两轮）；[S8 最终收尾](../../reviews/2026-11-27-s8-closeout-lmodule.md)（map/model 六段三段、九个写者选择迁 `LModulePlan`）；`test/ir` 15 checks。**REV 已签（2026-11-28）**：§3/§3e 回退类型、§3d 边界、§3f 行化边界逐条核对，「回退 ≠ 已降级」成立 | 边界：§3e.3 保留的 6 类函数级回退与 map/model JSON 写者选择按签字保留；S8a 见 E-V3-9d |
| E-V3-9b | **实现完成（待 REVIEW 补签）** | [dogfooding](../../planning/dogfooding.md) §3.5 + §3.6：D1（Arena/Diag/Pkg/Symbols 方法化）、D2 子集（Sh/Pkg 改 `Vec`；符号表三组并行数组改行块）、D5（Intern `Result`/`?`/`errdefer`）、D6 函子签名、D4（`backend/mem` 三个函数）、D3a–c 命名构建已落；用户语料 25/25 逐字节；源码 LOC 81,194→81,169、`snprintf` 326→308、`realloc` 101→96 前后报告入库。**2026-11-28 S8B-REM-1 收尾**：R3 `e23338db`、R4 `75fcb698`、R5 `9a0312a0`、R6 `3026f9bb`、R7 `233727d5`、R8 `bd252782`、§3.8 `9eb519c4`；现测 `snprintf` 292（`Pkg` 43 / `Symbols` 24）、`realloc` 87；`check-all` 8 门、seed 两轮 | **REQ 2026-11-28 裁定方案 A（条件通过）**：① REV 在 `dogfooding §3.8` 补 R3–R8 后的最终计数与生成 C 抽查；② 明确 SH-123（P2）随 1.2 保留、不按 `clean` 签；③ REV 补签后本行才转「通过（条件）」；在此之前不得写「通过」 |
| E-V3-9c | 通过 | [feature-examples-matrix](../../planning/feature-examples-matrix.md) 26 行无 `missing`；S2–S6 各有 ≥1 example；LANG-30 `test/ast/lang30_print.sh` 7/7；E3 类 26 个迁 22、保留 4（§2.2 编号登记 E3-1…E3-3、E3-5；E3-4 已迁出）。**B-5/B-7（2026-11-28 补）**：新增 `0.12_adt_tour` / `0.13_c_boundary` 两个可执行片段（snippets 10 个，`check-warnings` 逐片段编译运行），README §0.13 给出 C 边界逐行对照；README/tutorial/guide/idioms 的非互操作段改值类型，C 互操作段逐段标注 | 4 个保留项是「有理由例外」，不是待办；§0.13 的 `char *` 是对照样例，不属遗漏 |
| E-V3-9d | **待开（2026-11-28 撤回 deferred）** | S8a 未实施；[LANG-31](../../../issues/lang/lang-31-const-key-fold.md) 已转回 `open`；施工卡 [lang31-const-key-fold-construction](../../design/lang31-const-key-fold-construction.md) 已有 | 所有者 2026-11-28 裁定：随 1.2 一起交付，不再后推 |
| E-V3-9e | **待开（2026-11-28 新立）** | I2 阶段一未实施；四问已裁定（Q1 立项 / Q2 方法级 `index` / Q3 两阶段 / Q4 暂不承诺 ABI），见 [RFC 评估 §3.1](../../reviews/2026-11-27-indexable-rfc-evaluation.md) | 前置 ADR `D-034`；阶段一只读 |
| E-V3-9f | **待开（2026-11-28 新立）** | I2 阶段二未实施：`set` 的 `index` 与写语义 | 阶段一稳定后开工；同属 1.2 |
| E-V3-10 | 通过（口径后由 CR-V3-1 更新） | S9 提交 `5c0e6781`；默认 strict 下 `check-all` 8 门绿（§7.4）；**当时** `selfhost/`、`lib/core/` 零 allow；普通无 include 的 `.ct` 逐字节不变；`test/c-boundary-allow.tsv` 登记 examples/test 的显式例外；`ct migrate` 旧包夹具在 `check-ast`。**2026-11-28 按 CR-V3-1 补齐**：D-032 M1–M3 已落地（`feb6caa5`/`981f2ee9`/`653dec09`），`selfhost/ct-ast` 与 `lib/core` 各一处包根 manifest；shim 74 → 3（seed 5 → 3）；`--show-c-boundary` 正负例与 `p65_*`、goldens 25/25、`check-seed` 两轮均绿 | `examples`/`test` 的 C 互操作保留 allow 属设计，不是豁免回退；本行是 v1.2.0 历史证据，现行判据见 §8 CR-V3-1 |
| E-V3-11 | 通过 | `CTC_VERSION 1.2.0`；dist `ct-linux-x64.tar.gz` sha256 `98130730155f88934a2c4b4d0ce82e222bc81fc25e34a6fc0fdcf7736a0e28d3`；`check-all` 8 门、seed 两轮、stable-subset v1.2 冻结（§7） | **tag / release 未创建**：按所有者版本纪律由手工执行，见 §7.5 |

## 7 S10 收口记录（2026-11-27）

### 7.1 版本与版本落点

| 项 | 值 |
| --- | --- |
| 源码唯一落点 | `selfhost/ct-ast/main.ct:57` `#define CTC_VERSION "1.2.0"` |
| 其他落点 | `README.md`（头行 + 两处「v1.2.0 的实测」）、`docs/README.md` 头行、`AGENTS.md` 当前版本行、`docs/roadmap.md` 的 `v1-PH-2` 行、`docs/history/phase-log.md` 的 `v1.2.0` 行、`docs/stable-subset.md` 的 v1.2 冻结行、本卡 |
| 版本对应 | `MAJOR.MINOR = 1.2` ↔ `v1-PH-2`；`PATCH = 0`（整卡只 bump 一次 MINOR，阶段内 fix 为未发布返工，不占 PATCH） |
| 核对 ① 落点相等 | 全部落点均为 `1.2.0`（`check-docs` 的版本项与 §7.4 原始输出） |
| 核对 ② MINOR ↔ phase | `2` ↔ `v1-PH-2`（`version-minor: 2`、`tools/check.sh g8`） |
| 核对 ③ PATCH vs fix | `PATCH = 0`；本 phase 窗口内没有已发布 fix 占用 PATCH |
| 核对 ④ CHANGELOG vs tag | `docs/history/phase-log.md` 最新行为 `v1.2.0`；tag 尚未创建，由所有者按 §7.5 建于收口提交，届时二者一致 |

**seed**：`bootstrap/ct-ast` 由 `selfhost/gen-seed.sh` 重生成，共 **73 `.c` + 140 `.h`**。
跨版本时跑**两遍**：第一遍用 v1.1.0 seed 发射（banner 仍为 1.1.0，`main.c` 宏已 1.2.0）；
第二遍用 1.2.0 seed 发射，banner 与宏同为 1.2.0，成为冻结不动点。`bootstrap/MANIFEST.sha256`
随 seed 重生成。`check-seed` 两轮逐字节 + 手改负例红（§7.4）。

**golden/版本串**：`check-goldens-ast.sh` 对 banner 做 `vX` 归一化，25 份静态 golden 无需按
版本重基线（实测 25/25）；`test/cases/*.expected.{c,h}`、`test/goldens/ast/*.c` 与
`test/modules/p39_lib/lib.expected.abi.h` 的 banner 仅版本 token 更新；`p80_docs`/`p81_box`/
`p82_docs` 的版本断言同步到 1.2.0。`p83_*` / `pkg19_20_rows` 的 `1.1.0` 是**包版本夹具**，
不是编译器版本，未改。

### 7.2 冷 / 热构建（只记录，不立项）

| 项 | 命令 / 结果 |
| --- | --- |
| 机器 | Apple M6（arm64），macOS 27.2.1，Apple clang 21.0.0 |
| 冷构建 | `rm -rf .ctbuild` 后 `ct build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o <tmp>/ct`：**real 4.17s**（user 3.80s / sys 0.35s） |
| 热构建 | 同树连跑第二次：**real 3.47s**（user 3.14s / sys 0.32s） |
| 冷/热比 | `3.47 / 4.17 = 0.83`；构建缓存命中后仍要跑 `cc`，故差距有限 |
| 结论 | 只记录，不设门禁；异常进需求池，不在 S10 修 |

### 7.3 分发产物（Linux x86-64）

| 项 | 值 |
| --- | --- |
| 构建 | macOS 主机 `ZIG=<zig 0.17.1> bash selfhost/make-dist.sh --cross <zig>` |
| 产物 | `dist/ct-linux-x64.tar.gz`（2.0 MB，**不入 git**） |
| 内容 | `ct` + `ctc -> ct` 符号链接（`tar -tzf`） |
| 类型 | `ELF 64-bit LSB executable, x86-64, statically linked`（`file`） |
| sha256 | `98130730155f88934a2c4b4d0ce82e222bc81fc25e34a6fc0fdcf7736a0e28d3`；`sha256sum -c` OK |
| 版本串 | 提取的 `dist/ct` 内含 `1.2.0`（`strings` 核对） |
| 冒烟 | **UNVERIFIED**：本机无 `qemu-system-x86_64`、无 Linux 内核/busybox 资产，`run-linux-binary.sh` 退出 77；未伪装通过。所有者可在 Linux 主机或补齐 QEMU 资产后复跑 `sh selfhost/run-linux-binary.sh dist/ct-linux-x64/ct -v` |

### 7.4 门禁原始输出（S10 收口树）

```console
$ bash selfhost/check-all.sh
test/run: 4 passed, 0 failed
test/pkg: 165 passed, 0 failed
check-ast: 1741 passed, 0 failed, 6 skipped
check-warnings: 617 ok, 0 failed
check-docs: OK (3423 relative links in 459 files, v1.2.0, 8 hard gates, 73 phase status)
check-goldens-ast: 25/25
check-seed: OK (73 .c + 140 .h, two rebuild rounds byte-identical, hand-edit negative red)
acceptance: 20 pass, 0 new, 0 pending, 0 regression
check-all: OK (8 hard gates green)

$ bash selfhost/check-seed.sh
check-seed: OK (73 .c + 140 .h, two rebuild rounds byte-identical, hand-edit negative red)

$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (662 checks, no sanitizer report)

$ MATRIX_STRICT=1 bash tools/check.sh g4
check-docs: OK (3423 relative links in 459 files, 1757 fragment(s) in 824 Markdown files, v1.2.0, 8 hard gates, ...)
matrix: OK (every feature row has example/test/doc/status)

$ bash tools/check.sh g0 && bash tools/check.sh g1 && bash tools/check.sh g6 && bash tools/check.sh g8
g0: OK (block 1.18.0, session-map present)
g1: OK (phase IDs all v<M>-PH-<n>, window W2; 76 card(s), 76 ledger row(s))
g1: OK (12 active phase cards: title/status/tasks/exit-criteria/version-minor)
g6: OK (320 issues; open=4 verified=299 rejected=13 deferred=2 superseded=2)
g8: OK (PN-2 version coherence; 9 legacy offsets)

$ bash test/ir/run.sh <ct>
ir: corpus 82 files, 0 byte-differences
ir: OK (82 corpus byte-identical, 4 TIR negatives, 6 LIR negatives, 9 LIR fixtures, 2 module builds, selfhost=1, 15 checks)
```

### 7.5 所有者手工 tag（本卡不执行）

`v1.2.0` 的 annotated tag 与 release **不在本轮创建**。所有者在分支推送后执行：

```console
$ CLOSEOUT=<收口提交 sha>
$ git tag -a v1.2.0 -m "v1-PH-2 closeout $(git rev-parse --short "$CLOSEOUT")" "$CLOSEOUT"
$ git cat-file -t v1.2.0                     # 必须输出 tag（annotated）
$ test "$(git rev-parse 'v1.2.0^{commit}')" = "$(git rev-parse "$CLOSEOUT")" && echo commit-ok
$ git branch -r --contains "$CLOSEOUT"       # 非空（分支已推送）
$ git push origin v1.2.0                     # 四项校验全过后再推
```

发布（可选，同样由所有者执行）：

```console
$ gh release create v1.2.0 \
    dist/ct-linux-x64.tar.gz dist/ct-linux-x64.tar.gz.sha256 \
    --title "v1.2.0 — v1-PH-2 LIR 先行" --notes-file docs/history/phase-log.md
```

校验项：① tag 名 `v1.2.0`；② `git cat-file -t` 为 `tag`；③ `rev-parse 'v1.2.0^{commit}'`
等于收口提交；④ 收口提交已在远端分支上；⑤ release 资产 sha256 与本卡 §7.3 一致。

## 8 判据变更记录

> 只登记**已由所有者裁定**的退出判据改写；原文保留在「原判据」列，便于对照。判据以本表最新行
> 为准；与 §3 冲突时，以本表为准并同步 §3 的行。

| ID | 对象 | 原判据 | 新判据 | 理由 | 批准 | 日期 | 关联 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| CR-V3-1 | E-V3-10 | 「`selfhost/` 与 `lib/core/` 零 allow」 | 「**`selfhost/ct-ast` 与 `lib/core` 各用一处 manifest 显式 allow（`c-boundary = allow`，包根覆盖子树）；仓库其它目录零 allow**」；其余不变：默认 strict 下 `check-all` 绿、普通无 include 的 `.ct` 逐字节不变、显式 allow 正负例、`ct migrate` 夹具通过 | strict 的目的是防止**普通消费者**无留痕地直接调 C 库，不是约束编译器自身与内置层；现状为这条判据付出 74 个 shim（selfhost 66 + lib/core 8）。改用两处 manifest 后豁免可审计、可用删文件做负例；消费者默认不变。解析语义由 [D-032](../../decisions/D-032.md) 定为"包根 manifest 覆盖子树、向上止于所属根"，`leaks` 同批对齐 | 所有者 2026-11-28 | 2026-11-28 | [D-032](../../decisions/D-032.md)、[REQ-STD-COVER-1](../../planning/requirements-pool.md) |
| CR-V3-2 | E-V3-9d / E-V3-9e / E-V3-9f | E-V3-9d「S8a，**可砍**」，窗口不足即 deferred | E-V3-9d 改「**必做**」；新增 E-V3-9e（I2 阶段一只读）与 E-V3-9f（阶段二写入），均**必做** | 所有者 2026-11-28：I1 与 I2 不再后推，随 1.2 一起交付；1.2.0 已提交但**未打 tag**，tag 推迟到两者落地后。I2 四问已裁定：立项 / 方法级 `index` / 两阶段 / 暂不承诺 vtable ABI | 所有者 2026-11-28 | 2026-11-28 | [LANG-31](../../../issues/lang/lang-31-const-key-fold.md)、[RFC 评估 §3.1](../../reviews/2026-11-27-indexable-rfc-evaluation.md) |

