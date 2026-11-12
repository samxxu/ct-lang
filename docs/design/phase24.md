# Phase 24 · 数组 range 初值（`int a[] = 0..n(expr)`）

> 中文 · [English](#english)
>
> **状态：完成**（as-built，2026-11-09）。S1–S5 全部落地，收口到 **`v0.24.0`**。
> D24-1–D24-13 已定稿；实现与设计的偏差集中在 §12，正文已按 as-built 校正。
> **2026-11-09 修订**：索引占位符从 `i` 改为 `$`（它不是标识符，不可能被遮蔽或撞名）；
> D24-4 / L24-8 撤销，不引入 `range_shadow` kind；边界字面量的拼写与溢出改为显式校验。
> 关联：[phase23.md](../history/design/phase23.md)（`..` 词法与 `loop(a..b)`，本相前置）、
> [phase22.md](../history/design/phase22.md)、[roadmap.md](../roadmap.md)、[language-spec.md](../language-spec.md)、
> [closure-conventions.md](../closure-conventions.md)。

---

## 1. 定位

`loop(a..b)` 解决「按次数迭代」，本相解决**同一件事的声明式写法**：把由下标决定的数列
直接写成数组初值，不写循环。

```c
int odd[] = 0..13($ * 2 + 1);            /* 1, 3, 5, …, 25 —— 13 个元素 */
static const int sq[] = 0..11($ * $);    /* 0, 1, 4, …, 100 */
int base = 10;
int shifted[] = 0..3($ + base);          /* 局部：元素表达式可读运行期变量 */
```

展开恰好是**花括号初始化列表**，不生成任何循环：

```c
int odd[] = { ((((int)0) * 2) + 1), ((((int)1) * 2) + 1), …, ((((int)12) * 2) + 1) };
```

判断标准与 Phase 22 / 23 相同：**展开后的 C 与手写初始化列表等价，且更短**；并且比手写
`for` 多一条硬优势——**文件作用域、`static`、`const` 的静态表格都能用**，因为产物
里没有语句，只有初始化器。

### 1.1 本相不做

| 不做的东西 | 一句话理由 |
| --- | --- |
| 运行时边界（`0..n($)` 里 `n` 是变量、VLA `int a[n] = …`） | 初始化列表的长度必须在编译期固定；运行时边界只能退回循环 + 数组，与「文件作用域可用」直接冲突 |
| `Vec<int>` / `own Vec<int>` / 自定义容器 | CT 没有泛型，std 只有 `VecInt`（§4.10 之外），`own` 只收结构体指针 + `malloc`/`calloc`，初值列表无处安放 |
| 普通 `a..b` 区间表达式（`r = 2..8`） | 无类型推断，`r` 的目标类型无处安放；Phase 23 §1.1 已拒绝，本相不改 |
| 步长 / 闭区间 / 反向 | 需要就写原生 `for`；range 初值只覆盖「步长 1、左闭右开」 |
| `each (nums) { … item … }` 语句形态（旧名；D25-12 起定名 `foreach`） | 需要隐式名字与块参数，属语言级语法糖；SHIM / 宏做不到（§10）。**方法形态 `a.each(n, closure)` 已由 Phase 25 落地**，见 [phase25.md](phase25.md) |
| CT 侧常量折叠 | CT 从不折叠常量（`const_ok` 是结构判定）；`$` 的取值在**发射期**替换，表达式本身交给 C 折叠 |
| 元素为 struct / union / 接口值 / 数组 | 初始化列表的元素类型限于标量；聚合元素需要逐元素 vptr / 装箱，收益与风险不成比例 |
| 宏 / `enum` 边界 | 符号表只记 `is_const` 标志、不记数值（§3.2）；要支持就得先引入常量求值器 |
| `.m.ct` / shim 承载 | range 初值是语法，不是函数调用；映射层不参与 |

---

## 2. 词法

**新增一个 token：`$`**（仅 ct-ast；见 D24-12）。词法器给它一个显式分支，产出
`T_PUNCT` + 文本 `"$"`。它**不是标识符字符**：标识符扫描永远不收 `$`，所以 `$` 既不能
出现在名字里，也不可能与任何现有变量撞名。

`..` 仍是 Phase 23 的 token（`T_PUNCT` + 文本 `".."`，分支在 `...` 之后、`.5` 之前），
本相只新增**解析位置**：`..` 出现在数组声明的初始化式里，而不是 `loop` 参数里。两个位置
互不影响：

- `loop(0..n)` 仍只在语句位置 + 紧跟 `(` 时生效（Phase 22 / 23 的上下文关键字规则）；
- `int a[] = 0..n($)` 只在 `<类型> <名字>[<维度>?] =` 之后被识别（§3.1）。

`$` 只在 range 初值的**元素表达式**里被表达式解析器接受（§3.3）；在其它任何位置 ——
初始化式之外、维度里、`$ = 1`、`&$`、`$++` —— 都是**语法错误**（既有的
`unexpected token`，或 §3.3 的专门文案），绝不会静默当成标识符。

`..` 出现在其它位置仍是普通 token，由既有语法报 `unexpected token`。

L0 / L1 / L2 的词法器**不改**：`$` 在冻结编译器里仍是非法字符 / 语法错误，这正好符合
D24-12（功能只落 ct-ast）。

---

## 3. 解析

### 3.1 识别位置（D24-1）

两个入口，语法完全一致：

- 块作用域：`Stmt::parse_decl_node` 处理 `= <初值>` 的分支；
- 文件作用域：`Parser::parse_func` 的全局声明分支（全局初始化式不由 `parse_decl_node`
  解析，这是实现时必须补的第二处，见 §8 24.2）。

判定只看 `=` 之后的形状：

1. 先按字面量读第一个边界（可带一元 `-`），紧跟 `..`，再读第二个边界，紧跟 `(`；
2. 形状成立后才检查声明符**带维度**（`nodes[n].text3` 非空，即 `int a[]` / `int a[3]`）；
   不带维度报 L24-5（不是退回普通表达式）。

第 1 条是**唯一**的歧义防线：边界只收字面量，因此 `= 0..13($ * 2 + 1)` 不会走进表达式
解析器，也就不存在「`13(...)` 被当成函数调用」的贪婪问题（§9 R1）。探测用游标
save/restore 扫到本声明符的 `,` / `;`，只认**括号深度 0** 的 `..`；`{ … }` 里的 `..`
属于既有初始化式，不受影响。

### 3.2 边界的取值（D24-2）

边界**只接受整数字面量**，可带一元 `-`：

| 写法 | 接受 | 说明 |
| --- | --- | --- |
| `0`、`13`、`-2` | 是 | 十进制 |
| `0x10`、`0` 开头的八进制 | 是 | 与 C 一致 |
| `1U`、`2L`、`3ULL` | 是 | 后缀忽略（与 §4.37 的规范化同口径） |
| `0.0`、`1e3` | 否 | 浮点字面量 → L24-2 |
| `n`、`BASE`、`(1+2)`、`sizeof(x)` | 否 | 非字面量 → L24-2 |
| `0x`、`0xG` | 否 | 不完整的十六进制 → L24-2（`got '0x'`） |
| `99999999999999999999` | 否 | 超出 `long` → L24-9 |
| `- 3`（中间有空格） | 是 | 词法上是一元 `-` + 字面量 |

求值在解析期完成，结果存 `long`：`count = end - start`。

- `count <= 0` → L24-3（空区间是硬错；Phase 23 的 `loop(a..b)` 允许零次迭代，**本相不允许**，
  因为空初始化列表没有任何可写的目标语义）。
- `count > 1024` → L24-4。

**边界字面量必须自己校验拼写与溢出**（共享词法器不改，见 §9 R9）：词法器只把值累加进
`toknum`，既不拒绝 `0x`（无数字时静默为 0），也不检测溢出。边界读取器因此额外做两件事：

1. 用 `tokstart` / `pos` 从源码取回**原始拼写**；十进制 / 十六进制 / 八进制各自重新验证
   至少有一位数字、且后缀只含 `U` / `L`。不成立 → L24-2（`got '<spelling>'`）。
2. 重新累加时按 `LONG_MAX` 判溢出；越界 → L24-9（不落成负数或垃圾值，也不会被
   `count <= 0` 误报成“空区间”）。

这两条只作用于 range 边界，不会改变其它位置的字面量行为（词法器的缺口单列在 §9 R9，
留给后续单独处理）。

**不做符号求值**：`enum { N = 5 }; int a[] = 0..N($);` 报 L24-2。理由与 Phase 22 / 23 一致——
CT 的符号表只记 `is_const` 标志、不记 enum 数值，也不展开宏；引入常量求值器是另一个量级的
工程，且与「CT 不做常量折叠」的既定边界冲突。

### 3.3 元素表达式与 `$`（D24-3）

上界之后必须是 `(`，随后按普通表达式解析元素表达式，直到配对的 `)`。`$` 不是变量，
所以这里**没有作用域、没有符号登记、没有 `declare_const`**：

- 解析器在 `Expr` 上有一个 `dollar_ok` 标志，只有 `parse_range_init` 在 `parse_expr()` 前后
  置位 / 还原；
- `dollar_ok` 为真时，`$` 作为一个普通 primary 被接受，构造 `N_VAR`，`text2 = "$"`；
- 为假时 `$` 走既有 `unexpected token`（所以 range 初值之外、维度里、`loop` 参数里都报错）；
- `$` 的取值只在**发射期**替换（§5.1），AST 里不存任何下标值。

`$` 的四个约束：

1. **不可赋值 / 取地址 / 自增**：`$ = 1`、`&$`、`$++`、`++$` 都是硬错。`$ = 1` 由表达式的
   既有语法拒绝（`unexpected token`，`parse_expr` 本来就没有赋值）；其余三种由**解析期的
   三处定点检查**拒绝（`parse_unary` 的前缀 `++` / `--` 与 `&`、`parse_postfix` 的后缀
   `++` / `--`），文案 `the range index '$' is not a variable`（L24-11）。
   **as-built 偏差**：设计原写「元素子树解析完后显式 walk」，实现改为这三处定点检查——
   更精确（错误位置就是运算符所在处）、不依赖 kind 枚举是否完整，也不会漏掉将来新增的
   前缀 / 后缀形态。这**不是**“未声明变量”类错误，`$` 根本没有名字。
2. **不可出现在维度里**：维度是 `text3` 的原样文本。声明符解析处统一 `strchr(text3, '$')`，
   命中即报 L24-10（`'$' cannot be used in an array dimension`）——这样
   `int a[$]`（无论是否带 range 初值，如 `int a[$] = 5;`）都不会原样漏进 C，
   也不会落成未声明变量。文案刻意不提 "the range index"，因为这条检查与有没有 range 无关。
3. **没有遮蔽**：`$` 不是标识符，外层 `i`、`for (int i …)`、任何同名变量都与它无关；
   原 D24-4 / L24-8 撤销（编号保留不用）。
4. **可多次出现**：`0..3($ * $)` 的每个 `$` 都是同一个当前下标。

元素表达式里可以读外层变量、调用函数、写宏；但在**文件作用域 / `static`** 下，产物是
常量初始化器，只有常量表达式能编过（C 侧硬错，见 §4.3）。

### 3.4 维度校验（D24-6）

| 维度写法 | 处理 |
| --- | --- |
| `[]` | 交给 C 推断 |
| 字面量 `[13]` | 必须等于 `count`，否则 L24-7 硬错 |
| 其它（`[N]`、`[BASE + 1]`、`[sizeof(x)]`） | 原样发射，由 C 判断；不等时 C 报 `excess elements` 或补零，**不是** CT 的诊断 |

字面量维度的求值复用 §3.2 的同一个字面量求值函数，保证两侧口径一致。

### 3.5 元素类型（D24-5）

声明类型必须是**标量**元素：

- 接受：整型（含 `char` / `short` / `long` / 无符号 / `enum` / `_Bool`）、浮点、指针；
- 拒绝：`struct` / `union` / 接口值 / 数组元素 → L24-6。

判定放在构造节点之前，命中即 `return`。

### 3.6 AST 形态（D24-10）

新增节点 kind **61**：`N_INIT_RANGE`（`N_LOOP` 是 60）。

| 字段 | 含义 |
| --- | --- |
| `.a` | 元素表达式子树（**只存一份**，发射期复用） |
| `.num` | 下界（`long`） |
| `.aux` | `count` |

`N_DECL.a` 指向这个节点，替代 `N_RAW` / 表达式初值。节点数**不随 `count` 增长**——这是
把 cap 定在 1024 仍然安全的前提（§10 R4）。

`#define N_INIT_RANGE 61` 要同时加进 `Stmt.h.ct` 的 per-unit 宏块与 `Emitter.h.ct`
（该仓的宏是 per-unit 的，漏一处 `l2 build` 直接报未声明标识符，Phase 23 §3.1 有先例）。

---

## 4. 语义

### 4.1 展开形态（D24-7）

```c
int odd[] = 0..13($ * 2 + 1);
```

```c
int odd[] = { ((int)0) * 2 + 1, ((int)1) * 2 + 1, (((int)2) * 2 + 1), …, ((int)12) * 2 + 1 };
```

- `$` 的每一次出现渲染为 `((int)<k>)`，`k` 从 `start` 递增到 `end - 1`；
- 元素表达式在每一份里**原文重发**（同一棵 AST，不是复制节点），因此外层变量名、函数名、
  宏都按源码原样出现；
- 生成物中不出现 `0..13`、不出现 `$`、不出现循环、不出现临时变量；
- 不新增 `#line`（与 Phase 22 / 23 同口径：仍是单元级锚点）。

### 4.2 求值次数与顺序（D24-8）

- 元素表达式被求值 `count` 次（每次一个元素）；
- **顺序未指定**：C99 §6.7.8 不规定初始化列表中各项的求值顺序。因此文档规则是
  **元素表达式不得有副作用**；需要副作用请写 `loop` + 显式下标赋值。
- CT **不诊断**副作用（与「CT 不做流分析」一致）；这条是文档约定，不是门禁。

### 4.3 存储期与常量性

- 局部、局部 `static`、文件作用域、`extern` 声明（无初值，不适用）都支持；
- 文件作用域 / `static` 的元素表达式必须是 C 的常量表达式：字面量、`enum`、宏、
  `sizeof`、`((int)k)`。读运行期变量会被 C 拒绝（`initializer element is not constant`），
  这不是 CT 的诊断；
- `const` 与 `static const` 均可（测试 §8.1 覆盖）。

### 4.4 不参与的功能

- 不做装箱（§3.5 已排除接口元素）；
- 不做 vptr 初始化（同上）；
- 不做 AutoDrop / 泄漏分析（初值不是 `own` 目标）；
- 不做闭包绑定（元素表达式里出现闭包字面量 → 既有「闭包不能作元素」硬错）。

---

## 5. 发射

### 5.1 声明站点与 `N_VAR`

1. **三处**打印初始化式的地方都要接 `N_INIT_RANGE` → `emit_range_init()`：
   - `emit_inline` 的 `N_DECL` 分支（`nodes[n].a` 是 `N_RAW` 时走 `emit_raw_init`，
     否则 `= <expr>`）；
   - `emit_inline` 的 `N_DECLS` 分支（一行多个声明符时，后续声明符自己打印初值）；
   - `emit_node` 的 `N_GLOBAL` 分支（文件作用域不走 `emit_inline`）。
   Phase 23 的先例只提了第一处；实测 ct-ast 三处各自独立，漏任何一处都会让某一类声明
   打印成 `= unknown`。
2. `emit_expr` 的 `N_VAR` 分支：当 `self->range_depth > 0` 且 `text2` 是 `"$"` 时，打印
   `((int)<self->range_k>)`，而不是 `$`。

`emit_range_init()` 的形状：

```c
fputs(" = { ", out);
for (k = start; k < start + count; k++) {
    if (k != start) fputs(", ", out);
    self->range_depth++; self->range_k = k;
    emit_expr(node.a);                 /* 同一棵子树，重复发射 */
    self->range_depth--;
}
fputs(" }", out);
```

- `range_depth` / `range_k` 是 `Emitter` 新增的两个标量字段，默认 0；
- 用深度计数而不是布尔量：嵌套 range 初值（range 初值不能出现在元素表达式里，
  但 `$` 的替换必须能在任何嵌套深度下正确回退）；
- 全局与局部共用 `emit_inline`，所以**只改这一处**；`N_GLOBAL` → `emit_type_decl` →
  `emit_inline` 的路径不变。

### 5.2 与既有初始化路径的关系

- 不走 `emit_rewritten_init`（那是 `N_RAW` 文本的路径，需要 4 KiB / 16 KiB 上限与
  `rewrite_init_text`）；range 初值是**流式写出**的，不受文本池上限约束；
- 不走 `type_needs_init` / vptr 分支（§3.5 已排除聚合元素）；
- 不走 `hoist_rvalue`（元素表达式里若有右值接收者，按既有规则在表达式内部处理）。

### 5.3 产物示例

```c
/* 输入 */  int odd[] = 0..13($ * 2 + 1);
/* 输出 */  int odd[] = { ((((int)0) * 2) + 1), ((((int)1) * 2) + 1), …, ((((int)12) * 2) + 1) };
```

括号形态由既有 `emit_expr` 决定（每个二元 / 一元运算都加括号），本文不另行约定；
`check-ast.sh` 的断言只钉 `= {`、`((int)1)`、元素个数与「没有 `for (`」（§7.3）。

---

## 6. 诊断

| 编号 | 场景 | 文案 | 严重度 |
| --- | --- | --- | --- |
| L24-1 | `..` 之后直接 `(` | `a range initializer needs both bounds` | error（语法） |
| L24-2 | 边界不是整数字面量 | `a range bound must be an integer literal (got '<spelling>')` | error |
| L24-3 | `count <= 0` | `an empty range has no elements` | error |
| L24-4 | `count > 1024` | `too many range elements (limit 1024)` | error |
| L24-5 | 用在无维度的声明上（`int x = 0..3($);`） | `a range initializer declares an array` | error |
| L24-6 | 元素类型是 struct / union / 接口 / 数组 | `a range initializer cannot initialize '<type>' elements` | error |
| L24-7 | 字面量维度 ≠ `count` | `the array size '<n>' does not match the range (<count> elements)` | error |
| L24-8 | ~~内层 `i` 遮蔽外层 `i`~~ | **已撤销**（`$` 不是标识符，不存在遮蔽）；编号保留不复用 | — |
| L24-9 | 边界字面量超出 `long` | `a range bound is out of range` | error |
| L24-10 | `$` 出现在数组维度里 | `'$' cannot be used in an array dimension` | error |
| L24-11 | 对 `$` 赋值 / 取地址 / 自增（`&$`、`$++`、`++$`） | `the range index '$' is not a variable` | error |

- 文案风格与 Phase 22 / 23 一致：小写、无句号、标识符单引号、`got '…'` 形式；
- 所有诊断带 `file:line:col`；
- **不引入新的 warning kind**：`ct check` 的 kind 表、JSON `type` 与 `--diagnostics=json`
  的形状都不动（D24-4 撤销）。L24-8 编号空置，避免与历史引用冲突；
- `$ = 1` 走表达式的既有语法错误（`unexpected token`），不进上表；`&$` / `$++` / `++$`
  由解析期的三处定点检查报 L24-11（§3.3 约束 1）。

---

## 7. 验收与测试

### 7.1 正例（`test/ast/`）

| fixture | 覆盖 |
| --- | --- |
| `109_range_init_basic` | `int odd[] = 0..13($ * 2 + 1);`，与手写 `{1,3,…}` 并排对照、运行结果相同 |
| `110_range_init_static_const` | 文件作用域 `static const int sq[] = 0..11($ * $);`（本相的核心收益；`$` 重复出现） |
| `111_range_init_local_static` | 函数内 `static int tbl[] = 1..4($ * 10);` |
| `112_range_init_reads_outer` | 元素表达式读外层变量（局部场景零告警） |
| `113_range_init_negative_bounds` | `-2..3($)`，验证 `count = 5` 与 `((int)-2)` |
| `114_range_init_single` | `0..1($)`（1 个元素，列表无逗号） |
| `115_range_init_explicit_dim` | `int a[3] = 0..3($ * 2);`（字面量维度匹配） |
| `117_range_init_multi_declarator` | `int a[] = 0..3($), b[] = 0..2($ * 2);`（一行多个声明符各打印自己的初值） |

编号 `116` 与 L24-8 一样**保留不复用**：它曾是 `116_range_init_shadow`，随 D24-4 一并删除。

### 7.2 负例（`test/ast/errors/`）

字面量与形状：

`range_init_missing_end`、`range_init_nonliteral_bound`（`n`）、
`range_init_nonliteral_bound_base`（`BASE`，as-built 单独一个文件：前者在首个错误处即停）、
`range_init_empty`、`range_init_too_many`、`range_init_scalar_decl`、
`range_init_element_struct`、`range_init_dim_mismatch`。

`$` 的位置与用法：

- `range_index_outside` —— `$` 出现在 range 初值之外（`int x = $;`），报既有
  `unexpected token`，**不得**报成未声明变量；
- `range_index_in_dim` —— `int a[$] = 0..3($);`，报 L24-10；
- `range_index_assigned` —— `$ = 1`，报既有 `unexpected token`（`parse_expr` 没有赋值）；
- `range_index_address` —— `&$`、`$++`、`++$`，各报 L24-11（三个函数各一处，保证三条都命中）。

边界字面量的拼写与溢出（共享词法器不改，靠边界读取器兜住）：

- `range_init_bad_hex` —— `0..0x($)`，报 L24-2 且文案带 `got '0x'`，**不得**静默按 0 处理；
- `range_init_overflow` —— `0..99999999999999999999($)`，报 L24-9，**不得**落成负数或
  被 L24-3 误报成空区间。

### 7.3 硬断言（`check-ast.sh` 的 Phase 24 块）

- **形态**：`109` 的**生成声明行**含 `int odd[] = { `、含 `((int)1)`，**不含** `for`、
  **不含** `$`、**不含** `0..13`（`109` 自己还有一个手写 `for` 打印数组，所以断言按声明行取，
  不按整份文件取）；
- **元素个数**：把 `109` 的初始化器按 `,` 切分后元素数 == 13（`awk` / `tr` 计数）；
- **等价（两层）**：
  1. **逐字节层**：`109` 的初始化器与一份**手写同形**的显式列表（13 项）做 `cmp`。
     手写文件用的是 ct 的**规范括号形态**（见 §5.3：每个二元 / 一元运算各加一层括号），
     即 `{ ((((int)0) * 2) + 1), …, ((((int)12) * 2) + 1) }`，**不是**人类更习惯的
     `{ ((int)0) * 2 + 1, … }`——后者在 `cmp` 前必须先归一，那就等于放弃了「形态一变即红」。
     `{ … }` 走原文拷贝路径，所以这层钉的是：`$` 变成了且只变成了 `((int)k)`，别的什么都没动；
  2. **语义层**：另写一个普通字面量数组 `{1, 3, …, 25}`，两者分别运行、**输出逐字节相同**；
     这层钉的是值正确。
  两层比较前都按 Phase 23 §8.3 的先例剔除 banner；
- **文件作用域**：`110` 生成物里是文件作用域的 `static const int sq[] = { … };`，且后续
  `main` 读它打印正确；
- **`$` 负例**：`range_index_outside` / `range_index_in_dim` / `range_index_assigned` /
  `range_index_address`（**as-built 拆成 `range_index_address`、`range_index_address_post`、
  `range_index_address_pre` 三个文件**——编译器遇首个错误即停，一个文件只能命中一条）
  各命中预期文案（`grep`），且**没有**任何一条落成 `undeclared` / `未声明`；
- **边界负例**：`range_init_bad_hex` 的文案带 `got '0x'`；`range_init_overflow` 报
  `a range bound is out of range`；
- **编辑器 grammar**：`editors/vscode/syntaxes/ct.tmLanguage.json` 把 `$` 纳入标点匹配，
  `editors/vscode/test/check-grammar.py` 加一条 `$` 断言，第 6 道门禁保持全绿。

### 7.4 告警

`check-warnings.sh` 全绿：`$` 被发射成 `((int)k)` 之后不产生 `-Wall -Wextra` 告警
（无未使用变量、无符号/无符号比较）。`((int)k)` 强制转换故意保留：它让
`unsigned` / `char` 元素的 conversions 与手写 `(int)k` 完全一致。

### 7.5 golden 影响

功能本身对既有 golden **零变化**：`..` 在初始化式位置此前是语法错误，没有既有代码命中。
收口 bump 到 `v0.24.0` 时，74 个 golden 仅版本 token 变化。

---

## 8. 实现切点

| 切点 | 文件 | 内容 |
| --- | --- | --- |
| 24.1 字面量求值 | `frontend/parse/Stmt.h.ct`（as-built：文件级静态辅助 `range_bound_value` / `range_bound`；`$` 的判等 `is_range_index` 在 `Expr.h.ct`） | `range_bound_value()`：十进制 / 十六进制 / 八进制、`U`/`L`/`LL` 后缀、可选一元 `-`；**取回原始拼写校验位数与后缀**（L24-2）、按 `LONG_MAX` 判溢出（L24-9） |
| 24.2 解析 | `frontend/parse/Stmt.h.ct`、`frontend/parse/Parser.h.ct` | 块作用域 `parse_decl_node` 的 `=` 分支与文件作用域 `Parser::parse_func` 的全局分支：range 探测（§3.1）、边界求值、`dollar_ok` 置位、「`$` 作 primary」、`N_INIT_RANGE` 构造、维度校验（含 `$` → L24-10）、元素类型校验、cap |
| 24.3 发射 | `backend/emit/Emitter.h.ct` | `N_INIT_RANGE 61`、`range_depth` / `range_k` 字段、`emit_range_init()`、`N_VAR` 的 `$` 替换、`emit_inline` 的 N_DECL / N_DECLS 与 `emit_node` 的 N_GLOBAL 三处分支 |
| 24.4 诊断 | `frontend/parse/Stmt.h.ct` | L24-1–L24-7、L24-9–L24-11 全用 `ct_sem_error`；`$ = 1` 与 `$` 越界位置走既有 `unexpected token`；**不新增 warning kind、不动 `ct check`**（D24-4 撤销） |
| 24.5 测试 | `test/ast/**`、`selfhost/check-ast.sh`、`selfhost/check-warnings.sh` | §7 正负例与硬断言；编辑器 grammar（第 6 道门禁）补 `$` |
| 24.6 自举守卫 | `selfhost/check-ast.sh` | `selfhost/**` 的编译器源码不得使用 range 初值（与闭包 S7 守卫同口径），直至 `v0.24.0` tag 存在 |
| 24.7 文档 | `docs/**` | 本文件 + language-spec §4.47（实现后）+ tutorial（实现后）+ roadmap |

提交切片：**S1** 字面量求值 + 解析（节点构造、校验）；**S2** 发射（列表 + `$` 替换）；
**S3** 诊断与门禁断言（`$` 负例、边界负例、编辑器 grammar）；**S4** 文档与自举守卫；
**S5** `v0.24.0` 版本收口（语料级；已随本轮收口完成）。

---

## 9. 依赖与风险

| 项 | 结论 |
| --- | --- |
| Phase 23 | **硬前置**：复用 `..` token；不共用 `N_LOOP` 之外的任何代码 |
| Phase 21 | 无依赖；只是「闭包不能作元素」的既有检查要维持 |
| L0 / L1 / L2 | 功能只落 `selfhost/ct-ast/**`；S5 版本收口改五处 `CTC_VERSION` |
| R1 `0..13(` 与函数调用歧义 | 已消解：边界只收字面量，表达式解析器根本不参与边界 |
| R2 `i` 与 `loop` 的 `i` 混淆 | 已消解：占位符是 `$`，它不是标识符，既不能与 `for (int i …)` 撞名，也不可能被遮蔽；原 L24-8 因此撤销 |
| R3 初始化列表求值顺序未指定 | 文档规则「元素表达式不得有副作用」；不诊断 |
| R4 大 `count` 的节点 / 文本膨胀 | 元素表达式只存一棵 AST，发射期复用；cap 1024 |
| R5 维度里的 `$` | 维度是 `text3` 的原文，解析器显式扫一次 `$`，命中报 L24-10（**不**留给 C，也不落成未声明变量） |
| R6 与 boxing / vptr / 闭包路径冲突 | 元素限标量；三处既有分支按 `N_RAW` / `N_CLOSURE` / 接口类型判定，不命中 |
| R7 既有代码被误判 | `..` 在初始化式位置此前是语法错误，无既有命中；`..` 在 `loop` 里的语义不变 |
| R8 ~~`declare_const` 是否拒绝赋值 / 取地址~~ | **已撤销**：`$` 不是变量，没有 `declare_const`、没有符号登记；`$ = 1` 走既有语法错误，`&$` / `$++` / `++$` 由显式 walk 报 L24-11 |
| R9 共享词法器的缺口 | 词法器既不拒绝 `0x`（无数字时静默为 0），也不检测整数字面量溢出。**本相不改词法器**：边界读取器自己取原始拼写重验位数/后缀（L24-2）并判溢出（L24-9）。缺口本身另记，留待单独处理 |

---

## 10. `each` 的归属（与 Phase 25 的边界）

> **命名更新（2026-11-10）**：本节成文时把语句形态暂记为 `each (…)`；[D25-12](phase25.md#L287)
> 已作废该关键字名，语句形态现定名 **`foreach (…)`**，`each` 只保留为库层方法 / 泛型函数名。
> 以下保留原文作为历史记录。

用户提问：能否借 `.m.ct` + shim 给数组挂方法（例如 `each`），再用闭包处理元素。当时的
结论是「静态映射可以挂方法，但闭包传不进去」——这条判断在 Phase 25 之前成立，也正是
Phase 25 要补的缺口。依据如下（全部来自 Phase 25 之前的实现）：

1. **类型宿主能命中数组**：`map trait T for type int *` 的接收者匹配会对数组变量做 decay
   （[batch38 §5.2](../history/design/batch38-map-unit/spec.md)），所以 `int a[4]` 确实能写
   `a.m()`。
2. **长度在宿主里丢了**：decay 之后只剩 `int *`，方法拿不到元素个数；`int *p` 与 `int a[4]`
   命中**同一个**宿主，无法只给数组挂方法。`sizeof(a)/sizeof(a[0])` 的宏方案会把 `int *p`
   也算成数组，静默给出错误长度，因此长度必须显式传（Phase 25 D25-8）。
3. **闭包只在「已解析签名的普通函数调用」处展开**：`closure_arg_check` 唯一的调用点在
   `Expr.h.ct` 的普通调用解析里，且要求 `fi >= 0`
   （[Expr.h.ct](../../selfhost/ct-ast/frontend/parse/Expr.h.ct)）。方法调用（含静态映射的
   `a.each(…)`）不经过这条路——这是 Phase 25 补上的四个缺口（[phase25.md](phase25.md) §2）。
4. **shim 收不了闭包的环境**：环境是栈上的 `__ct_cl_env_v_N`，源码里没有名字可以传给 shim；
   `.shim.h` 只能接普通函数指针 + `void *`（档①）。Phase 25 让 recipe 把闭包拆成
   `tramp` / `&env` 两半分别落位，正是绕开这一点。
5. **成本口径不符**：即使做出来，每元素一次函数指针间接调用，与「零成本」相悖；CT 不做内联
   与去虚化。Phase 25 接受这个代价，它是**便利性**，不是零成本。

**归属结论**（2026-11-09，用户确认）：

- **方法形态 `a.each(n, closure)`** → **Phase 25**（已完成，`v0.25.0`，见 [phase25.md](phase25.md)）；
- **语句形态 `each (nums) { … item … }`** → 仍不做、不排期：需要隐式名字、块参数与
  `break`/`continue`，是语言级语法糖，成本远高于本相；
- **档①（`a.each(4, cb, &ctx)`）** → 今天就能用，不需要任何编译器改动
  （`test/ast/75_closure_param_pair` 证明「普通函数 + `(fn, env)` 形参 + 闭包字面量实参」可用）。

本相（Phase 24）因此**不引入任何 `each` 形态**，也不为它预留语法。

---

## 11. 已定决策

| 编号 | 决策 |
| --- | --- |
| D24-1 | 只支持数组声明初始化式位置；复用 `..`，新增一个 `$` token（ct-ast 专属） |
| D24-2 | 边界只收整数字面量（可带一元 `-`），解析期求值；`count <= 0` 硬错；不做符号求值；拼写与溢出显式校验 |
| D24-3 | `$` 是索引占位符：只在 range 初值的元素表达式里被识别，渲染为 `((int)k)`；它不是标识符、不是变量 |
| D24-4 | ~~外层同名 `i` 被遮蔽时编译 warning、`ct check` error（新 kind 8 `range_shadow`）~~ **已撤销**：`$` 不会被遮蔽，不引入新 kind、不改 `ct check` |
| D24-5 | 元素类型限标量；struct / union / 接口 / 数组元素硬错 |
| D24-6 | `[]` 交给 C；字面量维度必须等于 `count`；非字面量维度原样发射 |
| D24-7 | 展开为花括号列表，不走循环，不产生临时变量 |
| D24-8 | 求值顺序未指定（C99 §6.7.8），文档要求元素表达式无副作用，不诊断 |
| D24-9 | `count` 上限 1024；列表流式写出，不受初始化器文本池上限约束 |
| D24-10 | 新节点 `N_INIT_RANGE`（kind 61），元素表达式只存一棵 AST |
| D24-11 | 不做运行时边界 / VLA / 容器 / `each` / 独立区间表达式 / 步长 / 闭区间 / 常量折叠 / `.m.ct`（`each` 的**方法形态**归 Phase 25，语句形态不排期） |
| D24-12 | 仅 ct-ast；L0/L1/L2 不改（`$` token 只在 ct-ast 的词法器里存在，冻结编译器仍把它当非法字符）；编译器自身源码不得使用该语法（自举守卫） |
| D24-13 | 收口 bump `v0.24.0`；功能层既有 golden 零变化，带版本 token 的 74 个文件仅版本变化（`test/cases/**` 50 + `test/modules/**` 21 + `examples/tour/**` 3 = 74；roadmap 版本记录里的 71 是只统计测试 golden 的历史口径） |

## 12. 实现记录（as-built，2026-11-09）

| # | 设计写法 | 实际做法 | 理由 |
| --- | --- | --- | --- |
| A1 | `&$` / `$++` / `++$` 在元素子树解析完后由**显式 walk** 拒绝 | `parse_unary` 的前缀 `++` / `--` 与 `&`、`parse_postfix` 的后缀 `++` / `--` 共**三处定点检查**（`is_range_index`），文案不变 | 错误位置就是运算符所在处；不依赖 kind 枚举是否完整，新增前缀 / 后缀形态时不会漏 |
| A2 | 负例 `range_index_address.ct` 一个文件里三个函数，覆盖 `&$` / `$++` / `++$` | 拆成 `range_index_address.ct`、`range_index_address_post.ct`、`range_index_address_pre.ct` | 编译器遇首个错误即停，一个文件只能命中一条；三条都要被门禁看到 |
| A3 | 逐字节层的手写期望写成 `{ ((int)0) * 2 + 1, … }` | 手写文件采用 ct 的规范形态 `{ ((((int)0) * 2) + 1), … }` | 生成物由既有 `emit_expr` 决定（每层运算各加括号）；先归一再 `cmp` 就等于放弃「形态一变即红」 |
| A4 | 全局作用域与块作用域"语法完全一致" | 单声明符一致；**一行多个声明符只有块作用域支持**（`117` 因此落在块作用域） | 这是 ct-ast 全局声明的既有边界，Phase 24 未改动，也不在本相出口判据内 |
| A5 | §7.3 形态断言「整份生成物不含 `for (`」 | 按**生成的声明行**断言 | 夹具自己要用 `for` 打印结果；整份文件断言会误杀 |

其余与设计一致：`N_INIT_RANGE 61`、`range_depth` / `range_k`、三处声明站点、`dollar_ok`
开关、维度里的 `$` 在声明符解析处统一 `strchr(text3, '$')`、边界读取器自校验拼写与
`LONG_MAX` 溢出（共享词法器未改）。

切片与提交：

| 切片 | 提交 | 内容 |
| --- | --- | --- |
| S1 | `692e5d9` | 解析：`$` primary、`dollar_ok`、`range_init_ahead`（深度 0 扫 `,` / `;`）、边界拼写与溢出、L24-1–L24-7/9–11、`N_INIT_RANGE`、16 个负例 |
| S2 | `6578a5d` | 发射：`emit_range_init`、`$` → `((int)k)`、三处声明站点、8 个正例（109–115、117） |
| S3 | `a736048` | 门禁：`check-ast.sh` Phase 24 块（形态 / 13 元素 / 逐字节 `cmp` / 运行输出 `cmp` / 文件作用域 / 16 条负例）、编辑器 grammar 的 `$` 规则与断言 |
| S4 | `6d23fb4` | language-spec §4.47、tutorial §10.4、roadmap、as-built 记录、`selfhost/**` 自举守卫 |
| S5 | `71c2a0b` | 收口：`CTC_VERSION` 五处同步到 `0.24.0`、74 个 golden 仅版本 token 变化、tag `v0.24.0`；整轮 `check-all.sh` 11 道硬门禁 `EXIT 0` |

---

## 13. 收口核对（2026-11-09）

逐条对本文件自己列的出口判据，证据取自 `selfhost/check-all.sh` 在 `v0.24.0` 上的整轮运行
（11 道硬门禁全绿，`EXIT 0`）。

| # | 判据 | 证据 | 结果 |
| --- | --- | --- | --- |
| 1 | §7.1 的 8 个正例（109–115、117）全绿 | `check-ast.sh` 765 passed / 0 failed，其中 Phase 24 块 21 条全 `ok` | ✔ |
| 2 | §7.2 的 16 个负例各命中预期文案，且都不落成 `undeclared` | `rng_neg()` 逐条 `grep` 文案 + `! grep -Fiq 'undeclared'` | ✔ |
| 3 | 逐字节层：`109` 与手写 13 项列表相同 | `grep 'int odd\[\] = {'` 后 `cmp -s`，`BYTE_EQUAL` | ✔ |
| 4 | 语义层：`109` 与普通字面量数组的运行输出相同 | 两程序编译运行、剔除 banner 后 `cmp -s` | ✔ |
| 5 | 文件作用域 `static const` 可用 | `110` 生成行 `static const int sq[] = { … };`，`main` 读数正确（`0 9 100`） | ✔ |
| 6 | 生成物是列表：无 `for`、无 `$`、无 `0..13` | 对生成**声明行**的形态断言（夹具自带手写 `for`，故按行取） | ✔ |
| 7 | 零 `-Wall -Wextra` 告警 | 门禁 9：`check-warnings: 239 ok, 0 failed`；行为循环同旗标编译 | ✔ |
| 8 | 既有 golden 功能层零变化 | 门禁 2：`check-goldens: OK (no regression, and the self-hosted rebuild agrees)` | ✔ |
| 9 | 编辑器 grammar 认 `$` | 门禁 6：`40 checks, 0 failed`（含 `$` 命中与字符串/注释内不命中） | ✔ |
| 10 | 自举守卫在位 | 门禁 8：`ok range initialisers in selfhost/** (allowed: v0.24.0 is tagged)` | ✔ |
| 11 | 版本收口 | `CTC_VERSION` 五处 `0.24.0`、74 个 golden 仅版本 token、tag `v0.24.0` → `73915d9` | ✔ |
| 12 | 文档同步 | language-spec §4.47（中英）、tutorial §10.4（中英）、roadmap 两行、本文 as-built；门禁 11：`check-docs: OK (804 relative links in 169 files, v0.24.0, …)` | ✔ |
| 13 | 不引入 kind 8 / `range_shadow`；共享词法器不改 | D24-4、L24-8 撤销；`0x` 与整数溢出由边界读取器重验；`selfhost/ct-ast/frontend/lex/**` 零改动 | ✔ |

遗留项（**不属于**本相出口判据）：全局作用域一行多声明符仍不支持
（A4，ct-ast 既有边界，`117` 因此落在块作用域）；`ct check` 的诊断种类表未变，range 初值的
语义错误仍走编译路径。

---

## English

### Status

**Implemented (as-built, 2026-11-09)**. S1–S5 have landed and the phase is closed at
**`v0.24.0`**. D24-1–D24-13 are final and the deviations from the plan are collected in §12
(Chinese; the numbered rows A1–A5 are the authoritative list).
**Revised 2026-11-09**: the index placeholder is `$` instead of `i` (it is not an identifier, so it
can never be shadowed or collide); D24-4 / L24-8 are revoked and no `range_shadow` kind is
introduced; bound literals get explicit spelling and overflow validation.

### Positioning

`loop(a..b)` iterates; this phase writes the same sequence **declaratively, as an initializer**:

```c
int odd[] = 0..13($ * 2 + 1);            /* 1, 3, 5, …, 25 */
static const int sq[] = 0..11($ * $);    /* 0, 1, 4, …, 100 */
```

It expands to a braced initializer list, never to a loop:

```c
int odd[] = { ((((int)0) * 2) + 1), ((((int)1) * 2) + 1), …, ((((int)12) * 2) + 1) };
```

Because the output is an initializer and not a statement, file scope, `static` and `const` all
work — the one thing a `for`-based lowering could never deliver.

### Rules

- **Bounds are integer literals** (optional unary `-`), evaluated at parse time; `count = end - start`.
  `count <= 0` is a hard error; `count > 1024` is a hard error. No macro / `enum` / expression
  bounds: the symbol table records `is_const`, not values, and CT never folds constants. The bound
  reader re-validates the literal's original spelling (at least one digit, `U` / `L` suffix only)
  and checks `LONG_MAX`, because the shared lexer does neither; the lexer itself is left untouched.
- `$` is a new punctuation token, **not an identifier**. It is accepted only inside the range
  initializer's element expression and rendered as `((int)k)` per element. There is no scope, no
  symbol registration and no shadowing: `$` outside the element expression is a syntax error, and
  `$ = 1` / `&$` / `$++` / `++$` are hard errors ("the range index '$' is not a variable"), never
  "undeclared variable". `$` may appear several times in one element expression.
- Elements must be scalars; `struct` / `union` / interface / array elements are hard errors.
  `[]` is left to C; a literal extent must equal `count`; any other extent is emitted as written.
  A `$` in the extent is rejected (L24-10) rather than leaking into C.
- Element expressions are re-evaluated **once per element, in unspecified order** (C99 §6.7.8), so
  the documented rule is "no side effects". At file scope and for `static` objects C additionally
  requires a constant expression.
- The element AST is stored once (`N_INIT_RANGE`, kind 61) and re-emitted with `$` substituted at
  emission time; the node count does not grow with `count`.

### Diagnostics

`L24-1` missing bound, `L24-2` non-literal or malformed bound (including `0x`), `L24-3` empty range,
`L24-4` over the 1024 cap, `L24-5` on a declaration without a dimension, `L24-6` non-scalar element,
`L24-7` literal extent mismatch, `L24-9` bound out of `long` range, `L24-10` `$` in a dimension,
`L24-11` assignment / address-of / increment on `$` — all errors. `L24-8` is retired and its number
is not reused; no new warning kind is added and `ct check` is unchanged.

### Non-goals

Runtime bounds / VLAs, `Vec` / generics / custom containers, `each` in this phase, standalone
`a..b` expressions, step / closed ranges, CT-side constant folding, and `.m.ct` involvement.
§10 records where `each` went: the **method form** `a.each(n, closure)` is Phase 25,
which extends the `(fn, env)` expansion to static mapping calls; the **statement form**
`each (nums) { … }` is still unplanned, because C macros cannot take a block. Note that a decayed
`int *` still cannot know its length and `int *p` matches the same type host as `int a[4]`, so the
element count stays explicit in Phase 25 as well. The old placeholder keyword `each` was voided by
D25-12; the statement form is now named `foreach`.
