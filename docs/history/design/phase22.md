# Phase 22 · `loop` 循环语法糖

> 中文 · [English](#english)
>
> **状态：完成**（`v0.22.0`；2026-11-08 实现 S0–S7，S1/S2/S3/S4 各自独立提交）。语义口径沿用 2026-11-07 的定稿；
> 本轮按 HEAD 实测修正 4 处事实错误、补齐 S0–S7 切片、探针编号与诊断契约；
> 落地时又按代码现实修正 3 处：`loop_depth` 挂 `struct Stmt`（不是 `Parser`）、计数走 `emit_expr`
> （`emit_inline` 只吃语句形状节点）、`check-warnings.sh` 增加 `loop_count_type` 唯一固定例外。
> **版本口径：Phase 22 ↔ `v0.22.x`，收口 bump 到 `v0.22.0`。** 本文不写「当前版本」快照
> （DOC-63：钉死的版本号会在下一次 bump 后过期）。
> 前置：Phase 21 已收口；本相与 Phase 20 / 21 **无语义依赖**，仅共用 parser / emitter / diag 文件。
> 关联：[phase21.md](phase21.md)、[phase23.md](phase23.md)、[roadmap.md](../../roadmap.md)、
> [language-spec.md](../../language-spec.md)。
> 本相只新增一条语句级语法糖，**不改动现有语义、不新增运行时、不引入抽象类型**。

---

## 0. 一页结论（本轮细化）

| # | 判断 | 结论 |
| --- | --- | --- |
| 1 | 展开形态 `for (int i = 0, __ct_loop_n_K = (N); i < __ct_loop_n_K; i++)` 能否保证计数只求值一次 | **能**，且**不依赖** C 对同一声明中多个声明符初始化次序的保证：`i = 0` 无副作用，唯一有副作用的初始化器是计数；`for` 的 init 子句按 C99 §6.8.5.3 在首次条件判断前执行一次。禁止改成 `i < (N)` |
| 2 | `loop` 的识别点 | 语句位置、当前 token 为 `loop`、且下一个 token 是 `(`。分支必须放在 `label_ahead()` / `is_decl_start()` **之前**，且**不要**把 `loop` 加进 `kw[]` |
| 3 | 隐式 `i` 要不要进符号表 | **要**。闭包捕获、名字解析、遮蔽判定都走 `Symbols`；只登记 `int i`，不生成 `N_DECL`，由发射器在 `for` 头部打印 |
| 4 | 嵌套遮蔽的严重度 | 编译 warning（新 `Warn.kind = 7`）、`ct check` error；只判「内层 `loop` 遮蔽外层 `loop` 的 `i`」 |
| 5 | 与闭包的交互 | **不新增任何检查**。`closure_walk*` 已按 `a/b/c/d` 泛化递归，`N_LOOP` 的 body 在其覆盖内；写 `i` / `&i` / 逃逸分别命中 Phase 21 既有 E5 / E1–E7 |
| 6 | 与 Phase 23 的衔接 | 本相只冻结 **AST 布局**（`a` = 计数，`b` **恒为 -1** 作为「单界」哨兵）与临时量命名族；**不冻结**双界的展开形态与 ABI，留给 23 |
| 7 | 文档里 4 处需修正 | 旧 §3.5 的「既有语句路径重锚 `#line`」**不成立**；旧 §3.1 的「每函数内单调」**不成立**（`ntmp` 为进程级）；H22-1 **已由代码现状结案**；`Warn.kind = 7` **必须新增文本与 JSON 两个分支**，否则会落进 `potential_leak` 默认分支 |

### 0.1 本轮实测勘误（2026-11-08）

| 旧表述 | 实测 | 证据 | 处理 |
| --- | --- | --- | --- |
| `--line` 下「由既有语句路径重锚 `#line <loop 所在行>`」 | 发射器**没有逐语句** `#line`；只有单元级 `#line 1 "<path>"` 与 raw / 闭包产物的个别重锚 | `Emitter.h.ct:1092`（单元级）、`Emitter.h.ct:872`（raw）、`Emitter.h.ct:931/952/990`（闭包） | 改为「不新增逐语句锚点」，见 §3.7 |
| `__ct_loop_n_K` 的 `K`「每函数内单调递增」 | `ntmp` 挂在文件级单例 `g_emit` 上，**从不重置**，是进程级单调（跨单元也不重号） | `Emitter.h.ct:197`（字段）、`Emitter.h.ct:2238`（既有自增）、`Emitter.h.ct:3564`（单例） | 改为「进程级单调」，见 §3.9 |
| H22-1「未使用的隐式 `i` 可能触发告警」 | 编译器**没有**未使用局部变量的诊断；`unused` 只出现在生成物的 `__attribute__((unused))` 与 map 使用计数 | 全仓 `selfhost/ct-ast/**` 无「never read / never used」类检查 | **结案**：CT 侧零告警；C 侧 `-Wall -Wextra` 也不告警（`i` 参与条件与自增），见 §6.4 |
| `Warn.kind = 7` 只需 `record_*` 一处 | `Diag.emit` 对 kind 1–6 有专门文本与 JSON 分支，其余**一律落进 `potential_leak` 默认分支** | `Diag.h.ct:269-344`（JSON 链）、`Diag.h.ct:358-381`（文本链） | S3 必须同时加文本分支与 JSON 分支，见 §4.3 |

---

## 1. 定位

`loop` 是 `for` 的一个**零成本简写**：当循环只需要「从 0 数到 n」时，省掉
`int i = 0; i < n; i++` 这三段样板，同时保证计数表达式只求值一次。

它服务的场景是包与示例里最常见的计数循环：

```ct
loop(3) {
    printf("%d\n", i);
}
```

不是新语义，不是新运行时，不是回调或迭代器。判断标准只有一条：
**展开后的 C 与手写原生 `for` 等价，且更短。**

明确不属于本相：

- 自定义循环变量名（`loop(n, name)`）——需要命名就用原生 `for`；
- 迭代器 / 范围 / 集合遍历（`for x in xs`）——无泛型，另议；
- `loop` 作为表达式或宏——它只是语句。

以下场景一律回去写原生 `for`（`loop` 只覆盖「计数从 0 递增到上界、步长 1」）：

| 场景 | 为什么不用 `loop` |
| --- | --- |
| 倒序计数 | `loop` 只有自增，没有步长 / 方向 |
| 步长 ≠ 1 | 同上 |
| 遍历链表 / 指针链 | 不是计数循环；用原生 `for` 或 `while` |
| 循环结束后还要读 `i` | `i` 的作用域止于 loop 语句，循环外不可见（`undeclared identifier 'i'`） |
| 需要跳出全部嵌套层 | `break` 只跳内层；用标志或 `goto`，写原生 `for` 更直白 |

判据一句话：**控制流一旦超过「`i` 从 0 增到上界、步长 1」，`loop` 就不再是更短的写法。**

---

## 2. 语法形态

```text
loop-stmt  :=  "loop" "(" expr ")" block
```

- 计数是一个 `expr`，两侧括号必需，body 必须是块 `{ … }`。
- 计数按**逗号运算符已禁用**的完整表达式解析（与 `for` 条件同一策略），因此
  `loop(a, b)` 会在 `,` 处报 L22-3，而不是被当作逗号表达式吞掉。
- body 内隐式声明 `int i`，从 0 起，作用域为整个 loop 语句（条件、body、自增）。
- `loop(0)`、负数均为零次迭代；不报错。
- 不做 `loop(n, name)`；不省略括号；不允许单语句 body。

### 2.1 上下文相关关键字

`loop` **不是保留字**，按上下文识别：

| 位置 | 判定 |
| --- | --- |
| 语句位置，且下一个 token 是 `(` | 按 `loop` 语句解析 |
| 其余任何位置（`loop;`、表达式、`goto` 目标、字段 / 方法名、字符串、注释） | 仍是普通标识符 |

识别沿用仓库既有的「无 peek 则保存并回退」写法：
`loop_ahead()` 在当前 token 是 `loop` 时保存词法器状态、读下一个 token、判断是否为 `(`、
再完整回退。参考 `label_ahead()` 的现成写法
（[Stmt.h.ct](../../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1507-L1536)）。

**分派位置（必须照做）**：`parse_stmt` 里 `if (self->loop_ahead()) return self->parse_loop();`
要放在 `label_ahead()` 与 `is_decl_start()` **之前**
（[Stmt.h.ct](../../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1130-L1138)）。
原因：`loop` 不在 `kw[]` 表里（[Stmt.h.ct](../../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L601-L606)），
若落到 `is_decl_start()` 的未知类型兜底路径，会被当成声明报错，而不是进入表达式语句。
**不要**把 `loop` 加进 `kw[]`：那会让 `is_decl_start()` 对它返回真，掩盖 `loop_ahead()` 的分派。

**已知代价**：语句位置上，用户自定义的 `loop(...)` 函数调用会被当成关键字，随后因缺 block 报错。
这是上下文关键字的固有取舍，用下面的语料扫描结果作为接受依据。

### 2.2 语料扫描（2026-11-07；S0 必须重跑）

扫描范围：本仓库 `**/*.ct`、`**/*.c`、`**/*.h`（含 `examples/`、`bindings/`、`test/`，也覆盖
`test/modules/**/*.m.ct` 映射单元与 `*.h.ct` / `*.shim.h`），以及同级 `ct-pkg/**` 的包源码；
模式 `\bloop\b` 与 `\bloop\s*\(`。

| 结果 | 位置 | 是否与上下文规则冲突 |
| --- | --- | --- |
| 0 处 `loop(` 调用 | — | 否 |
| 1 处标签 `loop:` + 1 处 `goto loop;` | `test/ast/32_goto/prog.ct:32,36` | **否**（标签后是 `:`；`goto` 后是表达式位置） |
| 其余全部为注释 / 文档散文 | 如 `docs/architecture.md` 的 "main loop" | 否 |
| `ct-pkg` 内 3 处 | `net-posix` 的注释 | 否 |
| `*.m.ct` 映射单元 0 处 | — | 否（映射体的 `map trait … for type …` 里没有 `loop` 标识符） |

结论：**按上述上下文规则，现有语料零冲突、零 golden 预期变化。**
（S4 之后语料里新增的 `loop(` 全部来自本相自己的探针目录，不属于「既有语料」。）
S0 重跑；若届时新增了 `loop(...)` 语句调用，先改调用方或退回命名。

---

## 3. 语义规则（逐条给定论）

### 3.1 展开形式与展开点

```ct
loop(N) { BODY }
```

**唯一允许的展开**（`K` 来自 `Emitter.ntmp`）：

```c
for (int i = 0, __ct_loop_n_K = (N); i < __ct_loop_n_K; i++) { BODY }
```

- **展开点**：发射器的 `emit_node` 新增 `N_LOOP` 分支，紧挨 `N_FOR` 分支
  （[Emitter.h.ct](../../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L2521-L2539)）。
  解析期**不**降级成 `N_FOR`：`i` 需要在解析期进入符号表（闭包捕获、名字解析），
  而计数临时量与 `#line` 属于发射器。
- 展开只有一条语句，不引入辅助函数、结构体或回调。

### 3.2 计数只求值一次（含副作用）

- `N` 在 `for` 的 init 子句求值一次并存入 `__ct_loop_n_K`；body 修改 `N` 依赖的变量**不影响**迭代次数。
- C99 §6.8.5.3：`for` 的 init 子句在首次条件判断前执行一次；`continue` 回到自增、**不重新求值**。
- C99 §6.7.8 不保证同一声明里多个声明符的初始化次序；本展开**不依赖**该次序——
  唯一有副作用的初始化器是 `__ct_loop_n_K = (N)`，`i = 0` 无副作用，故无论编译器先算哪一个，
  可观察行为一致。因此不需要额外的逗号运算符（那是 Phase 23 双界才需要的）。
- **明确禁止**展开成 `for (int i = 0; i < (N); i++)`（每轮重算）。S4 用生成物断言钉住。

### 3.3 计数 `N` 的类型与边界

| 项 | 定论 |
| --- | --- |
| 接受的类型 | 所有整型：`char` / `short` / `int` / `long` / `long long`、`signed` / `unsigned` 各型、`_Bool`、`enum`、以及解析后落到这些类型的别名（含 `size_t`） |
| 判定方式 | `Expr.expr_type` 取类型串（[TypeCheck.h.ct](../../../selfhost/ct-ast/frontend/type/TypeCheck.h.ct#L218)）；别名先 `expand_type_alias`；**未知（返回 -1）不报**（宁漏不误报） |
| 非整数 | 静态可判定为 `float` / `double` / 指针 / 结构体 → L22-5；仍照常编译，按 C 赋值规则转成 `int` |
| 0 / 负数 | 条件 `0 < K` 为假，**零次迭代**，不报错、不告警 |
| 无符号 / `long` 越界 | 存入 `int` 是 C 的赋值转换：整型越界为**实现定义**（C99 §6.3.1.3p3），浮点越界未定义。本相只承诺 `int` 范围内的计数；越界不承诺，文档写明 |
| 已知漏洞 | 类型无法静态确定、运行期却是浮点的计数，L22-5 不报（与 Phase 21 E8 同类：诚实标注，不假装拦住） |

### 3.4 隐式 `i` 的语义

- 类型固定 `int`，每次执行到 loop 语句时从 0 开始（不是整个函数一次）。
- 作用域 = loop 语句本身（条件、body、自增都在内）；**循环之后不可见**，读 `i` 走既有
  `undeclared identifier 'i'`，不新增文案。
- **可写**：`i = 3`、`i++`、`i += 1` 都合法；写后影响下一次条件判断，与传统
  `for (int i = 0; …; i++)` 完全一致。
- **可取地址**：`&i` 合法（普通 `int` 局部）；指针活过循环是原生 `for` 就有的悬垂风险，本相不新增诊断。
- 不参与 `own` / AutoDrop / borrow：`int` 无 Drop，泄漏与借用分析不变。
- body 里显式写 `int i` 会遮蔽 loop 的 `i`（C 允许，原生 `for` 同形），**不新增诊断**；
  自增仍作用于外层 loop 的 `i`（自增在 body 块之外）。

### 3.5 与原生 `for` 的等价性判据

| 形态 | 定论 |
| --- | --- |
| `break` | 跳出本条 `for`，与原生一致 |
| `continue` | 跳到自增段，与原生一致（计数不重算） |
| `return` | 从所在函数返回，与原生一致 |
| `goto` 出循环 | 合法，与原生一致 |
| `goto` 进 body | C 允许；会跳过 `i` 的初始化，`i` 不确定——与原生 `for` 相同，不新增诊断 |
| body 内写 `i` / `&i` | 合法，语义见 §3.4 |
| body 内再声明 `int i` | 合法（遮蔽），不诊断 |
| 循环后读 `i` | 不可见，既有未声明错误 |

### 3.6 嵌套遮蔽（定稿）

**语义上允许遮蔽，`ct check` 判为错误，编译模式只告警。**

判定范围**只有一种**：解析内层 `loop` 时，外层正处于 `loop` 的 body 内（即 `loop_depth > 0`）。
函数里已有 `int i`、或外层是原生 `for (int i = …)`，都**不报**——那与原生 `for` 行为一致，
不属于本相要管的「隐式名字撞隐式名字」。

实现：`struct Stmt` 增加 `int loop_depth`（解析态由 `Stmt` 持有，`Parser` 不增字段）；进入
`parse_loop` 的 body 前自增、退出后自减；遮蔽判定发生在自增**之前**。

诊断只针对内层 loop 的 `loop` 关键字位置（行、列），文案与通道见 §4。

理由：

1. `loop` 的承诺是「与原生 `for` 等价」；原生 `for` 允许内层块重新声明 `i`。
2. 隐式变量无法改名（本相不做 `loop(n, name)`），嵌套时遮蔽不可避免；
   完全禁止会让「嵌套 `loop`」不可用。
3. 仓库已有成熟的严重度策略（19.1–19.4）：编译 warning、`ct check` 升 error；遮蔽正属于
   「语义明确但可疑」，沿用同一策略，不新造规则。

### 3.7 生成物可读性与 `#line`（勘误）

- 只展开为一行 `for`，不产生额外抽象层；生成物中不出现 `loop` 语句（临时量名含 `loop` 字样，
  但那是标识符，不是关键字）。
- **不新增逐语句 `#line`**。现状是单元级 `#line 1 "<path>"`（`Emitter.h.ct:1092`），
  所有语句都依赖它；只给 `loop` 单点加锚会造成「只有它准、其它都不准」的不一致，
  且锚点之后的生成行号整体偏移。已知限制：生成行号与源行号不保证逐行对齐，
  与其它语句相同；若将来引入全局逐语句锚点，`loop` 自动继承。
- 旧 §3.5 的「由既有语句路径重锚」是事实错误，本处更正。

### 3.8 与 Phase 23（`loop(a..b)`）的边界

本相**只冻结两件事**：

1. **AST 布局**：`N_LOOP` 的 `a` = 计数表达式，`b` = **恒为 -1**（单界哨兵），`d` = body。
   Phase 23 把 `a` 改作起点、`b` 改作上界 —— 已按此落地。
2. **临时量命名族**：`__ct_loop_n_<K>` 复用 `ntmp`。Phase 23 的 as-built 是：`__ct_loop_n_<K>`
   继续用作计数 / 下界，上界另加同族的 `__ct_loop_hi_<K>`，两者共用同一个 `K`、只消耗一个
   `ntmp`；**没有**引入 `__ct_loop_a_<K>`。

Phase 22 的 S2 当时为 `b != -1` 留了一条内部错误断言（`a two-bound count belongs to Phase 23`）；
Phase 23 的 S2 把该分支换成真正的双界实现，断言随之删除。单界分支的生成物保持 Phase 22 原样。

**当时不冻结**双界的展开形态、求值顺序实现（逗号运算符）与 `loop(0..n)` 的生成物字节。
as-built：Phase 23 用逗号运算符定序（`i` 的单个初始化器），并做到了 `loop(0..n)` 与
`loop(n)` 的**逐字节**相等。

### 3.9 命名与容量

- 临时量：`__ct_loop_n_<K>`，`K = self->ntmp++`。`ntmp` 是文件级单例 `g_emit` 上的
  **进程级单调计数器，从不重置**，与 `__ct_ret%d` / `__ct_tmp%d` 共用，故跨函数、跨单元不重号。
- `__ct_` 前缀已由 `Symbols::reserved_name` 拒绝用户声明
  （[Symbols.h.ct](../../../selfhost/ct-ast/frontend/sym/Symbols.h.ct#L401-L402)），无需新增检查。
- 不新增全局表 / 容量常量；隐式 `i` 只占 1 个 `Var` 槽（`MAX_VARS 4096`）。
- 生成物不登记进 `Symbols.Structs`，不占 `MAX_STRUCTS`。

---

## 4. 诊断（精确文案、位置、通道）

### 4.1 语法错误（`ct_sem_error`）

| 编号 | 触发 | 精确文案 | 位置 |
| --- | --- | --- | --- |
| L22-1 | `loop()` | `loop needs a count expression` | `)` token 的行 / 列 |
| L22-2 | `)` 之后不是 `{` | `loop body must be a block` | `)` 之后当前 token 的行 / 列 |
| L22-3 | 计数后出现 `,` | `loop takes exactly one count; use a native for to name the counter` | `,` token 的行 / 列 |

- 三条都走 `ct_sem_error(line, col, msg, path)` → `path:line:col: error: msg` 到 stderr，
  `nsem++`，计入 `MAX_ERRORS 20`，退出码 1；`ct check` 下同形（本来就是 error）。
- **不产生部分 AST**：任一语法错误立即返回 -1，不发射、不写输出。
- 缺 `)` / 缺 `{` 之外的通用符号错误复用 `expect()` 的既有文案 `unexpected token`
  （`ParseSupport.h.ct:187-192`），不新增 loop 专属文案。
- `loop(` 之后缺表达式与 `loop()` 同一条 L22-1。

### 4.2 遮蔽告警（`Warn.kind = 7`）

| 项 | 定论 |
| --- | --- |
| 触发 | 内层 `loop` 出现在外层 `loop` 的 body 内（`loop_depth > 0`） |
| 文案 | `loop shadows the outer 'i'; use a native for to name the inner counter` |
| 位置 | 内层 `loop` 关键字的行、列（`col` 存下来，但**编译模式不打印**，见下） |
| 通道 | 新的 `Warn` 记录（`kind = 7`），不走 `ct_sem_error`、不走 `ct_sem_note` |
| 编译 / build | stderr 文本：`<file>:<line>: warning: <文案>`，退出码 0 |
| `ct check` | `<file>:<line>:<col>: error: <文案>`，退出码 1（`nwarn() > 0`） |
| `--diagnostics=json` | `{"warnings":[{"type":"loop_shadow","file":…,"line":…,"message":…}]}`；`severity` 与 `col` **只在 strict** 出现 |

### 4.3 计数类型告警（复用 `Warn.kind = 5`）

| 项 | 定论 |
| --- | --- |
| 触发 | 计数类型静态可确定为非整数（`float` / `double` / 指针 / 结构体 / union） |
| 文案（`msg` 字段） | `count must be an integer (got 'float'); the value is converted to int`（`'float'` 处填实际类型串） |
| 渲染后的整行 | 编译：`<file>:<line>: warning: type mismatch: 'loop' <msg>`；`ct check`：`<file>:<line>:<col>: error: type mismatch: 'loop' <msg>` |
| 通道 | 既有 `ct_type_warn(line, col, "loop", msg, path)`（kind 5，`Diag.h.ct:447-451`） |
| 不报的情况 | `expr_type` 返回 -1（未知类型）；整型 / 枚举 / `_Bool` / 别名解析后为整型 |
| 生成物 | 不变；只告警，不改变展开 |

### 4.4 通道与契约影响

- **`ct_sem_note` 在本相不使用**。Phase 21 的 `note:` 通道保持不变，不新增 `note:` 行。
- 新增 `Warn.kind = 7` 要求 `Diag.emit` 同时加两个分支，否则会落到默认的
  `potential_leak` 形状（实测 `Diag.h.ct:336-343`、`378-380`）：
  - 文本：`else if (w->kind == 7) fprintf(tf, "%s %s: %s\n", loc, sev, w->msg);`
  - JSON：`{"type":"loop_shadow","file":…,"line":…[, "col":…][, "severity":"error"],"message":…}`
- 既有 kind 0–6 的文本、JSON 形状、`MAX_WARNINGS` 行为**不变**。
- `ct check` 的升级机制不改：`Driver.h.ct:101-104` 置 strict，
  `Diag.h.ct:257` 选 `error` 前缀，`Driver.h.ct:334-337` 以 `nwarn() > 0` 返回 1。
- 诊断只指向源位置，不出现 `__ct_loop_*`。

---

## 5. 切片 S0–S7（实现侧直接照此开工）

> 约定：每个切片一个提交；只动列出的文件；每片结束跑该片「完成判据」。
> 依赖顺序：`S0 → S1 → {S2 ∥ S3} → S4 → S5 → S6 → S7`。

| 切片 | 文件 | 改什么 | 完成判据 | 对应测试 |
| --- | --- | --- | --- | --- |
| **S0 基线** | 无代码 | 重跑 §2.2 语料扫描；确认 `N_LOOP = 60` 未被占用；记录 `bash selfhost/check-all.sh` 与 `git diff --stat test/cases` 的基线；确认 `test/ast` 现有最大编号 91 | 扫描 0 处 `loop(` 语句调用（或先改调用方）；基线全绿；编号 92 起可用 | 无（记录进本文 §2.2） |
| **S1 解析 / AST / 作用域** | `frontend/parse/Stmt.h.ct` | `#define N_LOOP 60`；`struct Stmt` 增 `int loop_depth`；`StmtOps` 声明 `int loop_ahead(void); int parse_loop(void);`；`parse_stmt` 在 `label_ahead()` 前分派；`parse_loop`：`expect("(")` → 空则 L22-1 → 解析计数（禁逗号）→ `,` 则 L22-3 → `expect(")")` → 非 `{` 则 L22-2 → `push_scope` → `declare_var("i", "int")` → 遮蔽判定（`loop_depth > 0`）→ `loop_depth++` → `parse_block` → 回退 | 92/94/95/96/97/100/101 编译并运行通过；`log:`/`loop:` 标签与表达式位置的 `loop` 行为不变；**不改** `Parser` / `Expr` / `Memory`（body 走 `parse_block`，闭包走泛化递归） | 92–101 的编译面；`test/ast/32_goto` 逐字节不变 |
| **S2 发射** | `backend/emit/Emitter.h.ct` | `#define N_LOOP 60`；`emit_node` 增 `N_LOOP` 分支：`for (int i = 0, __ct_loop_n_%d = (` + `emit_expr(a)` + `); i < __ct_loop_n_%d; i++) ` + `emit_node(d)`，`K = self->ntmp++`；`b != -1` 视为内部错误（Phase 23 的 S2 已把它换成双界分支并删除该断言）。计数是裸表达式节点，必须走 `emit_expr`（`emit_inline` 只接受语句形状节点） | 生成物恰为一行 `for (int i = 0, __ct_loop_n_K = (N); i < K; i++) {…}`；92/93/94/95/96/97/101 输出与等价原生 `for` 逐字节一致；既有 golden 0 变化 | 92–97、101；生成物 grep 断言（§6.3） |
| **S3 诊断** | `tool/diag/Diag.h.ct`、`frontend/parse/Stmt.h.ct` | `record_loop_warn` + `pub ct_loop_warn(line, col, msg, path)`（kind 7）；`emit` 的文本分支与 JSON 分支；`parse_loop` 调 `ct_loop_warn`；L22-5 调 `ct_type_warn(..., "loop", ...)`；三条语法错误调 `ct_sem_error` | 编译模式：97 出 1 条 `warning:`、退出 0；`ct check`：97 出 `error:` 带列、退出 1；float 计数同形；JSON 里 `type:"loop_shadow"`、`severity` 仅 strict；kind 0–6 输出不变 | 97、`loop_count_type`；errors 三条语法负例 |
| **S4 测试** | `test/ast/**`、`selfhost/check-ast.sh`、`selfhost/check-warnings.sh` | 新增 92–101 正例目录（`prog.ct` + `prog.expected.out`）、`loop_count_type`、`loop_own_drop`；新增 4 个 `errors/*.ct`；`check-ast.sh` 增加：三条语法错误的钉文案、闭包逃逸文案、97 与 float 计数的双模式断言、生成物 `for (int i = 0, __ct_loop_n_` 且不含 `i < (` 的形态断言；`check-warnings.sh` 允许且仅允许 `loop_count_type.err` 一条 `type mismatch` 记录 | 全部新探针绿；既有探针零变化（golden 由 L0-seed 段与 S0 基线记录覆盖，ct-ast 自身格式与 L0 golden 本就不同，不做逐字节比对）；`bash selfhost/check-ast.sh`、`bash selfhost/check-warnings.sh` 均绿 | 见 §6 |
| **S5 文档** | `docs/language-spec.md`、`docs/tutorial.md`、（必要时）`docs/glossary.md` | 在 `for` 语句之后新增 `loop` 小节：形态、展开、计数求值一次、`i` 语义、遮蔽策略、边界；中英对称；教程给一个可运行例子 | `python3 test/docs/check-docs.py` OK；中英小节一一对应；链接有效 | check-docs |
| **S6 自举与门禁** | 无代码（除非门禁红） | 跑 `bash selfhost/check-all.sh`（11 道）与 fixpoint；确认编译器源码仍不使用 `loop`（自举纪律，`v0.22.0` tag 前） | 11 道硬门禁 + fixpoint 全绿；生成物 `-Wall -Wextra` 零告警 | check-all / fixpoint / check-warnings |
| **S7 收口** | `CTC_VERSION` 五处、`test/cases` 版本 token、`docs/roadmap.md`、`README.md` / `docs/README.md` 的版本行 | bump `v0.22.0`；25 组 baseline 仅版本 token 变化；roadmap Phase 22 行改为已完成并写清 S0–S7 | 五处一致；golden 仅 token 变化；roadmap 与本文状态一致；tag 由用户确认后打 | 全门禁 |

**切片边界说明**

- S1 不写发射、S2 不写诊断、S3 不改 AST 形状；任何跨片改动视为切片失败。
- S1 必须验证「不改 `Expr` / `Memory`」：`closure_walk` / `closure_walk_mutate` 已按
  `a/b/c/d` 泛化递归（[Expr.h.ct](../../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L555-L584)），
  `N_LOOP` 的 body 天然在覆盖内；body 由 `parse_block` 解析，AutoDrop / `own` 作用域不变。
- S2 的 `b != -1` 断言是给 Phase 23 留的边界，不是本相功能；它在 Phase 23 的 S2 已随双界分支删除。

---

## 6. 测试与验收

### 6.1 正例探针（`test/ast/92…101`，编号接现有 91）

| 编号 | 用例要点 | 判据 |
| --- | --- | --- |
| 92 `loop_basic` | `loop(3) { printf("%d\n", i); }` | 输出 `0 1 2` |
| 93 `loop_count_once` | 计数是带副作用的调用 `next()`；`next` 自增计数 | 迭代 3 次，`next` 只调用 1 次 |
| 94 `loop_zero_negative` | `loop(0)`、`loop(-2)` | 0 次迭代，退出码 0，无诊断 |
| 95 `loop_write_i` | body 内 `i = i + 1` / `i++` | 与等价原生 `for` 的打印序列逐项一致 |
| 96 `loop_break_continue` | `break` / `continue` / `return` / `goto` 出循环 | 与等价原生 `for` 逐项一致 |
| 97 `loop_nested_shadow` | `loop(2) { … loop(2) { … i … } }` | 4 轮；编译 1 条 L22-4 warning；`ct check` 1 条 error |
| 98 `loop_closure_capture_i` | 每轮创建闭包捕获 `i` 并立即调用 | 输出按迭代快照（0/1/2），证明按值捕获 |
| 99 `loop_in_closure` | 闭包体内含 `loop(n)`，`n` 为捕获变量 | 输出正确；证明 `N_LOOP` 在闭包遍历覆盖内 |
| 100 `loop_contextual_label` | 同文件含 `loop:` 标签、`goto loop;`、表达式位置的 `loop` 标识符、以及真正的 `loop(2)` | 编译运行正常；标签 / 标识符行为不变 |
| 101 `loop_two_counters` | 一个函数内两个顺序 loop + 一个嵌套 loop | 临时量不重号（生成物含两个不同 `K`），输出正确 |

**构造规则**：每个正例必须同时打印 `loop` 与等价原生 `for` 的结果（或由后者生成
`prog.expected.out`），让「等价」成为可执行的判据，而不是散文。

### 6.2 负例（`test/ast/errors/*.ct`，扁平文件）

| 文件 | 触发 | 钉住的文案 |
| --- | --- | --- |
| `loop_missing_count.ct` | `loop() { }` | `loop needs a count expression` |
| `loop_non_block.ct` | `loop(3) printf("x");` | `loop body must be a block` |
| `loop_two_counts.ct` | `loop(3, x) { }` | `loop takes exactly one count; use a native for to name the counter` |
| `loop_closure_escape.ct` | loop body 里的闭包存到外层变量 | Phase 21 既有文案：`a closure cannot be stored in '<name>' (its scope outlives the closure)` |

前三个进 `check-ast.sh` 的钉文案列表（照 `raw_*` 的 `for pair in` 写法，
[check-ast.sh](../../../selfhost/check-ast.sh#L557-L573)）；第四个证明 loop 节点没有把 body
从既有逃逸检查里藏起来。

### 6.3 `check-ast.sh` 新增断言

1. 三条语法负例：非零退出 + 精确定位 + 精确文案 + 恰好 1 条 `error:`。
2. 97：编译模式退出 0、stderr 恰好 1 条 `warning: loop shadows the outer 'i'; …`；
   `ct check` 退出 1、`error:` 带列且文案相同。
3. `loop_count_type`（正例目录，非 `errors/`，因为它是 warning 不是 error）：
   编译模式退出 0 + `warning: type mismatch: 'loop' count must be an integer (got 'float'); …`；
   `ct check` 退出 1 + 同文案的 `error:`。
4. 92 的生成物：`grep -q "for (int i = 0, __ct_loop_n_"`；且**不**出现 `i < (`（防每轮重算）。
5. `git diff --stat -- test/cases` 为空；`test/ast` 既有目录逐字节不变。

### 6.4 golden 与告警

- **既有 golden 变化预期：0。** 依据：语料无 `loop(` 语句调用；`N_LOOP` 只在源码出现
  `loop` 语句时产生。新探针只新增文件。
- H22-1 结案：CT **没有**未使用局部变量诊断；C 侧 `-Wall -Wextra` 下 `i` 参与条件与自增，
  不触发 `-Wunused-but-set-variable`；`check-warnings.sh` 以「stderr 非空即失败」把关，
  本相新增探针全部纳入该门禁。
- `test/cases` 的 25 组 baseline 不新增 `loop` 用例（D22-10）。

---

## 7. 出口判据

1. 探针 92–101 全绿，`prog.expected.out` 与等价原生 `for` 一致。
2. 4 个负例全部按 §6.2 拒绝；三条语法文案被 `check-ast.sh` 逐字钉住。
3. 编译模式 L22-4 / L22-5 为 `warning:` 且退出 0；`ct check` 为带列 `error:` 且退出 1。
4. `--diagnostics=json`：新增 `type:"loop_shadow"`；既有 kind 0–6 形状与
   `severity` 规则不变；语法错误仍不进 JSON。
5. 生成物恰为一行 `for`；`__ct_loop_n_<K>` 由 `ntmp` 提供；无每轮重算。
6. 既有 25 组 golden 与全部 `test/ast` 既有目录零变化；`test/cases` 不加 loop golden。
7. `bash selfhost/check-all.sh` 11 道硬门禁 + fixpoint 全绿；`check-warnings.sh` 零告警。
8. `CTC_VERSION` 五处一致为 `0.22.0`；baseline 仅版本 token 变化。
9. `docs/language-spec.md` / `docs/tutorial.md` 中英对称；`check-docs.py` OK。
10. 编译器自身源码在 `v0.22.0` tag 前不使用 `loop`（自举纪律）；tag 后可选。
11. `docs/history/design/phase21.md` 未被本相修改；`docs/design/phase23.md` 的双界设计未被本相预占。

---

## 8. 与已发布文档的冲突（规划时记录；S5/S7 已按下表处置）

| # | 文档 | 冲突 | 建议 |
| --- | --- | --- | --- |
| 1 | [roadmap.md](../../roadmap.md) Phase 22 行 | 仍写「D22-1–D22-8 待确认」与「含 H22-1 实测」 | ✅ 已改：记为「D22-1–D22-12」、S1–S4 各自独立提交、`v0.22.0`，出口判据同步 |
| 2 | [phase23.md](phase23.md) §3.6 / §5 | 与旧 §3.5 相同的「既有语句路径重锚 `#line`」表述 | ✅ 已改：§3.6、23.3、D23-7 统一为「不新增逐语句 `#line`」（与本文 §3.7 同口径） |
| 3 | [phase23.md](phase23.md) 头部 | 「当前 `v0.19.1`」过期 | ✅ 已改：S5 删掉版本快照并写明前置 `v0.22.0`（DOC-63） |
| 4 | 本文件旧 §3.1 | 「`K` 每函数内单调」与 `ntmp` 的进程级语义不符 | ✅ 本文已更正（§3.9） |
| 5 | [language-spec.md](../../language-spec.md) | 尚无 `loop` 小节（不是冲突，是缺口） | ✅ S5 已补 §4.45（中英对称）与 tutorial §10.2 |

---

## 9. 风险

| 编号 | 风险 | 应对 |
| --- | --- | --- |
| R1 | 语句位置的 `loop(...)` 函数调用被误判为关键字 | §2.2 扫描为 0；S0 重跑；报错文案给出「rename the function or call it in an expression」 |
| R2 | 计数每轮重算 | 展开必须带 `__ct_loop_n_K`；探针 93 + 生成物断言（`i < (`）双保险 |
| R3 | 嵌套遮蔽被静默接受 | `Warn.kind = 7`；编译 warning、`ct check` error；探针 97 双模式断言 |
| R4 | 隐式 `i` 触发未使用告警 | **已结案**：CT 无该诊断；C 侧 `-Wall -Wextra` 不告警；`check-warnings.sh` 覆盖 |
| R5 | 新增节点影响既有 golden | `N_LOOP` 只在源码出现 loop 语句时产生；S4 断言 `test/cases` 与既有 `test/ast` 零变化 |
| R6 | 计数为 `long` / 无符号时截断 | 临时量与 `i` 同为 `int`；文档写明只承诺 `int` 范围；可判定的非整数报 L22-5 |
| R7 | `kind 7` 落进 `potential_leak` 默认分支 | S3 同时加文本与 JSON 分支；S4 用 JSON 断言钉住 `type:"loop_shadow"` |
| R8 | `loop(a, b)` 被逗号表达式吞掉 | 计数按禁逗号解析；探针 `loop_two_counts.ct` |
| R9 | `loop` 进了 `kw[]` 导致分派错位 | 明确不加 `kw[]`，分支前置于 `label_ahead()`；探针 100 与 `32_goto` 复跑 |
| R10 | 双界实现提前渗进本相 | 本相只冻结 AST 布局；Phase 22 的 S2 为 `b != -1` 留了内部断言，Phase 23 的 S2 换成双界分支后该断言删除 |

---

## 10. 已定决策

| 编号 | 决策 |
| --- | --- |
| D22-1 | 形态固定为 `loop(<次数>) { … }`，不做命名变体 |
| D22-2 | 隐式变量固定为 `int i`，从 0 起，loop 语句作用域内可写、可取地址 |
| D22-3 | 计数只求值一次：`for` init 子句的 `__ct_loop_n_K = (N)`；禁止 `i < (N)` |
| D22-4 | `loop` 是上下文相关关键字：仅语句位置 + 紧跟 `(`；分派前置于 `label_ahead()`，不进 `kw[]` |
| D22-5 | 嵌套遮蔽（仅 loop-over-loop）：编译 warning、`ct check` error，`Warn.kind = 7` |
| D22-6 | 0 / 负数零次迭代且不报错；静态可判定的非整数按 kind 5 告警 / check 报错 |
| D22-7 | 生成物为单行 `for`；**不新增**逐语句 `#line`；生成行号与源行号不保证逐行对齐 |
| D22-8 | 只新增 `N_LOOP = 60`；不改 `Expr` / `Memory`；闭包与内存分析零改动 |
| D22-9 | `__ct_loop_n_<K>` 复用进程级 `ntmp`（`g_emit` 单例，从不重置） |
| D22-10 | 测试放 `test/ast/92…101` 正例 + `errors/` 4 个负例；`test/cases` 不加 loop golden |
| D22-11 | 与 Phase 23 只冻结 AST 布局（`b = -1` 哨兵）与临时量命名族；双界展开与 ABI 留给 23 |
| D22-12 | 本相不使用 `ct_sem_note`；Phase 21 的 `note:` 通道与既有诊断契约不动 |

---

## English

### Positioning

`loop(n) { … }` is a zero-cost shorthand for `for (int i = 0; i < n; i++)`. It introduces no
runtime, no helper types and no new semantics: the generated C is a single `for` line with the
count evaluated exactly once into `__ct_loop_n_<K>`.

### Status and corrections (2026-11-08)

The semantic rules below were fixed on 2026-11-07; this revision turns them into executable
slices and corrects four claims against HEAD:

| Old claim | Measured | Evidence |
| --- | --- | --- |
| `--line` re-anchors each `loop` statement | there is **no per-statement** `#line`; only the unit-level `#line 1` | `Emitter.h.ct:1092` |
| `K` is per-function | `ntmp` lives on the `g_emit` singleton and **never resets** | `Emitter.h.ct:197`, `2238`, `3564` |
| H22-1 (unused `i` may warn) | the compiler has **no** unused-local diagnostic | no such check under `selfhost/ct-ast/**` |
| `kind 7` needs only a recorder | `Diag.emit` sends unknown kinds to the `potential_leak` default | `Diag.h.ct:269-344`, `358-381` |

No code is changed by this document.

### Syntax and lowering

- Form: `loop(<count>) { <block> }`; the block is mandatory, the count is one expression parsed
  with the top-level comma disabled (so `loop(a, b)` is L22-3, not a comma expression).
- The **only** lowering is
  `for (int i = 0, __ct_loop_n_<K> = (<N>); i < __ct_loop_n_<K>; i++) <block>`, emitted by a new
  `N_LOOP` branch next to `N_FOR` (`Emitter.h.ct:2521-2539`). The count is evaluated once by the
  `for` init clause (C99 §6.8.5.3); the lowering does **not** rely on declarator-initializer order
  (§6.7.8) because `i = 0` has no side effect, so exactly-once holds regardless. `i < (N)` is
  forbidden.
- `loop` is a **contextual keyword**: only in statement position immediately followed by `(`.
  `loop_ahead()` saves and restores the lexer state; the branch goes **before** `label_ahead()` and
  `is_decl_start()` (`Stmt.h.ct:1130-1138`) and `loop` is **not** added to `kw[]`
  (`Stmt.h.ct:601-606`). Everywhere else `loop` remains an identifier.
- A 2026-11-07 scan found **0** `loop(` call sites; the only code use is the label `loop:` in
  `test/ast/32_goto/prog.ct`, which the rule does not touch. S0 re-runs the scan.

### Semantics

- **Count**: any integer type is accepted (`char` / `short` / `int` / `long` / `long long`,
  signed and unsigned, `_Bool`, `enum`, and aliases such as `size_t`); a statically known
  non-integer is a warning in compile mode and an error under `ct check`, and still compiles by
  converting to `int`. An unknown type is not diagnosed. `0` and negative counts iterate zero
  times without a diagnostic. Values outside `int` range are not promised: integer conversion is
  implementation-defined (C99 §6.3.1.3p3) and float-to-int overflow is undefined.
- **`i`**: one `int`, starting at 0 each time the statement runs, writable, addressable, and in
  scope for the condition, body and step only. After the loop it is an ordinary
  `undeclared identifier 'i'`. It is not `own` / `borrow` and has no Drop.
  An explicit `int i` in the body shadows it (native-`for` parity, no diagnostic).
- **Control flow**: `break`, `continue`, `return`, `goto` and body writes to `i` behave exactly as
  in the equivalent native `for`; no new restriction.
- **Shadowing**: only an inner `loop` inside an outer `loop` body is diagnosed (tracked with a
  `loop_depth` field). Compile mode warns; `ct check` reports an error. Message:
  `loop shadows the outer 'i'; use a native for to name the inner counter`, at the inner `loop`
  keyword. A pre-existing local `i` or a native `for` counter is not diagnosed.
- **Closures**: no new checks. `closure_walk*` already recurses over `a/b/c/d`
  (`Expr.h.ct:555-584`), so a `loop` body is covered. Capturing `i` is legal and takes a
  per-iteration snapshot; writing `i`, `i++` or `&i` inside the closure hits the existing Phase 21
  E5 checks; a closure escaping the loop hits E1–E7. A `loop` inside a closure body is legal.
- **Generated names**: `__ct_loop_n_<K>` with `K = ntmp++`; `ntmp` is process-global and never
  reset, shared with `__ct_ret%d` / `__ct_tmp%d`. `__ct_` stays reserved for the compiler.
- **Debug lines**: no per-statement `#line` is added; the unit-level anchor is the only one, and
  generated lines are not guaranteed to line up with source lines. The old claim is corrected.

### Diagnostics

| Id | Trigger | Text | Channel / severity |
| --- | --- | --- | --- |
| L22-1 | `loop()` | `loop needs a count expression` | `ct_sem_error` at `)`, error |
| L22-2 | no `{` after `)` | `loop body must be a block` | `ct_sem_error`, error |
| L22-3 | `loop(a, b)` | `loop takes exactly one count; use a native for to name the counter` | `ct_sem_error` at `,`, error |
| L22-4 | inner loop shadows outer `i` | `loop shadows the outer 'i'; use a native for to name the inner counter` | `Warn.kind = 7`, warning; `ct check` error |
| L22-5 | statically non-integer count | `count must be an integer (got '<type>'); the value is converted to int` | `ct_type_warn` (kind 5, callee `loop`), warning; `ct check` error |

- Syntax errors increment `nsem`, count toward `MAX_ERRORS 20`, exit 1, and produce no partial AST.
- Warnings go through the `Warn` array: compile/build print `<file>:<line>: warning: …` and exit 0;
  `ct check` prints `<file>:<line>:<col>: error: …` and exits 1 (`nwarn() > 0`).
- Kind 7 needs both a text branch and a JSON branch (`type:"loop_shadow"`); `severity` and `col`
  appear only under strict. Kinds 0–6 keep their shapes.
- Phase 22 uses no `ct_sem_note`; Phase 21's `note:` channel is untouched.

### Slices

| Slice | Files | Done when |
| --- | --- | --- |
| S0 baseline | none | corpus rescan is 0 call sites; `N_LOOP = 60` is free; gates recorded; probes start at 92 |
| S1 parse / AST / scope | `Stmt.h.ct`, `Parser.h.ct` | probes 92/94/95/96/97/100/101 compile and run; `32_goto` byte-identical; no `Expr` / `Memory` change |
| S2 lowering | `Emitter.h.ct` | one-line `for`; 92–97 and 101 match the native-`for` output; `b != -1` was an internal error in Phase 22, replaced by Phase 23's S2 with the real two-bound branch (assertion removed) |
| S3 diagnostics | `Diag.h.ct`, `Stmt.h.ct` | L22-1…L22-5 exact text and positions; kind 7 text + JSON; compile warning / check error verified |
| S4 tests | `test/ast/**`, `check-ast.sh` | probes 92–101, 4 negatives, pinned text, lowering grep, zero golden drift |
| S5 docs | `language-spec.md`, `tutorial.md` | bilingual `loop` section; `check-docs.py` OK |
| S6 gates | none | 11 hard gates + fixpoint green; `check-warnings.sh` clean |
| S7 close | `CTC_VERSION` ×5, baseline tokens, roadmap | `v0.22.0` in all five places; only version tokens move |

### Tests

Probes 92–101 (numbered after the existing 91): basic, count-once with side effects, zero/negative,
writing `i`, break/continue/return/goto, nested shadow, closure capturing `i`, `loop` inside a
closure, contextual-keyword label, two counters. Each probe prints both the `loop` and the native
`for` result (or derives `prog.expected.out` from the latter) so equivalence is executable.

Negatives under `test/ast/errors/`: `loop_missing_count.ct`, `loop_non_block.ct`,
`loop_two_counts.ct`, and `loop_closure_escape.ct` (the last one pins Phase 21's existing escape
text and proves the loop node does not hide its body from the escape walker).
`check-ast.sh` pins the three syntax texts, asserts the warning/error split for L22-4 and L22-5
(two modes), greps the lowering for `for (int i = 0, __ct_loop_n_` and against `i < (`, and asserts
zero drift in `test/cases` and the existing `test/ast` directories.

### Phase 23 boundary

Phase 22 freezes only the AST layout (`a` = count, `b` = `-1` sentinel) and the temporary-name
family. It did **not** freeze the two-bound lowering, its evaluation order or the
`loop(0..n)` byte form; `loop(0..n) ≡ loop(n)` started as a semantic equality. As built,
Phase 23 sequences the bounds with the comma operator and folds `loop(0..n)` at parse time, so
the folded form prints the counted form byte for byte.

### Exit criteria

Probes and negatives green; compile warning / `ct check` error split verified; JSON gains only
`type:"loop_shadow"`; one-line lowering; zero golden drift; 11 hard gates + fixpoint; five
`CTC_VERSION` sites at `0.22.0`; bilingual docs; compiler sources still avoid `loop` before the
`v0.22.0` tag.

### Known conflicts (all resolved)

All five conflicts recorded at planning time were handled by S5/S7 and the 2026-11-08 correction
pass, and the table in the Chinese §8 is the authoritative record:

- `roadmap.md` no longer says D22-1–D22-8 are pending; the Phase 22 row reads D22-1–D22-12,
  S1–S4 as separate commits and `v0.22.0`, and H22-1 is closed.
- `phase23.md` no longer repeats the per-statement `#line` claim (§3.6, 23.3 and D23-7 now say
  "no new per-statement `#line`") and the `v0.19.1` snapshot is gone.
- `language-spec.md` §4.45 and `tutorial.md` §10.2 now document `loop(n)`, Chinese and English.
- This file's own §3.1 / §3.9 claim is corrected for the process-wide `ntmp`.

No follow-up is owed by this document; anything left belongs to Phase 23's design pass.
