# Phase 44 — `?` 错误传播运算符（后缀 `?`，同 `E`，临时量失效化）

> **状态：实施中**（2026-11-14；定稿；PH-43 v0.43.0 已收口，S1 红证待落）
> **基线**：`v0.43.0` / `dce8db7e`。
> **依赖**：[phase43.md](phase43.md)（`?` 的失败分支写作 `return err:`，需要 PH-43 的载荷契约；建议在 `v0.43.0` 收口后开工）。
> **规模**：编译器 280–450；夹具 150–260；文档 60–110；门禁 30–60；合计 **520–880**（±40%）。
> **评审来源**：[v043-split-plan.md](v043-split-plan.md) §4 与两份 battle 材料
> （`/Users/samxx/.trae-cn/assistant/2026-11-14/ct-43-44-battle/outputs/design.md`、`.../rebuttal.md`）。
> **版本**：收口 bump `v0.44.0`（五处 `CTC_VERSION` + 两处 README + 受影响 golden 重生成）；tag / push 需用户单独授权。
> **纪律**：完整语义一次交付，不做阉割版；不做 `Option` / `From` / 自动装箱；不改 `Result` 布局与 Drop 胶水契约。

## 0 背景与解决的问题

### 0.1 现状实测

`?` 今天只在一处被消费：三目运算符，遇到 `?` 无条件读表达式并要求 `:`。所有后缀形态都是语法错误；错误传播只能手写两行。

| 事实 | 数值 / 证据 |
| --- | --- |
| 三目解析 | `frontend/parse/Expr.h.ct:2879-2893`：无条件 `lex_next()` → `parse_expr()` → `expect(":")` |
| 后缀层 | `parse_postfix`（`Expr.h.ct:4016-4552`），循环在 `:4533` 退出；`++` / `--` 在循环外 `:4535-4550` |
| 一元集合（谁能开始表达式） | `Expr.h.ct:3301-3468`：`sizeof` / `_Alignof` 一类 T_ID、`++` / `--`、`-` / `!` / `~`、`&`、`*`、`(`；**没有一元 `+`** |
| `?` 的词法 | 单字符兜底，已是 `T_PUNCT`；注释由词法器跳过 |
| `->` 是**单个** token | `frontend/lex/Lexer.h.ct:274-280` → 字符级前瞻会把 `p?->x` 误判成三目 |
| 现成 peek 模板 | `kw_paren_ahead`（`frontend/parse/Stmt.h.ct:1339-1369`）保存 / 还原 lexer；`offsetof_ahead`（`Expr.h.ct:2745`）同法 |
| 全仓三目站点 | **28** 个，全部以表达式起始符继之；`? /*` / `? //` 站点 **0** |
| 后缀形态现状 | `x=a?;`、`f(a?)`、`f(a?,b)`、`a?+1`、`(a?)+1`、`a?-1`、`a?*b` 等 13 例**全部 rc=1**（语法错误） |
| 原型消歧后的语料平价 | 277 文件 `rc_diff=0`；12 个含三目的文件产物 **11 SAME / 0 BYTE-DIFF / 1 BOTH-FAIL**（负例 `examples/tour/16_diagnostics/sig_return`） |
| `Result<T,E>` 作返回类型 | 今天可用；`Result<int, char *>` 端到端 rc=0，输出 `1 5`（rebuttal A.8） |
| `ret_type` 形态 | `struct Result_int_char_p`（`Symbols.h.ct:522` 的 `char ret_type[160]`）；尾部 ` *` 需剥 |
| 实例表 | `StructInst.carg[2]` / `ctype[2]`（`frontend/sym/Symbols.h.ct:384-403`）；查表 `ct_inst_find`（`:1753`）；超 63 字符走 hash 截断（`:2126-2155`，名字仍是查询键） |
| `Result` 的 Drop | `lib/std/Result.h.ct:24-28`（`use Drop`）；胶水**无条件 drop 每一个 `uses_drop` 字段**（`lib/std/Option.h.ct:32-34` 的注释同口径），`Str` 的 drop 对空句柄安全（`lib/std/Str.h.ct:22-27`） |

### 0.2 能力缺口

- 手写传播要两行：`Result<int, char *> t = f(); if (t.is_err()) return err: t;`；链式调用尤其嘈杂。
- 失败分支若由用户手写 `Outer::err(t.err)`，错误类型不一致时没有确定性诊断。
- `Result<T,E>` 带 `use Drop`：任何「取走值却仍让临时量走 Drop」的展开都会 double-free；这是新语法的正确性核心，不是优化项。

## 1 目标 / 非目标

### 1.1 目标

| 编号 | 内容 |
| --- | --- |
| O1 | 后缀 `?`：`expr?` 对 `Result<T,E>` 做同 `E` 传播；成功取 `value`，失败走外层错误出口 |
| O2 | 确定性消歧：与既有三目运算符共存，`?` 后单 token 前瞻，正确处理 `->`、注释、`++` / `--` |
| O3 | 完整位置语义：非 void、void、链式、嵌套、实参位置；禁止位置给确定性硬错 |
| O4 | 临时量生命周期：取走 `value` / 拷贝 `err` 后失效化，ASAN 证明无 double-free、无 use-after-free、无泄漏；错误类型不一致有诊断 |

### 1.2 非目标

| 不做 | 理由 |
| --- | --- |
| `?` 用于 `Option` | 本相只服务错误传播；`Option` 无 err 载荷，另案 |
| `From` / 错误类型自动转换 | 无关联类型、无隐式转换；引入推断会把非法 C 推给 `cc` |
| 自动装箱 `?` 的返回值 | 超出同 `E` 传播；装箱路径另有规则 |
| 条件 / `&&` / `\|\|` 右操作数 / 三目分支里的 `?` | 展开含提前 `return`，会改变短路与条件求值语义；给硬错而不是静默接受 |
| 闭包体内的 `?` | 闭包没有自己的 `ret_type`（PH-43 §0.2 的既有缺陷），展开成 `return` 会落进 trampoline |
| 把 `Result` 改成原生 ADT / 改布局 | 破坏已发布布局与 Drop 胶水契约 |
| 前缀 `try expr` / 后缀 `expr!` | `try` 今天能当标识符；`!` 已被一元取反占用；都会引入新歧义 |

## 2 设计决定清单

| 编号 | 决定 | 为什么不用另一种 |
| --- | --- | --- |
| **D44-1** | 语法 = **后缀 `?`**；消歧 = **单 token 前瞻 + lexer 保存/还原**（套 `kw_paren_ahead` 模式） | 字符集扫描会把 `->` 当 `-` 开头、把注释里的 `/` 当非起始符；强制 `(expr)?` 不行：`(a) ? b : c` 今天就是合法三目；`try` / `!` 见 §1.2 |
| **D44-2** | 传播契约 = **同 `E`**：外层 `Result<U,E>`、操作数 `Result<T,E>`；`T` 可与 `U` 不同，`E` 按实例表 `ctype[1]` 字符串严格相等，不转换、不提升 | 冻结决定里的「同实例传播」按 `E` 参数一致解释；若要求整个实例相同（`T` 也相同），L44-2 就没有存在意义。用 `Result<int,char*>` → `Result<long,char*>` 正例锁死 |
| **D44-3** | 失败分支：非 void 写作 `return err: <Outer>::err(__ct_q.err);`；void 写作 `return err:;`；经 `defer_prepend` 走既有 `N_RET` 路径 | 复用 PH-40 的单栈 LIFO、errdefer / defer、`own` 泄漏分析；不新增清理路径 |
| **D44-4** | 临时量失效化：操作数在语句边界 hoist 成 `Result<T,E> __ct_qN`；成功侧取走 `value` 后把该字段清零，失败侧把 `err` 浅拷贝进外层后把该字段清零；临时量不得 double-drop、不得泄漏 | `Result` 的 Drop 胶水无条件 drop 每个 `uses_drop` 字段；只清零 `value` 不够，`E` 带 Drop 时失败侧同样会双释放。机制（自动 drop 注册 vs 显式释放）由实现选，但 **ASAN 契约冻结** |
| **D44-5** | void 函数：操作数只需是 `Result<_,E>`；失败即 `return err:;`，错误载荷按 PH-40 语义丢弃；`E` 不跨函数比较 | 与 PH-40 的 `return err:;` 一致；void 没有外层 Result 可承载 `E` |
| **D44-6** | 禁止位置 = 条件（`if` / `while` / `for` / `switch`）、`&&` / `\|\|` 右操作数、三目两侧、闭包体、errdefer 块内、函数体外；一律 L44-4 | 展开含提前 `return`；在短路或未求值分支里提前返回会改变语义。这是语言规则，不是实现偷懒 |
| **D44-7** | 链式与嵌套全部支持：`f()? + g()?`、`h(f()?)`、`v.set(i, f()?)`、`o.m(f()?)`；每个 `?` 操作数**恰好求值一次** | 冻结决定要求完整语义；只允许「声明初值 / 整条 return」的收缩版会让表达力退回手写两行 |
| **D44-8** | 求值顺序 = **`?` 操作数在语句边界按源码顺序求值，先于该语句内其余子表达式**；不承诺与 C 的未指定顺序一致 | C 对多数字二元运算符的操作数顺序未指定；本约定比 C 更严格且可测。禁止位置已排除短路 / 条件，因此不存在被跳过的分支 |
| **D44-9** | 操作数类型判不出是 `Result` → L44-3 **保守硬错**，不允许「判不出当成功」 | 静默发射会把非法 C 推给 `cc`，违反「禁发射坏 C」 |
| **D44-10** | 闭包体的 `?` 由 L44-4 拒绝；不修闭包 `ret_type` | 闭包缺陷按 PH-43 §0.2 记录另案；`?` 展开成 `return` 必然落进 trampoline |
| **D44-11** | 不动 `Result` 布局、Drop 胶水、三目语义、`Option`；不改 `ctc.c` / L1 / L2 | 本相只加语法、语义与局部展开 |

## 3 语法与语义

### 3.1 词法消歧（单 token 前瞻）

在 `parse_postfix` 的循环里，遇到 `?` 时：

1. 保存 lexer 状态（`pos` / `bol` / `tok` / `toknum` / `line` / `tokline` / `tokstart` / `lstart` / `toktext`），`lex_next()`；
2. 若 `?` 后的**首个 token 能开始一个表达式** → 还原状态，把 `?` 留给三目层（`break`）；
3. 否则 → 消费 `?`，建 `N_TRY` 节点，继续后缀循环（因此 `f()?.x` 可链式）。

能开始表达式的 token：`T_ID`（含 `sizeof` / `_Alignof` 一类）、`T_NUM`、`T_FNUM`、字符串 / 字符字面量、`(`、`-`、`!`、`~`、`&`、`*`、`++`、`--`。

| 形态 | 判定 | 结果 |
| --- | --- | --- |
| `x = a?;` / `f(a?)` / `f(a?, b)` / `(a?) + 1` | 后随 `;` / `)` / `,` / `)` | 后缀 |
| `a? + 1` | `+` 不是一元起始符 | 后缀（`(a) + 1`） |
| `p?->x` | `->` 是单个 token，不是起始符 | 后缀 |
| `a ? /* why */ b : c` | 注释由词法器跳过，看到 `b` | 三目 |
| `a ? b : c` / `a ? -1 : 0` / `a ? (b) : c` | 后随起始符 | 三目 |
| `a? - 1` / `a? * p` / `a? && b` / `a? ++b` / `a? --b` | 后随起始符 | 三目 → 缺 `:` 报错；需写括号 |

### 3.2 传播语义

| 外层返回类型 | 操作数要求 | 成功 | 失败 |
| --- | --- | --- | --- |
| `Result<U,E>`（非 void） | `Result<T,E>`；`E` 的 `ctype[1]` 字符串相等 | 整个 `expr?` 的类型是 `T`，取临时量的 `value` | `return err: <Outer>::err(__ct_q.err);` |
| `void` | `Result<_,E>` | 表达式类型是 `T`，值按语句上下文丢弃 | `return err:;`（触发 errdefer） |

- `T` 与 `U` 可以不同；不要求 `T == U`。
- `E` 不做转换、不做指针基类型放宽；不同 `E` → L44-2。
- 失败分支的 `Outer::err(...)` 是普通静态方法调用，发射名与用户手写一致（`Result_int_char_p_err(...)`）。
- 同一语句可含多个 `?`；每个独立展开、编号按源码顺序。

### 3.3 禁止位置

| 位置 | 判定 | 反馈 |
| --- | --- | --- |
| `if` / `while` / `for` / `switch` 的条件 | 禁止 | L44-4 |
| `&&` / `\|\|` 的右操作数 | 禁止（短路） | L44-4 |
| 三目运算符的两侧 | 禁止（未求值分支） | L44-4 |
| 闭包体 | 禁止（没有自己的 `ret_type`） | L44-4 |
| errdefer 块内 | 禁止（复用 errdefer 深度状态） | L44-4 |
| 函数体外 / 文件作用域 | 禁止（没有外层返回类型） | L44-4 |

左操作数不在禁止之列：它无条件求值，提前返回不改变跳过程序。三目的条件按「条件」处理，禁止。

### 3.4 临时量生命周期

- 操作数 hoist 成 `Result<T,E> __ct_qN`，位于语句边界、按源码顺序排列（D44-8）。
- **成功侧**：`value` 浅拷贝给表达式结果后，把临时量的 `value` 字段清零；否则 `T` 带 Drop 时临时量的 Drop 会再释放一次。
- **失败侧（非 void）**：`err` 浅拷贝进 `Outer::err(...)` 后，把临时量的 `err` 字段清零；否则 `E` 带 Drop 时同样双释放。
- **失败侧（void）**：`err` 按 PH-40 丢弃；临时量仍须处于可安全释放或已释放状态，ASAN 证明不泄漏、不双释放。
- 临时量名对用户不可见；不得进入 `own` 泄漏分析的可见名字集。
- 具体机制（是否注册进既有自动释放链、显式 `memset` 还是逐字段清零）由实现选择；**可观察契约 = ASAN 全绿**。

### 3.5 求值顺序

- 每个 `?` 操作数恰好求值一次，在语句边界按源码顺序先于其余子表达式（D44-8）。
- 这是语言约定，比 C 的「操作数顺序未指定」更严格；不含 `?` 的既有语句逐字节不变。
- 禁止位置排除了短路 / 条件，因此不会出现「不该求值却求值」的分支。

### 3.6 与 errdefer / defer / own 的衔接

失败分支走既有 `N_RET` + `defer_prepend`（`Stmt.h.ct:1976` / `:2054` 的同一入口）：errdefer 与 defer 共用单栈 LIFO，`own` 局部照常 `retire_before_return`，不新增清理路径、不改 PH-40 语义。

## 4 诊断清单（L44-n）

| 编号 | 触发 | 文案 | 位置 | 级别 |
| --- | --- | --- | --- | --- |
| **L44-1** | 非 void 函数里用 `?`，但返回类型不是 `Result`（含 `Result<...> *`） | `postfix '?' needs a function returning Result` | `?` | 硬错 |
| **L44-2** | 内层 `E` 与外层 `E` 不是同一类型 | `'?': expected error type '<E1>', got '<E2>'`（用 `carg` 源码拼写） | `?` | 硬错 |
| **L44-3** | 操作数判不出是 `Result`（含判不出类型） | `'?' needs a Result operand` | `?` | 硬错 |
| **L44-4** | 禁止位置（§3.3） | `'?' is not allowed here` | `?` | 硬错 |

errdefer 块内的 `?` 归 L44-4（复用既有 errdefer 深度状态），不新造编号；L40-6 仍只管显式控制转移。

## 5 完整性边界

| 维度 | 内容 |
| --- | --- |
| 交付后能写 | 非 void 的同 `E` 传播（`T` 可变）、void 失败传播、链式 / 嵌套 / 实参位置、多 `?` 组合 |
| 不能写 | 非 `Result` 操作数；外层非 `Result`（非 void）；`E` 不同；条件 / 短路右操作数 / 三目两侧 / 闭包体 / errdefer 块内 / 函数体外；`Option`；`From` 转换 |
| 不能写的反馈 | 全部编译期硬错（§4），无警告、无静默；不会生成任何 `?` 相关 C 残留 |
| 为什么条件 / 短路位置不做 | 展开需要把临时量与 `return` 提前到语句边界；在条件或短路右操作数里提前会让未求值的分支也执行返回，改变语义 |
| 为什么 `E` 不转换 | CT 无隐式转换、无关联类型；一旦推断就会把非法 C 推给 `cc`，与本相目标相反 |

## 6 任务切分（S 粒度）

| 切片 | 内容（一句话） | 先后 |
| --- | --- | --- |
| **S0** | 只读核查：复核 §0 行号、28 个三目站点、13 个后缀形态、`ret_type` / 实例表形态；写进卡，不产提交 | 起点 |
| **S1** | 红证：`test/ast/p44_try_syntax.sh`（消歧矩阵 ≥14 例）+ `test/ast/235_result_try/`（ok / err / 嵌套 / void）+ 负例目录 | S0 后 |
| **S2** | 解析：`q_suffix_ahead` 前瞻助手 + `parse_postfix` 后缀分支 + `N_TRY`；≤150 行、≤3 文件 | S1 后 |
| **S3** | 语义：Result 判定、同 `E` 比较、外层约束、禁止位置（L44-1..4）；≤150 行 | S2 后 |
| **S4** | 发射：临时量 + 失败分支 + 成功取值 + 失效化；≤150 行 | S3 后 |
| **S5** | 链式 / 嵌套 / 求值顺序 + 临时量 ASAN 夹具 `test/ast/p44_try_drop.sh`（`check-sanitizers.sh`） | S4 后 |
| **S6** | void 形态与 errdefer 交互（失败必须触发 errdefer） | S4 后 |
| **S7** | 样例：`examples/46_result_try/`（`//@ct-requires: ct-ast`）接入 `test/run.sh` | S5 / S6 后 |
| **S8** | 文档：`language-spec.md` 删掉 `?` 的「不做」条目 + 新增节（编号按当时顺延）、`tutorial.md`、`README.md` / `README.en.md`、`glossary.md` | S5 / S6 后 |
| **S9** | 门禁与收口：探针注册 `check-ast.sh`、`check-warnings` 零告警、`check-docs` 绿、`check-all` 11 道全绿、bump `0.44.0` | 最后 |

依赖关系：S1 → S2 → S3 → S4 → S5、S6 → S7、S8 → S9。每片 ≤150 行、≤3 文件，仓库随时可构建。

## 7 验收

### 7.1 退出判据

| ID | 断言 | 命令 / 阈值 | 夹具 |
| --- | --- | --- | --- |
| **E44-1** | 消歧矩阵 ≥14 例：既有 28 个三目 0 误判；6 个后缀形态可用；6 个歧义形态按规则报错 | `ok p44/syntax`，≥14/14；`rc_diff=0` | `test/ast/p44_try_syntax.sh` |
| **E44-2** | 传播：同 `E` 不同 `T`、void、嵌套、链式、实参位置全部 rc=0 且运行结果正确 | `ok p44/propagate`，≥6/6 | `test/ast/235_result_try/` |
| **E44-3** | L44-1 / L44-2 / L44-3 文案与位置精确（L44-2 用源码拼写） | `ok p44/errors`，≥6/6 | `test/ast/errors/p44_*` |
| **E44-4** | 六类禁止位置全部 L44-4，无静默接受 | `ok p44/positions`，6/6 | `test/ast/errors/p44_pos_*` |
| **E44-5** | 临时量：`Result<Str, char *>`、`Result<Str, Str>` 成功 / 失败两向 ASAN 无 double-free、无 use-after-free、无泄漏 | `bash selfhost/check-sanitizers.sh` rc=0 | `test/ast/p44_try_drop.sh` |
| **E44-6** | 求值顺序：含副作用夹具证明每个 `?` 操作数恰好求值一次、按源码顺序先于其余子表达式 | `ok p44/order`，2/2 | `test/ast/p44_order/` |
| **E44-7** | 文档与样例：spec / tutorial / README / glossary 同步；`examples/46_result_try` 进 `test/run.sh` | `check-docs` rc=0；样例 ok | `docs/**`、`examples/46_*` |
| **E44-8** | 11 道硬门禁全绿；版本 `0.44.0` 五处一致 + 两处 README + golden 重生成 | `bash selfhost/check-all.sh` rc=0 | 全量 |

### 7.2 正向夹具

- 非 void、同 `E`、`T` 不同：`Result<int, char *> g()` 里 `long v = f()?;`（`f` 返回 `Result<int, char *>`）。
- void：`void g()` 里 `f()?;`，失败触发 errdefer。
- 嵌套与链式：`f()? + g()?`、`h(f()?)`、`v.set(i, f()?)`、`o.m(f()?)`。
- 成功取值：`Result<Str, char *>` 取 `value` 后仍可安全使用，临时量不重复释放。
- 失败构造：外层 `Result<long, char *>` 从内层 `Result<int, char *>` 的失败传播。

### 7.3 负例夹具

- 外层 `int`（非 `Result`）里用 `?` → L44-1。
- 外层 `Result<long, int>` 里传播 `Result<int, char *>` → L44-2。
- 操作数是 `int` / 未知类型 → L44-3。
- 条件、`&&` 右操作数、`||` 右操作数、三目两侧、闭包体、errdefer 块内、函数体外 → L44-4。
- `Option<int>` 操作数 → L44-3（本相不支持 `Option`）。

### 7.4 门禁接线

| 门禁 | 接线 |
| --- | --- |
| `test/run.sh` | `examples/46_result_try`（`//@ct-requires: ct-ast`） |
| `check-ast.sh` | `test/ast/p44_try_syntax.sh` 等探针 + `test/ast/235_result_try/` 目录 |
| `check-sanitizers.sh` | `test/ast/p44_try_drop.sh`（ASAN，PH-44 必跑；该门禁不进 11 道硬门禁，见 D17-6，但本相验收必跑） |
| `check-warnings.sh` | 新增夹具零告警 |
| `check-docs` | spec / tutorial / README / glossary 同步 |
| `check-all.sh` | 收口 11 道全绿（不新增门禁条数） |

### 7.5 可量化平价

- **277 文件 rc 平价**：`test/ast/*/prog.ct` + `examples/*/*.ct`，原型 `rc_diff=0`。
- **28 个既有三目 0 误判**：字符直方图显示全部以表达式起始符继之；含三目的 12 个文件产物 11 SAME / 0 BYTE-DIFF / 1 BOTH-FAIL（负例）。
- **自举 fixpoint**：编译器自身源码里的三目必须继续被解析为三目；`check-ast.sh` 的 fixpoint 段全绿。
- **生成 C**：不含 `?` 的语句逐字节不变；含 `?` 的语句只新增临时量与失败分支。

## 8 完成定义（DoD）

| 面 | 交付 | 缺一不算完成 |
| --- | --- | --- |
| 实现 | 后缀识别 + 语义 + 发射 + 临时量失效化；无 TODO、无「暂不支持」分支 | ✓ |
| 诊断 | L44-1..4 全部负例、精确文案与位置；禁止位置无静默 | ✓ |
| 文档 | spec 新节 + 删除「不做」条目、tutorial、README / README.en、glossary；`check-docs` 绿 | ✓ |
| 门禁 | 夹具进入 `test/run.sh` / `check-ast.sh`；ASAN 全绿；`check-all` 11 道全绿；红证按 T-7 提交 | ✓ |

## 9 风险与不做项

| 编号 | 风险 / 不做项 | 触发信号 / 处置 |
| --- | --- | --- |
| R44-1 | 消歧误伤既有三目 | token 前瞻而非字符扫描；E44-1 覆盖 28 个站点 + 自举 fixpoint |
| R44-2 | `E` 比较因实例名 hash 截断而漂移 | 名字仍是 `ct_inst_find` 的查询键（`Symbols.h.ct:2126-2155`）；只影响可读性，不影响相等性 |
| R44-3 | 操作数类型判不出（数组 / 闭包 / 函数指针 / `sizeof`） | L44-3 保守硬错；写进 spec 的边界，不放行 |
| R44-4 | 临时量双释放 / 泄漏 | E44-5 的 ASAN 是硬验收；失败即阻塞收口 |
| R44-5 | 求值顺序与用户直觉不同 | D44-8 写进规范与教程；副作用夹具锁死 |
| R44-6 | 禁止位置漏一个上下文标志 | E44-4 六类逐条夹具；漏报视为阻塞缺陷 |
| R44-7 | 闭包路径：`?` 禁止，但闭包 `return` 的既有缺陷仍在（PH-43 §0.2） | L44-4 拒绝闭包体；不借机修闭包 `ret_type` |
| R44-8 | 自举：编译器源码含三目，新前瞻若误判会让 `check-ast` fixpoint 红 | S2 后立刻跑自举；红则回退前瞻规则，不改判据 |
| R44-9 | 范围膨胀到 `Option` / `From` / 自动装箱 / ADT | §1.2 明确不做；任何扩展停下来报用户 |
