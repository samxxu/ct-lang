# Phase 23 · `loop` 范围语法（`loop(a..b)`）

> 中文 · [English](#english)
>
> **状态：规划中**（2026-11-07；仅落规划，不含实现。2026-11-08 勘误：Phase 22 已随 `v0.22.0` 落地，
> 本相可直接在 `parse_loop` / `N_LOOP` 的 `b` 槽上接双界，`loop_depth` 在 `struct Stmt`）。
> **版本口径：Phase 23 ↔ `v0.23.x`，收口 bump 到 `v0.23.0`。** 前置 `v0.22.0`。
> 关联：[phase22.md](phase22.md)（`loop(n)`，本相前置）、[roadmap.md](../roadmap.md)、
> [language-spec.md](../language-spec.md)。Phase 20（包支持）、Phase 21（闭包）见 `phase20.md` / `phase21.md`。
> 本相只给 `loop` 增加「显式起点」形态：**不改已定稿语义、不新增类型、不新增运行时**。
> **提案基线**：本相源自一份基于 v0.12.0 的外部提案；其中「lexer `..` 特判」「`borrow` 前置」「`ct check` 待建」「C89 前提」等已由后续版本解决，本相不再重复处理。

---

## 1. 定位

`loop(a..b)` 是 `loop(n)` 的**显式起点**形态：把「从 `a` 数到 `b - 1`」写成一行。

**定义级等式**：

```text
loop(a..b)  ≡  for (int i = a; i < b; i++) { … }
loop(0..n)  ≡  loop(n)
```

边界语义固定为**左闭右开** `[a, b)`：`i` 从 `a` 起，取到 `b - 1`；`b <= a` 时零次迭代。
不做反向遍历，不做步长，不做闭区间。

判断标准与 Phase 22 相同：**展开后的 C 与手写原生 `for` 等价，且更短。**

### 1.1 本相不做（防止同一批提案被反复重提）

| 不做的东西 | 一句话理由 |
| --- | --- |
| `r = 2..8` 独立区间表达式 | 无类型推断，`r` 的目标类型无处安放；落到 `Range` trait 还要装箱，与零成本冲突 |
| `int a[] = 2..8` 编译期展开 | 需要魔法上限（如 256）与一批新诊断，收益最低，直接砍掉 |
| 步长变体（`loop(a..b step s)` / 反向） | 需要步长就写原生 `for`，`loop` 只覆盖步长 1 |
| `Range` trait + `each` | 硬依赖 Phase 21 闭包档②，且与「无泛型 / 零成本」冲突；留待闭包落地后再评 |
| `loop(..b)` / `loop(a..)` 半开边界 | 两侧都必须有表达式；缺任一侧退回 `loop(n)` 或原生 `for` |

本相只做上表之外的那一件事：`loop(a..b)`。

---

## 2. 语法形态

```text
loop-stmt  :=  "loop" "(" ( expr | expr ".." expr ) ")" block
```

- `a`、`b` 各是一个 `expr`；`..` 两侧不允许省略。
- `loop(n)`（Phase 22）与 `loop(a..b)`（本相）共用同一个 `loop` 语句入口，按 `)` 前是否出现 `..` 分派。
- `loop` 仍是上下文相关关键字（Phase 22 §2.1），本相不新增识别规则。
- body 必须是块；不做单语句 body；不做命名变体。

### 2.1 `..` 的词法现状

`..` **不是新 token**：词法器已保证 `2..8` 不会被切成浮点 `2.` + `.8`
（[Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L148-L155) 只在小数点后不是 `.` 时才算浮点），
`...` 也已单词化（[Lexer.h.ct](../../selfhost/ct-ast/frontend/lex/Lexer.h.ct#L219-L229)）。
因此 `2..8` 在词法层是 `NUM(2)` `PUNCT(.)` `PUNCT(.)` `NUM(8)`；
解析器在 `loop` 的参数位置识别「`.` 紧跟 `.`」即可，**不需要改词法器**。

> 提案里「`2..8` 的 lexer 浮点误切特判」这一项，在当前版本已经是既有机制，删除。

---

## 3. 语义规则

### 3.1 展开形式

```c
for (int __ct_loop_a_K = 0, __ct_loop_hi_K = 0, i = ((__ct_loop_a_K = (a)), (__ct_loop_hi_K = (b)), __ct_loop_a_K); i < __ct_loop_hi_K; i++) { BODY }
```

- 只有一条 `for`，不引入辅助函数、结构体或回调。
- `i` 的初值取 `a` 的快照；条件与自增与原生 `for` 完全相同。
- 两个临时量与 `i` 同为 `int`，命名沿用发射器的临时计数器（与 Phase 22 的 `__ct_loop_n_K` 同一套）。
- 两侧边界都先落到临时量，循环过程中修改 `a` / `b` 依赖的变量不影响本次迭代次数。

### 3.2 求值顺序与次数

- **先 `a` 后 `b`，各求值一次。**
- 实现方式：两个边界放在**同一个初始化表达式**里，用逗号运算符保证先 `a` 后 `b`；
  不依赖多个声明符初始化器之间的求值次序（C 不对此作保证）。
- 明确禁止展开成 `for (int i = (a); i < (b); i++)`——那会每轮重算 `b`，且 `a` 与 `b` 的求值次数不受控。

### 3.3 `i` 的语义

- 单一 `int`，从 `a` 起；作用域、可写性、不参与 `own` / AutoDrop，全部沿用 Phase 22 §3.3。
- `loop(0..n)` 与 `loop(n)` **等价**：同一起点、同一上界、同一迭代次数、同一生成物语义。
- `b <= a` 时零次迭代，不报错、不告警。

### 3.4 嵌套与遮蔽

沿用 Phase 22 D22-5，**不新增第二套规则**：

- 嵌套 `loop` 遮蔽外层 `i`：语义允许（与原生 `for` 一致），编译 warning，`ct check` error（L22-4）。
- 本相不引入 `i1` / 按深度改名的隐式变量；`loop` 的隐式变量永远叫 `i`。
- 用户显式写 `int i` 仍不新增诊断，与 Phase 22 §3.4 相同。

### 3.5 边界类型

- 整型（`char` / `short` / `int` / `long` / 无符号各型 / `enum` / `_Bool` / `size_t`）接受。
- 非整数在类型**静态可确定**时诊断：编译 warning、`ct check` error（沿用 L22-5 的严重度与 kind 5）。
- 边界值存入 `int` 临时量，计数范围是 `int` 范围；超出范围属未定义场景，不在本相承诺内。

### 3.6 生成物可读性

- 仍是一条 `for`，不产生抽象层。
- **不新增逐语句 `#line`**（与 Phase 22 §3.7 一致）：发射器只有单元级 `#line 1 "<path>"` 与
  raw / 闭包产物的个别重锚，既有语句路径**不会**为单条语句重新锚定；`--line` 下双界 `loop`
  与单界 `loop` 的可读性相同——生成行号与源行号不保证逐行对齐。
- 生成物中不出现 `loop` 或 `..` 字样。

---

## 4. 诊断

| 编号 | 场景 | 文案 | 严重度 |
| --- | --- | --- | --- |
| L23-1 | `loop(..b)` / `loop(a..)` | `a loop range needs both bounds` | error（语法） |
| L23-2 | 边界类型静态可确定为非整数 | 复用 L22-5 文案，callee 记为 `loop` | 编译 warning；`ct check` error |

规则细节：

- Phase 22 的 L22-1…L22-5 原样适用于 `loop(a..b)`；本相只新增 L23-1，L23-2 是 L22-5 对两个边界的覆盖。
- `b <= a` **不诊断**：零次迭代是合法语义。
- 嵌套遮蔽仍是 L22-4，不新增编号、不改严重度。
- 所有诊断带 `file:line:col`。

---

## 5. 验收判据

### 5.1 正例

| 编号 | 用例 | 判据 |
| --- | --- | --- |
| P23-1 | `loop(2..5) { print(i); }` | 输出 `2 3 4` |
| P23-2 | `loop(0..n)` 与 `loop(n)` 对照 | 迭代序列与生成物语义一致（定义级等式） |
| P23-3 | `loop(f()..g())`，`f` / `g` 各带副作用 | 各调用一次，且先 `f` 后 `g` |
| P23-4 | body 内修改 `a` / `b` 依赖的变量 | 迭代次数不变 |
| P23-5 | `loop(5..2)` / `loop(3..3)` | 0 轮，退出码 0，无诊断 |
| P23-6 | `break` / `continue` / body 内写 `i` | 与等价原生 `for` 逐项一致（`continue` 后仍自增） |
| P23-7 | 嵌套 `loop(0..2) { loop(1..3) { … } }` | 4 轮；编译有 L22-4 warning |
| P23-8 | 表达式位置的 `loop` 标识符、`loop:` 标签 | 与改动前 byte-identical |

### 5.2 负例

| 编号 | 用例 | 判据 |
| --- | --- | --- |
| N23-1 | `loop(..3) { … }` / `loop(2..) { … }` | 语法错误 L23-1 |
| N23-2 | `loop(2.5..5) { … }` / `loop(2..5.5) { … }` | `ct check` 报 L23-2；普通构建只告警 |
| N23-3 | 嵌套 `loop(a..b)` | `ct check` 非零退出（L22-4 升为 error） |

### 5.3 golden 影响

- **预期现有 golden 变化数：0。** `loop` 仍只在语句位置 + 紧跟 `(` 时生效；`..` 只在 `loop` 参数内部被识别，不改变任何既有表达式的解析。
- 新增正负例只新增 `test/ast/` 文件，不改既有 expected。

### 5.4 待实测假设

**H23-1：`loop(a..b)` 的两个边界临时量与 `i` 都不触发未使用告警。**

- 与 Phase 22 的 H22-1 同源；`i` 未使用、边界只写一次都必须零告警。
- 在实测完成前按**待验证**记录；若现状会告警，修复方向是豁免隐式计数与临时量，而不是要求用户使用。

---

## 6. 与其它阶段的依赖关系

| 阶段 | 关系 | 说明 |
| --- | --- | --- |
| Phase 22（`loop(n)`） | **硬前置** | 复用 `N_LOOP`、`loop_ahead()`、隐式 `i`、L22-4；本相只扩展参数形态 |
| Phase 20（包支持） | **无语义依赖** | 不改包解析、映射、`requires`、索引或命名空间 |
| Phase 21（闭包） | **无语义依赖** | 本相不涉及闭包、逃逸或 `(fn, env)` ABI |
| Phase 17/18/19 | 只读依赖 | 复用 `ct check` 严格化与诊断严重度策略 |
| L0/L1/L2 | 不触碰 | 三个冻结层不新增语法；实现只落 `selfhost/ct-ast/**` |

**合并次序**：三相共用 `Stmt.h.ct` / `Emitter.h.ct` / `Diag.h.ct`，语义无依赖，冲突只来自合并次序。
Phase 23 必须在 Phase 22 之后合入（它修改同一段 `loop` 解析）。

**自举纪律**：本相不要求编译器源码使用 `loop(a..b)`；编译器自身源码在 `v0.23.0` 前保持原生 `for`。

---

## 7. 实现切点

| 切点 | 文件 | 内容 |
| --- | --- | --- |
| 23.1 识别 | `frontend/parse/Stmt.h.ct` | 在 `loop` 参数位置识别「`.` 紧跟 `.`」；无 peek，沿用保存 / 回退词法器状态 |
| 23.2 AST | `frontend/parse/Stmt.h.ct` | `N_LOOP` 增加「单界 / 双界」两种形态；隐式 `i` 照旧 |
| 23.3 发射 | `backend/emit/Emitter.h.ct` | 三临时量单行 `for`；逗号运算符保证先 `a` 后 `b`；不新增逐语句 `#line` |
| 23.4 诊断 | `tool/diag/Diag.h.ct` + 解析器 | L23-1；L23-2 复用 kind 5；`ct check` 严格化 |
| 23.5 测试 | `test/ast/` | §5 正负例；golden 增量 |
| 23.6 文档 | `docs/language-spec.md`、`docs/tutorial.md` | 区间语义、求值顺序、与 `loop(n)` 的等式 |

---

## 8. 里程碑

| 里程碑 | 内容 | 出口 |
| --- | --- | --- |
| M23-A | 23.1 + 23.2 + 23.3 | P23-1/2/3/5 通过；生成物为单行 `for` |
| M23-B | 23.4 | N23-1…N23-3 按预期诊断；L22-4 无变化 |
| M23-C | 23.5 + H23-1 实测 | 正负例全绿；既有 golden 零变化 |
| M23-D | 23.6 + 全门禁 | 11 道硬门禁 + fixpoint 全绿；收口 `v0.23.0` |

---

## 9. 风险

| 编号 | 风险 | 应对 |
| --- | --- | --- |
| R1 | `..` 与成员访问 `.` 混淆 | 只在 `loop` 参数内部识别「`.` `.`」；参数外仍是单 `.`，`a.b.c` 不受影响 |
| R2 | 边界每轮重算或求值顺序不定 | 两个边界放进同一初始化表达式，逗号运算符保证「先 `a` 后 `b`」；P23-3 回归 |
| R3 | `loop(1...5)` 被当成 `...` | `...` 已是独立 token；`..` 要求恰好两个 `.`，三连点按语法错误处理 |
| R4 | 与 Phase 22 的 `loop(n)` 分派打架 | 共用入口，按 `)` 前是否出现 `..` 分派；P23-2 守住等式 |
| R5 | 隐式 `i` / 临时量触发未使用告警 | H23-1 待实测；若触发则修诊断豁免 |
| R6 | 边界为 `long` / 无符号时截断 | 临时量与 `i` 同为 `int`；文档写明范围；`ct check` 对可判定的非整数报 L23-2 |

---

## 10. 已定决策

| 编号 | 决策 |
| --- | --- |
| D23-1 | 形态固定为 `loop(a..b) { … }`，半开区间 `[a, b)` |
| D23-2 | `loop(0..n)` 与 `loop(n)` 等价，二者共用同一语句入口 |
| D23-3 | 两个边界各求值一次，顺序为先 `a` 后 `b` |
| D23-4 | `i` 仍是单一 `int`，从 `a` 起；作用域与可写性沿用 Phase 22 |
| D23-5 | 嵌套遮蔽沿用 L22-4（编译 warning、`ct check` error），不新增规则 |
| D23-6 | `b <= a` 零次迭代，不报错、不告警；非整数边界归 L23-2 |
| D23-7 | 生成物为单行 `for`，**不新增**逐语句 `#line`（与 D22-7 同口径） |
| D23-8 | 本相只规划，不改源码 / 测试 / golden / 版本号 |

---

## English

### Positioning

`loop(a..b)` is the explicit-start form of Phase 22's `loop(n)`: it counts from `a` up to `b - 1`.

```text
loop(a..b)  ≡  for (int i = a; i < b; i++) { … }
loop(0..n)  ≡  loop(n)
```

The range is **half-open** `[a, b)`; `b <= a` iterates zero times. No reverse iteration, no step,
no closed ranges. The acceptance test is the same as Phase 22: the lowered C must be equivalent to
the hand-written `for`, only shorter.

### Out of scope

| Not done | One-line reason |
| --- | --- |
| `r = 2..8` as a standalone expression | no type inference; a `Range` target would need boxing, contradicting zero cost |
| `int a[] = 2..8` compile-time expansion | needs an arbitrary cap and new diagnostics for little value |
| step / reverse variants | write a native `for` when you need a step |
| `Range` trait + `each` | hard dependency on Phase 21 closures; conflicts with "no generics / zero cost" |
| half-open `loop(..b)` / `loop(a..)` | both bounds are required |

### Syntax and semantics

- `loop` stays a contextual keyword; the parameter is either `expr` (Phase 22) or `expr ".." expr`.
- `..` is not a new token: the lexer already keeps `2..8` from becoming a float, and `...` is a
  single token. The parser only recognises `.` followed by `.` inside the `loop` parameter list.
- Both bounds are evaluated **exactly once**, `a` before `b`. The emitter puts them in one initializer
  expression so the comma operator, not declarator order, guarantees the sequence.
- `i` is the same single writable `int` as Phase 22, now starting at `a`; scope, shadowing and the
  warning / `ct check` error split are unchanged.
- `b <= a` iterates zero times without a diagnostic; a statically non-integral bound is a compile
  warning and a `ct check` error.

### Diagnostics and acceptance

- L23-1: a range with a missing bound is a syntax error.
- L23-2: a non-integral bound reuses the L22-5 severity (warning in compile mode, error under `ct check`).
- Existing goldens are expected to change by **0**; new fixtures add new files only.
- Open hypothesis H23-1: the two bound temporaries and an unused `i` must produce zero warnings.

### Dependencies

Phase 22 is a **hard prerequisite** (same `N_LOOP`, `loop_ahead()`, implicit `i`, L22-4). Phase 20
and Phase 21 have **no semantic dependency**; all share the parser / emitter / diagnostics files, so
only merge order couples them. L0/L1/L2 stay frozen; the implementation lands in `selfhost/ct-ast/**`
and closes at `v0.23.0`.
