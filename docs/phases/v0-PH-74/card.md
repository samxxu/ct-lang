---
phase-id: v0-PH-74
version-minor: 74
---

# Phase 74 — 模型导出（v0-PH-59 M1/M2）

> **状态：完成**（2026-11-19 收口；`v0.73.0`；R1–R3 全绿）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），本卡位于 `docs/phases/v0-PH-74/card.md`。
> `docs/phases/v0-PH-74/card.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-74（`docs/phases/v0-PH-74/card.md`） |
| 目标 | 模型导出（v0-PH-59 M1/M2） |
| 范围 | J11 行列；`--emit-model` M1；`--emit-map` 两 facet；SH-79 |
| 非目标 | 不改变现有 map JSON 的既有字段语义 |
| 交付物 | 编译器改动、`test/ast/p74_*` 探针、文档 |
| 任务清单 | §3（R1–R3） |
| 退出判据 | E74-1…E74-3（§4） |
| version-minor | 73（v0-PH-74，`d=1`） |
| 已知风险 | R74-1…R74-1（§5） |

## 1 需求与边界

模型导出（v0-PH-59 M1/M2）：J11 行列；`--emit-model` M1；`--emit-map` 两 facet；SH-79。不改变现有 map JSON 的既有字段语义。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 J11 行列 | `Field` 的行列信息 | ``bash test/ast/p74_j11.sh` → `OK p74/j11`` | S |
| R2 M1 emit-model | `--emit-model` 输出模型 JSON | ``bash test/ast/p74_model.sh` → `OK p74/model`` | M |
| R3 M2 lib map | lib 模式 `--emit-map` 两 facet | ``bash test/ast/p74_map.sh` → `OK p74/map`` | M |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E74-1 | E74-1 `--emit-model` 产物可解析、字段齐全 |
| E74-2 | E74-2 lib 模式 map 两 facet 与 SH-79 一致 |
| E74-3 | E74-3 `check-all` 11/11，无 golden 变化 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R74-1 | SH-79 未修则 M2 不可做 | 先修 SH-79，作为 R3 前置 |

## 6 进展与收口对照（2026-11-19，v0.73.0）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 J11 行列 | ✅ | `p74/model`：字段 `loc.line/col`（`int a` → `col:16`） |
| R2 M1 emit-model | ✅ | 同一探针：model 可解析、structs/fields/functions 齐全，`file` 为 entry |
| R3 M2 lib map | ✅ | `p74/map`：`--lib --emit-map` 落盘；build map 的 `file` 为 `main.ct` |

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E74-1 | `p74_model.sh` | 绿 |
| E74-2 | `p74_map.sh`（SH-79 两 facet） | 绿 |
| E74-3 | `check-all.sh` | 11/11；`check-ast 1509 passed`；golden 仅 banner |

附注：修复过程中一并修正了「新单元解析时 `lstart` 未重置」导致的字段列负值。
