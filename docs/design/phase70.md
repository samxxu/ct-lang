# Phase 70 — CFG/定值/控制流语义检查

> **状态：实施中（已开卡，排队实施）**（2026-11-19 立项；`v0.69.0` 拟）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径
> `docs/design/phase70.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-70（legacy 文件 `phase70.md`） |
| 目标 | CFG/定值/控制流语义检查 |
| 范围 | CFG/基本块；definite assignment；所有路径 return；break/continue/goto/switch；重复 case；不可达 |
| 非目标 | 只做控制流可判定子集；不做完整数据流/别名 |
| 交付物 | 编译器改动、`test/ast/p70_*` 探针、文档 |
| 任务清单 | §3（R1–R3） |
| 退出判据 | E70-1…E70-3（§4） |
| version-minor | 69（PH-70，`d=1`） |
| 已知风险 | R70-1…R70-1（§5） |

## 1 需求与边界

CFG/定值/控制流语义检查：CFG/基本块；definite assignment；所有路径 return；break/continue/goto/switch；重复 case；不可达。只做控制流可判定子集；不做完整数据流/别名。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 CFG 构建 | 基本块与边；供后续检查复用 | ``bash test/ast/p70_cfg.sh` → `OK p70/cfg`` | M |
| R2 定值/return | 未初始化读、所有路径 return | ``bash test/ast/p70_definite.sh` → `OK p70/definite`` | M |
| R3 跳转/switch | break/continue/goto 越界、重复 case、不可达 | ``bash test/ast/p70_flow.sh` → `OK p70/flow`` | M |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E70-1 | E70-1 控制流探针矩阵全绿 |
| E70-2 | E70-2 `ct check --semantics` 正负例通过 |
| E70-3 | E70-3 合法 C 零误报；`check-all` 11/11 且 golden 无变化 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R70-1 | 合法 C 写法多，易误报 | 只做可判定子集，skip 表入账 |

## 6 进展（2026-11-19，R1 部分）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 CFG 构建 | 🚧 部分 | 暂无 CFG/基本块；先落了语句级流上下文 |
| R2 定值/return | ⬜ 未开始 | `int x; return x;` 仍静默 |
| R3 跳转/switch | 🚧 部分 | `ct check --semantics` 下循环外的 `break`/`continue` 报错；循环/switch 内合法；`p70/flow` 绿；**重复 case、不可达**未做 |

实现：`Expr.check_mode` 指针 + `Stmt` 的 `nbreak`/`ncont` 判定；Driver 接受
`--semantics`（与 `--types` 同入口）。CFG/definite assignment 需要新的分析层，
留待后续轮次。
