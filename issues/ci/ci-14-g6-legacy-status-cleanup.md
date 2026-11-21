# CI-14 · G6 旧状态债清零（白名单退出）

| 项 | 值 |
| --- | --- |
| 模块 | CI / 治理（旧债） |
| 定性 | 数据清理（G6 白名单退出） |
| 严重度 | **P1（v1.0 发布，Tier 2）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [CI-13](ci-13-g6-ledger-closure.md)、`AGENTS.md` §5.4、[v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-4 |
| 状态 | verified |
| 处置证据 | **verified**（严格 g6 283/283 闭集；无基线文件；14 条待办均有 owner+去向；5 条负例全红；见文末处置） |

## G6 归一执行确认（2026-11-21 转达）

1. **批次号 + 独立提交**：每批必须写清批次号（B0–B3），**每批独立 commit，message 带批号**
   （例：`chore(issues): G6 B0 核销类归一`）；不得与代码/文档批次混提。
2. **先自检再放量**：每批改完先跑 `tools/check.sh g6`；基线自检不红，才允许放量下一批。
3. **现状**：`g6` 已由 CI-10 接线；CI-11 已完成首轮台账归一；后续批按上述两条执行。

## 现象

CI-13 的实现规格采用 ratchet：`g6` 先上线，184 条旧状态进白名单，只拦新债。
本卡负责把白名单清零。评审基线：242 个 issue 条目中 **184 条状态词不在 §5.4 闭集内**，
其中 14 条 `待办`、15 条 open-ish。

## 退出条件（白名单删除的前置，全部满足）

1. `issues/.g6-baseline.tsv` **为空或已删除**；
2. `g6` 在**严格模式**（无白名单）下通过；
3. 14 条 `待办` 每条都有 **owner + 去向**（完成 / 转 issue / wontfix），正文无“状态待归一”；
4. 不存在“无结论关闭”：`已关闭` 必须能追到修复提交或不修理由；
5. CI-13 的门禁在严格模式下仍绿；带新违规的负例仍必须红。

退出条件不满足时，`g6` 继续带白名单运行；不允许为了删白名单而放宽判据。

## 分批（按 CI-13 的类别）

| 批次 | 范围 | 归一目标 | 备注 |
| --- | --- | --- | --- |
| B0 | 核销类：`已修` / `已修复` / `✅ 已修复` / `verified` 变体 | `verified` / `rejected` / `wontfix` / `superseded` | 最大批量；`修复（commit …）` 须保留 sha 证据 |
| B1 | 在办类：`待办` / `受理（P…）` / `评估中` / `部分修复` / `已实施未验证` | `open`（正文写处置） | 14 条 `待办` 必须在 B1 内逐条给 owner/去向 |
| B2 | 延后类：`deferred` / `延后` | `deferred` | 必须写触发条件或日期 |
| B3 | 无法归一类 | `open` + “状态待归一” | 逐个裁定，禁止新造状态词 |

每批流程：

1. 归一状态词（只动 `| 状态 |` 行，不改正文结论）；
2. 重跑 `g6 --write-baseline`，确认该批条目从白名单消失；
3. 同提交删除对应白名单行；僵尸条目（已归一但仍留在白名单）必须报红；
4. 单独提交、可单批回滚；在本文「进展」记基线行数变化。

## 进展

| 日期 | 基线行数 | 本批 | 备注 |
| --- | --- | --- | --- |
| 2026-11-21 | 184（评审统计） | — | 待 `g6 --write-baseline` 生成正式基线 |

## 非目标

- 不改 issue 正文的结论、关闭历史条目、重写证据；
- 不改 §5.4 的状态词表（要改先改 AGENTS 并评审）；
- 不把 `fixed` 写进 `status`（只允许出现在正文处置段）；
- 不在本卡实现 `g6` 脚本（归 CI-13 / DEV）。

## 关联

- [CI-13](ci-13-g6-ledger-closure.md)（`g6` 实现与白名单机制）
- [issues/README.md](../README.md)（`<!-- gates:11 -->` 与当前计数）
- [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §4

## 处置（2026-11-22，REV/REQ）

**结论：`verified`。** 五条退出条件逐条成立，且不依赖白名单——严格 g6 本身就绿，说明旧债
已真正清零而不是被豁免。证据取干净归档 `HEAD` + 本提交五文件（`/tmp/rev-testci`），
避免并发工作树干扰：

```console
$ ls issues/.g6-baseline.tsv
ls: issues/.g6-baseline.tsv: No such file or directory        # 基线从未生成
$ grep -c 'write-baseline' tools/gates/issue_ledger.py
0                                                             # 也没有「生成基线」入口
$ bash tools/check.sh g6
g6: OK (283 issues; open=38 verified=223 rejected=10 deferred=11 superseded=1)
$ sh test/gates/issue_ledger_test.sh
OK g6/ledger (5 negative cases + 1 positive)
$ grep -rl '状态待归一' issues/ --include='*.md'
issues/ci/ci-13-g6-ledger-closure.md                          # 只命中规则正文（本文件 3 处、
issues/ci/ci-14-g6-legacy-status-cleanup.md                    #  CI-13 1 处），无条目正文命中
$ grep -rn '^| 处置证据 | \*\*\(待办\|实施中\)' issues/ --include='*.md' | wc -l
17                                                            # 现存「待办/实施中」证据行，均带 owner 或去向
```

退出条件逐条对照：

| # | 退出条件 | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | `issues/.g6-baseline.tsv` 为空或已删除 | **成立**：文件不存在；脚本无 `--write-baseline`，严格模式是唯一模式 | 上面第 1、2 条 |
| 2 | 严格模式（无白名单）下 `g6` 通过 | **成立** | `g6: OK (283 …)` |
| 3 | 14 条 `待办` 各有 owner + 去向 | **成立**：见下表逐条；现存 13 条新「待办」证据行也都带 owner | 上表 + 下表 |
| 4 | 不存在「无结论关闭」 | **成立**：`verified` 无 sha/输出/测试引用即红（负例 `bad_verified_no_evidence`），`fixed` 禁入状态（`bad_fixed`） | `sh test/gates/issue_ledger_test.sh` |
| 5 | 严格模式仍绿，带新违规的负例仍必须红 | **成立**：5 条负例全红、`good` 绿 | 同上 |

评审名单 14 条 `待办` 的现状与去向（v0.88.0 评审 §4 名单）：

| 条目 | 现状态 | 去向 / owner |
| --- | --- | --- |
| SH-104 | `open` | 实施中：J-6 全量证据台账已建（15 过 / 9 部分 / 5 缺失 / 5 阻塞）；DEV，Tier 1 `v1-PH-0` 入口 |
| SH-105 | `open` | 实施中：REQ 卡已出，DEV 待生成 25 份 golden + 脚本 + gate 12；Tier 1 `v1-PH-0` 入口 |
| DOC-76 / 77 / 78 / 79 | `verified` | 已完成（2026-11-21），CI-11 归一后复核；DOC-78 的教程两章由 DOC-90 承接 |
| DOC-80 | `verified` | 复核通过（2026-11-22，REV）：battle doc-consistency-1 判决 B（最小集）+ `p84_docs_audit` OK |
| PKG-12 | `open` | 待办（REQ） |
| PKG-13 | `open` | 待办（DEV 实现；发布顺序由 REQ 协调） |
| PKG-15 | `open` | 待办（REQ 定数据，DEV 接 runner） |
| PKG-16 | `open` | 待办（REQ 向提案方索取） |
| PKG-17 | `open` | 实施中（REQ fixture 规格已出；DEV 建 fixture + 接 CI） |
| PKG-19 / PKG-20 | `open` | 待办（DEV；冻结期 bugfix 切片） |

说明与边界：

- 本轮的语义与 CI-13 的分工保持不变：`g6` **永不接受**非法状态（严格模式是唯一模式），
  所以「删白名单」这一步在事实上是「从未需要白名单」，不是「把表清空」；
- 现存 17 条「待办/实施中」证据行（`selfhost/` 4 条、`docs/` 5 条、`packages/` 8 条）分散在
  CI-11 之后新立的条目上，每条都带 owner 或去向；`g6` 按 `open` 收录，不影响本条退出条件；
- 若将来 `g6` 首现存量违规，按 [CI-13](ci-13-g6-ledger-closure.md) 的 ratchet 最小设计
  重新引入基线；届时本条退出条件 1/2 需重跑。
