# claim — battle/review-v077-1（主张席 REQ，主张 A）

| 项 | 值 |
| --- | --- |
| 主张 | `docs/reviews/full-review-v0.77.0.md` 的 5 条 P1 基本成立，**全部阻塞 v1.0**，均应落 issue/任务 |
| 基线 | `5b13fef4`（v0.77.0，2026-11-19） |
| 席位 | 主张席 REQ；opposition REVIEW；judge EDITOR |
| 举证口径 | 以下命令均在本机只读工作树实跑、原样粘贴；未读 `counter.md`，未改源码/规范/测试/issues，只写本文件 |
| 结论 | **4 条独立 issue + 1 条合并的文档批 issue**；整批阻塞 v1.0；报告「13 条已修」清单有 1 条不成立、1 条版本位无出处，落库时须逐条重核（见 §4 U2、§6） |

## 1 主张

报告对 v0.77.0 的定性是对的：产品正确性可信（11 门禁离线绿、1517/0），**1.0 的缺口在发布契约**——
门禁未把契约纳入机械判据、台账不闭合使发布说明不可审计、phase-ID 未迁移使 `v1-PH-0` 无法干净开卡、
文档实参漂移使 G0/L-3 读到错的 phase。五项不同类，但**同一时点阻塞**：1.0 是「对外承诺」，不是「编译器能跑」。

## 2 逐条：事实 / 证据 / 为何阻塞 1.0

### P1-1 `ct get` 的 git 子进程无超时 → 硬门禁可无限挂起

- 事实：`git_run` 的唯一实现是 `return system(full);`（`Pkg.h.ct:770`），`git clone --quiet`（`:944`）与
  `git -C … fetch`（`:951`）都经它；无 `timeout`、无 `GIT_TERMINAL_PROMPT=0`。探针只给**索引**的 `curl` 加了
  `--max-time 10`（`p77_external.sh:32`），`ct get` 调用在 `:62` 裸调；`check-ast.sh:994` 同步执行、无外层超时（§3 末条）。
- 证据：`/tmp/ct-full-review-check-all-offline.log:2269` 显示离线在 `curl` 阶段就以 77 skip 返回——
  **挂起窗口从未被离线复跑覆盖**：只有「索引可达 + clone 被黑洞/等凭据」才卡住。
- 为何阻塞 1.0：gate 8 是 11 道硬门禁之一，`check-all` 的 VERDICT 依赖它返回；挂起即拿不到裁决，
  发布检查表**不可满足**（不是「慢」，是「无结论」）；且这是产品缺陷，任何 `ct get` 用户同样会挂。
  让步：归 P1 而非 P0 是对的——离线/CI 有 skip 兜底，正常网络不挂。

### P1-2 治理门禁缺位，且未登记 deviation

- 事实：`tools/check.sh` 分派只有 `g0`/`g8`/`battle-selftest`（`:63-65`），`g6`/`g1` 实测 exit=2（§3 首条）；
  G4 前置 `docs/snippets/` 不存在；G2 的 `ACC-*` 只在规范副本里出现、仓内无映射；G7 无密钥扫描脚本。
- 为何阻塞 1.0：§6.4 的判据是「脚本是实现」；缺 G6 正是 P1-3 二十多个版本无人拦的**直接原因**（可指认的因果链）。
  要宣称「1.0 门禁全绿」就得说清哪套门禁——当前那套不含发布契约。
- 已让步：11 道产品门禁真实且强，「产品可信、契约未测」成立；「全绿不可信」只限于**发布契约维度**。

### P1-3 台账不闭合（状态词越界 + 已修仍 open）

- 事实：220 个 issue 有 `| 状态 |` 行，`open` 24 条，**168 条不在 §5.4 的 8 词闭集内**（与报告数字一致）。
  自相矛盾可指认到行：`pkg-10:9` 写 `**open**`，同文件 `:63` 写「版本：`v0.63.3`（fix，+PATCH）」（`phase-log.md:203`）；
  `pkg-11:9` open / `:43` v0.63.4 / phase-log:202 同形。
- 为何阻塞 1.0：G6「无结论关闭」无从执行；下游按 issue 表读到 24 条 open（含已发 fix），发布说明不可审计，
  `fixed` 的 DEV / `verified` 的 REV 分权（5.4）实际失效。
- 已让步：报告清单中 `PKG-9` 一条不成立（§4 U2），「13 条」须逐条重核；但**结论不依赖该清单**。

### P1-4 phase-ID 迁移未执行

- 事实：`phase-id-ledger.md` 与 `docs/phases/` 均不存在，`phase-migration-blockers.md:6` 写「**迁移未开始**」；
  AGENTS 实例化节仍写 `phase=PH-66`（`AGENTS.md:452`），实际已 PH-77。
- 为何阻塞 1.0：主规范 pin 1.17.0（`g0` OK），PN-1…PN-17 生效；`v1-PH-0` 干净开卡需账本 + `window:` + 负例，
  否则一开卡即违反 PN-1/PN-3/PN-8。影响面 66 roadmap 行 / 142 引用 / 51 ID（blocker §4）。
- 已让步：blocker A（参照实现只认 `minor == n`）是**主规范侧工具缺陷**，项目不得在适配层私改（PN-11），
  故正确落法是「issue + decision（待裁定）」，不是派给 DEV 的实现任务——削弱「可执行性」，不削弱「阻塞」。

### P1-5 文档漂移成簇（作为**一批**）

- 事实：`typecheck-semantic-plan.md:1` 仍写「规划中/未开卡」，而 PH-68…71 已收口于 v0.67.0–v0.70.0（`phase-log.md:193-196`）；
  `docs/README.md:41` 同口径写「**未开卡**」；`test/README.md:6` 写 141 个负例（实际 295）、`:18` 写 119 个目录（实际 299）；
  `tutorial.md:1903` 写 16 个示例（实际 51）；`AGENTS.md:452` 写 `phase=PH-66`；`session-map.md:21` 表格中插 blockquote，其后行脱表。
- 为何阻塞 1.0：`AGENTS.md:452` 不是散文——它是 `g0-landing` 的实参与 L-3 的输入，`session-map` 是 §9.3 的映射。
  计数类单看是 P2，但**同批**与 phase 值一起构成「用户与模型的第一入口是错的」。
- 已让步：D-1+D-2、D-3+D-4 合并成一条批 issue + 2 条 `check-docs` 断言，不逐条开 6 个 P1；`D-13` 报告自压 P2，不升格。

## 3 E1：命令 + 原始输出（实跑，未改写）

```console
$ bash tools/check.sh g6; echo "exit=$?"
usage: tools/check.sh g0 | g8 | battle-selftest
exit=2
$ grep -n "迁移未开始" docs/planning/phase-migration-blockers.md; ls docs/planning/phase-id-ledger.md
6:| 状态 | **迁移未开始**；先解决 blocker |
ls: docs/planning/phase-id-ledger.md: No such file or directory
$ grep -n "^| 状态 |" issues/packages/pkg-10-default-git-tag-oldest.md; sed -n "63p" issues/packages/pkg-10-default-git-tag-oldest.md
9:| 状态 | **open** |
- 版本：`v0.63.3`（fix，+PATCH）；`test/pkg` 144/0。
$ ls -d test/ast/*/ | wc -l; ls test/ast/errors/*.ct | wc -l; ls -d examples/*/ | wc -l; grep -n "phase=PH-" AGENTS.md
     299
     295
      51
452:| 对话清单 | 单会话；三类常驻会话未建，按 `deviation: single-session-workflow`；phase=PH-66 |
$ grep -n 'GIT_TERMINAL_PROMPT\|timeout' test/ast/p77_external.sh selfhost/check-ast.sh; echo "rc=$?"
rc=1
$ python3 -c 'import re,glob;C=set("open fixed verified reopened rejected deferred wontfix superseded".split());S=[re.sub(r"^\*\*|\*\*$","",m.group(1)).strip("`") for p in glob.glob("issues/**/*.md",recursive=True) for m in [re.search(r"^\|\s*状态\s*\|\s*(.*?)\s*\|\s*$",open(p,encoding="utf-8").read(),re.M)] if m];T=[x.split("（")[0].strip("*` ").lower() for x in S];print(len(S),sum(t=="open" for t in T),sum(t not in C for t in T))'
220 24 168
```

## 4 E2：`file:line`（S=支持己方，U=不利己方）

- **S1** `selfhost/ct-ast/tool/pkg/Pkg.h.ct:770` `return system(full);`（唯一子进程调用点，无超时）。
- **S2** `selfhost/check-ast.sh:994` 同步执行 `p77_external.sh`，case 只分 0/77/其它，无外层超时。
- **S3** `tools/check.sh:63-65` 分派仅 3 个子命令；`AGENTS.md:454` 的「门禁入口」行只写 `g0` + 11 道产品门禁 + `check-docs`。
- **S4** `issues/packages/pkg-10-default-git-tag-oldest.md:9` 对 `:63`；`pkg-11…md:9` 对 `:43`（同日状态与处置并存）。
- **S5** `docs/planning/phase-migration-blockers.md:6`；账本文件缺失。
- **S6** `AGENTS.md:452`；`docs/tutorial.md:1903`；`test/README.md:6,:18`。
- **U1（不利）** `tools/check.sh:5-8` 自述「this entry only makes G0 runnable; … eleven hard gates remain in
  `selfhost/check-all.sh`」+ `AGENTS.md:454`——项目是**明示替换**而非隐瞒，故措辞须限定为「未实现 §6.4 判据、未登记 deviation」。
- **U2（不利）** `docs/design/phase75.md:56` 写 `R1 SH-65 ⬜ 未做`、`:66` 又写 `✅`，`sh65…md:9` 仍 `open`；
  `pkg-9…md:97` 只有「**建议** v0.58.2」，报告写成「已修于 v0.58.2」——把计划当事实（A1/A2 行为在 `Pkg.h.ct:2158/2170`，引入于 `aa8621de` v0.55.0）。

## 5 E3：可证伪预测 + 反例

| # | 预测（若主张成立） | 一次性验证 | 反例（会使该条不成立） | 实测 |
| --- | --- | --- | --- | --- |
| 1 | 无超时兜底 | `grep -n 'timeout\|GIT_TERMINAL_PROMPT' p77_external.sh check-ast.sh` 无输出 | 任一命中 → P1-1 降级 | rc=1、零命中 |
| 2 | 治理门禁无实现 | `tools/check.sh g6` 非 0 | 存在同名子命令且绿 → P1-2 不成立 | exit=2 |
| 3 | 台账越界且不闭合 | 闭集外 ≥100 且 open ≥20 | 全部落在 8 词内 → P1-3 不成立 | 168 / 24 |
| 4 | 文档计数漂移 | `test/README` 应为 299/295，tutorial 应为 51 | 实测 119/141/16 → D-3/D-4 不成立 | 299/295/51 |

**反例自查（同时证伪报告细节）**：报告写「52 个示例目录」，实测 `ls -d examples/*/` = **51**。这不使 P1-5 失效
（方向与量级正确），但证明**计数必须脚本回填**——手工数字连评审报告都会错，落库以命令输出为准。

## 6 E4：代价

| P1 | 改动面 | 影响门禁 | 回退 |
| --- | --- | --- | --- |
| 1 | `Pkg.h.ct:757-770` + 调用点 `:944/:951`；`p77_external.sh` 外层 `timeout` + 假 `git` 负例；≈20–40 行 | gate 8 / 产品 `ct get` | 单提交 `git revert`，不波及其它门禁 |
| 2 | `tools/check.sh` 分派 + `tools/gates/*.py` 最小 G6/G5；或 AGENTS 0.3 登记 deviation（5–15 行，需用户签字）；实现路径 ≈200–400 行 | G1/G4/G6 | 新文件，revert 即净 |
| 3 | 220 处状态行归一 + 逐条 `fixed` 证据（引用提交 sha）；≈200 文件 / 220 行，脚本辅助 + 人工判定 | G6 | revert；但返工需重跑脚本 |
| 4 | 账本 + 迁移脚本 + 51 ID / 142 引用 / 66 roadmap 行 | G1/G4/G8 | **非纯 revert**：需账本 `window:` W2→W1，成本最高 |
| 5 | 6 处文档 + 2 条 `check-docs` 断言；≈60 行 / 6 文件 | gate 11 | 纯 revert |

## 7 E5：steelman B 与反驳

B 原文（`question.md` 位置 B）：「文档漂移应降为 P1/P2 混合批处理，不必每项单独阻塞；计数类可由脚本回填」、
「报告个别结论需重核/降级…」、「不能用「报告说 P1」代替可复现证据」。

**Steelman（B 最强处，先行自认）**：报告最脆弱的不是文档，而是**它自己没给逐条证据**——§2 挂起只有叙述，
13 条清单我没能全复现（PKG-9 版本位无出处、SH-65 卡自相矛盾），P1-4 的 blocker A 又不在项目权限内。
「按报告原文整批落 P1」确实会把 1 处错误与 1 处越权写进台账。

**反驳**：(1) 我自认的是**清单精度**与**修复路径**，不是「台账是否闭合」——PKG-10/11 两条自身矛盾即足以立案，
不依赖那 13 条；(2) 文档应合并为一批，但合并 ≠ 降级：`AGENTS.md:452` 是 `g0-landing`/L-3 的实参，错的是**治理事实**；
(3) 「不能用报告代替证据」我同意，本文件 §3/§4 已换成一手命令与 `file:line`——B 应指出哪条命令重跑不一致，而非要求降级；
(4) D-13/设计窗口/样例覆盖报告本就压 P2，P1 只有 5 条，无「误升 P1」膨胀（J-4 通过）。

## 8 结论：落法与合并建议

| # | P1 | 落法（§5.4 分权） | 阻塞 1.0 | 可合并 |
| --- | --- | --- | --- | --- |
| 1 | `ct get` 无超时 | 缺陷 issue（`issues/ci/` 或 `packages/`），含假 `git` 负例与红证 | **是** | 否：代码修复与探针兜底同属一事 |
| 2 | 治理门禁缺位 | issue：实现 G6+G5 最小子集 **或** 登记 `deviation:`（须用户签字） | **是** | 与 #3 同批验收，但独立条目 |
| 3 | 台账不闭合 | issue：220 处状态归一 + 逐条 `fixed`/`verified` 证据（DEV/REV 分权） | **是** | 可并入 #2 的批，但保留独立验收命令 |
| 4 | phase-ID 迁移 | issue + `docs/decisions/D-*.md`（blocker A/B/C 需裁定）；账本 + 迁移脚本 | **是**（`v1-PH-0` 开卡硬前置） | 否：涉及主规范裁定 |
| 5 | 文档漂移 | **一条** `DOC-*` 批：D-1+D-2 合并、D-3+D-4 交由 2 条 `check-docs` 断言、D-5/D-6 逐项勾 | **是**（整批，不逐条） | **是**（6 处合一，成本最低） |

**判定请求**：按 §7.9 请 EDITOR 逐条判 J-1…J-6；我方对 J-1、J-3 主张成立，对 J-4（无系统性升格）、J-6（P1-5 须合并）自认
——**唯一不接受「文档批可降级」**：合并是落法，降级是力度，二者不可互换。
