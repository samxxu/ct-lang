---
id: DOC-75
title: "v0.77 文档漂移批：typecheck/test README/tutorial/AGENTS/session-map"
status: open
area: docs
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# DOC-75 · v0.77 文档漂移批

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §4；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## P1 子项

| ID | 位置 | 现状 | 修正 |
| --- | --- | --- | --- |
| D-1 | [typecheck-semantic-plan](../../docs/planning/typecheck-semantic-plan.md) | “未开卡”，基线 v0.65.1 | PH-68–71 已收口；改为历史计划/已完成 |
| D-2 | [docs/README](../../docs/README.md#L41) | 类型检查“未开卡” | 同上 |
| D-3 | [test/README](../../test/README.md#L6) | ast/errors 141、ast 119 | 实际 295 / 299 |
| D-5 | [AGENTS](../../AGENTS.md#L452) | `phase=PH-66` | 当前 PH-77 |

## P2 子项（可批处理）

- D-4 tutorial“16 个示例” → 实际 **51**（报告写 52，错）；
- D-6 session-map 表格被 blockquote 截断；
- D-7 roadmap Phase 76 写 v0.76.1 → v0.76.0（v0.76.1 是 SH-92 fix）；
- D-8 README 0.44.1 基线应标“最近实测/历史”；
- D-9 README 缺 `--emit-model` / `ct check --types`；
- D-10 architecture 只讲 L0；
- D-11 selfhost/README grammar 40 → 169；
- D-12 bare-metal 提案状态；
- D-13 `v[0]` 描述分包重核（A2 已硬错，A1/A3 未实现）；
- design window 12/12：下一次开 phase 前必须把 phase66 退役到 `docs/history/design/`；
- package-guide 补“官方 pin 强校验 / 第三方索引仅便利”的信任模型；
- README/package-guide 明确 git 网络失败/超时行为（与 CI-9 联动）。

## 验收

- 所有计数由脚本回填或在 `check-docs` 断言；
- 51/299/295/169 等数字与实测一致；
- `AGENTS` phase、session-map 表、roadmap 版本位一致；
- D-1/D-2 不再把已完成 phase 说成未开卡；
- 不把 D-4/D-6 等 P2 冒充 P1。

## 范围

P1 批，不占 phase；纯 docs，除计数脚本外不 bump。
