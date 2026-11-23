# SH-109 · `MAX_FUNCS` 按需增长（初始 512，安全阀 65536；当前 pre 窗口）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（自举容量） |
| 定性 | 容量切片（动态增长；v1.1 前落地） |
| 严重度 | **P1（当前 pre 窗口；不阻塞 v1.0）** |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [容量提案](../../docs/proposals/ct-max-funcs-growth.md)；[v0.88.0 评审](../../docs/reviews/full-review-v0.88.0.md) P1-2；[p88_metrics](../../docs/history/p88_metrics.md) §4 #3；[v1 路线](../../docs/planning/v1-release-plan.md) |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23 所有者改判：v1.1 前放开固定 512，当前 pre 窗口落地；安全阀 65536 只作 OOM 保护）** |

## 现象

`MAX_FUNCS` 是整程序顶层函数预算（512）。PH-88 的 76 个 `em_*` free function 后
实测 **501/512，余 11**；`v1-PH-0` 计划再把切片改成穷尽 `match`，新增 helper 就会撞顶。

- 代码副本：ct-ast 三处 `Symbols.h.ct:36` / `Expr.h.ct:65` / `ParseSupport.h.ct:27`，
  以及 L2 `core.ct:45`；L0/L1 的 64 不动；
- 文档已统一到 501/512（本轮 D-4/D-5/D-6 勘误）；
- 所有者 2026-11-21 决定：改为按需增长 + 65536 安全阀；2026-11-23 改判提前到当前 pre 窗口。

## 决策

`MAX_FUNCS` **改为按需增长（初始 512、安全阀 65536）**，详细改动、L2 冻结层例外、
门禁与回滚见 [ct-max-funcs-growth.md](../../docs/proposals/ct-max-funcs-growth.md)。

**2026-11-23 所有者改判**：不再把 512 当功能上限，也不等到 v1.1 `S0`；本切片在当前 pre 窗口
（v1.1 前）落地。`v1-PH-0` 不再有“新增顶层函数 ≤11”的预算，LANG-24 / LANG-26 也不再受
501/512 约束。安全阀 65536 保留为 OOM 保护，不是功能限制。

## 验收

1. 复算 501/512 的命令与输出入库；
2. 动态增长方案与所有者 2026-11-21 决定记录在案（见提案）；
3. 补增长（512→1024→2048）与安全阀（65536/65537）负例；
4. `v1-PH-0` 不再设“新增顶层函数 ≤11”预算；本切片在当前 pre 窗口（v1.1 前）落地；
5. 不改 `MAX_METHODS` / `MAX_IO_CALLS` 的既有口径，除非同案批准。

## 非目标

- 不在本 issue 内实现 `match` 切片重写（归 `v1-PH-0`）；
- 不改 `MAX_IO_CALLS 1024`（PH-88 已定）；
- 不做“静默提上限”。

## 关联

- [容量提案](../../docs/proposals/ct-max-funcs-growth.md)
- [v1-readiness-1 判决](../../battle/v1-readiness-1/verdict.md)：原 Tier 1，2026-11-21 改落 `v1-PH-1 / S0`；
  2026-11-23 所有者再次改判提前到当前 pre 窗口
- [PH-88 卡](../../docs/design/phase88.md) §7.5
- [p88_metrics](../../docs/history/p88_metrics.md) §4 #3、§5
- [v1 路线](../../docs/planning/v1-release-plan.md) §1.5 / §2.3

## 处置（REV/REQ，2026-11-22）

**结论：`open`（2026-11-23 所有者改判：不再等 v1.1，固定 512 不再是功能上限）。**
所有者 2026-11-21 已定「按需增长（初始 512、安全阀 65536）」，2026-11-23 进一步提前到当前
pre 窗口；`v1-PH-0` 不再按 501/512 施工，也不再设 ≤11 预算。

**HEAD `38cd4ae4` 实查**：容量仍固定，没有增长分支或安全阀：

```console
$ grep -n '#define MAX_FUNCS' selfhost/ct-ast/frontend/sym/Symbols.h.ct
36:#define MAX_FUNCS   512
$ grep -rn 'MAX_FUNCS_CAP\|65536' selfhost/ct-ast/frontend/sym/Symbols.h.ct selfhost/l2/core.ct
（无命中）
```

**口径说明**：D-017 是 v1-pre 的单元切分裁定（M0/M1），不裁 `MAX_FUNCS` 容量；容量结论在
[ct-max-funcs-growth.md](../../docs/proposals/ct-max-funcs-growth.md) 与本条「决策」段，二者一致。
PH-88 只把 `MAX_IO_CALLS` 512→1024，并把 `MAX_FUNCS` 用量推到 501/512（余 11），不等于本条
要求的动态增长。

**触发/下一步**：**当前 pre 窗口**（v1.1 前；2026-11-23 改判）；负责人 DEV；P1。
落法见提案：初值 512、翻倍增长、65536 安全阀，L2 冻结层例外、门禁与回滚同提案；
补 512→1024→2048 与 65536/65537 负例。落地后 LANG-24 / LANG-26 / LANG-28 不再受
501/512 约束，也不再以“预计新增 >11 就停”为入口判据。

## 复核（REV，2026-11-23）

主干 `041b9f73`：函数表按需增长（初值 512，翻倍，安全阀 65536）；1200 函数编译 rc=0；
`cap funcs` 夹具改为增长断言；`p88_metrics` 9/0。
