---
id: CI-12
title: "fix-tags deviation 与本地 tag 不一致：v0.63.3/.4/.5 缺失"
status: verified
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

## 复核（2026-11-20，REV）

**结论：verified（处置段的 deferred 已被后续回补取代）。**

```console
$ git tag --list 'v0.63.*'
v0.63.0
v0.63.1
v0.63.2
v0.63.3
v0.63.4
v0.63.5
$ for t in v0.63.3 v0.63.4 v0.63.5; do
    printf '%s type=%s peeled=%s\n' "$t" "$(git cat-file -t "$t")" "$(git rev-parse "$t^{commit}")"
  done
v0.63.3 type=tag peeled=6879f85d9eea956b6baa9c142e682ea69ead4870
v0.63.4 type=tag peeled=fbb635629fc4e59b0db8cf44ee4880ed80e94147
v0.63.5 type=tag peeled=506039e815acc525f2a3a0de00bacd67f8696212
$ git ls-remote --tags origin v0.63.3 v0.63.4 v0.63.5
b899da2e8d51679727e3615e1855ba2905de78f8  refs/tags/v0.63.3
799dd4a201a591184f1c7606567fca73b10f4a5c  refs/tags/v0.63.4
595213e96db684c6a1e53735c2209b29f661ecb1  refs/tags/v0.63.5
```

三个 tag 均为 annotated；peeled 提交与 `docs/history/phase-log.md:201–203` 的
v0.63.5（SH-90）/v0.63.4（PKG-11）/v0.63.3（PKG-10）一一对应；远端 tag 对象 sha
与本地一致，已在 origin。处置段“按本轮不 push、不打 tag”的 deferred 文字是回补前的
历史陈述，不影响本条闭合。`g8` 自动查 fix tag 仍未实现（验收写“若纳入”，不阻断）。
