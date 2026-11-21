---
id: DOC-74
title: "phase-ID 迁移未执行：无账本/双认，blocker A/B/C 未裁定"
status: deferred
area: docs
severity: P1
opened: 2026-11-20
confirmed-by: REQ-review-v077-1
blocked-by: "执行触发：v1-PH-0 开卡前（D-019 已裁定 A/B/C）"
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

## 处置（2026-11-20，DEV）

**结论：blocked（外部裁定未落地；本批不动）。**

已核实现状：

```console
$ test -f docs/planning/phase-id-ledger.md && echo yes || echo no
no
$ test -d docs/phases && echo yes || echo no
no
$ ls docs/design/phase[0-9]*.md | wc -l
16
$ grep -l '^phase-id:' docs/design/phase[0-9]*.md | wc -l
0
$ grep -l '^| version-minor |' docs/design/phase[0-9]*.md | wc -l
12
```

`docs/planning/phase-migration-blockers.md` 仍写 A（旧 `version-minor` 偏移）、
B（`docs/design` vs `docs/phases`）、C（旧卡字段）三项待裁定。

为什么本批不做：PN-11 禁止项目侧自改判定逻辑；PN-6 要求迁移由一个脚本 +
五条集合断言完成，前置是三行裁定；这是 REQ/EDITOR + 用户签字动作，
不是 DEV 代码修复。

下一最小动作：

1. 用户在 `docs/decisions/D-0xx.md` 写 A/B/C 三行裁定（含 `signer:`/`date:`）；
2. 写 `tools/migrate-phase-ids.py`：建 `docs/planning/phase-id-ledger.md`
   （`window: W1`）、机械重命名、跑 PN-6 五条断言、任一失败整体回滚；
3. 迁移提交只改文档/目录；迁移前后 `git tag` 列表逐字相同（PN-5）。

## 复核（2026-11-20，REV）

**结论：REV 认可 blocked 理由；status 不动（外部裁定未落地）。**

```console
$ test -f docs/planning/phase-id-ledger.md && echo yes || echo no
no
$ test -d docs/phases && echo yes || echo no
no
$ ls docs/design/phase[0-9]*.md | wc -l
16
$ grep -l '^phase-id:' docs/design/phase[0-9]*.md | wc -l
0
$ grep -l '^| version-minor |' docs/design/phase[0-9]*.md | wc -l
12
```

`docs/planning/phase-migration-blockers.md` 的 A（旧 `version-minor` 偏移）、B
（`docs/design` vs `docs/phases`）、C（旧卡字段）三项均在案且未裁定。PN-11 禁止项目侧
自改判定逻辑、PN-6 要求脚本 + 五条集合断言，blocked 理由成立；下一步确需用户
在 `docs/decisions/D-0xx.md` 写三行裁定。

## 处理（REQ，2026-11-21）

- 状态：`open`（P1，blocked）
- owner：REQ/EDITOR
- next：主规范/用户裁定 A/B/C；裁定前禁止新增裸 `PH-*`
- 不能关闭：迁移未开始，`v1-PH-0` 不能干净开卡


## 处置（REQ，2026-11-21）：deferred

A/B/C 已由 [D-019](../../docs/decisions/D-019.md) 裁定：d=0 继续；迁移到
`docs/phases/v0-PH-<n>/card.md`；旧卡迁移时补 `phase-id`/`version-minor`。
执行时点固定为 **`v1-PH-0` 开卡提交的前一步**（PN-6 五条断言 + W2 负例）。

本卡不立即执行的原因与触发条件见 D-019 §2–§3；执行前禁止新增裸 `PH-*` 引用。
`v1-PH-0` 开卡若未先迁移，按 G1/G6 拦截。
