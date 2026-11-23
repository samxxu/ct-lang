---
phase-id: v0-PH-71
version-minor: 71
---

# Phase 71 — own/borrow/Drop + 包级 strict

> **状态：完成**（2026-11-19 收口；`v0.70.0`；R1–R3 全绿）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），本卡位于 `docs/phases/v0-PH-71/card.md`。
> `docs/phases/v0-PH-71/card.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-71（`docs/phases/v0-PH-71/card.md`） |
| 目标 | own/borrow/Drop + 包级 strict |
| 范围 | 作用域/逃逸/初始化/释放顺序；`own` 转移、`borrow` 回手、Drop 可达性；跨单元资源 |
| 非目标 | 不做 Rust 级借用检查；不做别名/并发完整证明 |
| 交付物 | 编译器改动、`test/ast/p71_*` 探针、文档 |
| 任务清单 | §3（R1–R3） |
| 退出判据 | E71-1…E71-3（§4） |
| version-minor | 70（v0-PH-71，`d=1`） |
| 已知风险 | R71-1…R71-1（§5） |

## 1 需求与边界

own/borrow/Drop + 包级 strict：作用域/逃逸/初始化/释放顺序；`own` 转移、`borrow` 回手、Drop 可达性；跨单元资源。不做 Rust 级借用检查；不做别名/并发完整证明。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 own/borrow | `own` 转移与 `borrow` 回手的作用域判定 | ``bash test/ast/p71_own.sh` → `OK p71/own`` | M |
| R2 Drop/释放顺序 | Drop 可达性与释放顺序、双重释放 | ``bash test/ast/p71_drop.sh` → `OK p71/drop`` | M |
| R3 包级 strict | `ct.pkg` 的包级 strict 开关 | ``bash test/ast/p71_pkgstrict.sh` → `OK p71/pkgstrict`` | S |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E71-1 | E71-1 own/borrow/Drop 探针全绿 |
| E71-2 | E71-2 包级 strict 可开可关，默认 opt-in |
| E71-3 | E71-3 `check-all` 11/11 且 golden 无变化 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R71-1 | 与现有 Memory 台账重复 | 复用现有台账，不另建 |

## 6 进展与收口对照（2026-11-19，v0.70.0）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 own/borrow | ✅ | `p71/own`：同一 own 变量第二次 `delete` 报 `double delete of an owned object`；单次释放静默 |
| R2 Drop/释放顺序 | ✅ | `p71/drop`：内层先于外层释放、显式 `delete` 只释放一次（构建并运行生成的 C） |
| R3 包级 strict | ✅ | `p71/pkgstrict`：`ct.pkg` 的 `strict = on` 让 `verify` 拒绝 dir 行；缺省关；`--strict` 仍可强制 |

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E71-1 | `p71_own.sh`、`p71_drop.sh` | 绿 |
| E71-2 | `p71_pkgstrict.sh` | 绿（opt-in 可开可关） |
| E71-3 | `check-all.sh` | 11/11；`check-ast 1498 passed`；golden 仅 banner 变化 |

残余（诚实记录）：未做「所有逃逸路径」的完整借用检查（非目标）；`borrow` 回手
顺序沿用既有 AutoDrop，不改。
