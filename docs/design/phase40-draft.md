# Phase 40 — `errdefer` 与显式错误出口

> **状态：✅ 完成**（2026-11-13；v0.40.0 收口，v0.40.1 为 SH-68 review fix；R1–R7 落地，E40-1–E40-9 全绿；收口记录见 §8.1）。
> **基线**：PH-39 收口提交（`v0.39.0`）；S0 在该提交上重建并记录实际 sha 与门禁数字。
> **文档形态**：`phase40-draft.md`；design window 7/12，不触发归档。
> **前置**：[phase38-draft.md](phase38-draft.md)（`defer` 已落地）、[phase39-draft.md](phase39-draft.md)（收口基线）。
> **关联**：[language-spec §4.9.1](../language-spec.md)、[phase38 T38-1](phase38-draft.md)、[modern-oo-gap.md](../modern-oo-gap.md) §6.2。
> **规模**：解析/发射 250–400；夹具 150–250；文档 60–100；合计 **460–750**（±40%）。
> **纪律**：收口时 bump `v0.40.0`；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-40 |
| 目标 | 用显式 `err:` 标记错误出口，新增 `errdefer` 条件回滚与「声明 + 清理块」尾随绑定；零运行时判断、不猜返回类型 |
| 范围 | O1/O2/O3；不做 `Result`/`?`、`goto err`、`switch` 内 errdefer、赋值形式尾随、错误传播 |
| 交付物 | `Stmt.h.ct` / `Emitter.h.ct`；`test/ast/**` 的 p40 夹具与负例；`examples/43_errdefer`；`language-spec` / `tutorial` / tmLanguage；`check-ast.sh` 的 p40 段 |
| 任务清单 | §4.1（R1–R7；R3 拆 a/b，共 8 项） |
| 退出判据 | E40-1…E40-9（§5） |
| 依赖 | PH-38 `defer` 已落地；PH-39 收口 `v0.39.0`；编辑器语法门禁 |
| 规范版本 | 1.9.0 |
| version-minor | 40 |
| 已知风险 | R40-1…R40-7（§7） |

## 1 需求与边界

### 1.0 AN-40（四段）

| 段 | 内容 |
| --- | --- |
| 问题 | 多步初始化失败时，手写逐层回滚链易漏；`defer` 无条件清理无法表达「成功移交、失败回滚」 |
| 范围 | 显式错误出口（`return err:` / `break err:` / `continue err:`）+ 块级 `errdefer` + 声明绑定尾随；不改 `defer` 既有行为 |
| 验收 | E40-1…E40-9 全部可在 `check-ast.sh` / `check-all.sh` / `check-grammar.py` 上机械核对 |
| 依赖与风险 | 不依赖 `Result`/`?`；风险集中在普通出口丢弃 errdefer、`break err` 不传播、尾随注册早于失败检查 |

### 1.1 一句话

`errdefer` 只在**显式错误出口**执行回滚；错误出口由 `err:` 语法标记，不由返回类型或返回值推断。尾随形式把「声明 + 清理」合成一行，`$` 只是声明变量名的别名。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | 错误出口标记：`return err: expr;` / `return err:;`（void）/ `break err:;` / `continue err:;`；`err` 只在三处之后是关键字 | 无错误标记；`return err: x` 是语法错误 |
| O2 | `errdefer { … }`：块级注册，只在错误出口执行；与 `defer` 同栈 LIFO；普通出口丢弃 | 无；`defer` 无条件 |
| O3 | 尾随声明绑定：`Type name = expr defer { … };` / `errdefer { … };`；`$` = `name` 的 AST 别名，块内只读 | 需两行书写 |

### 1.3 非目标

- 不做 `Result`/`?`/`try`/异常；错误传播另立卡（T40-1）。
- 不做 `goto err:`；`goto` 仍按 P38 的跨 defer 块硬错（T40-2）。
- 不在 `switch` 内使用 `defer`/`errdefer`（沿用 P38）。
- 不做赋值形式尾随（`lhs = expr errdefer { … };`）、多声明符、`for` 初始化里的尾随（T40-3）。
- 不做函数级错误标志；`break err:` / `continue err:` 只是块局部回滚（D40-7）。
- 不做 `$` 可写、闭包内重新绑定、宏体里的 `return err:`（T40-4、R40-6）。
- 不改 `ctc.c`、不改 C 侧；全部落 ct-ast。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D40-1 | 错误由语法标记，**不按返回类型/返回值推断** | C 没有统一错误约定；`write` 正数成功、`find` 的 NULL 不是错误 |
| D40-2 | `return err: expr;` / `return err:;`（void）/ `break err:;` / `continue err:;`；`err:` 只在三处之后识别 | 冒号在 return/break/continue 的表达式位置本来不合法，无歧义 |
| D40-3 | 清理集合：`return err` 跑函数内所有活跃 errdefer；`break err`/`continue err` 只跑退出到的块；普通出口只跑 defer、丢弃 errdefer | 块级作用域与退出一致；普通出口不猜错误 |
| D40-4 | **单栈 LIFO**：errdefer 是带 `on_error` 标记的 defer 条目，与 defer 同栈；不按种类分两段 | 两段式会让后注册的 defer 读到已被 errdefer 释放的资源 |
| D40-5 | errdefer 块级；函数体、`if`、循环体都可用；`switch`、`.h.ct`、文件作用域禁止 | 与 P38 defer 的边界一致 |
| D40-6 | errdefer 内禁止 `return`/`break`/`continue`/`defer`/`errdefer`；`goto` 跨块硬错；`own` 与 errdefer 同对象硬错 | 控制转移与双重释放 |
| D40-7 | `break err:`/`continue err:` 是块局部回滚，不设置函数级错误；要传播用 `return err:` 或用户 flag | 避免隐式函数状态；名字只表示"错误退出本块" |
| D40-8 | 尾随只允许**声明**：`Type name = expr defer/errdefer { … };`；`$` 是 `name` 的 AST 别名、只读；不引入临时量、不新增词法 token | `$` 只是名字替换，无运行时语义；声明保证绑定对象稳定 |
| D40-9 | 尾随块在初始值后立即注册；块内必须自行 guard 失败值（如 `if ($) …`）；普通出口丢弃 errdefer | 注册点早于任何成功检查，`fclose(NULL)` 一类必须由作者处理 |
| D40-10 | 本卡以 `err:` 标记替代 P38 `T38-1` 的「等 `Result` + `?`」触发条件；不修改 P38 已收口判据 | 错误信号显式化后不需要 `Result` 才能做回滚；`Result`/`?` 仍属 T40-1 |

## 2 现状与基线

### 2.1 门禁基线

参考值（历史量级）：`check-ast` 1329/0、`check-warnings` 600/0、`test/run` 148、`check-docs` 900+ links、design window 7/12。S0 在 PH-39 收口提交上重建 `ct` 并实测替换本节。

### 2.2 设计探针（2026-11-13 实测）

| 探针 | 命令 | 结果 |
| --- | --- | --- |
| `defer` 已具备块级 LIFO / 四出口 | `test/ast/220_defer_*` | 已绿（P38） |
| `$` 已是单字符标点 | 读 `Lexer.h.ct` | `T_PUNCT`，无需新增词法 token |
| `errdefer` 当前是普通标识符 | `ct check` 对 `int errdefer = 1;` | rc=0 |
| `return err: x` 当前非法 | `ct check` | 语法错误（冒号在 return 表达式里不合法） |
| `fclose(NULL)` | 小 C 探针 | 未定义行为（本机返回 -1，不可依赖） |

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| `defer` 关键字判定 | `frontend/parse/Stmt.h.ct` 的 `defer_ahead` |
| defer 块栈 / 出口 | `Stmt.h.ct` 的 `defer_add` / `defer_mark_block` / `defer_flush_block` |
| `return` / `break` / `continue` 解析 | `Stmt.h.ct` 的语句分支 |
| defer 发射 / N_DEFER_RUN | `backend/emit/Emitter.h.ct` |
| 模块 `.h` 类型-only / C 产物 | `Emitter.h.ct` / `Module.h.ct` |

## 3 语义与落码

### 3.1 错误出口

| 形式 | 语义 |
| --- | --- |
| `return err: expr;` | 求值 `expr` 到临时量；跑函数内所有活跃 errdefer + defer（LIFO）；`return` 临时量；生成的 C 是 `return (expr);` |
| `return err:;` | 仅 `void`；跑所有活跃 errdefer + defer；`return;` |
| `break err:;` | 仅循环内；跑 break 退出到的块（循环体及内层）的 errdefer + defer；再 break |
| `continue err:;` | 仅循环内；跑 continue 退出到的块（循环体及内层）的 errdefer + defer；再 continue |
| 普通 `return` / `break` / `continue` / 落出 | 只跑 defer；errdefer 丢弃，不执行 |

`break err:` 在 `switch` 内禁止（switch 的 break 目标不是循环）；`continue err:` 只在循环内。`err:` 只在上述三个关键字之后识别；其它位置 `err` 仍是普通标识符。

### 3.2 errdefer 的顺序与作用域

- **单栈 LIFO**：errdefer 与 defer 进入同一条块栈；errdefer 条目带 `on_error` 标记；出口逆序走，标记项只在错误出口执行。
- `return err` 从最内层到函数体跑全部；`break err`/`continue err` 只跑被退出块；外层条目不跑、继续保留。
- 普通出口：errdefer 条目随块退出**丢弃**；如果资源需要普通出口也释放，用 `defer` 或显式释放。
- 与 `own`：同一块内 defer/errdefer 先于 `own`；`own` 对象出现在 errdefer 中 → 硬错（按标识符/字段名，别名逃逸文档记录）。
- `switch` 内、`.h.ct` 内、文件作用域禁止；errdefer 内禁止控制转移、嵌套 defer/errdefer。

### 3.3 尾随声明绑定

```c
Item *it = acquire(i) errdefer { if (it) release(it); };
FILE *fp = fopen(path, "r") defer { if (fp) fclose(fp); };
```

- 只支持单声明符声明，块出现在初始值与分号之间；
- `$` 是声明名的 AST 别名（`$` → `it`），只读；块内也可直接写名字；
- 不引入临时量、不新增词法 token；表达式只求值一次就是初始值本身；
- 初始值可能失败：块内必须 guard（`if ($) …`），或在检查之后另写 defer；
- 普通出口丢弃 errdefer；`defer` 在所有出口执行；
- 不支持赋值形式、多声明符、`for` 初始化；`$` 不允许出现在其它位置。

### 3.4 诊断（L40-n）

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L40-1 | 非 void 写 `return err:;` | `an error return needs a value` |
| L40-2 | void 写 `return err: expr;` | `a void function cannot return a value` |
| L40-3 | `break err:` / `continue err:` 在循环外 | `err: break/continue is only allowed in a loop` |
| L40-4 | `break err:` 在 `switch` 内 | `err: break is not allowed in a switch` |
| L40-5 | errdefer 在 `switch` / `.h.ct` / 文件作用域 | `errdefer is not allowed here` |
| L40-6 | errdefer 内控制转移、嵌套 defer/errdefer | `an errdefer block cannot transfer control` |
| L40-7 | `own` 对象出现在 errdefer | `an own object cannot be rolled back by errdefer` |
| L40-8 | `goto` 跨带 errdefer 的块 | `a goto cannot cross a block with errdefer` |
| L40-9 | 尾随用于赋值 / 多声明符 / `for` 初始化 | `a trailing defer needs a single declaration` |
| L40-10 | `$` 出现在尾随块外，或 `$ = …` | `'$' is read-only and only valid in the trailing block` |

## 4 任务清单

开工前 **S0（不占任务行）**：在 PH-39 收口提交上重建 `ct`、复跑 §2.2、写 §2.1 与 `baseline.sha`；不产提交。

R1–R5 每项先提 `test(cleanup): <task-id> 红`，实现提交随后转绿；R6 为纯文档/编辑器 `no-test:`（6.6 T-7 例外），R7 为等价性证据 `no-test:`（3.9 test-fix），两者须评审签字。

### 4.1 冻结任务表

| 任务 | 交付物（路径） | 验收命令 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| R1 | `err:` 语法与诊断（`Stmt.h.ct`） | `p40/err-syntax`：5 正例 + 5 负例全绿 | M | revert |
| R2 | errdefer 解析、条件栈、作用域/诊断（`Stmt.h.ct`） | `p40/errdefer-scope`：6 负例全绿 | M | revert |
| R3a | `return err:` 发射、返回值临时量（`Emitter.h.ct`） | `p40/return-err`：全栈 LIFO、成功跳过 | M | revert |
| R3b | `break err:` / `continue err:` 发射验证（test-only；is_err 已在 R3a 接入） | `p40_break_continue`：只跑退出块 | S | test-only |
| R4 | defer/errdefer/own 单栈顺序（`Emitter.h.ct`） | `p40/order-own`：pool/buffer 顺序、own 硬错 | M | revert |
| R5 | 尾随声明绑定（`Stmt.h.ct`） | `p40/trailing`：`$` 别名、guard、4 负例 | M | revert |
| R6 | 文档与编辑器（`docs/language-spec.md` / `tutorial.md` / tmLanguage / `examples/43_errdefer`） | `p40/docs` + `check-grammar.py` 168/168；`no-test:` 纯文档/编辑器 JSON | S | revert |
| R7 | 零回归（全量门禁） | `bash selfhost/check-all.sh` 11/11 + `p40/regression`；`no-test:` 只做等价性证据（3.9 test-fix） | M | revert |

映射：R1→E40-4；R2→E40-5；R3a→E40-1；R3b→E40-2；R4→E40-3；R5→E40-6；R6→E40-8；R7→E40-7。**每项至多覆盖 1 条退出判据**（6.6 T-5）。

## 5 退出判据（E40-n）

所有 p40 断言挂在既有 `selfhost/check-ast.sh` 内；不新增门禁编号。

| ID | 断言 | 命令与阈值 | 夹具 |
| --- | --- | --- | --- |
| E40-1 | `return err:` 跑函数内全部 errdefer+defer，LIFO；成功 return 跳过 errdefer；返回值先求值 | `ok p40/return-err`，1/1；顺序逐字节 | `test/ast/p40_return_err` |
| E40-2 | `break err:`/`continue err:` 只跑退出块；普通 break/continue 丢弃 errdefer；外层不动 | `ok p40/break-continue-err`，1/1 | `test/ast/p40_break_continue` |
| E40-3 | defer/errdefer/own 单栈 LIFO；own 同对象硬错 | `ok p40/order-own`，1/1 | `test/ast/p40_order_own` |
| E40-4 | `err:` 5 正例 + 5 负例（L40-1…4 + 循环外） | `ok p40/err-syntax`，10/10 | `test/ast/p40_err_*` |
| E40-5 | errdefer 6 负例（L40-5…8 + own） | `ok p40/errdefer-scope`，6/6 | `test/ast/errors/p40_*` |
| E40-6 | 尾随声明：`$` 别名、guard、赋值/多声明符/for/`$` 只读 4 负例 | `ok p40/trailing`，1/1 + 4/4 | `test/ast/p40_trailing` |
| E40-7 | 既有 defer/own/C 产物零变化 | `bash selfhost/check-all.sh` exit 0（11/11）；全量门禁即回归证据 | 全量 |
| E40-8 | 文档可执行 + 编辑器覆盖 | `check-docs` exit 0；`check-grammar.py` 168/168（无 node；有 node 169）；`ok p40/docs` | `docs/**`、`editors/**` |
| E40-9 | **任务清单每项可独立验收（6.6 T-6）** | 逐项跑 §4.1，8/8 exit 0；§8.1 逐行对照 | §4.1 |

承诺映射：O1→E40-4；O2→E40-1/2/3/5；O3→E40-6；E40-7/8 守边界与文档；E40-9 守任务粒度。

## 6 负例台账（L40-n）

| 编号 | 触发 | 夹具（`test/ast/errors/`） |
| --- | --- | --- |
| L40-1 | 非 void `return err:;` | `p40_err_no_value/` |
| L40-2 | void `return err: x;` | `p40_err_void_value/` |
| L40-3 | 循环外 `break err:` / `continue err:` | `p40_err_break_outside/` |
| L40-4 | `switch` 内 `break err:` | `p40_err_break_switch/` |
| L40-5 | errdefer 在 switch / `.h.ct` / 文件作用域 | `p40_errdefer_scope/` |
| L40-6 | errdefer 内控制转移/嵌套 | `p40_errdefer_control/` |
| L40-7 | own 对象出现在 errdefer | `p40_errdefer_own/` |
| L40-8 | goto 跨带 errdefer 的块 | `p40_errdefer_goto/` |
| L40-9 | 尾随用于赋值/多声明符/for 初始化 | `p40_trailing_shape/` |
| L40-10 | `$` 在块外或 `$ = …` | `p40_trailing_placeholder/` |

## 7 风险与开放项

| 编号 | 风险 | 触发信号 / 处置 |
| --- | --- | --- |
| R40-1 | 普通 `break`/`continue` 丢弃 errdefer，资源泄漏 | 文档与示例强制「错误路径写 err:」；可选 lint 提示同块普通 break |
| R40-2 | `break err`/`continue err` 不传播，函数可能仍成功返回 | D40-7 文档化；需要函数级失败时用 `return err:` 或用户 flag |
| R40-3 | 尾随块注册早于失败检查，失败值被清理 | D40-9 要求块内 guard；示例 `if ($)` |
| R40-4 | `$` 与块内同名 shadowing | AST 绑定到声明变量，不按文本查找；负例覆盖 |
| R40-5 | errdefer 与 own 双重释放 | D40-6 硬错；别名逃逸记开放项 |
| R40-6 | 宏体里的 `return err:` 不被识别 | `#define` 行直通 C；文档写明宏内不可用 |
| R40-7 | 改动 `defer` 关键字位置（D38-7）与栈结构，回归面大 | 单栈改造、全量 `check-all`；E40-7 拦 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T40-1 | `Result`/`?` 与 errdefer 的传播语义 | 有真实调用方需要跨函数传播 |
| T40-2 | `goto err: label` | 需要 C 风格 goto 回滚时另立卡 |
| T40-3 | 赋值形式尾随 `lhs = expr errdefer { … };` | 有稳定的绑定值语义 |
| T40-4 | `$` 可写 | 有明确需求且不破坏只读约定 |
| T40-5 | 函数级错误标志/传播 | 与 T40-1 一并评估 |

## 8 估算与收口

- 解析/发射 250–400 = R1 60–100 + R2 40–80 + R3a 60–100 + R3b 40–80 + R4 30–60 + R5 60–100；夹具 150–250；文档 60–100。
- 开工前 S0：PH-39 收口提交上重建 `ct`（`ct -v` = v0.39.0）、复跑 §2.2、写 `baseline.sha`；不占任务行。
- 收口动作：11 道门禁绿、`p40/*` 全绿、`version-minor=40`、五处 `CTC_VERSION` 与全部版本落点同步到 `v0.40.0`、phase-log 与对照表落盘；tag/push 按 0.3 等用户批准。
- 每个实现任务 ≤3 个源码文件；每个实现提交的父提交是它的 `test(cleanup): <task-id> 红`；仓库任何时刻可构建。

### 8.1 收口记录（2026-11-13）

| 项 | 结果 |
| --- | --- |
| version-minor | 40；五处 `CTC_VERSION` 与 README/docs/AGENTS 同步到 `v0.40.0` |
| R1–R7 | 全部落地；R3b 的 `is_err` 发射在 R3a 已接好，R3b 用夹具验证；R6/R7 为文档/回归 |
| R1 | `bash test/ast/p40_err_syntax.sh <ct-ast>` | 10/10 OK |
| R2 | `bash test/ast/p40_errdefer_scope.sh <ct-ast>` | 6/6 OK |
| R3a | `p40_return_err` build/run/diff | OK（d2,e2,d1,e1 / d2,d1） |
| R3b | `p40_break_continue` build/run/diff | OK（只跑退出块） |
| R4 | `p40_order_own.sh` | OK（d,e,own；own 引用拒绝） |
| R5 | `p40_trailing.sh` | OK（正例 + 9 负例） |
| R6 | `check-grammar.py` / `check-docs` / `examples/43_errdefer` | 168 / 0（无 node）、962 links、test/run 153 |
| R7 | `bash selfhost/check-all.sh` | 11/11 hard gates |
| E40-1–E40-9 | `p40 r1` / `r2` / `r4` / `r5` / `docs` + `p40_return_err` / `p40_break_continue` / `p40_order_own` / `p40_trailing` |
| 全量门禁 | `check-all: OK (11 hard gates green)`；check-ast 1350/0（review fix 后）、check-warnings 607/0、test/run 153、goldens 82、docs 962 links / 217 files、acceptance 20 |
| 样例 | `examples/43_errdefer`（成功跳过 errdefer；错误路径 LIFO） |
| tag/push | annotated tag `v0.40.0` 与分支已 push；v0.40.1 为 PATCH review fix，不新建 tag（V-7） |
