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

## 处置（2026-11-20，DEV）

**结论：deferred（本批不做；不阻塞 CI-9/SH-93）。**

已核实现状：

```console
$ for g in g1 g2 g4 g5 g6 g7 g9; do bash tools/check.sh "$g" >/dev/null 2>/tmp/e; printf '%s: exit=%s %s\n' "$g" "$?" "$(head -1 /tmp/e)"; done
g1: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g2: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g4: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g5: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g6: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g7: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g9: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
```

`tools/check.sh` 的分派仍只有 `g0 | g8 | battle-selftest`。

为什么不本批做：

- G6 依赖 CI-11 的 220 行台账迁移；先落门禁会把当前台账直接判红；
- G1/G4 依赖 DOC-74 的 A/B/C 裁定；PN-11 禁止项目侧自改判定逻辑；
- G5 需要“判据 ↔ 用例/负例”的机械映射，前置是 phase 卡任务清单字段；
- G2/G7/G9 属 P2，且 G9 的 pin 部分已由 `test/docs/check-docs.py` 覆盖。

下一最小动作（按序）：

1. `tools/gates/issue_ledger.py`：按 §5.4 八词校验 `issues/**/*.md` 的
   `| 状态 |` 与 front-matter `status`，在 `test/gates/ledger/` 配 3 条负例，
   于 `tools/check.sh` 增加 `g6)`；
2. CI-11 迁移后跑 `bash tools/check.sh g6`；
3. G1/G4 等 DOC-74 裁定；未裁定前在 `AGENTS.md` 0.3 登记
   `deviation: g1-g4-missing`（需用户签字，DEV 不代签）。
