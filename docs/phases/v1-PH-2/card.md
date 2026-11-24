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
| 目标 | 先把 LIR + 清理 CFG 落成唯一发射底座，再在同一底座上补完下标协议、函子、ADT 模式、检查器，并把 **全局默认 strict** 作为 V1 欠账补齐 |
| 范围 | S0 小欠账 → S1 IR-1（闸）→ S2–S7 功能 → S8 IR-2 收尾切换 → S9 全局默认 strict 迁移 → S10 收口；见 §2 |
| 非目标 | 优化器、SSA、C ABI 破坏性变更、未列明的用户语法、真板硬件（`HW-*`）、外部包排期 |
| 交付物 | ABI-3/4 修复、CI 两个 job、LANG-25 码表；TIR 视图 + LIR + 清理 CFG + 验证器；REQ-JSACCESS-1 / REQ-INDEX-1；函子 `(A,B) => R`；ADT 模式扩展；REQ-TYPE-1 / REQ-MEM-2 / P-1.3；**全局默认 strict（in-repo 迁移 + 默认翻转）**；`v1.2.0` |
| 任务清单 | §2（S0–S10，四列齐全） |
| 退出判据 | E-V3-1…E-V3-11（§3） |
| version-minor | 2 |
| 已知风险 | R-V3-1…R-V3-8（§4） |

## 1 入口与闸

> **1.0 所有者裁定（2026-11-25）**：**全局默认 strict 是 V0 阶段已定项，不是 v1.2 新增的颠覆性变更。**
> [v0-PH-65](../v0-PH-65/card.md) 的“Ct 仓内四目录豁免”只是 pre-1.0 临时安排；selfhost 已不再以
> L2 语法为基础，不应直接 `#include` C 库。spec 的“不再自称 C 超集”不等于“Ct 仓永久 allow”。
> 因此 v1.2 把默认翻转为 strict，并迁移 `selfhost/`、`lib/core/`、`examples/`、`test/`；C 互操作
> 用例保留，但必须显式 allow（manifest / CLI / shim）。

| 闸 | 内容 | 现状 |
| --- | --- | --- |
| 前置 | `v1.1.0` 已发布；D-026 只完成设计验收 | 已完成 |
| 总闸 | **S1 IR-1**：未过闸，S2–S9 不开工（2026-11-25 所有者选择“LIR 先行”） | 未开工 |
| 例外 | S0 不依赖 S1，可先做并独立切 `v1.1.1` | 未开工 |
| stage 闸 | 每 stage 独立红证 → 独立合入 → 独立回滚；未过闸不进入下一 stage | 未开工 |
| 收口闸 | E-V3-* 全绿；`check-all`；seed 两轮逐字节；`v1.2.0` tag | 未开工 |

### 1.1 真实依赖矩阵

| stage | 真实前置 | 说明 |
| --- | --- | --- |
| S0 小欠账 | 无 | 缺陷与 CI 可立即开工；可独立切 `v1.1.1` |
| S1 IR-1 | 无 | 本卡总闸；TIR 只做现有 AST 的 typed 视图，不新建前端/优化器/SSA |
| S2 下标协议 | S1 | 在 LIR 上实现，避免 AST→LIR 二次迁移 |
| S3 函子 | S1 | 签名糖在 LIR 类型/发射层落地 |
| S4 ADT 模式 A | S1 | 只扩模式文法与穷尽框架 |
| S5 ADT 模式 B | S4 | or / 守卫复用 S4 的模式文法 |
| S6 泛型 ADT | S4 | 只依赖模式基础设施，不依赖 S5 |
| S7 检查器 | S1 | `REQ-MEM-2` 直接用 S1 的清理 CFG；`REQ-TYPE-1` 用现有检查器 |
| S8 IR-2 | S1 | emitter 契约 + 语义图 + 自举切换；建议在 S2–S7 之后，避免反复搬发射逻辑 |
| S9 全局默认 strict | S7 | 默认翻转 + in-repo 迁移；依赖 S7 的类型检查证据与 S1 的 LIR |
| S10 收口 | S0–S9 | — |

> **约束（N-1…N-5）**
> N-1：S1 是唯一总闸；S1 未过，S2–S9 不开工。这是 2026-11-25 所有者对“省一次迁移成本”的取舍。
> N-2：S1 范围封顶——TIR 是现有 AST 的 typed 视图；LIR 只覆盖现有发射形态；不做新前端、SSA、优化器。
> N-3：S0 独立于 S1；缺陷修复不因 IR 延期。
> N-4：S8 不得反向阻塞 S2–S7；功能先落在 LIR，切换最后做。
> N-5：外部/触发式条目（`REQ-PKG-1`、`REQ-ABI-2`、`TEST-22`、`PKG-16`）不进入本卡判据。

## 2 任务（stage）

| stage | 交付 | 对应条目 | 验收 | effort |
| --- | --- | --- | --- | --- |
| S0 小欠账与基线 | 枚举形参 / `union *` 形参的 `.abi.h` 前置声明；nightly 补 TSan 与 ASAN 栈逃逸 job；诊断码 registry 完整化；文档纠偏（AGENTS pin、需求池过期字段） | [REQ-ABI-3](../../planning/requirements-pool.md#L175-L187)、[REQ-ABI-4](../../planning/requirements-pool.md#L188-L200)、[REQ-CI-1](../../planning/requirements-pool.md#L279-L293)、[REQ-CI-2](../../planning/requirements-pool.md#L295-L309)、[LANG-25](../../../issues/lang/lang-25-diagnostic-code-registry.md)、[DOC-100](../../../issues/docs/doc-100-upstream-ct-cr.md) | 两个缺陷各开 issue 并各带正负例；两个 nightly job 绿；码表与源码一致；文档门禁绿；生成物零变化 | M |
| S1 IR-1（总闸） | TIR typed 视图；LIR 覆盖现有发射形态；scope 树 + 清理条目栈 + 每条出口清理集；`return` / `break` / `continue` / 合法 `goto` / `?` 失败 / errdefer 清理边；TIR/LIR 两处不变量检查点（`E-IR-1xx`）；AST 路径保留为 oracle 双跑 | [SH-112](../../../issues/selfhost/sh112-typed-ir-architecture.md)、typed-lowered-ir §2–§5 | 全语料生成 C 逐字节不变；六类清理边夹具；验证器负例不产出 C；IR 覆盖清单 | L |
| S2 下标协议完整化 | REQ-JSACCESS-1（名 + 参数类型匹配）→ REQ-INDEX-1（读/写/借写；`+=` / `++` / `&x[k]` 二值化） | [REQ-JSACCESS-1](../../planning/requirements-pool.md#L71-L103)、[REQ-INDEX-1](../../planning/requirements-pool.md#L105-L142) | 两条 A1–A7 全绿；无匹配硬错并列候选；`p52_*` 零回归；`ct-json` / `rill` 冒烟 | L |
| S3 函子签名糖 | `(A,B) => R`：先 ADR（与 trait/闭包关系、类型语法、ABI、IDE 展开），再在 LIR 上实现 | [REQ-FUNCTOR-1](../../planning/requirements-pool.md)、[pointer-free-v2 §2.5](../../proposals/pointer-free-v2.md) | ADR 通过；正负例；零运行期成本；spec 新节 + IDE 语法高亮 | M |
| S4 ADT 模式 A | 字面量模式、嵌套模式、结构体模式 | [REQ-ADT-PATTERN-1](../../planning/requirements-pool.md)、[v0-PH-84 非目标](../v0-PH-84/card.md) | 三种模式正负例；穷尽性覆盖；`spec §4.73` 改口径 | L |
| S5 ADT 模式 B | or 模式 + 守卫；穷尽算法扩展（或分支计数、守卫不可穷尽） | 同上 | `A | B` 双臂；守卫不穷尽负例；漏分支负例 | M |
| S6 泛型 ADT | 泛型 ADT（`enum Option<T>` / `Result<T,E>`）；布局、实例化、与 `Box`/`Vec` 交互 | 同上 | 泛型实例夹具；`Box`/`Vec` 互操作；golden；sized 上限复核 | L |
| S7 检查器与证据 | REQ-TYPE-1（`--types` 三类判定进 `build/compile` 默认，先 FP=0 再分切片）；REQ-MEM-2（用 S1 的 CFG 做单元内写入摘要）；REQ-MEM-1 只复评；P-1.3 迁移 lint | [REQ-TYPE-1](../../planning/requirements-pool.md#L229-L243)、[REQ-MEM-2](../../planning/requirements-pool.md#L261-L277)、[J-6 台账](../../planning/j6-evidence/ledger.md) | FP=0 证据；`--check-level=off` 逃生；写入摘要正负例；迁移 lint 三档 dry-run；`check-all` 绿 | L |
| S8 IR-2 | emitter 契约（类型/实例化/生命周期判定移出 emitter）；内建层/泛型实例语义依赖图；golden 差异清单后重基线；自举切换 | typed-lowered-ir §4、§6–§8、[SH-113](../../../issues/selfhost/sh113-builtin-live-boundary.md) | emitter 无类型/实例化/生命周期判定（评审签字）；全语料等价或差异清单签字；自举 2 轮（tag 前 3 轮）逐字节；旧路径一提交可回滚 | L |
| S9 全局默认 strict（V1 欠账） | ① 审计 `798` 处 `#include`（`selfhost` 35 / `lib` 8 / `examples` 180 / `test` 575），分三类：边界单元、C 互操作用例、待清理；② `selfhost/` 与 `lib/core/` 迁到边界单元（`.m.ct` / shim），**零 allow**；③ `examples/`、`test/` 能迁则迁，C 互操作/负例显式 allow；④ `c_boundary_for` 去掉四目录豁免，默认 strict；manifest 无键改为 strict，`ct migrate` 为旧包写 `c-boundary = allow`；⑤ spec §1.2 / §4.66 与 README 更新；⑥ 自举与 seed 重生成 | [REQ-STRICT-1](../../planning/requirements-pool.md)、[v0-PH-65](../v0-PH-65/card.md) | 默认 strict 下 `check-all` 绿；`selfhost/`、`lib/core/` 零 allow；普通 `.ct` 无 include 不受影响；显式 allow 仍可用；`ct migrate` 旧包夹具通过；自举 2 轮 + seed 两轮逐字节 | L |
| S10 收口 | `stable-subset` 分档更新；冷/热构建各测一次并记录（不立项）；`v1.2.0` 版本、annotated tag、release、dist；seed 重生成 | — | E-V3-11 | M |

> **S9 的边界（重要）**：这不是“加一个显式开关”，而是把 [v0-PH-65](../v0-PH-65/card.md) 的
> pre-1.0 四目录豁免收回，**默认翻转为 strict**。C 互操作不删除：`.m.ct` / shim、manifest
> `c-boundary = allow`、CLI `--c-boundary=allow` 继续可用，但必须显式。`798` 处 `#include` 是
> **待迁移清单**，不是保留默认 allow 的理由；`examples` / `test` 中确实在测 C 互操作的用例保留并标注 allow。
> **stage 纪律**：每个 stage 独立提交、独立回滚；同一时刻只有一个会话持有施工分支。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E-V3-1 | S0：ABI-3 / ABI-4 各有一张 issue 与正负例；nightly TSan、ASAN 栈逃逸 job 绿；LANG-25 码表与源码一致；文档纠偏无死链 |
| E-V3-2 | IR-1：TIR 视图 + LIR 覆盖现有发射形态；全语料双跑逐字节；六类清理边夹具；`E-IR-1xx` 负例不产出 C |
| E-V3-3 | 下标协议：JSACCESS-1 A1–A5、INDEX-1 A1–A7 全绿；`p52_*` 零回归；下游冒烟通过 |
| E-V3-4 | 函子：ADR 通过；正负例；`(A,B) => R` 零运行期成本；spec + IDE 同步 |
| E-V3-5 | ADT 模式 A：字面量 / 嵌套 / 结构体模式正负例；穷尽性覆盖 |
| E-V3-6 | ADT 模式 B：or 模式 + 守卫；守卫不穷尽与漏分支负例 |
| E-V3-7 | 泛型 ADT：`Option<T>` / `Result<T,E>` 夹具；布局与实例化稳定；与 `Box`/`Vec` 互操作 |
| E-V3-8 | 检查器：REQ-TYPE-1 FP=0 + 分切片；REQ-MEM-2 写入摘要；P-1.3 迁移 lint；`off` 逃生 |
| E-V3-9 | IR-2：emitter 不再做类型/实例化/生命周期判定；语义图替换文本判活；golden 差异清单签字；自举 2 轮（tag 前 3 轮）逐字节 |
| E-V3-10 | 全局默认 strict：默认下 `check-all` 绿；`selfhost/` 与 `lib/core/` 零 allow；普通无 include 的 `.ct` 逐字节不变；显式 allow（manifest / CLI / shim）正负例；`ct migrate` 旧包夹具通过 |
| E-V3-11 | 收口：`CTC_VERSION 1.2.0`、annotated tag、release 与 dist 同 v1.1 流程、`check-all` 全绿、seed 两轮逐字节 |

## 4 风险与回滚

| # | 风险 | 处置 |
| --- | --- | --- |
| R-V3-1 | S1 成为总闸，IR 拖延会挡住全部功能 | S1 范围封顶（N-2）；接受标准全为机械判据；S0 先独立交付；每 stage 不可静默延期，未过闸就地停并改卡 |
| R-V3-2 | LIR 先行导致功能需在 LIR 上重写发射 | 这正是选此顺序的原因：只写一次；禁止为赶进度回写 AST 发射路径 |
| R-V3-3 | IR 范围扩张（优化器/SSA/新前端） | N-2；超出范围的提案一律进池，不加进 S1/S8 |
| R-V3-4 | 泛型 ADT 波及布局、实例化与 `Box`/`Vec` 互操作 | 放 S6，单独 golden 与容量复核；可独立回滚 |
| R-V3-5 | `--types` 默认化打破语料 | 先复用 v1.0/v1.1 的 FP=0 证据；分切片推进；`--check-level=off` 保留 |
| R-V3-6 | 默认 strict 翻转使 in-repo 用例/旧包大面积变红 | 先审计再迁移；`examples`/`test` 的 C 互操作显式 allow；旧包用 `ct migrate` 写 `c-boundary = allow`；E-V3-10 用 `check-all` 兜底 |
| R-V3-7 | 改 `lib/core` 或内置层却忘重生成 seed | 任何内置层改动同批重生成；gate 13 两轮逐字节 + 手改负例 |
| R-V3-8 | 外部项被误当本卡前置 | N-5；`REQ-PKG-1` / `REQ-ABI-2` / 硬件项不进 E-V3-* |

回滚：S0–S10 各自独立提交；`v1.2.0` 的版本/tag 单独回滚；不改已发布 tag。

## 5 关联

- [v1-PH-1](../v1-PH-1/card.md)（v1.1 收口）、[v1-PH-0](../v1-PH-0/card.md)（v1.0 收口）
- [D-026](../../decisions/D-026.md)（IR 设计裁定）、[typed-lowered-ir](../../proposals/typed-lowered-ir.md)
- [SH-112](../../../issues/selfhost/sh112-typed-ir-architecture.md)、[SH-111](../../../issues/selfhost/sh111-lowering-invariants.md)、[SH-113](../../../issues/selfhost/sh113-builtin-live-boundary.md)
- [requirements-pool](../../planning/requirements-pool.md)、[pointer-free-v2](../../proposals/pointer-free-v2.md)、[pointer-free-phase-plan](../../planning/pointer-free-phase-plan.md)
- [LANG-25](../../../issues/lang/lang-25-diagnostic-code-registry.md)、[LANG-29](../../../issues/lang/lang-29-adt-match-complete.md)
- [J-6 证据台账](../../planning/j6-evidence/ledger.md)（P-1.3）
