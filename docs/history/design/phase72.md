# Phase 72 — 静默错误与诊断批

> **状态：完成**（2026-11-19 收口；`v0.71.0`；R1–R6 全绿）。
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

## 6 进展与收口对照（2026-11-19，v0.71.0）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 LANG-3 | ✅ | `p72/maxcalls`：3000 条通过；9000 条报 `too many calls (MAX_CALLS=8192; ...)` |
| R2 LANG-4 | ✅ | `p72/subscript`：`char *get(char *)` 收到 `j[0]` 报 `argument 1` |
| R3 LANG-11 | ✅ | `p72/collision`：同 base 单元报 `both emit 'cfg.c'` |
| R4 LANG-16+DF-1 | ✅ | `p72/diagpos`：超长 `#` 行硬错；注释后列号 5:17 |
| R5 SH-76 | ✅ | `p72/stdmissing`：`unresolved generic type ... CT_STD_DIR`；裸 `Map` 报需类型实参 |
| R6 SH-18+LANG-15 | ✅ | `p72/qualified`：271/272/273 全绿（v0.59.0 已修，验收） |

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E72-1 | 六个 `p72_*` 探针 | 全绿（R1–R5 红→绿，R6 验收） |
| E72-2 | 六条 issue 的处置段 | 见各 issue「处置（2026-11-19，PH-72）」 |
| E72-3 | `check-all.sh` | 11/11；`check-ast` 全绿；golden 仅 banner |
