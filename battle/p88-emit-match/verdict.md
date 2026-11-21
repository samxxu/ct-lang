# battle/p88-emit-match 判决（DEV 建议稿，待 REVIEW / EDITOR 追签）

- 日期：2026-11-21
- 状态：**proposed（DEV 2026-11-21 建议；未追签，不得记作已判决）**
- 判据来源：[question.md](question.md)；承接自 [battle/p87-kind-match](../p87-kind-match/verdict.md)
  与 [PH-87 复核 §3.3](../../docs/reviews/2026-11-21-phase87-rev-verdict.md)。
- 判据 × 证据：[p88 度量 §3/§5](../../docs/history/p88_metrics.md)、
  [p88 证据](../../test/probes/p88_evidence.txt)。

## 建议判决

采用 **A**：

1. **PH-88 内不做字面 `match`**：L2 引导链不认 ADT/`match`，写进 ct-ast 源码
   必断链（question.md 原始输出；`L1`/`L2` 中 ADT/match 下降命中 0）。这是
   工具链前置，不是实现选择。
2. S88a 的交付改为**按 kind 切片的单一判别**：`emit_node` / `emit_expr` /
   `emit_type_decl` / `emit_inline` / `emit_field` 的 76 个分支体各自成为
   `em_*` free function，判别式只读一次 `nodes[n].kind` 并以 `nk` 传入；
   `p88_emit` 钉住 76 条清单、每个判别式恰 1 次读取、删一支必红。
3. **承接目标写死为 v1.0 的 seed cutover（`v1-PH-0`）**，不在 PH-88 内换 seed。
   `v1-PH-0` 的出口判据必须包含：用新 seed 构建第一代 ct-ast 后，把 76 个发射器
   切片与 PH-87 §3.3 点名的 `expr_ctype`、`maybe_box`、`chk_type` **全部**改成
   「一 kind 一臂，共用体调同一 helper」的穷尽 `match`（PH-84 无 or 模式）。
   漏一项即 E88-1 欠账未清。
4. **E88-1 记“部分通过 + 承接”**：切片、单判别、等价、探针完成；字面 `match`
   未做，承接见第 3 条。不得记成“全部通过”。

## 判据 × 证据

| # | 判据 | 证据 | 结论 |
| --- | --- | --- | --- |
| J1 | L2 前置 | question.md 原始输出：L2 发射 `enum NodeKind { AdtCtor(int n), … }`，`cc rc=1`；同源码 ct-ast `rc=0` 且产物可编 | 成立 |
| J2 | 切片可验证 | `p88emit: slices=76`；`p88emit: missing-arm negative is red`；每个判别式 `nodes[n].kind` 读 1 次（`p88_metrics` 复算 34+26+6+8+2） | 成立 |
| J3 | 等价 | `p88emit: 66 corpus files are byte-identical`；`p86errors: 23 passed, 0 failed`（345 条诊断）；`fixpoint: 2/3 rounds byte-identical` | 成立 |
| J4 | 承接写死 | [phase88 卡 §3.1](../../docs/design/phase88.md) 与 [v1-pre 证据 §2](../../docs/history/v1-pre-evidence.md) 同一条：`v1-PH-0`；范围含三项剩余判别 | 成立（待 REV/EDITOR 复核） |
| J5 | 不假绿 | 卡/账本明确 E88-1 = 部分通过；未在 ct-ast 源码写 ADT 语法 | 成立 |

## 承接条件（写进 v1.0）

1. **触发**：`v1-PH-0` 的 seed cutover 完成，第一代 ct-ast 由新 seed 构建，
   且该构建器能编 ADT/`match`（PH-84）源码；
2. **范围**：76 个发射器切片（`em_node_*` 26、`em_expr_*` 34、`em_decl_*` 6、
   `em_inline_*` 8、`em_field_*` 2）+ `expr_ctype` + `maybe_box` + `chk_type`；
3. **判据**：`p88_emit` 的清单从“切片函数”改为“`match` 臂”；66 语料逐字节、
   345 诊断逐字、自举不动点（日常 2 / tag 前 3）继续成立；新增一条“漏一臂”
   语言级负例（`match does not cover variant`，已有
   [test/ast/p87_checker/missing_arm.ct](../../test/ast/p87_checker/missing_arm.ct) 可复用）；
4. **回退**：若 `v1-PH-0` 的 seed 决策改回“PH-88 内换 seed”，需以本 battle 的
   失效条件显式覆盖，不得静默改口径。

## 与 PH-86 / PH-87 battle 的关系

PH-86 battle 已裁定 `?`/errdefer 不在 ct-ast 源码使用；PH-87 battle 裁定
`switch→match` 移交 PH-88。本判决对 `match` 采用同一口径：**语法新特性在引导链
支持前不得写进 ct-ast 源码**；区别是 `match` 的阻塞点已定位到 seed，所以承接
目标是 v1.0 的 cutover 而不是“再看”。

## 追签区（非作者席位）

> 待 REVIEW / EDITOR 填写。DEV 不自签（0.7/T-8）。追签前本文件不构成范围裁定，
> E88-1 的部分通过只在 phase 卡与收口报告里按“待签”记录。

- REVIEW：
- EDITOR：
