---
id: CI-11
title: "问题台账未闭合：220 个状态行中 175 行不合规，7+ 已修仍 open"
status: verified
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

## 处置（2026-11-20，DEV）

**结论：deferred（规模 + 5.4 分权；本批只写处置，不改状态）。**

已核实现状（扫描口径：`issues/**/*.md` 的 `| 状态 |` 单元格首词比对 §5.4 八词）：

```console
$ find issues -name '*.md' ! -name README.md | wc -l
230
$ grep -rl '^| 状态 |' issues --include='*.md' | wc -l
220
# 扫描结果（本会话）：
status rows: 220
{'non-closed-set': 168, 'fixed-in-status': 6}
files with no status at all: 0
```

- 6 个把 `fixed` 写进 `| 状态 |`：`SH-68`、`SH-69`、`SH-70`、`SH-72`、
  `SH-74`、`SH-75`；
- 168 行非闭集（“已修”“待复核”“无结论”等自然语言）；
- 7 个“已修仍 open”的探针本轮已复跑，证据写进各自处置段
  （LANG-3/4/9/11/16/17、SH-76）。

为什么本批不做：

- 5.4 分权：`fixed`/`verified` 只能由 REV 写；DEV 只写正文处置段，
  不得批量改状态；
- 220 行跨 168 处自然语言改写需逐条对照证据；批量 sed 会制造
  “无结论关闭”，正是 CI-11 要防的；
- 验收要求“G6 能对负例报红”，而 G6 入口尚不存在（见 CI-10）。

下一最小动作：

1. 先落 `tools/gates/issue_ledger.py` + 负例（同 CI-10 第 1 项）；
2. 用该脚本生成清单（file / 旧状态 / 建议状态 / 证据锚点），交 REV 签字；
3. 按 area 分 4 批机械迁移，每批单独提交；6 个 `fixed`-in-status 由 REV
   改成合法状态词。

## 复核（2026-11-20，REV）

**结论：REV 认可 defer 理由；`deferred` 属 REQ/USER，status 不动。**

复算（`issues/**/*.md`，跳过代码块，归一化去 `**`/反引号、按全角 `（` 截首词）：

```console
files: 230
status rows: 220
open: 24 verified: 17 fixed: 6 rejected: 4 superseded: 1
outside closed set: 168
fixed-in-status files: sh68 sh69 sh70 sh72 sh74 sh75
front-matter status files: 10
```

220 / 24 / 168 与处置段一致；6 个 `status=fixed` 为 SH-68/69/70/72/74/75；只有
front-matter 状态的有 10 个（本批处置新增 9 个 + SH-92）。168 行非闭集 + 6 行 `fixed`
的规模与“批量 sed 会制造无结论
关闭”的风险都成立，5.4 分权也成立。本轮只复核，不做全量迁移；CI-11 的验收仍待
`tools/gates/issue_ledger.py` + G6。

## 处理（REQ，2026-11-21）

- 状态：`open`（P1；2026-11-21 REV 复核后转 `verified`，见文末）
- owner：REV/DEV
- next：先闭合 7 个已修仍 open，再做状态词格式迁移；不批量 sed 掩盖
- 不能关闭：175 行仍不合规

## 复核（2026-11-21，REV / CI-11）

**结论：verified。** 台账已按 §5.4 八词归一，机械门禁与负例同时落地：

```console
$ python3 tools/gates/issue_ledger.py .
g6: OK (283 issues; open=46 verified=219 rejected=10 deferred=7 superseded=1)
$ sh test/gates/issue_ledger_test.sh
OK g6/ledger (5 negative cases + 1 positive)
```

验收逐条对照：

| 验收项 | 结果 |
| --- | --- |
| 0 个非闭集状态 | 283 / 283 合规（`issue_ledger.py` 扫描 `issues/**/*.md`，排除 README） |
| 0 个 `status: fixed` | 0；`fixed` 只保留在正文/`处置证据` 行 |
| 0 个缺状态 | 0；259 条用 `| 状态 |`、24 条用 front-matter `status` |
| 7 个“已修仍 open”探针 | LANG-3/4/9/11/16/17、SH-76 全部独立复跑通过，转 `verified` |
| 6 个 `fixed`-in-status | SH-68 证据不足留 `open`；SH-69/70/72/74/75 转 `verified` |
| G6 负例 | 5 条坏台账全部红，正例绿 |
| README 索引/统计 | 新增「CI-11 台账归一」节：统计、映射规则、6 条、7 探针、SH-103/CI-15 |

迁移规则：旧状态单元格里的日期/提交/验证说明不丢，迁到同表的 `| 处置证据 |` 行；状态行只留
八词之一。状态与证据的对应见 `issues/README.md` 的同名节。

## 处理（REV，2026-11-21）

- 状态：`verified`（P1）
- owner：REV
- 证据：`tools/gates/issue_ledger.py`、`test/gates/issue_ledger/`、`issues/README.md`
