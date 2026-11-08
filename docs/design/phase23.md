# Phase 23 · `loop` 范围语法（`loop(a..b)`）

> 中文 · [English](#english)
>
> **状态：完成**（2026-11-08；S1–S4 落地，收口 `v0.23.0`；D23-1–D23-9 已定稿）。
> 本文是 **as-built** 记录：实现与最初的规划稿有几处偏离（词法、归一化、诊断严重度），
> 文中均以实测结果为准；被推翻的规划假设保留在 §11。
> 关联：[phase22.md](phase22.md)（`loop(n)`，本相前置）、[roadmap.md](../roadmap.md)、
> [language-spec.md](../language-spec.md)。

---

## 1. 定位

`loop(a..b)` 是 `loop(n)` 的**显式起点**形态：把「从 `a` 数到 `b - 1`」写成一行。

```text
loop(a..b)  ≡  for (int i = a; i < b; i++) { … }
loop(0..n)  ≡  loop(n)          （仅当 a 是字面量 0，见 §3.2）
```

区间固定为**左闭右开** `[a, b)`：`i` 从 `a` 起，取到 `b - 1`；`a >= b` 时零次迭代。
不做反向遍历，不做步长，不做闭区间。

判断标准与 Phase 22 相同：**展开后的 C 与手写原生 `for` 等价，且更短。**

### 1.1 本相不做

| 不做的东西 | 一句话理由 |
| --- | --- |
| `r = 2..8` 独立区间表达式 | 无类型推断，`r` 的目标类型无处安放；落到 `Range` trait 还要装箱，与零成本冲突 |
| `int a[] = 2..8` 编译期展开 | 需要魔法上限与一批新诊断，收益最低 |
| 步长变体（`step` / 反向） | 需要步长就写原生 `for`，`loop` 只覆盖步长 1 |
| `Range` trait + `each` | 硬依赖 Phase 21 闭包档②，且与「无泛型 / 零成本」冲突 |
| `loop(..b)` / `loop(a..)` 半开边界 | 两侧都必须有表达式（L23-1） |
| 闭区间 `[a, b]` | 与 `for (i = a; i < b; …)` 的等式冲突，且多写一个 `<=` 并不省事 |

---

## 2. 词法（D23-1）

`..` 是**新增的独立 token**，在 [Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct) 中以
`T_PUNCT` + 文本 `".."` 表示。分支必须放在 **`...` 之后、`.5` 之前**：

```c
if (c == '.' && self->src[self->pos + 1] == '.') {
    self->toktext[0] = '.'; self->toktext[1] = '.'; self->toktext[2] = 0;
    self->tok = T_PUNCT;
    self->pos += 2;
    return;
}
```

- **在 `...` 之后**：三连点已经由更早的分支整体吃掉，`case 1 ... 5` 不受影响。
- **在 `.5` 之前**：浮点分支会把 `.8` 当作 `N_FNUM`；若先走它，`2..8` 会切成
  `NUM(2)` `.` `FNUM(.8)`，`..` 永远拼不出来。
- 数字扫描**未改**：它原本就只在 `src[pos+1] != '.'` 时才把尾随小数点当浮点。

> 实测订正：规划稿曾断言 `2..8` 在旧词法下是 `NUM(2) PUNCT(.) PUNCT(.) NUM(8)`，
> 这是错的——旧词法实际产出 `NUM(2)` `.` `FNUM(.8)`。这正是本相必须新增 token 的原因，
> 而不是「不需要改词法器」。

`..` 出 token 之后，`1..2..3` 是 `NUM(1)` `..` `NUM(2)` `..` `NUM(3)`，解析器在第二个 `..`
处报 `unexpected token`（列 14）。这条列位是词法回归的硬断言（§8）。

---

## 3. 解析与归一化（D23-2）

### 3.1 语法

```text
loop-stmt  :=  "loop" "(" ( expr | expr ".." expr ) ")" block
```

`loop` 仍是上下文相关关键字（Phase 22 §2.1），本相不新增识别规则；body 必须是块。

`N_LOOP` 节点沿用 Phase 22 的字段：`.a` = 计数或下界，`.b` = 上界（单界时 `-1`），`.d` = body。
解析器在 `Loop` 单元内补了 `#define N_NUM 8`——该仓的宏是 **per-unit** 的，漏掉这行
`l2 build` 会直接报 `use of undeclared identifier 'N_NUM'`。

两个边界都在隐式 `i` 进入作用域**之前**解析，因此边界里只能引用外层绑定。

### 3.2 字面量 0 的归一化

`hi` 初值 `-1`；解析完第一个表达式后若当前 token 是 `..`，消费它并解析第二个边界，然后：

```c
if (self->arena->nodes[cnt].kind == N_NUM && self->arena->nodes[cnt].num == 0) {
    cnt = hi;
    hi = -1;                     /* 折回单界形态 */
}
```

判定**只看 `N_NUM && num == 0`，不看后缀**。实测边界（文档如实记录）：

| 写法 | 是否归一为 `loop(n)` | 原因 |
| --- | --- | --- |
| `loop(0..n)`、`(0)..n`、`0L..n`、`0x0..n`、`0U..n` | 是 | 都是 `N_NUM` 且 `num == 0` |
| `loop(-0..n)` | 否 | `-0` 是一元负号节点，不是 `N_NUM` |
| `loop(0+0..n)` | 否 | 加法节点，不做常量折叠 |
| `loop(0.0..n)` | 否 | 浮点是 `N_FNUM`，天然不误伤 |

`-0` / `0+0` 不归一只是少了一条优化，语义不变（`i = -0` 与 `i = 0` 等价，生成的 `for`
仍然正确求值一次）。

---

## 4. 语义

### 4.1 求值次数与顺序（D23-3）

- 两个边界**各求值一次**，先 `a` 后 `b`。
- 发射形态把两者放在同一条 `for` 声明的两个初始化器里：
  `for (int i = (a), __ct_loop_n_K = (b); …)`。C 保证同一声明中的声明符按书写顺序初始化，
  因此顺序由语法保证，不依赖未指定的求值次序。
- 循环体内修改 `a` / `b` 依赖的变量不影响本次迭代次数（边界已快照）。

### 4.2 `i` 的语义

- 单一 `int`，从 `a` 起；可写；作用域、`break` / `continue` / `return` 行为与原生 `for` 一致。
- 不参与 `own` / AutoDrop；闭包捕获 `i` 是**每轮快照**（与 Phase 22 相同）。
- `loop` 的隐式变量永远叫 `i`，本相不引入 `i1` / 按深度改名。

### 4.3 嵌套与遮蔽

沿用 Phase 22 D22-5，**不新增第二套规则**：嵌套 `loop` 遮蔽外层 `i` 时，编译模式 warning，
`ct check` 报 `loop_shadow`（kind 7）并以退出码 1 结束。用户显式写 `int i` 仍不新增诊断。

### 4.4 零次迭代

`a >= b` 时零次迭代，不报错、不告警。

---

## 5. 边界类型（D23-3 / D7 / D8）

两条边界走**同一套**判定；单界时只查一条。

### 5.1 接受

整型（`char` / `short` / `int` / `long` / 无符号各型 / `enum` / `_Bool` / `size_t`）接受。

### 5.2 D7：仍是 `int`，截断是已发布语义

边界值与 `i` 都存入 `int`。`size_t` / `long` 超过 `INT_MAX` 时**静默截断**，这是 Phase 22
已发布的语义，本相不改；文档如实写明，修改变量类型属于后续阶段。

### 5.3 D8：地址形 / 聚合类型改为硬错（breaking change）

以下三类在 Phase 22 会静默编译（数组那条尤其危险），本相改为 `ct_sem_error`：

| 边界 | 文案 |
| --- | --- |
| 指针（类型串含 `*`） | `a loop bound must be an integer (got 'int *')` |
| 结构体 / 联合体值 | `a loop bound must be an integer (got 'struct Pair')` |
| 数组 | `a loop bound must be an integer (got the array 'a')` |
| 函数指针（类型串含 `(`） | `a loop bound must be an integer (got '<type>')` |

数组单独判定：`int a[4]` 与 `int *p` 的类型串相同，只有符号表的 `is_array` 能区分；
这是 Phase 22 的洞，`loop(arr)` 今天完全静默。

这是一处**有意的 breaking change**：既有代码若把地址当计数，会从「编译通过」变为硬错。
判定放在 `loop_count_class` 之前，命中即 `return`。

### 5.4 保留 warning 的那一档

`float` / `double` / `void` 等 `cls == 0` 的静态类型**仍只告警**（L22-5，kind 5），
文案未改：`count must be an integer (got '<type>'); the value is converted to int`。
编译模式 warning，`ct check` error。`loop_count_type` fixture 依赖这条文案，不能升为硬错。

---

## 6. 发射

删除 Phase 22 留在 [Emitter.h.ct](../../selfhost/ct-ast/backend/emit/Emitter.h.ct) 的
`b != -1` 守卫，改为两支：

```c
/* b == -1：单界，形态与 Phase 22 完全一致 */
for (int i = 0, __ct_loop_n_K = (<count>); i < __ct_loop_n_K; i++)
/* b != -1：双界 */
for (int i = (<start>), __ct_loop_n_K = (<stop>); i < __ct_loop_n_K; i++)
```

- `K = self->ntmp++`，进程级单调分配；嵌套靠它拿到不同名字，**不预扫、不引入外层块**。
- 生成物中不出现 `loop` 或 `..` 字样。
- 不新增逐语句 `#line`（与 Phase 22 §3.7 同口径）：仍是单元级锚点。

---

## 7. 诊断

| 编号 | 场景 | 文案 | 严重度 |
| --- | --- | --- | --- |
| L23-1 | `loop(..b)` / `loop(a..)` | `a loop range needs both bounds` | error（语法） |
| L23-2 | 边界静态可确定为 `float` / `double` / `void` | 复用 L22-5 文案，callee 记为 `loop` | 编译 warning；`ct check` error |
| L23-3 | 边界是指针 / 数组 / 结构体 / 联合体 / 函数指针（D8） | `a loop bound must be an integer (got …)` | error（硬错） |

- L22-4（嵌套遮蔽）与 L22-5（静态非整数）原样适用，编号与严重度未改。
- `a >= b` 不诊断。
- 所有诊断带 `file:line:col`；`loop(1..2..3)` 在第二个 `..` 处报 `unexpected token`。

---

## 8. 验收与测试

### 8.1 正例（`test/ast/`）

| fixture | 覆盖 |
| --- | --- |
| `102_loop_range_basic` | `loop(2..5)` 半开语义，与原生 `for` 并排对照 |
| `103_loop_range_eval_once` | 两边界各求值一次、顺序先 `a` 后 `b`；循环体内改上界变量不改迭代数 |
| `104_loop_range_empty` | `loop(5..2)`、`loop(3..3)`、`loop(a..b)` 全零次 |
| `105_loop_range_control` | `break` / `continue` / 循环体内写 `i` |
| `106_loop_range_nested` | 嵌套遮蔽，编译 warning + `ct check` 的 `loop_shadow` error |
| `107_loop_range_closure_capture` | 双界下闭包捕获 `i`，每轮快照 |
| `108_loop_range_contextual` | `int loop = 5;`、`goto loop;`、`loop:` 标签不受影响 |
| `loop_range_own_drop` | `own` 在循环体尾每轮释放 |

### 8.2 负例（`test/ast/errors/`）

`loop_range_missing_low`、`loop_range_missing_high`、`loop_range_chained`、
`loop_range_pointer`、`loop_range_struct`、`loop_range_array`。

### 8.3 硬断言（`check-ast.sh` 的 Phase 23 块）

- **归一化逐字节**：`loop(0..n)` 与 `loop(n)` 两个临时输入的生成 C，`tail -n +2` 后 `cmp` 相等
  （首行 banner 含输入路径，必须剔除）。
- **词法回归**：列位 pin `loop_range_chained.ct:3:14: error: unexpected token`；
  既有 `41_case_range`（`case 1 ... 5`）继续 PASS。
- **形态**：生成物含 `for (int i = (` 与 `), __ct_loop_n_`，不含 `i < (`。
- **双模式**：嵌套 range loop 编译 warning + `ct check --diagnostics=json` 的
  `"type":"loop_shadow"` / `"severity":"error"`、退出码 1。

### 8.4 H23-1 实测

**通过**：隐式 `i` 与两个边界临时量均不触发 `-Wall -Wextra` 告警
（`check-warnings.sh` 全绿，`type mismatch` 只允许 `loop_count_type` 一条 pin）。

### 8.5 golden 影响

功能本身对既有 golden **零变化**：`loop` 仍只在语句位置 + 紧跟 `(` 时生效；`..` 只在
`loop` 参数内部被识别。收口 bump 到 `v0.23.0` 时，71 个 golden 仅版本 token 变化。

---

## 9. 实现切点（as built）

| 切点 | 文件 | 内容 |
| --- | --- | --- |
| 23.1 词法 | `frontend/lex/Lexer.h.ct` | 新增 `..` token（`...` 之后、`.5` 之前） |
| 23.2 解析 | `frontend/parse/Stmt.h.ct` | 双界解析、字面量 0 归一、`N_NUM` 宏、`.b` 写入 |
| 23.3 发射 | `backend/emit/Emitter.h.ct` | 删守卫，改两支单行 `for`；`ntmp` 单调分配 |
| 23.4 诊断 | `frontend/parse/Stmt.h.ct` | L23-1 / L23-3 用 `ct_sem_error`；L23-2 复用 kind 5；未改 `Diag.h.ct` |
| 23.5 测试 | `test/ast/**`、`selfhost/check-ast.sh` | §8 正负例与硬断言 |
| 23.6 文档 | `docs/**` | 本文件 + language-spec / tutorial / glossary / roadmap 中英 |

提交切片：**S1** 词法+解析，**S2** 发射，**S3** 测试与门禁，**S4** 文档，**S5** `v0.23.0` 版本收口（语料级）。

---

## 10. 依赖与风险

| 项 | 结论 |
| --- | --- |
| Phase 22 | **硬前置**：复用 `N_LOOP`、`loop_ahead()`、隐式 `i`、L22-4 |
| Phase 20 / 21 | 无语义依赖；仅共用 parser / emitter 文件，注意合并次序 |
| L0 / L1 / L2 | 不触碰；实现只落 `selfhost/ct-ast/**` |
| R1 `..` 与成员访问 | 已消解：`..` 只在 `loop` 参数内部被解析消费；参数外仍是单 `.` |
| R2 每轮重算边界 | 已消解：上界快照进 `__ct_loop_n_K`，§8.3 的 `! grep 'i < ('` 守住 |
| R3 `loop(1...5)` | 三连点仍是 `...`，`loop` 参数里报 `unexpected token`（不进 L23-1 之外的路径） |
| R4 与 `loop(n)` 分派打架 | 已消解：同一入口，按 `..` 是否出现分派；归一化后逐字节相等 |
| R5 未使用告警 | H23-1 实测通过 |
| R6 边界截断 | 保留为已发布语义（D7），文档写明 |

---

## 11. 规划稿中被推翻的假设

| 原假设 | as-built |
| --- | --- |
| 「`..` 不是新 token，解析器识别 `.` 紧跟 `.` 即可」 | 错。旧词法把 `2..8` 切成 `NUM(2)` `.` `FNUM(.8)`，必须新增 token（§2） |
| 展开形态用三个临时量与逗号运算符 | 改为两个初始化器：`int i = (a), __ct_loop_n_K = (b)`；C 保证声明符按序初始化，更短 |
| 非整数边界一律 warning | 拆成两档：`float`/`double`/`void` 仍 warning；指针/数组/结构体/函数指针升为硬错（D8） |
| 「既有 golden 零变化」 | 功能层面成立；版本收口时 71 个 golden 仅版本 token 变化 |
| `loop(0..n)` 恒等价 `loop(n)` | 仅字面量 0 归一；`-0`、`0+0` 不归一（语义仍等价，只是发射形态不同） |

---

## 12. 已定决策

| 编号 | 决策 |
| --- | --- |
| D23-1 | 新增 `..` 单词 token；分支置于 `...` 之后、`.5` 之前 |
| D23-2 | 解析期把字面量 0 下界归一为单界形态；判定只看 `N_NUM && num == 0`，不看后缀 |
| D23-3 | 两个边界各求值一次，顺序为先 `a` 后 `b`，由 `for` 声明的初始化顺序保证 |
| D23-4 | `i` 仍是单一 `int`，从 `a` 起；作用域与可写性沿用 Phase 22 |
| D23-5 | 嵌套遮蔽沿用 L22-4（编译 warning、`ct check` error） |
| D23-6 | `a >= b` 零次迭代，不诊断 |
| D23-7 | 边界类型仍为 `int`；`size_t` / `long` 超 `INT_MAX` 的截断是已发布语义，本相不改 |
| D23-8 | 指针 / 数组 / 结构体 / 联合体 / 函数指针边界改为硬错（breaking change）；`float` / `double` / `void` 保留 L22-5 warning |
| D23-9 | 生成物为单行 `for`，`K` 由 `ntmp` 单调分配；不新增逐语句 `#line` |

---

## English

### Status

**Done** (2026-11-08; S1–S4 landed, closed at `v0.23.0`; D23-1–D23-9 final). This is the
**as-built** record: it differs from the planning draft on lexing, normalisation and diagnostic
severity, and the discarded assumptions are listed in "Superseded planning assumptions".

### Positioning

`loop(a..b)` is the explicit-start form of Phase 22's `loop(n)`:

```text
loop(a..b)  ≡  for (int i = a; i < b; i++) { … }
loop(0..n)  ≡  loop(n)          (only when the lower bound is the literal 0)
```

The range is **half-open** `[a, b)`; `a >= b` iterates zero times. No reverse iteration, no step,
no closed ranges.

### Lexing

`..` is a **new token** (`T_PUNCT`, text `".."`), tried **after** `...` and **before** `.5`.
The order matters twice: `...` already owns the three-dot form (`case 1 ... 5` is unaffected), and
the float branch would otherwise turn `2..8` into `NUM(2)` `.` `FNUM(.8)`, so `..` could never form.
The number scanner is unchanged.

### Parsing and normalisation

`loop` stays a contextual keyword; the parameter is `expr` or `expr ".." expr`, and the body must be
a block. The `N_LOOP` node keeps `.a` = count / lower bound, `.b` = upper bound (`-1` for the counted
form), `.d` = body; `Stmt.h.ct` adds its own `#define N_NUM 8` because macros are per-unit.

After parsing the second bound, a lower bound that is a literal zero is folded back to the counted
form. The test is purely syntactic (`kind == N_NUM && num == 0`) and ignores the suffix:

| Form | Folded? | Why |
| --- | --- | --- |
| `0..n`, `(0)..n`, `0L..n`, `0x0..n`, `0U..n` | yes | all are `N_NUM` with `num == 0` |
| `-0..n` | no | a unary-minus node, not `N_NUM` |
| `0+0..n` | no | an addition node; no constant folding |
| `0.0..n` | no | a float is `N_FNUM` |

Not folding is only a missed optimisation: `-0` and `0` behave identically at run time.

### Semantics

Both bounds are evaluated **exactly once**, `a` before `b`: they are the initialisers of one `for`
declaration, and C initialises declarators in writing order. `i` is the same single writable `int`
as Phase 22 (per-iteration snapshot when captured by a closure, no `own`, `break` / `continue` /
`return` behave like a native loop). Nesting shadowing reuses L22-4: a compile warning and a
`loop_shadow` (kind 7) error under `ct check`. `a >= b` iterates zero times without a diagnostic.

### Bound types

D23-7: bounds and `i` stay `int`; a `size_t` / `long` bound above `INT_MAX` is silently truncated,
which is the published Phase 22 semantics and is not changed here.

D23-8 is a deliberate **breaking change**: a pointer, array, struct/union value or function pointer
bound is now `ct_sem_error` (`a loop bound must be an integer (got 'int *')` and variants), where
Phase 22 compiled silently -- the array case (`loop(arr)`) in particular had no diagnostic at all.
`float` / `double` / `void` keep the softer L22-5 rule (compile warning, `ct check` error) with the
unchanged message, because `loop_count_type` pins it. Both bounds go through the same checks.

### Emission

One line per loop:

```c
for (int i = 0, __ct_loop_n_K = (<count>); i < __ct_loop_n_K; i++)
for (int i = (<start>), __ct_loop_n_K = (<stop>); i < __ct_loop_n_K; i++)
```

`K` comes from the monotonic `ntmp`, so nested loops get distinct names without a pre-scan or an
extra scope. The output contains neither `loop` nor `..`, and no per-statement `#line` is added.

### Diagnostics

- L23-1: `a loop range needs both bounds` (syntax error).
- L23-2: a statically non-integral `float` / `double` / `void` bound reuses the L22-5 message
  (compile warning, `ct check` error).
- L23-3: an address-shaped or aggregate bound is a hard error (`a loop bound must be an integer
  (got …)`).
- L22-4 and L22-5 keep their numbers and severities; `1..2..3` reports `unexpected token` at the
  second `..` (column 14), which is how the lexer change is pinned.

### Acceptance

Positive fixtures `test/ast/102`–`108` plus `loop_range_own_drop`; negative fixtures
`loop_range_{missing_low,missing_high,chained,pointer,struct,array}`. `check-ast.sh` pins the
hard assertions: `loop(0..n)` and `loop(n)` produce identical output after `tail -n +2` (the first
line names the input path); the column pin above; the lowering shape (`for (int i = (` and
`), __ct_loop_n_`, never `i < (`); and both modes of the nested-shadowing diagnostic. `41_case_range`
still passes. The feature changes **no** existing golden; the `v0.23.0` bump moves 71 goldens by
the version token only. H23-1 measured green: no warnings from `i` or the bound temporaries.

### Superseded planning assumptions

| Planning claim | As built |
| --- | --- |
| "`..` is not a new token; the parser just sees two dots" | wrong: `2..8` used to lex as `NUM(2)` `.` `FNUM(.8)`, so a token was required |
| three temporaries joined by the comma operator | two declarator initialisers, shorter and still ordered by C |
| every non-integer bound only warns | split: `float`/`double`/`void` warn; pointers / arrays / structs / function pointers are hard errors |
| "existing goldens change by 0" | true for the feature; the release bump moves 71 goldens by the version token |
| `loop(0..n)` always equals `loop(n)` | only a literal zero is folded; `-0` and `0+0` stay ranges (same semantics) |
