# Phase 22 · `loop` 循环语法糖

> 中文 · [English](#english)
>
> **状态：规划中**（2026-11-07；语义口径已定稿，仅落规划，不含实现）。
> **版本口径：Phase 22 ↔ `v0.22.x`，收口 bump 到 `v0.22.0`。** 当前 `v0.19.1`。
> 关联：`phase20.md`（包支持）、`phase21.md`（闭包）、
> [roadmap.md](../roadmap.md)、[language-spec.md](../language-spec.md)。
> 本相只新增一条语句级语法糖，**不改动现有语义、不新增运行时、不引入抽象类型**。

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

---

## 2. 语法形态

```text
loop-stmt  :=  "loop" "(" expr ")" block
```

- 计数表达式是一个 `expr`，两侧括号必需，body 必须是块 `{ … }`。
- body 内隐式声明 `int i`，从 0 起，作用域为 body（含展开后的条件与自增）。
- `loop(0)`、负数均为零次迭代；不报错。
- 不做 `loop(n, name)`；不省略括号；不允许单语句 body。

### 2.1 上下文相关关键字

`loop` **不是保留字**，按上下文识别：

| 位置 | 判定 |
| --- | --- |
| 语句位置，且下一个 token 是 `(` | 按 `loop` 语句解析 |
| 其余任何位置（表达式、`goto` 目标、字段 / 方法名、字符串、注释） | 仍是普通标识符 |

识别方式沿用仓库既有的「无 peek 则保存并回退」写法
（`label_ahead` / `record_body_ahead`，见 [Stmt.h.ct](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1135-L1160)
与 [Parser.h.ct](../../selfhost/ct-ast/frontend/parse/Parser.h.ct#L1116-L1140)）：
新增 `loop_ahead()`，当前 token 是 `loop` 时保存词法器状态、读下一个 token、判断是否为 `(`、再完整回退。

**已知代价**：语句位置上，用户自定义的 `loop(...)` 函数调用会被当成关键字，随后因缺 block 报错。
这是上下文关键字的固有取舍，用下面的语料扫描结果作为接受依据。

### 2.2 语料扫描（2026-11-07）

扫描范围：本仓库 `**/*.ct`、`**/*.c`、`**/*.h`（含 `examples/`、`bindings/`、`test/`），
以及同级 `ct-pkg/**` 的包源码；模式 `\bloop\b` 与 `\bloop\s*\(`。

| 结果 | 位置 | 是否与上下文规则冲突 |
| --- | --- | --- |
| 0 处 `loop(` 调用 | — | 否 |
| 1 处标签 `loop:` + 1 处 `goto loop;` | `test/ast/32_goto/prog.ct:32,36` | **否**（标签后是 `:`；`goto` 后是表达式位置） |
| 其余全部为注释 / 文档散文 | 如 `docs/architecture.md` 的 "main loop" | 否 |
| `ct-pkg` 内 3 处 | `net-posix` 的注释 | 否 |

结论：**按上述上下文规则，现有语料零冲突、零 golden 预期变化。**
该扫描需在实现开工时重跑一次；若届时新增了 `loop(...)` 语句调用，先改调用方或退回命名。

---

## 3. 语义规则

### 3.1 展开形式

```ct
loop(N) { BODY }
```

展开为**一行** `for`，计数只求值一次：

```c
for (int i = 0, __ct_loop_n_K = (N); i < __ct_loop_n_K; i++) { BODY }
```

- `__ct_loop_n_K` 的 `K` 取发射器现有的临时计数器（`__ct_ret%d` 同一套），
  每函数内单调递增；`__ct_` 前缀为生成物保留，用户不可声明。
- 边界值 `N` 存入 `int` 临时量（与 `i` 同型），因此计数范围是 `int` 范围；
  超出范围属于未定义场景，不在本相承诺内。
- 展开只有一条语句，不引入辅助函数、结构体或回调。

### 3.2 计数只求值一次

- `N` 在进入循环时求值一次并存入临时量；body 修改 `N` 依赖的变量**不影响**迭代次数。
- 不得展开成 `for (int i = 0; i < (N); i++)`——那会每轮重算，**明确禁止**。
- `continue` 不重新求值；`break` 直接离开。

### 3.3 `i` 的语义

- `i` 是 body 作用域内的普通 `int`，可写、可自增、可传给任何接受 `int` 的位置。
- 行为与原生 `for (int i = 0; …; i++)` 的循环变量完全一致：
  body 改写 `i` 会影响下一次条件判断；自增发生在每轮 body 之后。
- `i` 只在 body（含条件与自增）可见；循环之后不可见，也不泄漏到外层作用域。
- 不参与 `own` / AutoDrop：`int` 无 Drop，泄漏与借用分析不变。
- `break` / `continue` / `return` / `goto` 的既有规则原样继承，不新增限制。

### 3.4 嵌套与遮蔽（定稿结论）

**语义上允许遮蔽，`ct check` 判为错误，编译模式只告警。**

理由：

1. `loop` 的承诺是「与原生 `for` 等价」。原生 `for` 允许内层块重新声明 `i`；
   若在解析层直接禁止，`loop` 就与 `for` 分叉，违背第 1 节的定义。
2. 隐式变量无法改名（本相不做 `loop(n, name)`），嵌套时遮蔽不可避免；
   完全禁止会让「嵌套 `loop`」不可用，损失大于收益。
3. 仓库已有成熟的严重度策略（19.1–19.3）：编译模式 warning、`ct check` 升为 error。
   遮蔽恰好属于「语义明确但可疑」，沿用同一策略，不新造规则。

诊断只针对**内层 `loop` 遮蔽外层 `loop` 的隐式 `i`**。用户在 body 里显式写 `int i`
属于原生 `for` 也允许的写法，不新增诊断。

### 3.5 生成物可读性

- 只展开为一行 `for`，不产生额外抽象层。
- `--line` 模式下，该 `for` 行前由既有语句路径重锚 `#line <loop 所在行> "<源文件>"`，
  运行期错误能映回 `.ct`；默认模式与现有语句一致，不额外插入指令。
- 生成物中不出现 `loop` 字样，也不会生成注释以外的辅助符号。

---

## 4. 诊断

| 编号 | 场景 | 文案 | 严重度 |
| --- | --- | --- | --- |
| L22-1 | `loop` 后缺 `(` 或计数 | `loop needs a count expression` | error（语法） |
| L22-2 | 计数后不是 `{` | `loop body must be a block` | error（语法） |
| L22-3 | `loop(n, name)` | `loop takes exactly one count; use a native for to name the counter` | error（语法） |
| L22-4 | 嵌套 `loop` 遮蔽外层 `i` | `loop shadows the outer 'i'; use a native for to name the inner counter` | 编译 warning；`ct check` error |
| L22-5 | 计数类型静态可确定为非整数 | `loop count must be an integer (got 'float'); the count is truncated to int` | 编译 warning；`ct check` error |

规则细节：

- L22-4 新增 `Warn.kind = 7`；`ct check` 的严格化沿用 19.4 的判定，与 kind 4/5/6 同列。
- L22-5 复用 `record_type_warn`（kind 5），callee 记为 `loop`；只在类型**能静态确定**时报：
  整数字面量、已知声明类型的变量 / 字段、已知返回类型的调用。未知类型（不透明调用、
  无法解析的表达式）**不报**，宁漏不误报。
- 整型范围：`char` / `short` / `int` / `long` / 无符号各型 / `enum` / `_Bool` / `size_t` 均接受；
  `float` / `double` / 指针 / 结构体在可判定时诊断。
- 所有诊断都带 `file:line:col`，与既有 `ct_sem_error` / `Warn` 路径一致。
- 语法错误不产生部分 AST；L22-4 / L22-5 不改变生成物。

---

## 5. 验收判据

### 5.1 正例

| 编号 | 用例 | 判据 |
| --- | --- | --- |
| P22-1 | `loop(3) { print(i); }` | 输出 `0 1 2` |
| P22-2 | `int n = 3; loop(n) { n = 100; print(i); }` | 恰好 3 轮，证明只求值一次 |
| P22-3 | body 内 `i = 3` | 迭代序列与等价原生 `for` 逐项一致 |
| P22-4 | `break` / `continue` | 与等价原生 `for` 行为一致（`continue` 后仍自增） |
| P22-5 | `loop(0)` / `loop(-5)` | 0 轮，退出码 0，无诊断 |
| P22-6 | 嵌套 `loop(2) { loop(2) { … } }` | 4 轮；编译有 L22-4 warning |
| P22-7 | 表达式位置的 `loop` 标识符、`loop:` 标签 | 编译行为与改动前一致（`test/ast/32_goto` 保持 byte-identical） |

### 5.2 负例

| 编号 | 用例 | 判据 |
| --- | --- | --- |
| N22-1 | `loop(3, x) { … }` | 语法错误 L22-3，含 native for 提示 |
| N22-2 | `loop() { … }` | 语法错误 L22-1 |
| N22-3 | `loop(3) print(i);` | 语法错误 L22-2 |
| N22-4 | `loop(2.5) { … }` | `ct check` 报 L22-5；普通构建只告警 |
| N22-5 | 嵌套 `loop` | `ct check` 非零退出（L22-4 升为 error） |

### 5.3 golden 影响

- **预期现有 golden 变化数：0。** 依据：§2.2 扫描无 `loop(` 语句调用；
  `loop` 关键字只在语句位置且紧跟 `(` 时生效。
- 新增 `test/ast/` 下的正例 / 负例会带来**新增** golden 文件，不改旧文件。
- `selfhost/check-goldens.sh`（L1/L2 冻结线）不涉及本相；`check-ast.sh` 的既有 fixture
  应全部保持 byte-identical，新增 fixture 单独计数。
- 实现完成后用 `git diff --stat -- test/` 复核：只允许新增目录，不允许既有 expected 文件改动。

### 5.4 待实测假设（不作为既成事实）

**H22-1：`i` 未被使用的 `loop` 必须零告警。**

- 现状未知：CT 是否对未使用的局部变量告警需要在实现前实测
  （`loop(3) { printf("x"); }`，分别在默认模式与 `--diagnostics` 下）。
- 判据：两种模式都不得新增任何 warning；`ct check` 也不得产生 finding。
- 若现状会告警：修复方向是**对隐式 `i` 豁免未使用诊断**，而不是要求用户使用 `i`；
  该修复计入本相验收，不得以「本来就会告警」结案。
- 在实测完成前，本条按**待验证**记录，不写成「已保证零告警」。

---

## 6. 与其它阶段的依赖关系

| 阶段 | 关系 | 说明 |
| --- | --- | --- |
| Phase 20（包支持） | **无语义依赖** | `loop` 不改变包解析、映射、`requires`、索引或命名空间；包可以用 `loop`，但不是包支持的前置 |
| Phase 21（闭包） | **无语义依赖** | 闭包是表达式与逃逸分析；`loop` 是语句展开。两者可独立实施、独立验收 |
| Phase 17/18/19 | 只读依赖 | 复用 19.x 的诊断严重度策略与 `ct check` 严格化；不改其行为 |
| L0/L1/L2 | 不触碰 | 三个冻结层不新增语法；实现只落 `selfhost/ct-ast/**` |

**并行性**：语义上可与 20/21 并行；工程上三者都会触碰
`frontend/parse/Stmt.h.ct` / `backend/emit/Emitter.h.ct` / `tool/diag/Diag.h.ct`，
合并冲突是唯一耦合。建议按「谁先合并谁先跑全门禁」的次序串行合入，而不是语义上排队。

**自举纪律**：本相不要求编译器源码使用 `loop`。顺序是「先让编译器认识 `loop`，
再（可选地）在后续提交中使用」；编译器自身源码在 `v0.22.0` 前保持原生 `for`，
避免出现「编译器自己先用了新语法、却还没有能力编译自己」的倒挂。

---

## 7. 实现切点

| 切点 | 文件 | 内容 |
| --- | --- | --- |
| 22.1 识别 | `frontend/parse/Stmt.h.ct` | `loop_ahead()`（保存/回退词法器状态）；`parse_stmt` 的语句分派 |
| 22.2 作用域 | `frontend/parse/Stmt.h.ct` | 新节点 `N_LOOP`；push scope 并登记隐式 `int i`，body 正常解析 |
| 22.3 发射 | `backend/emit/Emitter.h.ct` | 单行 `for` + `__ct_loop_n_K`；沿用语句的 `#line` 路径 |
| 22.4 诊断 | `tool/diag/Diag.h.ct` + 解析器 | kind 7 遮蔽告警；L22-5 复用 kind 5；`ct check` 严格化 |
| 22.5 测试 | `test/ast/` | §5 正例 / 负例；golden 增量 |
| 22.6 文档 | `docs/language-spec.md`、`docs/tutorial.md` | 展开规则、上下文关键字、边界 |

实现策略选择：**新增 `N_LOOP` 节点**，不在解析期降级成 `N_FOR`。
理由：`i` 需要在解析期进入符号表；计数临时量的命名与 `#line` 由发射器统一处理，
合成声明节点反而更绕。

---

## 8. 里程碑

| 里程碑 | 内容 | 出口 |
| --- | --- | --- |
| M22-A | 22.1 + 22.2 + 22.3 | P22-1/2/3/5 通过；生成物为单行 `for` |
| M22-B | 22.4 | N22-1…N22-5 全部按预期诊断；既有诊断无变化 |
| M22-C | 22.5 + H22-1 实测 | 正负例全绿；既有 golden 零变化；`i` 未使用零告警 |
| M22-D | 22.6 + 全门禁 | 11 道硬门禁 + fixpoint 全绿；收口 `v0.22.0` |

---

## 9. 风险

| 编号 | 风险 | 应对 |
| --- | --- | --- |
| R1 | 语句位置的 `loop(...)` 函数调用被误判为关键字 | §2.2 扫描为 0；实现前重跑；报错文案给出「rename the function or call it in an expression」 |
| R2 | 计数每轮重算 | 展开必须带 `__ct_loop_n_K` 临时量；P22-2 作为回归 |
| R3 | 嵌套遮蔽被静默接受 | L22-4 在编译告警、`ct check` 报错；N22-5 验收 |
| R4 | 隐式 `i` 触发未使用告警 | H22-1 待实测；若触发则修诊断豁免，不要求用户使用 |
| R5 | 新增节点影响既有 golden | N_LOOP 只在源码出现 `loop` 时产生；既有 fixture 不含 `loop` 语句 |
| R6 | 计数为 `long` / 无符号时截断 | 临时量与 `i` 同为 `int`；文档写明范围；`ct check` 对可判定的非整数报 L22-5 |

---

## 10. 已定决策

| 编号 | 决策 |
| --- | --- |
| D22-1 | 形态固定为 `loop(<次数>) { … }`，不做命名变体 |
| D22-2 | 隐式变量固定为 `int i`，从 0 起，body 作用域内可写 |
| D22-3 | 计数只求值一次，用 `for` 初始化段的临时量实现 |
| D22-4 | `loop` 是上下文相关关键字：仅语句位置 + 紧跟 `(` |
| D22-5 | 嵌套遮蔽：语义允许，编译 warning，`ct check` error |
| D22-6 | 0 / 负数零次迭代且不报错；非整数在 `ct check` 诊断 |
| D22-7 | 生成物为单行 `for`；`--line` 模式下带 `#line`，不引入抽象 |
| D22-8 | 本相只规划，不改源码 / 测试 / golden / 版本号 |

---

## English

### Positioning

`loop(n) { … }` is a zero-cost shorthand for `for (int i = 0; i < n; i++)`. It introduces no
runtime, no helper types and no new semantics: the generated C is a single `for` line with the
count evaluated exactly once into a temporary (`__ct_loop_n_K`).

### Syntax and semantics

- Form: `loop(<count>) { <block> }`; the block is mandatory, the count is one expression.
- The body sees an implicit `int i` starting at 0. It is an ordinary writable variable with the
  same behaviour as a native `for` counter; `break` / `continue` / `return` / `goto` are unchanged.
- `loop` is a **contextual keyword**: only in statement position immediately followed by `(`.
  Everywhere else it stays an identifier. A 2026-11-07 scan found **0** `loop(` call sites; the only
  code use is the label `loop:` in `test/ast/32_goto/prog.ct`, which the rule does not touch.
- `loop(0)` and negative counts iterate zero times without an error. A non-integral count is a
  compile warning and a `ct check` error when its type is statically known.
- Nested `loop`s shadow the outer `i`. Semantics follow native `for`; the compiler warns and
  `ct check` raises it to an error.

### Diagnostics and acceptance

- Parse errors: missing count, non-block body, `loop(n, name)` (the last one points at native `for`).
- Existing goldens are expected to change by **0**; new fixtures add new files only.
- Open hypothesis H22-1: an unused implicit `i` must produce zero warnings; this must be measured
  before implementation and, if wrong, fixed by exempting the implicit counter rather than changing
  the user model.

### Dependencies

Phase 20 (package support) and Phase 21 (closures) have **no semantic dependency** on this phase.
All three touch the same parser / emitter / diagnostics files, so only merge order couples them.
L0/L1/L2 stay frozen; the implementation lands in `selfhost/ct-ast/**` and closes at `v0.22.0`.
