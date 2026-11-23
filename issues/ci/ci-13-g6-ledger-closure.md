# CI-13 · G1/G6 治理门禁缺位（台账闭合）

| 项 | 值 |
| --- | --- |
| 模块 | CI / 治理 |
| 定性 | 能力缺口（门禁未实现；或登记 deviation） |
| 严重度 | **P1（v1.0 发布，Tier 2）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-4；`AGENTS.md` §5.4；`tools/check.sh` |
| 状态 | deferred |
| 处置证据 | **核心验收已达成（严格 g6，283/283 闭集）；ratchet/基线未实现且当前无必要 → deferred（触发：台账再增长 > 0，或 v1.1 复核点；owner REV）** |

## 实施规格（方案 A：ratchet 版 G6，2026-11-21）

### 1. 状态归一映射（含核销类）

§5.4 的 `status` 闭集是 7 个值：`open` / `verified` / `reopened` / `rejected` /
`deferred` / `wontfix` / `superseded`（`fixed` 只允许出现在正文处置段，不得写进 `status`）。
按**类别**归一，避免逐条猜：

| 类别 | 现状写法（模式） | 归一为 | 说明 |
| --- | --- | --- | --- |
| **核销类** | `已修` / `已修复` / `✅ 已修复` / `修复（commit …）` | `verified` | 有独立复现与证据；只有作者自证时正文写 `fixed`，`status` 仍由 REV 置 `verified` |
| **核销类** | `不采纳` / `rejected` / `已关闭（不采纳）` | `rejected` | 理由与决策记录 |
| **核销类** | `wontfix` / `永不修` | `wontfix` | USER 裁定 |
| **核销类** | `superseded` / `被取代` | `superseded` | 指向新条目 id |
| **在办类** | `open` / `**open**` / `待办` / `待办（DEV…）` / `受理（P…）` / `评估中` / `部分修复` / `已实施未验证` | `open` | 处置写正文；`部分修复` 不置 verified |
| **在办类** | `reopened` | `reopened` | 复核未过 |
| **延后类** | `deferred` / `延后` | `deferred` | 触发条件或日期 |

- 无法归一的写法：先归 `open`，并在正文补“状态待归一”一行；不得新造状态词。
- `已关闭` 必须按原因拆分：修复完成 → `verified`；不修 → `wontfix`/`rejected`；
  仅“没人跟了”不允许关闭。

### 2. 白名单（挂 issue，带退出条件）

- 基线文件 `issues/.g6-baseline.tsv`：`path<TAB>现状<TAB>归一键<TAB>类别`；
  只收**尚未归一**的存量行，由 `g6 --write-baseline` 生成、REQ 复核后入库。
- **白名单必须挂追踪 issue**：旧债清零由 [CI-14](ci-14-g6-legacy-status-cleanup.md) 跟踪；
  退出条件写在 CI-14（基线清空、`g6` 严格模式无白名单、14 条 `待办` 全有去向）。
- 反向约束：白名单条目对应的文件已归一、或文件不存在 → 按“僵尸条目”报红；
  新增 issue 不受白名单保护，必须直接写合法 `status`。

### 3. G1 与 check-docs 的边界

| 检查 | 归属 | 覆盖 | 不覆盖 |
| --- | --- | --- | --- |
| G1 `g1-phase-card` / `g1-version` | `tools/check.sh g1` | phase 卡字段：`phase-id`、`version-minor`、状态、入口/出口判据非占位；新卡窗口规则 | 文档链接、版本 token、门禁计数、设计窗口归档 |
| check-docs（第 11 道） | `test/docs/check-docs.py` | 链接、版本 token、门禁条数、design window、phase 状态与 roadmap 一致、spec pin | phase 卡字段完整性（不在 docs 门禁里重复） |

- 唯一交集是「phase 状态」：**状态词合法性归 G6**，**状态与 roadmap 一致性归 check-docs**；
  两边不互相替代，也不重复报同一错误。
- G1/G6 通过 `tools/check.sh` 提供同名子命令；是否并入 `check-all.sh` 的 11 道硬门禁，
  由 EDITOR 记录，不默认加条数。

### 4. 门禁先开，不等旧债清完

- `g6` 与基线白名单**同一次提交**落地；落地即进 CI（或 `tools/check.sh` 的常规路径），
  立刻拦新债。
- 184 条旧债的清零是 [CI-14](ci-14-g6-legacy-status-cleanup.md) 的节奏，不阻塞 `g6` 上线；
  禁止把“旧债清零”当作门禁实现的前置。
- 上线证据：一次带新违规的负例提交必须红；一次不带新违规的提交必须绿（基线内）。

## 现象

`tools/check.sh` 只有 `g0` / `g8` / `battle-selftest`；G1（phase 卡完整性）与
G6（台账闭合）没有机械实现，也没有 `deviation:`。

评审统计：242 个 issue 条目中 **184 条状态词不在 §5.4 的 8 词闭集内**；
14 条 `待办`、15 条 open-ish；其中 SH-104/105 是 v1.0 硬闸门，DOC/PKG 多项是
v1-pre / 包契约收尾。

## 期望（二选一，需 EDITOR 记录）

| 方案 | 内容 | 验收 |
| --- | --- | --- |
| A 实现 G6 | 状态词闭集校验 + phase 收口去向 + `待办`/open 闭环 | `g6` 进 `tools/check.sh`；对当前台账给出可复跑的通过/失败清单 |
| B 登记 deviation | 写清不实现 G6 的理由、替代人工流程、复核频率 | `AGENTS.md` 的 `deviation:` 条目 + 下一次评审复核点 |

G1 至少覆盖：卡顶字段 `phase-id` / `version-minor` / 状态 / 入口/出口判据非占位。

## 验收（Tier 2，v1.0 发布前）

1. 184 条非闭集状态归一到 §5.4 闭集，或建立映射表并在 G6 中豁免；
2. 14 条 `待办` 逐条有 owner/去向（完成、转 issue、wontfix）；
3. G6 实现（方案 A）或 deviation（方案 B）二者有一；
4. G1 对 phase 卡字段做机械检查；
5. `check-all` 增加对应门禁或明确不计入的理由。

## 非目标

- 不在本 issue 内改 issue 内容/关闭历史条目（只做状态归一与门禁）；
- 不替代 SH-104/105 的证据台账；
- 不改 §5.4 的闭集词表（如需改，先改 AGENTS 并评审）。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（Tier 2）
- [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) §4
- [issues/README.md](../README.md)

## 处置（2026-11-22，REV/REQ）

**结论：`deferred`（触发：台账再增长 > 0，或 v1.1 复核点；owner REV）。**
本条的**核心验收已达成并被严格门禁替代**；未达成的是「ratchet + 基线白名单」那一段——
核对结果是**没有实现**，而且按当前台账已无必要，故整段延后而不是补写一个空机制。

核对（干净归档 `HEAD` + 本提交五文件，`/tmp/rev-testci`）：

```console
$ ls issues/.g6-baseline.tsv
ls: issues/.g6-baseline.tsv: No such file or directory      # 基线不存在
$ grep -n 'write-baseline\|whitelist\|ratchet\|baseline' tools/gates/issue_ledger.py ; echo rc=$?
rc=1                                                        # 脚本里 0 命中：没有基线/白名单模式
$ grep -n '^g6()\|g6)' tools/check.sh
73:g6() { gate=g6; python3 "$root/tools/gates/issue_ledger.py" "$root"; }
104:  g6) g6 ;;
$ bash tools/check.sh g6
g6: OK (283 issues; open=38 verified=223 rejected=10 deferred=11 superseded=1)
$ sh test/gates/issue_ledger_test.sh
OK g6/ledger (5 negative cases + 1 positive)
$ bash tools/check.sh g1
g1: OK (12 phase cards: title/status/tasks/exit-criteria/version-minor)
```

**为什么不补 ratchet。** ratchet 的目的只有一个：让门禁在旧债未清时先上线，白名单是
「先不判红」的缓冲。CI-11 已把 283 条全部归一到 §5.4 八词（0 条非闭集、0 条无证据
`verified`），严格模式本身就是绿的；此时加一张基线表只会多出一个**可被滥用的豁免口**，
并让「g6 绿」不再等价于「台账干净」。因此本条的判断是：**判据不放宽，机制不做**。

验收逐条对照：

| # | 验收（见「验收」节） | 结果 | 证据 |
| --- | --- | --- | --- |
| 1 | 184 条非闭集归一，或建立映射并在 G6 豁免 | **已达成**：0 条非闭集 | 上面 g6 的 283 全绿 |
| 2 | 14 条 `待办` 有 owner/去向 | **已达成** | [CI-14](ci-14-g6-legacy-status-cleanup.md) 的处置表逐条列出 |
| 3 | G6 实现（A）或 deviation（B） | **已达成**：严格 A | `tools/check.sh g6` + 5 条负例 |
| 4 | G1 对 phase 卡字段机械检查 | **已达成** | `g1: OK (12 phase cards: …)` |
| 5 | `check-all` 计入或写清不计入的理由 | **已达成**：理由已记录——`check-all.sh` 的治理预检只跑 G0/G8，G6 的台账检查与 G5 的 phase 卡检查不进构建链，见 [CI-10](ci-10-governance-gates-missing.md) 的 REV 复核段 | `selfhost/check-all.sh` 预检段 |

最小设计（**台账再增长时**按此落地，不重新设计；本文件 §2 即设计记录）：

1. 基线文件 `issues/.g6-baseline.tsv`，列 `path<TAB>违规键<TAB>归一键<TAB>类别`，只收**已存在**
   的存量违规，由 `--write-baseline` 生成、REQ 复核后入库；
2. `issue_ledger.py` 增加 `--write-baseline`；默认读基线：命中 → 计 `known` 并在汇总行报数，
   **未命中 → 立刻红**（新债零豁免）；
3. 僵尸检测：基线里的文件已归一或已不存在 → 红（防「基线永久化」）；
4. 基线必须挂追踪 issue 且带退出条件（清空、严格模式绿、遗留项各有去向），否则红；
5. 负例三条进 `test/gates/issue_ledger/`：新增违规红、僵尸条目红、严格模式无基线仍绿。

触发条件（任一即启动，并同时把本文件状态改回 `open`）：

- **台账再增长 > 0**：`g6` 首现「非闭集 / 无证据 `verified` / 缺状态」违规且判为存量
  （例如历史回填引入的旧写法），按上面 1–5 落地 ratchet；
- 或 **v1.1 复核点**：届时若仍无存量违规，本条的 ratchet 一段直接记 `rejected`
  （无需实现），只保留「严格 g6 + 5 条负例」，本条随之闭合。

若 EDITOR 之后决定把 g6 进 CI，落点是 `ci.yml` 的 governance 步骤（与 g0/g8 并列），
**不进** `check-all.sh` 的 11 道产品硬门禁——这与上面第 5 条的理由是同一条。

## 实现（2026-11-23，DEV；状态字段未改）

按本文件「最小设计」1–5 落地 ratchet，**默认严格模式不变**；基线 0 行，因此三种模式当前等价。

- `tools/gates/issue_ledger.py`：`--ratchet` / `--write-baseline` / `--baseline` / `--tracking`；
  违规结构化出「现状 / 归一键 / 类别」，新增违规零豁免，僵尸行报红，减少只能显式重写；
- `tools/check.sh g6 [--ratchet|--write-baseline]`：默认仍走严格判据；
- `issues/.g6-baseline.tsv`：4 列格式 + `# tracking: CI-14`，当前 0 数据行；
- `docs/planning/g6-ratchet.md`：两种模式、格式、追踪 issue 要求、何时用；
- `test/gates/issue_ledger_test.sh`：在原有 5 负例 + 1 正例上追加 7 个 ratchet 用例
  （新债红、僵尸红、已知绿、重写减少、无 tracking 红、tracking 无退出条件红、严格无基线绿）。

```console
$ bash tools/check.sh g6 --write-baseline
g6: baseline written (0 row(s), tracking CI-14)
$ bash tools/check.sh g6 --ratchet
g6: OK (297 issues; ratchet: known=0 new=0 zombie=0 baseline=0)
$ bash tools/check.sh g6
g6: OK (297 issues; verified=246 rejected=12 deferred=38 superseded=1)
$ sh test/gates/issue_ledger_test.sh
OK g6/ledger (5 negative cases + 1 positive; ratchet 7 cases)
```

状态仍为 `deferred`：本段只落实现与证据，等 REV 复核后决定是否改状态（本次任务要求不改状态）。
