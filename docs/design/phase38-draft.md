# Phase 38 — `defer` 块级清理

> **状态：实现完成（含独立评审 P0/P1 修复）**（2026-11-13；版本 bump / tag 待用户批准）。
> **基线**：`5e395e9`（Phase 37 收口 + runtime-checks 样例；S0 复跑全量门禁并记录实际 baseline）。
> **文档形态**：`phase38-draft.md`；design window 12/12，转正时归档当时最老的一张。
> **前置**：[phase36-draft.md](phase36-draft.md)（`own`/Drop 的顺序）、[phase34-draft.md](phase34-draft.md)（`Result` 只作对照，本相不做 `errdefer`）。
> **红证**：§2.2（2026-11-12，HEAD `bd91bfe`，`v0.30.0` 重建的 `ct-ast`）。
> **关联**：[modern-oo-gap.md](../modern-oo-gap.md) §6.2。
> **规模**：编译器 260–520；夹具 100–180；文档 50–90；合计 **410–790**（±40%）。
> **纪律**：收口时 bump `v0.38.0`；tag/push 按 `AGENTS.md` 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | PH-38 |
| 目标 | 块级 `defer { … }`：语句块退出时按 LIFO 执行清理，覆盖正常落出 / `return` / `break` / `continue` |
| 范围 | O1/O2/O3；不做 errdefer / try / 单语句 defer / 全局或 `.h.ct` defer |
| 交付物 | `Stmt.h.ct` / `Emitter.h.ct` 的 defer 解析/发射/诊断；`test/ast/**` 与负例；`examples/42_defer`；文档 |
| 任务清单 | §4.1（S0–S7） |
| 退出判据 | E38-1…E38-8（§5） |
| 依赖 | Phase 37 收口；全量门禁基线 `5e395e9` |
| 规范版本 | 1.9.0 |
| version-minor | 38 |
| 已知风险 | R38-1…R38-4（§7） |

## 1 目标与边界

### 1.1 一句话

加入 **块级 `defer { … }`**：语句块退出时按后进先出执行清理，覆盖正常落出、`return`、`break`、`continue`；`goto` 跨出带 `defer` 的块是硬错。

### 1.2 三项

| 编号 | 内容 | 今天 |
| --- | --- | --- |
| O1 | `defer { … }` 语法、块级作用域、LIFO | 无 `defer`；`defer { … }` 解析成未声明变量 |
| O2 | `return` / `break` / `continue` / 正常落出四条路径都执行对应块的 defer | 无 |
| O3 | `goto` 跨出（或跨入）带 defer 的块 → 硬错；defer 内禁止控制转移 | 无 |

### 1.3 非目标

- 不做 `errdefer`：它需要错误协议（`Result` 的 `?` 尚未落地，Phase 34 只做类型）；本相不猜语义。
- 不做 `try` / `?` / 异常（见 [phase34-draft.md](phase34-draft.md) T34-1）。
- 不做单语句形态 `defer free(p);`：只收块形态，避免 `defer` 与同名函数调用的歧义（D38-1）。
- 不做全局/文件作用域 defer，不做 `.h.ct` 内的 defer（头单元只放声明）。
- 不改 `own`/AutoDrop 的既有释放点，只定义二者的先后。

### 1.4 关键决策

| 编号 | 决策 | 理由 |
| --- | --- | --- |
| D38-1 | 只收 `defer { … }`，不收单语句 | `defer(x);` 与函数调用无法稳定区分；块形态已是主力写法 |
| D38-2 | 块级作用域，LIFO；内层先于外层 | 与 C++/Go 的直觉一致，也与 `own` 的块尾释放一致 |
| D38-3 | `return` 先求值返回值到临时量，再跑 defer，最后返回临时量 | defer 不应改变已求值的返回结果；与 C++ 语义一致 |
| D38-4 | 同一块内 defer 先于 `own` 自动释放；两组各自 LIFO | defer 是显式清理，先于隐式清理；不改变既有 `own` 的释放点 |
| D38-5 | `goto` 跨出/跨入带 defer 的块一律硬错 | C 的 `goto` 不会执行清理，静默跳过比报错更危险 |
| D38-6 | defer 块内禁止 `return` / `break` / `continue` / 嵌套 `defer` | 控制转移与清理顺序纠缠，v1 直接拒绝 |
| D38-7 | `defer` 只在语句位置、后跟 `{` 时是关键字 | 其余位置仍是普通标识符，不扩大保留字 |

## 2 现状与基线

### 2.1 门禁基线

参考值（**历史量级参考**，v0.30.0）：`check-ast` 1155/0、`check-warnings` 389/0、`test/run` 145、`check-docs` 1036 links / 181 files、`design window 12/12`。S0 在 Phase 37 收口提交上实测并替换本节。

### 2.2 红证探针（2026-11-12 实测）

| 探针 | 命令 | 基线输出 |
| --- | --- | --- |
| `defer { printf("x"); }` | `ct-ast prog.ct` | `4:5: error: use of an undeclared variable`（`defer` 被当标识符） |
| `int x = maybe()?;` | `ct-ast prog.ct` | `5:20: error: expected an expression` |
| 手工 `goto cleanup` | 现有 C 写法 | 可用，但每个提前返回都要手写一遍；漏写即泄漏 |

### 2.3 代码锚点

| 主题 | 位置 |
| --- | --- |
| 语句解析入口 | `frontend/parse/Stmt.h.ct`（`parse_stmt` 的关键字分派） |
| 块作用域 / 变量表 | `frontend/parse/Stmt.h.ct` 的 `push_scope`/`pop_scope` |
| `return` 发射 | `backend/emit/Emitter.h.ct` 的 `N_RETURN` |
| `own` 自动释放 | `Emitter.h.ct` 的块尾 drop 发射 |
| `goto` 检查 | `Stmt.h.ct` 的标签扫描（batch 7 的四条诊断） |

## 3 语义与落码

### 3.1 语法与作用域

```c
int read_file(const char *path)
{
    FILE *f = fopen(path, "rb");
    if (!f) return -1;

    defer {
        fclose(f);          /* 块退出时执行；后声明先执行 */
    }

    char *buf = malloc(4096);
    defer {
        free(buf);
    }

    return parse(f, buf);
}
```

- `defer` 块内按普通语句解析，但禁止 `return` / `break` / `continue` / 嵌套 `defer`（L38-2）。
- 注册顺序 = 源码顺序；执行顺序 = 逆序。
- 只有**语句块**（`{ … }`）持有 defer 栈；函数体本身也是一个块。

### 3.2 四条退出路径

| 路径 | 发射 |
| --- | --- |
| 正常落出块尾 | 逆序 emit 该块所有 defer，再落出 |
| `return expr` | 先 `ret_type __ct_ret = expr;`，再逆序 emit 从最内层到函数体的所有 defer，最后 `return __ct_ret;` |
| `break` / `continue` | 逆序 emit 被跳出块（含循环体）的 defer，再跳 |
| `goto` | 目标与源在同一 defer 作用域集合内才允许；否则 L38-1 |

`void` 函数不需要临时量；`return;` 直接跑 defer 后返回。

### 3.3 与 `own` 的顺序

同一块内：

```c
own FILE *f = fopen(...);   /* 自动释放 */
defer { log("done"); }      /* 显式清理 */
```

退出时先跑 `defer`，再跑 `own` 的 drop；两者各自 LIFO。D38-4 固定这个顺序，E38-5 用输出顺序断言。

### 3.4 诊断

| 编号 | 触发 | 文案要点 |
| --- | --- | --- |
| L38-1 | `goto` 跨出/跨入带 defer 的块 | `a goto cannot cross a block with defer` |
| L38-2 | defer 块内出现 `return`/`break`/`continue`/`defer` | `a defer block cannot transfer control` |
| L38-3 | 文件作用域或 `.h.ct` 内的 defer | `defer is only allowed inside a function` |

三条都是新文案，各自一条负例，`ct compile` 与 `ct check` 同文案同位置。

## 4 切片（每片 ≤150 行）

| 片 | 内容 | 主要文件 | 预估行 |
| --- | --- | --- | --- |
| S0 | 在 Phase 37 收口提交上重建、复跑 §2.2、记录 gate 基线 | 无源码改动 | 0 |
| S1 | `defer { … }` 解析 + 块级 defer 栈 | `Stmt.h.ct` | 50–100 |
| S2 | defer 内的控制转移/嵌套/作用域诊断（L38-1–L38-3） | `Stmt.h.ct` | 40–80 |
| S3 | 正常落出与 `break`/`continue` 的逆序发射 | `Emitter.h.ct` | 60–120 |
| S4 | `return` 临时量 + 全层逆序发射；`void` 分支 | `Emitter.h.ct` | 80–160 |
| S5 | 与 `own` 的顺序（D38-4） | `Emitter.h.ct` | 30–60 |
| S6 | 正负例与门禁；产物层断言 defer 调用顺序 | `test/ast/**` / `check-ast.sh` | 60–120 |
| S7 | 文档：language-spec、tutorial、gap | `docs/**` | 50–90 |

依赖：S1→S2→S3→S4→S5；S6 依赖 S4/S5；S7 最后。

### 4.1 任务清单（冻结）

| 任务 | 交付物 | 验收 | effort | 回滚 |
| --- | --- | --- | --- | --- |
| S0 | §2.2 红证 + p38 夹具的失败输出 | `bash selfhost/check-ast.sh` 在 p38 段失败；`baseline: 5e395e9` | S | 删除夹具/断言 |
| S1 | `defer { … }` 解析 + 块级 LIFO 栈 | `ast/220_defer_order` 输出顺序正确 | M | revert |
| S2a | `goto` 跨出/跨入带 defer 的块诊断 | `errors/p38_goto_cross.ct` 报 L38-1 | S | revert |
| S2b | defer 内控制转移 / 嵌套 defer 诊断 | `errors/p38_defer_control.ct` 报 L38-2 | S | revert |
| S2c | 文件作用域 / `.h.ct` defer 诊断 | `errors/p38_defer_scope.ct` 报 L38-3 | S | revert |
| S3 | 正常落出 / `break` / `continue` 的逆序发射 | `ast/221_defer_paths` 四条路径输出正确 | M | revert |
| S4 | `return` 临时量 + 全层逆序发射、void 分支 | `ast/222_defer_return` 返回值先求值 | M | revert |
| S5 | defer 先于同块 `own` drop（各自 LIFO） | `ast/223_defer_own_order` 输出顺序正确 | S | revert |
| S6 | 正负例、样例与全量门禁 | `check-ast.sh` / `check-all.sh` 绿 | M | revert |
| S7 | 文档：language-spec、tutorial、gap、`examples/42_defer` | `check-docs.py` + 样例运行 | S | revert |

映射：S1→E38-1；S2a→E38-4；S2b→E38-6；S2c→E38-7；S3→E38-2；S4→E38-3；S5→E38-5；S6→E38-8；S0/S7 无退出判据。

## 5 退出判据（E38-n）

| ID | 断言 | 夹具 | 门禁 |
| --- | --- | --- | --- |
| E38-1 | 两个 defer 按后进先出执行，输出顺序逐字节正确 | `ast/220_defer_order` | `check-ast` |
| E38-2 | 正常落出、`return`、`break`、`continue` 四条路径都执行对应 defer | `ast/221_defer_paths` | `check-ast` |
| E38-3 | `return f()` 的返回值在 defer 之前求值；defer 修改局部变量不影响返回值 | `ast/222_defer_return` | `check-ast` |
| E38-4 | `goto` 跨出带 defer 的块报 L38-1，不写产物；同一块内 `goto` 仍可用 | `errors/p38_goto_cross.ct` | `check-ast` |
| E38-5 | 同块内 defer 先于 `own` drop，输出顺序正确 | `ast/223_defer_own_order` | `check-ast` |
| E38-6 | defer 内 `return`/`break`/`continue`/嵌套 defer 各报 L38-2 | `errors/p38_defer_control.ct` / `p38_defer_break.ct` / `p38_defer_continue.ct` / `p38_defer_nested.ct` | `check-ast` |
| E38-7 | 文件作用域的 defer 报 L38-3；`.h.ct` 内（含函数体）报 `defer is not allowed in a .h.ct unit` | `errors/p38_defer_scope.ct` / `p38_defer_header.h.ct` | `check-ast` |
| E38-8 | 既有 corpus 与 golden 零变化；自举链在 L0/L1/L2 上可构建 | 全量 | `check-all` + fixpoint |

## 6 负例台账（L38-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L38-1 | `goto` 跨出/跨入带 defer 的块 | `errors/p38_goto_cross.ct` | `a goto cannot cross a block with defer` |
| L38-2 | defer 内控制转移或嵌套 defer | `errors/p38_defer_control.ct` | `a defer block cannot transfer control` |
| L38-3 | 文件作用域 / `.h.ct` 的 defer | `errors/p38_defer_scope.ct` / `p38_defer_header.h.ct` | `defer is only allowed inside a function` / `defer is not allowed in a .h.ct unit` |
| L38-4 | `switch` 内 defer（含 case 内嵌套块） | `errors/p38_defer_switch.ct` | `defer is not allowed inside a switch` |
| L38-5 | defer 体内 label | `errors/p38_defer_label.ct` | `a defer block cannot declare a label` |

L38-1/L38-2 各自一条断言；L38-3 分文件作用域与 `.h.ct` 两条文案；L38-4/L38-5 为评审后新增。

## 7 风险与开放项

| 编号 | 风险 | 处置 |
| --- | --- | --- |
| R38-1 | `return` 临时量与聚合类型/数组返回的交互 | S4 只对可赋值返回类型用临时量；数组/函数指针返回沿用既有路径，S0 列清单 |
| R38-2 | defer 与 `goto` 的标签扫描冲突 | S2 复用 batch 7 的标签表，先建立「块 → defer 数」映射 |
| R38-3 | 与 `own` 的释放顺序被误读 | D38-4 写进语言规范；E38-5 产物级断言 |
| R38-4 | `defer` 作为标识符的既有代码被误伤 | D38-7 仅在语句位置 + `{` 时识别；S6 加一条 `int defer = 1;` 正例 |

开放项：

| 编号 | 内容 | 触发条件 |
| --- | --- | --- |
| T38-1 | `errdefer` | `Result` + `?` 落地后另立卡 |
| T38-2 | 单语句 `defer expr;` | 有稳定的无歧义语法后 |
| T38-3 | defer 内的 `return` | 若评审认为语义可定义，再放开 L38-2 |

## 8 估算与收口

- 编译器 260–520 = S1 50–100 + S2 40–80 + S3 60–120 + S4 80–160 + S5 30–60；夹具 60–120；文档 50–90。
- 收口：S0 红证提交（`test(cleanup): P38 红`）；每片 ≤3 文件；仓库任何时刻可构建。
- 收口动作：全量 11 道门禁绿、样例 `examples/42_defer` 进 `test/run.sh`、文档同步、`version-minor=38`；版本 bump 与 tag 按 0.3 `phase-tag-requires-user-approval` 等用户批准。

## 9 收口记录（2026-11-13）

| 项 | 结果 |
| --- | --- |
| 红证 | `de16f54 test(cleanup): P38 红`；基线上 defer 被当未声明变量，三条负例文案不符 |
| 实现 | `1015e39 feat(cleanup): P38 block defer`；解析期 defer 栈、退出物化 N_DEFER_RUN、return 临时量、defer 先于 own、L38-1–L38-3 |
| E38-1 | `220_defer_order`：`body` / `b` / `a`（LIFO） |
| E38-2 | `221_defer_paths`：正常落出 / `return` / `break` / `continue` 四条路径 |
| E38-3 | `222_defer_return`：`defer x=99` 后 `ret=1`（返回值先求值） |
| E38-4 | `errors/p38_goto_cross.ct` / `p38_goto_sibling.ct` 报 `a goto cannot cross a block with defer`；同块 goto 按顶层 defer 块 id 放行 |
| E38-5 | `223_defer_own_order`：`defer` / `drop` 顺序 |
| E38-6 | `errors/p38_defer_control.ct` 报 `a defer block cannot transfer control` |
| E38-7 | `errors/p38_defer_scope.ct` 报 `defer is only allowed inside a function` |
| E38-8 | 全量 11 道门禁绿：test/run 152、goldens 82、check-ast 1327、check-warnings 600、check-docs 944 links、acceptance 20；样例 `examples/42_defer` |
| 版本/tag | 版本仍 `v0.37.0`；按 0.3 `phase-tag-requires-user-approval`，`v0.38.0` bump 与 tag/push 等用户批准 |

### 9.1 独立评审与修复（2026-11-13）

| 项 | 结果 |
| --- | --- |
| 评审结论 | 初版 Phase 38 **不通过**；Phase 37 有条件通过 |
| P0 修复 | 无括号 if/for/while/do 的 defer 上下文（`ac040d1`）；switch 内 defer v1 禁止；goto 改用顶层 defer 块 id，兄弟块跨跳不再漏清理 |
| P1 修复 | defer 体内禁止 label（避免多出口重复发射）；`--runtime-checks` 进入缓存 key；guard 改为 `__ct_vt_guard`，vt 只求值一次，三种派发都覆盖 |
| 新增测试 | 224 分支/循环/嵌套/同块 goto；p38_defer_switch / p38_defer_label / p38_goto_sibling / p38_goto_in / p38_defer_header / break / continue / nested；P37 warm-cache 双向 |
| 剩余已知项 | 同块 goto 跨过 defer 声明仍保守拒绝；switch 内 defer 连嵌套块也禁止；非 hoist 接收者在 guard 下仍按既有两次求值（不再多第三次）；均记录为 v1 边界 |
| 门禁 | `check-ast 1327/0`、`test/run 152`、P37 warm-cache probe OK、aux2 清零值接收者 abort |
| 版本/tag | 仍 `v0.37.0`；`v0.38.0` bump/tag 待用户批准；`v0.37.0` tag 仍含评审前的 runtime cache/guard 缺陷 |

