---
id: CI-11
title: "问题台账未闭合：220 个状态行中 175 行不合规，7+ 已修仍 open"
status: open
area: ci
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# CI-11 · 问题台账未闭合

## 来源

[full-review-v0.77.0](../../docs/reviews/full-review-v0.77.0.md) §5.1；battle [review-v077-1](../../battle/review-v077-1/verdict.md)。

## 实测

- 221 个 issue 文件；220 个有 `| 状态 |` 行，1 个只有 front-matter `status`；
- 24 行 `open`；
- 175 行不合规：168 个非 §5.4 闭集 + 6 个把 `fixed` 写进 `status` + 1 个缺状态行；
- 7 个已修仍 open 的探针：LANG-3/4/11/16/17、SH-76、LANG-9；
- PKG-10/11 有 fix 提交但仍 open；PKG-9 当前仍 open（报告“v0.58.2 修复”归因错）。

## 期望

1. 所有 issue 的 `status` 只允许 §5.4 八词；
2. `fixed` 只在正文处置段，不写进 `status`；
3. 每个 fixed/verified 有提交 sha/原始输出/复核；
4. front-matter 与表格状态单一来源，或明确迁移规则；
5. 已修仍 open 的逐条转 `fixed`/`verified`，不靠批量 sed 掩盖。

## 验收

- 机械扫描：0 个非闭集状态、0 个 `status: fixed`、0 个缺状态；
- 7 个已修项全部闭合；
- PH-75 卡“未做 vs ✅”矛盾消除；
- G6 能对负例报红。

## 范围

P1；与 CI-10 的 G6 同批；REV 负责复核，DEV 负责格式迁移。
