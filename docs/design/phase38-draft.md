# Phase 38 — `defer` 块级清理

> **状态：规划中**（2026-11-12 立项草案；不写实现）。
> **基线**：Phase 37 收口提交；S0 在实现提交的父提交上重建二进制并复跑 §2.2，红证记录 `baseline: <sha>`。
> **文档形态**：`phase38-draft.md`；design window 12/12，转正时归档当时最老的一张。
> **前置**：[phase36-draft.md](phase36-draft.md)（`own`/Drop 的顺序）、[phase34-draft.md](phase34-draft.md)（`Result` 只作对照，本相不做 `errdefer`）。
> **红证**：§2.2（2026-11-12，HEAD `bd91bfe`，`v0.30.0` 重建的 `ct-ast`）。
> **关联**：[modern-oo-gap.md](../modern-oo-gap.md) §6.2。
> **规模**：编译器 260–520；夹具 100–180；文档 50–90；合计 **410–790**（±40%）。
> **纪律**：不 bump、不打 tag、不 push；只暂存本相文件。

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

## 5 退出判据（E38-n）

| ID | 断言 | 夹具 | 门禁 |
| --- | --- | --- | --- |
| E38-1 | 两个 defer 按后进先出执行，输出顺序逐字节正确 | `ast/220_defer_order` | `check-ast` |
| E38-2 | 正常落出、`return`、`break`、`continue` 四条路径都执行对应 defer | `ast/221_defer_paths` | `check-ast` |
| E38-3 | `return f()` 的返回值在 defer 之前求值；defer 修改局部变量不影响返回值 | `ast/222_defer_return` | `check-ast` |
| E38-4 | `goto` 跨出带 defer 的块报 L38-1，不写产物；同一块内 `goto` 仍可用 | `errors/p38_goto_cross.ct` | `check-ast` |
| E38-5 | 同块内 defer 先于 `own` drop，输出顺序正确 | `ast/223_defer_own_order` | `check-ast` |
| E38-6 | defer 内 `return`/`break`/`continue`/嵌套 defer 各报 L38-2 | `errors/p38_defer_control.ct` | `check-ast` |
| E38-7 | 文件作用域 / `.h.ct` 的 defer 报 L38-3 | `errors/p38_defer_scope.ct` | `check-ast` |
| E38-8 | 既有 corpus 与 golden 零变化；自举链在 L0/L1/L2 上可构建 | 全量 | `check-all` + fixpoint |

## 6 负例台账（L38-n）

| 编号 | 触发 | 夹具 | 文案要点 |
| --- | --- | --- | --- |
| L38-1 | `goto` 跨出/跨入带 defer 的块 | `errors/p38_goto_cross.ct` | `a goto cannot cross a block with defer` |
| L38-2 | defer 内控制转移或嵌套 defer | `errors/p38_defer_control.ct` | `a defer block cannot transfer control` |
| L38-3 | 文件作用域 / `.h.ct` 的 defer | `errors/p38_defer_scope.ct` | `defer is only allowed inside a function` |

三条均为新诊断，各自恰一条断言并钉位置。

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
