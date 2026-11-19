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

## 处置（2026-11-20，DEV）

**结论：deferred（提交已确认可达；按本轮“不 push、不打 tag”约束未创建 tag）。**

已核实现状：

```console
$ git tag --list 'v0.63.*'
v0.63.0
v0.63.1
v0.63.2
$ for t in v0.63.3 v0.63.4 v0.63.5; do printf '%-9s ' "$t"; git rev-parse -q --verify "refs/tags/$t^{commit}" || echo MISSING; done
v0.63.3   MISSING
v0.63.4   MISSING
v0.63.5   MISSING
$ for sha in 6879f85d fbb63562 506039e8; do git merge-base --is-ancestor "$sha" HEAD && echo "$sha reachable"; done
6879f85d reachable
fbb63562 reachable
506039e8 reachable
$ git show -s --format='%h %s' 6879f85d fbb63562 506039e8
6879f85d fix(pkg): default get selects newest tag
fbb63562 fix(pkg): report ct get details
506039e8 fix(ct-ast): SH-90 compile 模式 --freestanding 不再拼内置层（v0.63.5）
```

`docs/history/phase-log.md:201/202/203` 的 v0.63.5 / v0.63.4 / v0.63.3 行
与上面三个提交一一对应。**三项都可达，不属于“不可达/无法确认”例外。**

为什么没打 tag：本轮任务书在总则与提交要求两处写明“不 push、不打 tag”，
与“可回补则创建 annotated tag”冲突；按更严/更近的用户约束，本轮只登记
证据，不创建 tag。

下一最小动作（需用户一句授权；只建本地 annotated tag，不 push）：

```console
$ git tag -a v0.63.3 6879f85d -m "v0.63.3 PKG-10 默认取最新 tag（6879f85d）"
$ git tag -a v0.63.4 fbb63562 -m "v0.63.4 PKG-11 get 输出详情（fbb63562）"
$ git tag -a v0.63.5 506039e8 -m "v0.63.5 SH-90 compile 模式 --freestanding（506039e8）"
$ git tag -l --format='%(refname:short) %(objecttype)' 'v0.63.*'
```

之后可把 fix-tag 一致性并入 `tools/gates/version_coherence.py`（当前只查
message 含 `PH-<n> closeout` 的 phase tag）。
