# SH-109 · `MAX_FUNCS` 按需增长（初始 512，安全阀 65536；v1-PH-1 / S0）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（自举容量） |
| 定性 | 容量切片（动态增长；v1.1 实现） |
| 严重度 | **P1（v1.1 `v1-PH-1 / S0`；不阻塞 v1-PH-0）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [容量提案](../../docs/proposals/ct-max-funcs-growth.md)；[v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-2；[p88_metrics](../../docs/history/p88_metrics.md) §4 #3；[v1 路线](../../docs/planning/v1-release-plan.md) |
| 状态 | **已决（动态增长 + 65536 安全阀）；2026-11-21 所有者改落 `v1-PH-1 / S0`** |

## 现象

`MAX_FUNCS` 是整程序顶层函数预算（512）。PH-88 的 76 个 `em_*` free function 后
实测 **501/512，余 11**；`v1-PH-0` 计划再把切片改成穷尽 `match`，新增 helper 就会撞顶。

- 代码副本：ct-ast 三处 `Symbols.h.ct:36` / `Expr.h.ct:65` / `ParseSupport.h.ct:27`，
  以及 L2 `core.ct:45`；L0/L1 的 64 不动；
- 文档已统一到 501/512（本轮 D-4/D-5/D-6 勘误）；
- 所有者 2026-11-21 决定：**改为按需增长 + 65536 安全阀，落 `v1-PH-1`**。

## 决策

`MAX_FUNCS` **改为按需增长（初始 512、安全阀 65536）**，详细改动、L2 冻结层例外、
门禁与回滚见 [ct-max-funcs-growth.md](../../docs/proposals/ct-max-funcs-growth.md)。

`v1-PH-0` 的边界：不包含本切片，按 501/512 施工，新增顶层函数预算 ≤11；
若预计超过 11 个 helper，停止并提前本切片，不得在 `v1-PH-0` 内顺手提上限。

## 验收

1. 复算 501/512 的命令与输出入库；
2. 动态增长方案与所有者 2026-11-21 决定记录在案（见提案）；
3. 补增长（512→1024→2048）与安全阀（65536/65537）负例；
4. `v1-PH-0` 边界：新增顶层函数预算 ≤11；`v1-PH-1 / S0` 执行容量切片；
5. 不改 `MAX_METHODS` / `MAX_IO_CALLS` 的既有口径，除非同案批准。

## 非目标

- 不在本 issue 内实现 `match` 切片重写（归 `v1-PH-0`）；
- 不改 `MAX_IO_CALLS 1024`（PH-88 已定）；
- 不做“静默提上限”。

## 关联

- [容量提案](../../docs/proposals/ct-max-funcs-growth.md)
- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)：原 Tier 1，2026-11-21 所有者改落 `v1-PH-1 / S0`
- [PH-88 卡](../../docs/design/phase88.md) §7.5
- [p88_metrics](../../docs/history/p88_metrics.md) §4 #3、§5
- [v1 路线](../../docs/planning/v1-release-plan.md) §1.5 / §2.3
