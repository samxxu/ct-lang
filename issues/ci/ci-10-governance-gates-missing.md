---
id: CI-10
title: "治理门禁 G1/G2/G4/G5/G6/G7/G9 无同名入口，也未登记 deviation"
status: open
area: ci
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# CI-10 · 治理门禁只实现 g0/g8

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §5.2；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 现状

`tools/check.sh` 的分派只有：

```text
g0 | g8 | battle-selftest
```

`g1`–`g7`、`g9` 全部 exit 2；AGENTS §6.4 列出的 G1/G2/G4/G5/G6/G7/G9 没有同名子命令，也没有 `deviation:`。

## 分组（battle 裁定）

**P1 先做**

- G6：台账闭合（与 CI-11 同批）；
- G5：判据 ↔ 用例/负例的最小机械子集；
- G1：phase 卡完整性（依赖 DOC-74 的 phase-ID blocker B/C）。

**P2 / deviation**

- G2 ACC 映射；
- G4 snippet/300 行/`applies-to`；
- G7 密钥/sanitizer；
- G9 独立入口（`check-docs` 已覆盖 pin/版本部分）。

## 期望

- 每个未实现的 G 编号要么有最小入口，要么在 `AGENTS.md` 0.3 登记明确 `deviation:`（含理由、日期、收敛）；
- 不得用“`check-all` 替代”代替 G1/G2/G5/G6/G7 的判据；
- `tools/check.sh` 的 usage 与实际分派一致。

## 验收

- `tools/check.sh g6` 对已知坏台账返回非 0；
- `g5` 至少能抓一条“判据无测试”；
- 每个未实现项有 deviation 或 P2 issue 编号；
- `g0`/`g8` 不回归。

## 范围

P1/P2 拆分；不占 phase。
