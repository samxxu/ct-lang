# DOC-99 · v1.1 前置准备跟踪（不 bump 版本）

| 项 | 值 |
| --- | --- |
| 模块 | docs（跨模块跟踪：CI / 包 / 语言 / 测试） |
| 定性 | 发布前置准备跟踪（不是新特性、不是 fix） |
| 严重度 | Low |
| 锚点 | `d5e273e0`（`v1.0.0` 后；2026-11-24） |
| 依据 | [AGENTS §6.7](../../AGENTS.md#L139-L148) V-2/V-3/V-4；[v1 路线](../../docs/planning/v1-release-plan.md) |
| 状态 | open |
| 处置证据 | **accepted（2026-11-24 所有者同意：v1.1.0 开卡前先做这些准备项，全部不动版本号）** |

## 1. 目的

`v1-PH-1` 尚未开卡。开卡前有一批**不需要版本位**的准备项：它们是文档、裁定、
评审或测试，按 V-4 不进 PATCH，也不该等到 v1.1 施工时才做。本卡是清单与归属，
**不替代各原卡的状态**——每项仍以原卡自己的验收为准。

## 2. 清单

| # | 事项 | 原卡 | 类型 | 完成判据 |
| --- | --- | --- | --- | --- |
| P-1 | tag 触发的 linux-x64 发布构建与原生冒烟 | [CI-19](../ci/ci-19-tag-release-build.md) | CI 配置 | ✅ workflow 绿；`workflow_dispatch` 对 `v1.0.0` 重建并覆盖资产（run 45289869573） |
| P-2 | ct-pkg 索引重构三项裁定 | [PKG-21](../packages/pkg-21-ct-pkg-index-refactor-ruling.md) | 决策（文档） | 三项各给裁定与理由；原卡转终态 |
| P-3 | 绑定点转换 ADR **缺口复核**（D-020 已存在，核剩余三项） | [LANG-26](../lang/lang-26-binding-site-conversion.md) | 设计（文档） | `out` 写回 / `decode<T>` / 开关三项各有“覆盖、部分、未覆盖”结论；不够则出 D-020 增量 |
| P-4 | JSON 树方案 B 的 30 天重评 | [LANG-28](../lang/lang-28-json-tree-b.md) | 评审（文档） | LANG-27 已 verified；**截止 2026-12-23**；五条判据逐条给证据，结论三选一（维持 A / 切 B / B 限定子集） |
| P-5 | 覆盖缺口分批补测试 | [TEST-23](../testing/test-23-v077-coverage-gaps.md) | 测试 | 行覆盖与 `ct-ast` 单测分批进 `test/**`；不改产物 |
| — | 巨型单元与重复常量 | [SH-94](../selfhost/sh94-giant-units-duplicate-constants.md) | 源码重构 | **不在本卡执行**：并入 v1.1 S1（M1 精细切分）的 MINOR 窗口 |

## 3. 约束

- **不 bump 版本**：本卡全部事项不得移动 `CTC_VERSION`；不得占用 PATCH（V-2），
  也不得把“加测试”写成 fix（V-4）；
- **不实现语言特性**：P-3/P-4 只出文档；`LANG-26/28` 的代码归 v1.1；
- 每项独立提交、独立回滚；P-5 按批次提交，每批单独可回退；
- 期间若发现真实缺陷，按 V-3 另开 `fixed` 项走 `v1.0.x`，不混进准备项。

## 4. 验收

- P-1…P-5 各有其原卡要求的证据，且本卡逐项打勾；
- `check-docs` 绿；`g8-version` 绿（全卡零版本移动）；
- 原卡状态由各自承接方改，本卡只记录指针；
- 全部完成后，本卡转 `verified` 并作为 `v1-PH-1` 开卡的入口证据。

## 5. 非目标

- 不排 `LANG-26` / `LANG-28` 的代码实现（v1.1 MINOR）；
- 不排 `SH-94` 重构（并入 v1.1 S1）；
- 不排 `box<T>` 别名删除（LANG-24 Stage B，v1.1）；
- 不碰外部项 `PKG-16`（外部基线排期）与硬件项 `TEST-22`（真板 DMA）。

## 6. 关联

- [v1-PH-0](../../docs/phases/v1-PH-0/card.md)（v1.0 收口）
- [v1 路线](../../docs/planning/v1-release-plan.md)（v1.1 train 表）
- [AGENTS §6.7](../../AGENTS.md#L139-L148)（V-2/V-3/V-4）
- [D-021](../../docs/decisions/D-021.md)（JSON 树方案 B 与唤醒条件）
