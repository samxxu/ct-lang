---
id: v1-readiness-1
head: 5605eb6c
trigger: 用户 2026-11-21 提交《v0.88.0 全面评审报告》并要求“有争议的地方 battle 决定”
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/**
---

# battle/v1-readiness-1 — v1.0 五项 P1 前置：全部作为 v1-PH-0 硬门禁，还是按归属分两级

## 争点

评审列出五项 P1：SH-104/105、`MAX_FUNCS` 501/512、phase-ID 迁移、G1/G6 治理、历史 High 证据债。
分歧是**处置层级**：

- **A（REQ）按归属拆分**：本仓能清的立即清（文档勘误、G6 机械门禁、容量决策记录）；
  跨仓/主规范项（index 仓、phase-ID blocker A/B）外派或挂主规范；历史债逐条“修记录或 wontfix”；
  不把五项都堵在 `v1-PH-0` 门口。
- **B（REVIEW）五项全部作为 v1-PH-0 硬前置**：清零前不开 `v1-PH-0`，不接受外派/降级。

只讨论**层级与归属**，不讨论各项内部实现；评审 D-1…D-8 的文档勘误不在本 battle（已按事实接受）。

## 背景与触发

- 触发：用户 2026-11-21 提交 [v0.88.0 全面评审](../../docs/reviews/full-review-v0.88.0.md)，
  要求接受项落库、争议项 battle。
- 当前 HEAD：`5605eb6c`（tag `v0.88.0`）。
- 相关：[v1 路线](../../docs/planning/v1-release-plan.md)、[phase 迁移 blocker](../../docs/planning/phase-migration-blockers.md)、
  [SH-104](../../issues/selfhost/sh104-j6-evidence-ledger.md)、[SH-105](../../issues/selfhost/sh105-goldens-static-freeze.md)、
  [SH-107](../../issues/selfhost/sh107-m0-commit-not-buildable.md)、[DOC-81](../../issues/docs/doc-81-phase85-clean-archive-dead-link.md)、
  [DOC-82](../../issues/docs/doc-82-phase85-e85-2-gate.md)。

## 逐条判据（J-1…J-6）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 五项逐项写明归属（本仓/跨仓/主规范）、负责人、验收命令 | 处置矩阵每行三列非空；缺项不通过 |
| J-2 | 不把跨仓或主规范决策伪装成本仓可清 | phase-ID blocker A/B、index 仓 `verify_row` 不得计入本仓清零 |
| J-3 | `v1-PH-0` 入口不被非本仓项阻塞；SH-104/105 必须在开卡前清零 | 入口清单只含本仓可验收项；证据链可复跑 |
| J-4 | 历史 High 证据债不得静默 open | SH-107/DOC-81/DOC-82 每项有“修/不修+理由+日期” |
| J-5 | `MAX_FUNCS` 决策有实测数据与用户签字位 | 501/512 实测；提高上限需 USER 签字；改用 `impl`/调整切片需数据 |
| J-6 | 处置可按项回滚，不夹带重写/特性 | 每项独立提交或独立 issue；与 PH-85…88 重写切片分离 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ（A：按归属拆分） |
| opposition | REVIEW（B：全部 v1-PH-0 硬门禁） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/**` |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2（§7.11）。
- 最多 3 轮；三轮无结论按 §7.10 出 C 或 open-question。
