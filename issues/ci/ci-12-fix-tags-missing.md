---
id: CI-12
title: "fix-tags deviation 与本地 tag 不一致：v0.63.3/.4/.5 缺失"
status: open
area: ci
severity: P2
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
---

# CI-12 · fix tag 缺失

## 来源

battle [review-v077-1](../../battle/review-v077-1/verdict.md) 证据席额外发现；`AGENTS.md` 的 `deviation: fix-tags`。

## 现象

`deviation: fix-tags` 要求 fix 也打 annotated tag；本地 `v0.63.3`、`v0.63.4`、`v0.63.5` 缺失，但 phase-log 有对应 fix 行；`g8` 不检查 fix tag。

## 期望

- 明确 fix tag 是本地/远程都必须，还是仅远程；
- 缺失的 tag 回补（若提交仍可达）或登记例外；
- `g8` 增加 fix tag 一致性检查，或把该 deviation 收敛为“仅远程”并写清。

## 验收

- `git tag --list 'v0.63.*'` 与 phase-log 的 fix 行一致；
- 缺失项有回补或例外记录；
- `g8` 能对缺失 fix tag 报红（若纳入）。

## 范围

P2；不阻塞 1.0，但影响发布可追溯。
