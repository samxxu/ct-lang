# CI-13 · G1/G6 治理门禁缺位（台账闭合）

| 项 | 值 |
| --- | --- |
| 模块 | CI / 治理 |
| 定性 | 能力缺口（门禁未实现；或登记 deviation） |
| 严重度 | **P1（v1.0 发布，Tier 2）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-4；`AGENTS.md` §5.4；`tools/check.sh` |
| 状态 | **待办（CI/REQ）；或按 §5.4 登记 deviation** |

## 现象

`tools/check.sh` 只有 `g0` / `g8` / `battle-selftest`；G1（phase 卡完整性）与
G6（台账闭合）没有机械实现，也没有 `deviation:`。

评审统计：242 个 issue 条目中 **184 条状态词不在 §5.4 的 8 词闭集内**；
14 条 `待办`、15 条 open-ish；其中 SH-104/105 是 v1.0 硬闸门，DOC/PKG 多项是
v1-pre / 包契约收尾。

## 期望（二选一，需 EDITOR 记录）

| 方案 | 内容 | 验收 |
| --- | --- | --- |
| A 实现 G6 | 状态词闭集校验 + phase 收口去向 + `待办`/open 闭环 | `g6` 进 `tools/check.sh`；对当前台账给出可复跑的通过/失败清单 |
| B 登记 deviation | 写清不实现 G6 的理由、替代人工流程、复核频率 | `AGENTS.md` 的 `deviation:` 条目 + 下一次评审复核点 |

G1 至少覆盖：卡顶字段 `phase-id` / `version-minor` / 状态 / 入口/出口判据非占位。

## 验收（Tier 2，v1.0 发布前）

1. 184 条非闭集状态归一到 §5.4 闭集，或建立映射表并在 G6 中豁免；
2. 14 条 `待办` 逐条有 owner/去向（完成、转 issue、wontfix）；
3. G6 实现（方案 A）或 deviation（方案 B）二者有一；
4. G1 对 phase 卡字段做机械检查；
5. `check-all` 增加对应门禁或明确不计入的理由。

## 非目标

- 不在本 issue 内改 issue 内容/关闭历史条目（只做状态归一与门禁）；
- 不替代 SH-104/105 的证据台账；
- 不改 §5.4 的闭集词表（如需改，先改 AGENTS 并评审）。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（Tier 2）
- [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §4
- [issues/README.md](../README.md)
