# CI-13 · G1/G6 治理门禁缺位（台账闭合）

| 项 | 值 |
| --- | --- |
| 模块 | CI / 治理 |
| 定性 | 能力缺口（门禁未实现；或登记 deviation） |
| 严重度 | **P1（v1.0 发布，Tier 2）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-4；`AGENTS.md` §5.4；`tools/check.sh` |
| 状态 | open |
| 处置证据 | **已决 A（2026-11-21 所有者）；REQ 规格已出，DEV 实现 `g6`** |

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
