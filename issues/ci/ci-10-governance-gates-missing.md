---
id: CI-10
title: "治理门禁 G1/G2/G4/G5/G6/G7/G9 无同名入口，也未登记 deviation"
status: verified
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

## 复核（2026-11-20，REV）

**结论：REV 认可 defer 理由；`deferred` 属 REQ/USER，status 不动。**

```console
$ for g in g1 g2 g4 g5 g6 g7 g9; do
    bash tools/check.sh "$g" >/dev/null 2>/tmp/e
    printf '%s: exit=%s %s\n' "$g" "$?" "$(head -1 /tmp/e)"
  done
g1: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g2: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g4: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g5: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g6: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g7: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
g9: exit=2 usage: tools/check.sh g0 | g8 | battle-selftest
```

`tools/check.sh:66` 只分派 `g0 | g8 | battle-selftest`，与处置段一致。G6 依赖 CI-11、
G1/G4 依赖 DOC-74、G5 依赖 phase 卡字段、G2/G7/G9 属 P2，理由成立；缺的
`deviation: g1-g4-missing` 需用户签字，DEV 无权代签。

## 处理（REQ，2026-11-21）

- 状态：`open`（P1；2026-11-21 REV 复核后转 `verified`，见文末）
- owner：REQ/DEV
- next：G6/G5/G1 最小入口先做；G2/G4/G7/G9 登记 P2/deviation
- 不能关闭：门禁仍未实现

## 复核（2026-11-21，REV / CI-10）

**结论：verified。** `tools/check.sh` 的分派已覆盖 `g0|g1|g2|g4|g5|g6|g7|g8|g9`，每个
门禁都有可运行的入口、负例或明确偏离：

```console
$ for g in g0 g1 g2 g4 g5 g6 g7 g8 g9; do bash tools/check.sh "$g"; done
g0: OK (block 1.17.0, session-map present)
g1: OK (12 phase cards: title/status/tasks/exit-criteria/version-minor)
g2: SKIP (deviation: g2-acc-mapping; docs/design has no ACC-* map yet, tracked by CI-16)
check-docs: OK (2577 relative links in 397 files, v0.88.0, ...)   # g4
g5: OK (91 criteria: each has a definition + acceptance/test reference)
g6: OK (283 issues; open=46 verified=219 rejected=10 deferred=7 superseded=1)
g7: OK (secret scan 0 hits; check-warnings green)
g8: OK (PN-2 version coherence; 9 legacy offsets)
g9: OK (spec 1.17.0, sha256 c22c85ee08f2…, master spec)

$ sh test/gates/issue_ledger_test.sh
OK g6/ledger (5 negative cases + 1 positive)
$ sh test/gates/phase_card_test.sh
OK g1/g5 (good + 2 negative cases)
$ sh test/gates/secret_scan_test.sh
OK g7/secret-scan (clean + 1 negative)
```

逐项落实：

| 门禁 | 实现 | 负例 |
| --- | --- | --- |
| g6 | `tools/gates/issue_ledger.py`（闭集 / `fixed` 禁入 / 缺状态 / 双源一致 / `verified` 证据） | `test/gates/issue_ledger/` 5 条坏台账，全部红 |
| g5 | `tools/gates/phase_card.py g5`（E-ID 定义 + 验收/测试引用） | `bad_eid` 定义一次且无引用，红 |
| g1 | `tools/gates/phase_card.py g1`（title/status/tasks/exit-criteria/version-minor） | `bad_missing` 缺冻结字段，红 |
| g2 | `tools/check.sh g2` 只打印 SKIP；`deviation: g2-acc-mapping` + P2 CI-16 | 偏离有日期/理由/收敛/签字 |
| g4 | 复用 `test/docs/check-docs.py`（链接、版本、`applies-to`、phase 状态） | check-docs 自带既有负例/断言 |
| g7 | `secret_scan.py` + `selfhost/check-warnings.sh`；`G7_SANITIZERS=1` 追加 `check-sanitizers.sh` | `test/gates/secret_scan/leak`，红 |
| g9 | `tools/gates/spec_pin.py`（主规范在场比 sha/版本；不在场比 `docs/spec` 副本） | pin 漂移即红 |

- `g0`/`g8` 未改动；`selfhost/check-all.sh` 保持 11 道硬门禁不变，`tools/check.sh` 是
  AGENTS §6.4 的治理门禁入口（0.1 `门禁入口` 已同步）。`check-all` 不调用这些入口，避免把
  `g6` 的台账检查与 `g5` 的 phase 卡检查塞进构建链；
- **clean-HEAD 与 worktree 的差异**：复核时工作树有并发的 PKG-23 / v0.88.1 未提交改动，
  `g4` 因 `docs/README.md` 仍是 v0.88.0、`g7` 因 PKG-23 注释里的 `/*` 告警而红；两者在干净
  归档 HEAD `600e6595` 上分别为 `check-docs: OK` 与 `check-warnings: 502 ok, 0 failed`。
  并发改动落地后重跑 `bash tools/check.sh g4` / `g7` 即可。

## 处理（REV，2026-11-21）

- 状态：`verified`（P1 三项 + P2/P0 入口；P2 的 G2 以偏离 + CI-16 收敛）
- owner：REV
- 证据：`tools/check.sh` 分派、`test/gates/*` 负例、AGENTS 0.3 `deviation: g2-acc-mapping`
