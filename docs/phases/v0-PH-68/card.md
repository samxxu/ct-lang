---
phase-id: v0-PH-68
version-minor: 68
---

# Phase 68 — 类型核心（`ct check --types`）

> **状态：完成**（2026-11-19 收口；`v0.67.0`；R1–R4 全绿）。
> **依据**：[typecheck-semantic-plan](../../planning/typecheck-semantic-plan.md) §3、
> [battle typecheck-1](../../../battle/typecheck-1/verdict.md)（B′）。
> **前置**：v0-PH-67 收口（`v0.66.0`）。
> **布局说明**：phase-ID 迁移（`v0-PH-*`）仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/phases/v0-PH-68/card.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-68（`docs/phases/v0-PH-68/card.md`） |
| 目标 | 把 `ct check --types` 从 12 个表达式节点的粗检扩成可核验的表达式类型检查，并先修掉唯一合法语料误报（234） |
| 范围 | 字面量、算术/比较/逻辑、指针/数组衰减、struct/union/enum、函数指针、cast、三元、闭包入口；四个位置（初值/赋值/return/容器实参） |
| 非目标 | 不进 `ct build`/`ct compile`；不做跨单元（v0-PH-69）、CFG（v0-PH-70）、own/borrow（v0-PH-71）；不做 Rust 级借用检查 |
| 交付物 | `TypeCheck.h.ct` / `Expr.h.ct` / `Stmt.h.ct` 的类型表与判定、`test/ast/p68_*` 夹具、文档 |
| 任务清单 | §3（R1–R4） |
| 退出判据 | E68-1…E68-4（§4） |
| 依赖 | 规划 §3（估算 1,000–1,500 LOC） |
| version-minor | 67（v0-PH-68，`d=1`，见 AGENTS §0.3） |
| 已知风险 | R68-1…R68-3（§5） |

## 1 需求与边界

`ct check --types` 当前只有 4 个判定位置、6 条 L32 诊断（`chk_type` 覆盖 12 个节点、
`expr_type` 18 个），且唯一合法语料误报是 `static char s[] = "x"`（234 号夹具）。
本相先把误报清零、再把"表达式类型"变成机械可核的表，最后把四个位置接上。

## 2 证据口径

- 合法语料 FP 统计：对 `test/ast/**`、`examples/**`、`test/modules/**` 中
  `ct check --types` 可判定的件逐件跑，记录 rc 与诊断；234 必须转绿；
- 门禁：`check-all` 11/11，golden 不得变化（只改 `--types` 路径）。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 数组维度丢失 | `Stmt.ct` 初值检查识别 `text3` 维度；`char s[]`/`char s[2]` 与字符串字面量相容 | `bash test/ast/p68_typebuf.sh` → `OK p68/typebuf (234 green)` | S |
| R2 表达式类型表 | `Expr.ct`/`TypeCheck.ct` 扩充 12 节点，输出可核对的类型串 | `bash test/ast/p68_exprtypes.sh` → `OK p68/exprtypes` | M |
| R3 四位置判定 | 初值/赋值/return/容器实参统一走 `chk_assignable`，负例报错、正例不误报 | `bash test/ast/p68_positions.sh` → `OK p68/positions` | M |
| R4 误报账 | 合法语料 FP 清单与 skip 表入账，234 转绿 | `bash test/ast/p68_fp.sh` → `OK p68/fp (FP=0/438)` | S |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E68-1 | 234 夹具 `ct check --types` 退出码 0 且无 `initializer:` 诊断 |
| E68-2 | 表达式类型表覆盖 §1 列出的 12 类节点，探针全绿 |
| E68-3 | 四个位置各有正例与负例；负例报 `expected/got`，正例零诊断 |
| E68-4 | 合法语料 FP=0/438（可判定件），skip 表逐条入账；`check-all` 11/11 且 golden 无变化 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R68-1 | 类型表扩张引入新误报 | 先跑合法语料统计，再收紧；每项带正负例 |
| R68-2 | 与 v0-PH-69 跨单元工作重叠 | 本相只做单单元；跨单元留接口 |
| R68-3 | 与模板化/闭包交互复杂 | 闭包入口只做最小形状，深水留 v0-PH-75 |

## 6 收口对照表（2026-11-19，v0.67.0）

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E68-1 | `bash test/ast/p68_typebuf.sh <ct-ast>` | `OK p68/typebuf (234 green)`；234 的 `initializer:` 误报消失 |
| E68-2 | `bash test/ast/p68_exprtypes.sh <ct-ast>` | `OK p68/exprtypes`（bin/unary/tern/cast 均有类型） |
| E68-3 | `bash test/ast/p68_positions.sh <ct-ast>` | `OK p68/positions (init/assign/return/container arg)` |
| E68-4 | `bash test/ast/p68_fp.sh <ct-ast>`；`bash selfhost/check-all.sh` | `OK p68/fp (FP=0/301 legal fixtures; 1 documented skip)`；11/11；`check-ast 1483 passed` |

任务级红证：R1 为 `42a1932d` 的父提交（`test(ast): v0-PH-68-R1 红…`），R2 为
`p68_exprtypes 红` 提交；R3/R4 是对既有判定的验收任务（无实现提交，探针本身
即交付物），不适用 T-7 红绿。
实现提交：R1 `42a1932d`、R2 `0a8438a4`。

边界与偏差：
- 语料基线为 301 个单单元合法件（含 234；REV 按 battle 口径复现 FP=0/438，
  438 含 import 多单元，跨单元可检属 v0-PH-69）；
- `loop_count_type` 的 L22-5 报告是有意行为，列入 skip 表；
- 内建容器（`Vec<T>.push`）的实参类型仍不检查，属 v0-PH-69 的跨单元/泛型范围。

复核记录：[2026-11-19-phase68-rev-verdict.md](../../reviews/2026-11-19-phase68-rev-verdict.md)（REV: 通过）。
