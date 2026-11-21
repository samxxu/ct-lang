# SH-109 · `MAX_FUNCS` 501/512 容量决策（v1-PH-0 入口）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（自举容量） |
| 定性 | 决策项（bugfix/特性取决于方案；先决策后施工） |
| 严重度 | **P1（v1-PH-0 入口）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-2；[p88_metrics](../../docs/history/p88_metrics.md) §4 #3；[v1 路线](../../docs/planning/v1-release-plan.md) |
| 状态 | **待决策（REQ 复算 + USER 签字；DEV 施工）** |

## 现象

`MAX_FUNCS` 是整程序顶层函数预算（512）。PH-88 的 76 个 `em_*` free function 后
实测 **501/512，余 11**；`v1-PH-0` 计划再把切片改成穷尽 `match`，新增 helper 就会撞顶。

- 代码副本：`Symbols.h.ct:36` 与 `Expr.h.ct:65` 各有一份 `#define MAX_FUNCS 512`；
- 文档已统一到 501/512（本轮 D-4/D-5/D-6 勘误）；
- 评审 P1-2 要求：先复算，再决定提上限 / 改用 `impl` 方法 / 调整切片，并把容量写进
  `v1-PH-0` 前置。

## 待选方案（三选一，需 USER 签字）

| 方案 | 做法 | 代价/风险 |
| --- | --- | --- |
| A 提上限 | `MAX_FUNCS` 512 → 640/768（两处同步） | 改自举预算；需说明内存/栈影响；USER 签字 |
| B 改用 `impl` 方法 | 新 helper 进 `impl`（方法不占 `MAX_FUNCS`） | 受 `MAX_METHODS`（64）约束；可能改 vtable/派发 |
| C 调整切片 | 合并/减少 free function，控制新增数 | 可能牺牲 PH-88 的“一 kind 一臂”可读性 |

## 验收

1. 复算 501/512 的命令与输出入库；
2. 三选一方案写入本 issue 或 ADR，USER 签字（方案 A 必须）；
3. 补 `MAX_FUNCS` 临界（501/512）与越界（513）两条负例；
4. `v1-PH-0` 入口检查：容量方案已定，且新增切片预算不超过余量；
5. 不改 `MAX_METHODS` / `MAX_IO_CALLS` 的既有口径，除非同案批准。

## 非目标

- 不在本 issue 内实现 `match` 切片重写（归 `v1-PH-0`）；
- 不改 `MAX_IO_CALLS 1024`（PH-88 已定）；
- 不做“静默提上限”。

## 关联

- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)（Tier 1）
- [PH-88 卡](../../docs/design/phase88.md) §7.5
- [p88_metrics](../../docs/history/p88_metrics.md) §4 #3、§5
- [v1 路线](../../docs/planning/v1-release-plan.md) §1.5 / §2.3
