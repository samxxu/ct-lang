# 提案：大版本重置 phase 编号，保留 `MINOR == PH-n`

| 项 | 值 |
| --- | --- |
| 性质 | 主规范 CR 提案；**未生效**，不改当前 AGENTS 生成块 |
| 日期 | 2026-11-18 |
| 目标规范 | 主规范 §6.7 / `g1-version` / `g8-version` / `g4-version` |
| 触发 | v1.0.0 是 MAJOR，现有 `MINOR == PH-n` 与 `v1.0.0` 冲突；v1.1 又需要“语法重写 + A”两个大切片 |

## 0. 一句话

**每个 MAJOR 从 `PH-0` 重新编号，phase ID 带 major 作用域：`v1-PH-0`、`v1-PH-1`；`MINOR == 本 major 内的 n`。历史 `PH-1…PH-73` 规范化为 `v0-PH-1…v0-PH-73`，旧写法作为别名保留，永不复用。**

## 1. 现状

- 现有 phase 全局递增：`PH-67`、`PH-68`…
- 版本规则：`PH-<n>` 收口时 `MINOR == n`（有 `d` 偏移按表换算）。
- v1.0.0 的 `MINOR=0`，按现有规则应开 `PH-0`；但 `PH-0` 在全局号段会与历史 `PH-1` 产生歧义。
- v1.1 若拆“语法重写 + A”两个 phase，则会得到 `v1.1.0` 和 `v1.2.0`，与“A 放 v1.1”冲突。

## 2. 新规则

1. phase ID 带 major 作用域：`v<M>-PH-<n>`，例如 `v1-PH-0`、`v1-PH-1`、`v2-PH-0`。
2. 每个 MAJOR 的第一相为 `n=0`；`v1.0.0 ↔ v1-PH-0`，`v1.1.0 ↔ v1-PH-1`。
3. `MINOR == n`，PATCH 仍只记 fix；不再需要新 major 的 `d` 偏移。
4. 历史 `PH-1…PH-73` 保留原名，不重编号、不复用；新 major 的 ID 与历史不冲突。
5. release train 允许一个 phase 内多个 stage（`S1`/`S2`），但**只有一个 phase 号、一次 MINOR bump**；stage 不是 phase，不单独占版本。
6. tag 仍是 `v<M>.<n>.<p>`；phase 卡 `version-minor` 写 `n`（v1.0 为 0）。
7. 旧 major 的 `deviation: version-minor-offset` 保留为历史；新 major 不再继承偏移。
8. 历史 ID 规范化为 `v0-PH-<n>`（1–73）；`PH-<n>` 作为**兼容别名**继续可解析，
   但新文档、新卡、工具输出使用 `v0-PH-*`。文件路径、tag、历史 battle 证据不强制改名。

### 2.1 历史 ID 的“改名”边界

“统一”指 **ID 文本**，不是重命名文件/tag：

| 对象 | 是否改 | 说明 |
| --- | --- | --- |
| 文档中的 `PH-43` | 改成 `v0-PH-43` | roadmap、卡标题、phase-log、issue 标题、活跃文档 |
| 卡文件名 `phase43.md` | **不改** | 改文件名会断链接；卡片内 `phase-id` 用新 ID |
| tag `v0.43.0` | **不改** | 历史 tag 不可回改 |
| battle 证据原文 | **不改** | 历史命令/输出保留 `PH-*`，加 alias 注记 |
| 代码/测试字符串 | 不改 | 不因文档改名动行为 |
| 新 major ID | `v1-PH-0` | 不复用 `PH-0` |


## 3. 例子

| 事件 | phase | 版本 |
| --- | --- | --- |
| 旧 Phase 43 | `v0-PH-43`（旧 `PH-43` 别名） | `v0.43.0`（历史 tag 不动） |
| v1.0 AST-only | `v1-PH-0` | `v1.0.0` |
| v1.0.1 fix | 同 `v1-PH-0` | `v1.0.1` |
| v1.1 语法重写 S1 + A S2 | `v1-PH-1`（S1/S2） | `v1.1.0` |
| v1.2 下一相 | `v1-PH-2` | `v1.2.0` |
| v2.0 | `v2-PH-0` | `v2.0.0` |

## 4. 工具改动

| 检查 | 改动 |
| --- | --- |
| `g1-version` | 解析 `v<M>-PH-<n>`，`version-minor == n`；旧 `PH-<n>` 走旧规则/偏离表 |
| `g8-version` | 新 major 首相允许 MAJOR bump；同 major 内 MINOR 只 +1；tag 指向 |
| `g4-version` | 版本落点核对支持 `v<M>`；CHANGELOG/tag 对齐 |
| `g8-phase-freeze` | phase ID 带 major；stage 不改 phase 号 |
| phase 卡 | 新增 `phase-id: v0-PH-43` / `v1-PH-0`；`version-minor` 取 local n（v1.0 为 0） |
| AGENTS | 生成块由主规范同步；项目侧不手改 |

## 5. 迁移

- 已有 v0.x 的 phase/版本不动；`deviation: version-minor-offset` 继续作为历史。
- v1.0 开卡时用 `v1-PH-0`；旧 `PH-71` 之类的规划号作废，不创建卡。
- 文档中 `PH-71/72/73` 的引用统一改为 `v1-PH-0` / `v1-PH-1`（S1/S2）。
- 检查脚本先兼容两种 ID，再在新 major 生效后只认新 ID。
- 迁移顺序：先加 alias 解析 → 再加 `phase-id` 字段 → 再批量替换活跃文档文本 → 最后把新文档默认写 `v0-PH-*`；
  不要先删旧解析。
- 批量替换只覆盖 `docs/design/**`、`docs/planning/**`、`docs/decisions/**`、`docs/proposals/**`、
  `docs/roadmap.md`、`issues/**` 的 ID 文本；跳过 `battle/**` 原始证据、文件路径、tag、代码/测试。
- 完成后跑 `check-docs` 与全量链接检查；`PH-*` 只应出现在别名说明/历史证据中。

## 6. 待裁定

1. `n` 从 0 还是 1 开始？本提案按用户要求从 **0**。
2. v1.1 的 S1/S2 是否允许同一 phase 内跨多个 release candidate？建议允许，但只 bump 一次 MINOR。
3. MAJOR 是否必须由用户显式签字？建议是，MAJOR 不能由 phase 自动触发。
4. 旧 `PH-*` 是否补 `v0-` 前缀？建议不补，保留历史。

## 7. 验收

- 用 `v1-PH-0` 假卡跑 `g1-version`/`g8-version`/`g4-version`，全部通过；
- 旧 `PH-66` 卡仍通过旧规则；
- `v1-PH-1` 的 S1/S2 只产生一个 `v1.1.0`；
- 历史 `PH-1…PH-73` 无重编号、无断链；
- 主规范同步后，CT 项目 `AGENTS.md` 生成块更新，`g0` 绿。
