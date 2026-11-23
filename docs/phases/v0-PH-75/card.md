---
phase-id: v0-PH-75
version-minor: 75
---

# Phase 75 — 闭包作方法实参（SH-65/SH-67）

> **状态：完成**（2026-11-19 收口；`v0.74.0`；R1–R2 全绿）。
> **前置**：上一相收口；本卡在轮到时才开始实现。
> **布局说明**：phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），本卡位于 `docs/phases/v0-PH-75/card.md`。
> `docs/phases/v0-PH-75/card.md`，迁移时统一改名。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-75（`docs/phases/v0-PH-75/card.md`） |
| 目标 | 闭包作方法实参（SH-65/SH-67） |
| 范围 | 闭包作为方法实参的解析与类型推导；当前静默产出非法 C |
| 非目标 | 不扩展到闭包捕获的高级语义 |
| 交付物 | 编译器改动、`test/ast/p75_*` 探针、文档 |
| 任务清单 | §3（R1–R2） |
| 退出判据 | E75-1…E75-3（§4） |
| version-minor | 74（v0-PH-75，`d=1`） |
| 已知风险 | R75-1…R75-1（§5） |

## 1 需求与边界

闭包作方法实参（SH-65/SH-67）：闭包作为方法实参的解析与类型推导；当前静默产出非法 C。不扩展到闭包捕获的高级语义。

## 2 证据口径

每项任务 T-7：先 `test(...) 红`（含 `baseline: <sha>` 与原始输出），再实现。
合法语料零误报；`check-all` 11/11；golden 变化必须逐条说明。

## 3 任务清单（冻结）

| 任务 | 交付物 | verify | effort |
| --- | --- | --- | --- |
| R1 SH-65 | 闭包作方法实参被接受并正确发射 | ``bash test/ast/p75_closure.sh` → `OK p75/closure`` | M |
| R2 SH-67 | 错误形态硬错而非静默非法 C | ``bash test/ast/p75_closure_neg.sh` → `OK p75/closure-neg`` | S |

## 4 退出判据

| 编号 | 判据 |
| --- | --- |
| E75-1 | E75-1 SH-65 正例通过、SH-67 负例硬错 |
| E75-2 | E75-2 不再产出非法 C（`cc` 编译通过） |
| E75-3 | E75-3 `check-all` 11/11 |

## 5 风险

| 编号 | 风险 | 缓解 |
| --- | --- | --- |
| R75-1 | 与 v0-PH-69 调用检查重叠 | 共用调用表，避免重复实现 |

## 6 进展（2026-11-19，R2 已交付，R1 未做）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 SH-65 正例 | ⬜ 未做 | 闭包作 struct/trait 方法实参仍不支持（pair ABI 未发射） |
| R2 SH-67 负例 | ✅ 完成 | `p75/closure-neg`：字面量与绑定变量都报 `a closure cannot be passed to a method argument yet (SH-65); pass '(fn, env)' explicitly`；容器 `each` 豁免（examples/18、19 保持可构建） |

实现：trait 方法判定路径与 `chk_mcall_args` 在 `ct_is_container_type` 为假时扫描
`N_CLOSURE`/`is_closure` 变量；`argtype_check` 不扫描（否则误伤容器）。

## 7 收口对照表（2026-11-19，v0.74.0）

| 任务 | 状态 | 证据 |
| --- | --- | --- |
| R1 SH-65 | ✅ | `p75/closure`：pair 形方法（`f(env,x), env`）收闭包，`check --types` 通过，构建并运行返回 0 |
| R2 SH-67 | ✅ | `p75/closure-neg`：单 fp 形方法仍报 `a closure cannot be passed ...`（字面量与绑定变量），不再静默坏 C |

| 判据 | 命令 | 结果 |
| --- | --- | --- |
| E75-1 | `p75_closure.sh`、`p75_closure_neg.sh` | 绿 |
| E75-2 | 构建产物经 `cc` 编译并运行 | 绿（`(int x) => b.total + x` → 10） |
| E75-3 | `check-all.sh` | 11/11；`check-ast 1511 passed` |

实现口径：只有「2 参且第二参为 `void *`」的 pair 形方法收闭包；单函数指针形
仍是硬错（ABI 不匹配）。闭包实参在方法调用里按 `(tramp, &env)` 两参发射。
