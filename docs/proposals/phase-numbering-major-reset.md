# 提案：大版本重置 phase 编号，保留 `MINOR == PH-n`

| 项 | 值 |
| --- | --- |
| 性质 | 主规范 CR 提案；**主规范已评审、按意见修订中；未生效** |
| 日期 | 2026-11-18 |
| 目标规范 | 主规范 §6.7 / `g1-version` / `g8-version` / `g4-version` |
| 评审意见 | `/Users/samxx/trae-ws/.ai-engineering/reviews/cr-ct-lang-phase-numbering-major-reset.md` |
| 触发 | v1.0.0 是 MAJOR，现有 `MINOR == PH-n` 与 v1.0.0 冲突；v1.1 需要“语法重写 + A”两个 stage |

## 0. 一句话

**每个 MAJOR 从 `PH-0` 重新编号，ID 带 major：`v1-PH-0`、`v1-PH-1`；`MINOR == 本 major 内的 n`。
历史 `PH-1…PH-73` 一次性机械迁移为 `v0-PH-1…v0-PH-73`，旧 `PH-*` 只存在于双认窗口、迁移账本和历史证据中。**

## 0.1 CR 评审结论（已接受）

| # | 意见 | 处置 |
| --- | --- | --- |
| 1 | `v<M>-PH-<n>`、`MINOR == n`、n 从 0 | 接受；n=0 不是可选项，由 v1.0.0 推出 |
| 2 | 旧号段改 `v0-PH-*`，不是永久别名 | 接受；机械重命名 + 账本 + 集合相等断言 |
| 3 | 不改 tag / 历史提交 | 接受；只改文件、目录、文档引用 |
| 4 | 双认窗口 | 接受；窗口内 `g1/g4/g8` 认两形态，窗口结束旧形态必须红 |
| 5 | MAJOR 签字门禁 | 接受；新 major 首次收口必须有 decision 记录，否则 `g8-version` 红 |
| 6 | stage 独立回滚 | 接受；S1/S2 各自有红/绿提交与收口判据，同一张卡分段记录 |
| 7 | 撤号规则 | 接受；允许留空号，禁止复用 |
| 8 | 补被否方案 | 接受；见 §6.2 |
| 9 | `n` 起点 | 固定为 0，不再列为待裁定 |

## 1. 现状

- 现有 phase 全局递增：`PH-67`、`PH-68`…
- 版本规则：`PH-<n>` 收口时 `MINOR == n`（有 `d` 偏移按表换算）。
- v1.0.0 的 `MINOR=0`，按新规则应开 `v1-PH-0`；旧 `PH-0` 不存在，避免与历史 `PH-1` 歧义。
- v1.1 若拆“语法重写 + A”两个 phase，会得到 v1.1/v1.2，与“A 放 v1.1”冲突。

## 2. 新规则

1. phase ID 带 major：`v<M>-PH-<n>`，例如 `v1-PH-0`、`v1-PH-1`、`v2-PH-0`。
2. 每个 MAJOR 第一相 `n=0`；`v1.0.0 ↔ v1-PH-0`，`v1.1.0 ↔ v1-PH-1`。
3. `MINOR == n`；PATCH 只记 fix；新 major 不再需要 `d` 偏移。
4. 历史 `PH-1…PH-73` 迁移为 `v0-PH-1…v0-PH-73`；迁移完成后旧 `PH-*` 不再作为常规 ID。
5. release train 允许一个 phase 内多个 stage（S1/S2），但只有一个 phase 号、一次 MINOR bump；
   **每个 stage 必须有独立红/绿提交与独立收口判据**（CR 第 4 条）。
6. tag 仍是 `v<M>.<n>.<p>`；phase 卡 `version-minor` 写 local n（v1.0 为 0）。
7. 旧 major 的 `deviation: version-minor-offset` 保留为历史；新 major 不继承。
8. 撤号：允许留空号，禁止复用；`v1-PH-2` 撤销后不得由后来者顶上。

## 3. 历史 ID 的“全面更名”边界

CR 要求“只改文件、目录、文档引用；不改 tag/历史提交”。因此：

| 对象 | 是否改 | 规则 |
| --- | --- | --- |
| 文档中的 `PH-43` | 改 | `v0-PH-43` |
| 卡文件名 `phase43.md` | 改 | `v0-phase43.md` |
| 卡文件名 `phase64-draft.md` | 改 | `v0-phase64.md`（同时去掉 `-draft`） |
| `history/design/phase43.md` | 改 | `history/design/v0-phase43.md` |
| planning 的 `phase53-*.md` | 改 | `v0-phase53-*.md` |
| 目录名含 phase 号 | 改 | `v0-phaseNN`（如有） |
| tag `v0.43.0` | **不改** | 历史 tag 不可回改 |
| 历史提交信息 | **不改** | 不改写历史 |
| battle 原始证据 | **不改** | `battle/**` 的旧 ID/命令/输出保留；账本注明它是历史证据 |
| 代码/测试字符串 | **不改** | 不因文档重命名动行为 |

> `AGENTS.md` 生成块由主规范同步；项目侧不手改。当前 `phase=PH-66` 等实例化行在窗口结束后
> 改为 `v0-PH-66`。

## 4. 迁账本与集合断言

新增 `docs/planning/phase-id-ledger.md`，一行一条：

| 旧 ID | 新 ID | 旧路径 | 新路径 | 版本 | 状态 |
| --- | --- | --- | --- | --- | --- |
| PH-43 | v0-PH-43 | docs/design/phase43.md | docs/design/v0-phase43.md | v0.43.0 | migrated |

机械断言（迁移脚本内）：

- 旧 ID 集合 = 新 ID 集合（1–73，不增不减、不新增空洞）；
- 旧路径集合 = 新路径集合；
- 每个新路径存在、旧路径不存在；
- `docs/roadmap.md` 的 phase 行数不变；
- 链接/锚点在 `check-docs` 中零 dead；
- `PH-*` 只允许出现在账本、battle 原始证据、别名说明中。

## 5. 双认窗口

| 阶段 | `g1/g4/g8` | 状态 |
| --- | --- | --- |
| W0 | 只认旧 `PH-*` | 迁移前 |
| W1 | 同时认 `PH-*` / `v0-PH-*`；两种目录形态 | 重命名落地前 |
| W2 | 只认 `v0-PH-*` / `v1-PH-*` | 迁移提交后；旧形态负例必须红 |
| W3 | 新 major `v1-PH-*` only | v1.0 开卡后 |

窗口结束条件由 ct-lang 自行裁定；CR 不设条件。建议 W1 不超过一个 patch 窗口。

## 6. MAJOR、stage、撤号

### 6.1 MAJOR 签字

新 major 首次收口时，`g8-version` 必须找到一份 decision 记录，至少含：

- `major: 1`
- `target: v1.0.0`
- `signer: <用户>`
- `date: YYYY-MM-DD`

查不到即红；不能只靠口头确认。

### 6.2 被否方案

| 方案 | 否决理由 |
| --- | --- |
| 保留全局 `PH-n`，废掉 `MINOR == n` 改映射表 | 版本与 phase 永久脱钩；每次收口查表，正是当前 `d` 偏移的问题；用户明确要求保留 `MINOR == PH-n` |
| MAJOR 不作 phase，v1.0.0 沿用全局号段只改 MINOR 口径 | v1.0.0 没有对应 phase，`MINOR=0` 无号可对；v1.1 的 S1/S2 仍会被挤成 v1.x 两相 |

### 6.3 stage 回滚

- S1/S2 共用 `v1-PH-1`，但各有独立红/绿提交、独立收口段；
- 回滚 S2 不撤销 S1；回滚 S1 不把 S2 的版本位提前；
- 卡内用 `## S1` / `## S2` 分段，各自贴验收输出。

## 7. 工具改动

| 检查 | 改动 |
| --- | --- |
| `g1-version` | 解析 `v<M>-PH-<n>`，`version-minor == n`；W1 兼容旧 `PH-<n>`；W2 负例旧形态 |
| `g8-version` | 新 major 首相允许 MAJOR bump；同 major 内 MINOR 只 +1；tag 指向；MAJOR decision 门禁 |
| `g4-version` | 版本落点核对支持 `v<M>`；CHANGELOG/tag 对齐 |
| `g8-phase-freeze` | phase ID 带 major；stage 不改 phase 号；stage 独立回滚 |
| phase 卡 | `phase-id: v0-PH-43` / `v1-PH-0`；`version-minor` 取 local n |
| AGENTS | 生成块由主规范同步；项目侧不手改 |

## 8. 迁移与文档漂移审查

### 8.1 顺序

1. 主规范落条款 + 参照实现；
2. `g1/g4/g8` 进 W1 双认；
3. 生成账本，跑集合断言；
4. 机械 `git mv` 文件/目录 + 全局替换文档引用；
5. 跑全量 `check-docs`、`g1/g4/g8`；
6. 进 W2：删旧解析，补旧形态负例；
7. **单独**做文档漂移审查（不混在重命名提交里）。

### 8.2 漂移审查清单

| 项 | 判据 |
| --- | --- |
| roadmap ↔ 卡 | 每个 phase 行有卡；每个卡有 roadmap 行 |
| 卡 ↔ 版本 | `phase-id`、`version-minor`、tag、README/AGENTS 一致 |
| 状态词 | 完成/实施中/规划中/跳过/撤销与 phase-log 一致 |
| 链接 | `check-docs` 零 dead；重命名后锚点不丢 |
| 重复/空号 | 有账本；空号只增不补；无复用 |
| 历史证据 | battle/旧提交不改；账本可追溯 |
| 漂移 issue | 发现即立 `DOC-*`/`TEST-*`，不与重命名混提 |

> 重命名提交只做机械变更；漂移发现另开提交/issue。把两者混在一起，失败无法归因。

## 9. 验收

- 账本集合相等：1–73 无增无减、无空洞；
- W1 旧/新 ID 都能过 `g1/g4/g8`；W2 旧形态负例红；
- `v1-PH-0` 假卡：`version-minor=0`、MAJOR decision 存在、tag 检查通过；
- `v1-PH-1` 的 S1/S2 只产生一个 `v1.1.0`，S1/S2 各自可回滚；
- 文件/目录/文档引用全部新名；tag/提交/battle 证据未改；
- `check-docs` 零 dead；漂移审查报告单独落盘。
