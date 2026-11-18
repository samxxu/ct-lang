# Phase 72 — 静默错误与诊断批

> **状态：实施中（已开卡，排队实施）**（2026-11-19 立项；`v0.71.0` 拟）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/design/phase72.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-72（legacy 文件 `phase72.md`） |
| 目标 | 静默错误与诊断批 |
| 范围 | LANG-3 MAX_CALLS、LANG-4 下标类型错配、LANG-11 同名产物冲突、LANG-16 诊断负列、DF-1 预处理行截断、SH-76 内置层误诊、SH-18+LANG-15 限定名 |
| 非目标 | 只修静默/诊断，不加新语法 |
| 交付物 | 编译器改动、`test/ast/p72_*` 探针、文档 |
| 任务清单 | §3（R1–R6） |
| 退出判据 | E72-1…E72-3（§4） |
| version-minor | 71（PH-72，`d=1`） |
| 已知风险 | R72-1…R72-1（§5） |

## 1 需求与边界

静默错误与诊断批：LANG-3 MAX_CALLS、LANG-4 下标类型错配、LANG-11 同名产物冲突、LANG-16 诊断负列、DF-1 预处理行截断、SH-76 内置层误诊、SH-18+LANG-15 限定名。只修静默/诊断，不加新语法。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 LANG-3 | MAX_CALLS 固定上限的诊断与扩容 | ``bash test/ast/p72_maxcalls.sh` → `OK p72/maxcalls`` | S |
| R2 LANG-4 | 下标方法类型错配不再静默空值 | ``bash test/ast/p72_subscript.sh` → `OK p72/subscript`` | M |
| R3 LANG-11 | 同名 `.h.ct`/`.ct` 产物冲突硬错 | ``bash test/ast/p72_outputcollision.sh` → `OK p72/collision`` | S |
| R4 LANG-16 + DF-1 | 诊断负列与预处理行截断 | ``bash test/ast/p72_diagpos.sh` → `OK p72/diagpos`` | M |
| R5 SH-76 | 内置层缺失的误诊改为明确诊断 | ``bash test/ast/p72_stdmissing.sh` → `OK p72/stdmissing`` | S |
| R6 SH-18+LANG-15 | 限定类型名与枚举限定值 | ``bash test/ast/p72_qualified.sh` → `OK p72/qualified`` | M |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E72-1 | E72-1 六组问题各带负例红证并转绿 |
| E72-2 | E72-2 对应 issue 处置段齐全（sha + 原始输出） |
| E72-3 | E72-3 `check-all` 11/11 且 golden 无变化（除诊断文本） |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R72-1 | 诊断文本变化影响 golden | 只改 error 路径；golden 需逐条说明 |
