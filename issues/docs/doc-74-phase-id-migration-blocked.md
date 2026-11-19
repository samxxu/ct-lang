---
id: DOC-74
title: "phase-ID 迁移未执行：无账本/双认，blocker A/B/C 未裁定"
status: open
area: docs
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
blocked-by: "主规范采纳 + A/B/C 裁定"
---

# DOC-74 · phase-ID 迁移仍被 blocker 挂起

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §5.3；[phase-migration-blockers](../../docs/planning/phase-migration-blockers.md)；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 现状

- `docs/planning/phase-id-ledger.md` 不存在；
- `docs/phases/` 与 `window:` 不存在；
- 卡片仍是 `docs/design/phaseNN.md`，0 张有顶层 `phase-id:`/`version-minor:`；
- blocker A（旧 major offset）、B（`docs/design` vs `docs/phases`）、C（旧卡字段）未裁定；
- 主规范文本仍自标“草稿（未落入任何项目）”，报告“1.17.0 已生效”不被规范自称支持。

## 期望

- 先由主规范/用户裁定 A/B/C；不得在未裁定前迁移；
- 迁移前**禁止新增裸 `PH-*` 引用**；
- 裁定后按 PN-4→PN-8：账本 W0→W1→W2、双认、旧形态负例；
- 不在 `v1-PH-0` 开卡前跳过迁移。

## 验收

- 账本存在且 `window:` 合法；
- 1–73 集合断言通过；
- W2 旧形态负例红；
- 新卡无裸 `PH-*`；
- 迁移提交不改 tag/battle/代码/测试。

## 范围

P1，blocked；非纯 DEV 任务；需 REQ/EDITOR + 主规范裁定。
