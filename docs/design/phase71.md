# Phase 71 — own/borrow/Drop + 包级 strict

> **状态：实施中（已开卡，排队实施）**（2026-11-19 立项；`v0.70.0` 拟）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/design/phase71.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-71（legacy 文件 `phase71.md`） |
| 目标 | own/borrow/Drop + 包级 strict |
| 范围 | 作用域/逃逸/初始化/释放顺序；`own` 转移、`borrow` 回手、Drop 可达性；跨单元资源 |
| 非目标 | 不做 Rust 级借用检查；不做别名/并发完整证明 |
| 交付物 | 编译器改动、`test/ast/p71_*` 探针、文档 |
| 任务清单 | §3（R1–R3） |
| 退出判据 | E71-1…E71-3（§4） |
| version-minor | 70（PH-71，`d=1`） |
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
