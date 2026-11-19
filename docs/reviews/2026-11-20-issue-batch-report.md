# 2026-11-20 issue 批处理报告

> 基线：v0.77.0（`5b13fef4`）→ 发布 v0.77.1（`9f1cf69d`）；复核 `e53f469c`。
> 范围：v0.77.0 全量评审开出的 9 条 front-matter open + 7 条“已修仍 open”的探针 + 同族 CI/DOC。

## 1 结果总览

| 结果 | 条数 | 条目 |
| --- | --- | --- |
| 修复并经 REV 复核（`verified`） | 17 | CI-9、CI-12、SH-93、DOC-75、SH-65、SH-67、SH-76、SH-79、LANG-3/4/9/11/16/17/19、PKG-10/11 |
| 维持原状（defer/block 理由成立） | 5 | CI-10、CI-11、DOC-74、SH-94、TEST-23 |
| 待 REQ 改判 | 1 | LANG-20（复测为误报，`rejected` 属 REQ/USER） |
| 未验证（宿主 skip） | 1 | TEST-21（Renode 本机 skip 77，CI Linux 为权威） |

## 2 已修复（发布 v0.77.1）

| issue | 修复 | 证据 |
| --- | --- | --- |
| CI-9 | `git_run` 加 `GIT_TERMINAL_PROMPT=0`、低速/超时配置与 `timeout` 包装 | `p77_net_timeout`: 基线 40s 挂起红 → v0.77.1 5s 有界失败绿 |
| SH-93 | 删除 `c_boundary_for` 的 `c_cwd_in_tree()` 全量 allow | `p65_policy`: 基线仓根+外部输入 allow 红 → v0.77.1 `OK p65/policy`；1299 源回归绿 |
| CI-12 | 回补 annotated tag `v0.63.3/.4/.5` 并推送 | `cat-file -t`=tag，peeled 分别 `6879f85d`/`fbb63562`/`506039e8`，远端三条俱全 |
| DOC-75 | D-1…D-13 文档批（13 项） | `check-docs OK`、`g0 OK`；计数 295/299/51/169 实测一致 |

版本：五处 `CTC_VERSION=0.77.1`；`check-all: OK (11 hard gates green)`，`check-ast 1519 passed / 4 skipped`，包用例 147/0。

## 3 维持原状（需用户/REQ 决策）

| issue | 结论 | 原因 / 下一步 |
| --- | --- | --- |
| CI-10 | defer | `g1/g2/g4/g5/g6/g7/g9` 仍 exit 2；实现到 `tools/gates/` 或登记 deviation（需用户签字） |
| CI-11 | defer | 220 状态行 / 168 非闭集 / 6 个 `status=fixed`；需先落 G6 再批量规范化 |
| DOC-74 | blocked | 无 `phase-id-ledger`/`docs/phases`；A/B/C blocker 待裁定 |
| SH-94 | defer | Expr 7575 / Emitter 6694 / Stmt 4458 行；`MAX_TEXT` 实测 14 处；1.0 后重构 |
| TEST-23 | defer | 无 llvm-cov/lcov、ct-ast 无单测；容量边界夹具待补 |
| LANG-20 | open（待 REQ） | 复测为误报；`rejected` 只能 REQ/USER 写 |
| TEST-21 | skip | 本机 Renode 不可用；CI Linux 才是权威运行点 |

## 4 已知偏差（诚实记录）

- v0.77.1 把 CI-9 与 SH-93 两个 fix 合入一个 PATCH，未严格按 V-3“一次 fix 一次 +1”；两处实现提交也早于版本 bump（V-5 非字面满足）。如需严格拆分，可回滚后分两次 PATCH，但会重写已推历史。
- CI-12 期望的 `g8` 自动检查 fix tag 未实现（原验收写“若纳入”）。
- SH-79 处置段引用的 `a0f2e2c` 不是可解析 sha（实际 PH-74 为 `ffc08538`/`5d271142`），仅引用瑕疵。
- CI-11 的 175 行历史状态未批量改写：按 5.4，`verified/deferred` 需 REV/REQ，不能由 DEV 机械回填。
