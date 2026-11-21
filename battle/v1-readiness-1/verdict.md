# battle/v1-readiness-1 判决

> **状态：`closed`**（2026-11-21；裁判 EDITOR；1 轮 claim/counter）。
> **判决：C —— 两级门禁 + `v1-PH-0` 出口复核。**
> Tier 1 在 `v1-PH-0` 开卡前清零；Tier 2 在 `v1.0` 发布前清零，并在 `v1-PH-0`
> 出口做一次“是否被拖延”的复核。五项一个都不删除。

## 1 逐项判决

| 项 | 层级 | 归属 / 负责人 | 落点 |
| --- | --- | --- | --- |
| SH-104 J-6 证据台账 | **Tier 1：v1-PH-0 入口** | REQ 建台账，DEV 补证据 | [SH-104](../../issues/selfhost/sh104-j6-evidence-ledger.md) |
| SH-105 goldens 静态化 | **Tier 1：v1-PH-0 入口** | DEV 实现，REQ 定验收 | [SH-105](../../issues/selfhost/sh105-goldens-static-freeze.md) |
| `MAX_FUNCS` 501/512 | **Tier 1：v1-PH-0 入口决策** | REQ 复算/给选项，USER 签字 | [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md) |
| E88-1 字面 `match` 承接 | **Tier 1：v1-PH-0 seed cutover** | DEV；EDITOR 追签 | [battle/p88-emit-match](../../battle/p88-emit-match/verdict.md) |
| phase-ID 迁移 | **Tier 2：v1.0 发布** | 主规范裁 blocker A/B；本仓执行 W0→W2 | [DOC-83](../../issues/docs/doc-83-phase-id-migration-decision.md) |
| G1/G6 治理 | **Tier 2：v1.0 发布** | CI/REQ；实现或显式 `deviation:` | [CI-13](../../issues/ci/ci-13-g6-ledger-closure.md) |
| 历史 High 证据债 | **Tier 2：v1.0 发布** | DOC/DEV；逐项“修/不修+理由” | [SH-107](../../issues/selfhost/sh107-m0-commit-not-buildable.md)、[DOC-81](../../issues/docs/doc-81-phase85-clean-archive-dead-link.md)、[DOC-82](../../issues/docs/doc-82-phase85-e85-2-gate.md) |
| index 仓 `verify_row` Q2 | 外派（不计 v1 门禁） | index 仓 | 见 [PKG-21](../../issues/packages/pkg-21-ct-pkg-index-refactor-ruling.md) ① |

## 2 判据矩阵

| J | 结论 | 依据 |
| --- | --- | --- |
| J-1 归属/验收 | **通过** | 上表每项有层级、owner、issue；Tier 1 验收命令见各 issue |
| J-2 不伪装跨仓 | **通过** | phase-ID blocker A/B 外派主规范；index 仓 Q2 不入本仓清零 |
| J-3 入口不阻塞 | **通过** | Tier 1 只含本仓可验收项；SH-104/105 在 V1-C1/C2 |
| J-4 历史债不静默 | **通过** | SH-107/DOC-81/DOC-82 必须在 v1.0 前给出“修/不修+理由”，否则不放行 |
| J-5 容量决策有数据/签字 | **通过** | 501/512 实测；提上限需 USER 签字，`impl`/调切片需数据 |
| J-6 可回滚 | **通过** | 逐项独立 issue/提交；与 PH-85…88 重写切片分离 |

## 3 `v1-PH-0` 出口复核（C 的关键）

`v1-PH-0` 收口时，EDITOR 必须复核 Tier 2 三项：

1. phase-ID：blocker A/B 是否已有主规范裁定；账本 W0 是否启动；
2. G1/G6：是否有实现或 `deviation:`；非闭集状态是否下降；
3. 历史债：三项是否已有处置结论与证据。

任一项仍无 owner/证据，或复核发现它实际阻塞 `v1-PH-0` 的命名/验收，按 §7.12
追加注记升入 Tier 1；不得以“v1.0 还早”为由继续挂起。

## 4 不采纳

- **B（五项全部作为 `v1-PH-0` 硬门禁）**：phase-ID blocker A/B 需主规范裁定，
  不在本仓可控范围；把不可控项放在开卡门口会让重写收口后无限期停摆。
- **A（纯两级、无出口复核）**：Tier 2 有被后续重写挤掉的风险（SH-107/DOC-81 先例）；
  出口复核是 C 对 A 的必要补丁。

## 5 后续动作

- 新开 [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)、
  [DOC-83](../../issues/docs/doc-83-phase-id-migration-decision.md)、
  [CI-13](../../issues/ci/ci-13-g6-ledger-closure.md)。
- 现有 SH-104/105/107、DOC-81/82 状态不变；在各自 issue 内补“层级 + v1.0 门禁”注记。
- 本轮不改 `selfhost/**`、`test/**`；所有处置由 DEV/CI 在各自卡内施工。

## 追加注记（2026-11-21 所有者改判）

- `MAX_FUNCS` 容量切片从 **Tier 1（v1-PH-0 入口）** 改为 **`v1-PH-1 / S0`（v1.1）**；
  决策为 512 → **1024**，见 [提案](../../docs/proposals/ct-max-funcs-1024.md) 与
  [SH-109](../../issues/selfhost/sh109-max-funcs-capacity.md)。
- `v1-PH-0` 仍按 **501/512** 施工，新增顶层函数预算 ≤11；预计超过 11 个 helper 时
  停止并提前 S0，不得在 `v1-PH-0` 内顺手提上限。
- 本注记只改 Tier 归属，不推翻 §1 其余四项（SH-104/105、E88-1、phase-ID、G1/G6、历史债）。
