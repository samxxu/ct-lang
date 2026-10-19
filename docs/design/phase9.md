# Phase 9 设计（已冻结）：AST 版编译器（新主线）

> 中文 · [English](#english)
>
> **状态：设计已冻结（2026-10-18）；9.1–9.7 已全部落地（同日收口 v0.9.0），Phase 10 起该实现是安装入口的主线。**
> D28–D37 全部定案；冻结的是设计契约，实现按 §7 的切片推进并已逐片交付。
> 主线切换、L2 的回归 oracle 角色与回退 tag 见 [phase10.md](phase10.md)。
> 决策编号从 **D28** 起（D21–D27 见 [phase8.md](phase8.md)）。

---

## 中文

### 1. 范围与目标

现有编译器（L2，`selfhost/src/**`）是**行重写**架构：逐行扫描、按前缀匹配改写、原样透传。
它足以支撑到 Phase 8，但三类需求都要求真正的语法树：

1. **类型检查**（路线图长期待定项）——没有 AST 只能做文本启发，误报不可避免；
2. **结构化诊断**——错误定位、恢复与跨行语义判断都需要节点；
3. **AST 主线本身**——2026-10-17 用户已决定「AST 版编译器作新主线，旧 L1 打 tag 归档，
   出口口径由 byte-identical 换成行为等价」。

**Phase 9 只做 AST 编译器**，不叠加类型检查。类型检查作为 Phase 10+ 的候选，等 AST 稳定后再议。

**非目标**：

- 不改变 CT 语言（语法、命名规则、banner、`.c` 自包含契约全部不动）；
- 不做优化（保持「可读的普通 C」这一输出性质）；
- 不删除 `ctc.c`（L0）与 `selfhost/ctc.ct`（L1）——它们是冻结种子，永不整体删除；
- 不追求与旧管线逐字节一致。

### 2. 事实基线（2026-10-18，v0.8.0）

| 事实 | 数据 | 对设计的影响 |
| --- | --- | --- |
| 现有管线 | 行重写：`core.ct` 主流程 + `RewriteOps` 行重写层，`driver.ct` 驱动 | 新编译器**独立实现**，不复用其扫描/改写逻辑 |
| 符号表容量 | `MAX_VARS 512`、`MAX_SCOPE 256`、`MAX_DEPTH 8` | AST 递归走指针/接口，不消耗 `MAX_DEPTH` |
| plain-C 签名 | `MAX_FUNCS 64`，`src/**` 已用 ~58（含 10 个 `pub` 包装器） | 新逻辑**必须**写进 `impl` 块；新编译器是新单元树，额度**独立**计算 |
| CT `struct`（可 `use`） | `MAX_STRUCT 32`，`src/**` 仅用 2 | AST 节点若全走 `struct` + `use` 会**迅速触顶** |
| CT `trait` | `MAX_TRAITS 16`，`src/**` 用 3 | 每个 trait 一套 vtable + iface；要省着用 |
| 每 trait 方法 | `MAX_METHOD 32`，`PipeOps` 已 31 | 新 trait 的额度是全新的（32），但仍需分批 |
| 每 struct 字段 | `MAX_FIELDS 32`，`Pipe` 已 31/32 | 数据节点尽量走 `typedef struct`（不计入 `MAX_STRUCT`） |
| 单元 | `MAX_UNITS 64`、`MAX_IMPORTS 16` | 新树可按职责拆单元；`driver.ct` 的 `build` 可直接编它 |
| 验收探针 | `p01`–`p17` + `ast_spike` + `ast_parse_spike`，19 pass / 1 pending / 0 regression | 已证明「树 + 接口派发 + 递归下降」在现有子集内可行 |
| 归档点 | tag `pre-ast-mainline`（2026-10-17 的 frozen 边界；Phase 9 起点由 `v0.8.0` 标出） | 旧管线的 byte-identical 出口到此为止 |
| 自举阶梯 | 新编译器的表容量由**上一代**编译器决定，增长一代滞后 | 第一代 AST 编译器必须落在 32 struct / 16 trait / 64 签名内 |

### 3. 已定决策（D28–D37，2026-10-18 用户确认）

| 编号 | 问题 | 结论 |
| --- | --- | --- |
| D28 | Phase 9 主题 | ✅ **AST 版编译器作新主线** |
| D29 | 9.1 首个里程碑出口 | ✅ **最小端到端子集**：`int` 函数 + 表达式 + `return` + `printf` 调用，能编并跑通一个 hello 级程序；先把「词法 → AST → 发射 C」管道打通 |
| D30 | 代码落点 | ✅ **新目录 `selfhost/ast/**`，与旧管线并行**：由 L2 构建，旧 `selfhost/src/**` 原地冻结但保留；行为等价后再切主线，可回退 |
| D31 | Phase 9 最终出口 | ✅ **自编 + 行为等价**：AST 编译器能编自己，且对 `test/cases` + `examples` + `modules` 的编译成功性与程序输出与旧管线等价 |
| D32 | AST 节点表示 | ✅ **`typedef struct` 数据节点 + `kind` 判别字段**（`typedef struct` 不计 `MAX_STRUCT`），遍历/发射由少量 trait（如 `NodeOps`）承载，内部按 `kind` 分派；分派逻辑集中在一处，新增节点只改那一处 |
| D33 | 符号表与作用域 | ✅ **分类扁平表**：类型（struct / trait / typedef）、函数、变量各一张；只有变量表压/弹作用域（进入记录长度、退出回滚）。与 C 的名字空间语义一致，不自造跨类冲突规则；查找线性，容量内成本可忽略；越界即 `die`，不静默截断 |
| D34 | 行为等价判据 | ✅ **退出码一致 + 成功产物可被 `cc -Wall -Wextra -std=c99` 零警告编译 + 程序输出与 `*.expected.out` 一致**；诊断文本与告警不比对 |
| D35 | AST 线门禁 | ✅ **新增 `selfhost/check-ast.sh`**，9.1 起纳入 `check-all.sh` 作为硬关卡；四态 `PASS / NEW / PENDING / REGRESSION`，仅 `REGRESSION` 非零 |
| D36 | 旧管线归档时点 | ✅ **9.6 自编成功后继续跑到 9.7 全量行为等价，再打 tag 归档** `selfhost/src/**`（冻结但保留），归档前始终可回退 |
| D37 | 容量增长 | ✅ **一代滞后**：每代只提高新编译器自己的 `MAX_*`，且新源码必须仍由上一代编得过 |

### 4. 决策清单收口

D28–D37 全部定案，**无待定项**。本节保留编号占位；后续若出现新决策，从 **D38** 起编号。

### 5. 「行为等价」的精确含义

对同一输入单元：

1. **退出码相同**：成功 / 失败（非 0）两侧一致；
2. **成功时**：生成的 `.c` 能被 `cc -Wall -Wextra -std=c99` 零警告编译，且链接后**程序输出**与
   `*.expected.out` 逐字节一致；
3. **失败时**：两侧都失败即可，**不要求**诊断文本逐字一致（错误码、行号可不同）；
4. **告警**：不要求一致；若某个用例只有一侧告警，记入本文件的「已知差异」，不视为回归；
5. **产物契约不变**：banner、命名规则（`<Trait>_vtbl` / `<Struct>_<Trait>_<method>` 等）、
   `.c` 自包含、`.h` 只放类型——这些是**契约**，不是「字节一致」的要求。

### 6. 代码组织（草案，受 D32/D33 影响）

```
selfhost/ast/
├── ast.h.ct        # 节点类型与少量 trait（导出给各单元）
├── lex.ct          # 词法器
├── parse.ct        # 递归下降解析器（表达式 → 语句 → 声明）
├── emit.ct         # C 发射器（含 banner / #line / 命名规则）
└── main.ct         # 驱动：读文件 → 解析 → 发射（与 ct build 的接口对齐）
```

- 单元数远低于 `MAX_UNITS 64`；跨单元只导出 `pub` 类型与标量包装器（旧管线已踩过的坑：
  `pub` 前缀进不了 `.h`，宏必须各自复制）。
- **节点形状（D32）**：`ast.h.ct` 只放 `typedef struct` 节点、`kind` 枚举常量与 `NodeOps` trait；
  `parse.ct` 负责构造节点，`emit.ct` 按 `kind` 分派发射。新增节点 = 加一个 `kind` + 在分派处加一支。
- **符号表（D33）**：类型 / 函数 / 变量三张扁平表，只有变量表压/弹作用域；越界即 `die`。
- 构建方式复用现成的 `ct build`：`l2 build selfhost/ast/main.ct -o <dir>`。
- 产物名称：关卡内部暂称 `ct-ast`（与 `ctc-l2` 同为内部名）；用户入口在切换后仍是 `ct`。

### 7. 实现切片（9.1 → 9.7）

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| 9.1 | 最小端到端：词法 + 表达式/`return` 解析 + 发射 C；`int main` + `printf` 调用 | ✅ **已落地（2026-10-18）**：`selfhost/ast/main.ct`（单文件：词法 + 递归下降 + 按 `kind` 发射 + banner/头文件）；`test/ast/01_hello`、`02_expr` 两个行为用例与 `errors/missing_semi` 负例；`selfhost/check-ast.sh` 已接入 `check-all.sh` 第 8 关 |
| 9.2 | 语句与控制流：局部声明、赋值、`if` / `while` / `for`、函数调用（含前置声明） | ✅ **已落地（2026-10-18）**：新增局部声明 / 赋值 / `if`-`else` / `while` / `for`、函数原型与参数、`void` 返回、比较与 `%`、一元 `-`/`!`、后缀 `++`/`--`；D33 的函数表 + 变量表（作用域栈）就位；`test/ast/03_control`、`04_void` 两个行为用例全绿（`03` 的完整语料等价留到 9.3/9.4） |
| 9.3 | 声明与类型：`struct` / `typedef`、指针、数组、函数签名（含 `static`） | ✅ **已落地（2026-10-18）**：类型说明符（`int`/`void`/`char`/`unsigned long`/`const`）、`struct` 定义与 `typedef`（含匿名 struct）、指针 `*`/`&`、`.`/`->`/下标、数组、`static` 函数与全局；`03_passthrough` 已能被 `ct-ast` 编译并通过 `cc -c`；仍推迟花括号初始化式、强制转换与 `sizeof`（9.4/后续） |
| 9.4a | 特性子集：`trait` / `struct use` / `impl` 与派发（值/指针/`self` 兄弟调用） | ✅ **已落地（2026-10-18）**：生成 `<Trait>_vtbl` / `<Trait>_iface`、`__<trait>_vptr` 字段、`<S>_<T>_<m>` 方法与 `<S>_<T>_vtable`；方法调用重写为 `recv.__x_vptr->m(&recv, …)` / `recv->__x_vptr->m(recv, …)`；声明期自动写 vptr（含花括号初始化式追加）。`01_trait_basic` 已行为等价（编、跑、输出一致），新增 `test/ast/09_methods` |
| 9.4b | 接口值与接口数组：trait 当类型、装箱、运行期派发 | ✅ **已落地（2026-10-18）**：trait 名作类型时发射 `struct <T>_iface`；声明 / 赋值 / 实参 / `return` 处按静态类型装箱为 `(struct T_iface){ (void *)&x, &S_T_vtable }`（指针则不带 `&`）；`g.m()` → `g.vt->m(g.self)`，接口数组元素同样支持。`18_polymorphism`、`21_empty_init_iface` 已行为等价（含空 `{}` 初始化式），新增 `test/ast/10_iface_array` |
| 9.5a | 模块层：`import` / `pub` / `build` / `namespace` / `--ns-root` | ✅ **已落地（2026-10-18）**：`build <inputs…> -o <dir> [-I <dir>] [--ns-root <dir>]` 逐单元产出 `.c` + `.h`；导入闭包深度优先解析，`a::b` → `<root>/a/b.ct` 或 `a/b.h.ct`（导入方目录优先）；`pub` 只导出 trait / struct / typedef / 原型；`namespace A::B` 的类型名压成 `A_B_`，`--ns-root` 按 D13-A 校验目录。`test/modules` 的 split / ns_dir / inc / hdr 行为等价，两条负例非零退出 |
| 9.5b | 元数据：`#line` 与 `--emit-map` | ✅ **已落地（2026-10-18）**：词法与节点带行号，`#line 1 "<输入>"` 在 compile 模式由 `--line` 开启、在 build 模式默认开启（`--no-line` 关闭）；`--emit-map <file|->` 输出与旧管线同形的 JSON（compiler / file / traits / structs / functions / impls / calls），行号与调用图取自解析期记录。新增 `test/ast/11_map`；`check-ast.sh` 30 项全绿 |
| 9.6 | 自编：用 AST 编译器编 `selfhost/ast/**` 自身，产出下一代 | ✅ **已落地（2026-10-18）**：`ct-ast` 编自己的 `main.ct` → 产物零警告编出 `ct-ast2` → `ct-ast2` 再编同一源码，与首轮产物**逐字节一致**（不动点）。`check-ast.sh` 新增 self-hosting 一节，31 项全绿 |
| 9.7 | 全量行为等价 + 切主线 | ✅ **已落地（2026-10-18）**：`test/cases` + `examples` + `modules` 行为等价；新增 corpus equivalence 一节，`check-ast.sh` **60 项全绿**（含自编不动点、方言示例先展开）；旧管线 `selfhost/src/**` 按 D36 冻结归档（tag `pre-ast-mainline`），`selfhost/ast/**` 成为唯一主线；收口 bump 到 **v0.9.0**（经用户授权） |

每片出口都要求：`bash selfhost/check-all.sh` 七道旧关卡**零回退**，且 `check-ast.sh` 全绿。

### 8. 测试与门禁

- **新关卡** `selfhost/check-ast.sh`（D35）：构建 `selfhost/ast/**` → 对探针与语料跑「编译 →
  cc → 运行 → 比对输出」；四态 `PASS / NEW / PENDING / REGRESSION`，仅 `REGRESSION` 非零。
- **行为等价矩阵**（9.7 出口）：`test/cases/**`、`examples/**`、`test/modules/**` 三个语料面，
  按 §5 的口径逐例判定。
- **旧关卡**继续跑旧管线：`check-goldens` / `check-archive` / `check-m2a` / `ct-tour` 在双轨期
  语义不变；切换后按 D36 重写。
- **单元测试**：词法与解析的纯函数适合放 `test/unit` 风格的 C 测试？——不适用（新编译器是 CT
  源码），改为**探针 + 行为等价**两层，不引入新测试框架。

### 9. 风险与未决

| 风险 | 说明 |
| --- | --- |
| 容量天花板 | D32 已用 `typedef struct` 规避 `MAX_STRUCT`；剩余压力在 `MAX_TRAITS 16`、`MAX_FUNCS 64` 与 `MAX_FIELDS 32` |
| 双轨维护 | 并行期两套编译器同时演进；旧管线应**只修 bug 不加特性** |
| 等价口径漂移 | 告警与诊断文本不比对，容易掩盖真实差异；需要在 9.7 前逐例人工复核 |
| AST 内存 | 节点用堆分配 + `own`/Drop；泄漏会拖垮长输入，需要泄漏关卡 |
| `MAX_UNITS` | 新树 5 个单元，远低于 64；但 `import` 上限 16 需留意 |
| 自编断链 | 下一代提高 `MAX_*` 后，上一代可能编不过新源码（一代滞后原则，D37） |

### 10. 与既有阶段的关系

- **不修改** Phase 0–8 的任何行为与语料；`ctc.c` / L1 `/ selfhost/src/**` 在双轨期冻结。
- `pre-ast-mainline` 标记 byte-identical 时代的 frozen 边界；Phase 9 的起点是 v0.8.0 收口。此后新能力只落 `selfhost/ast/**`。
- 版本：Phase 9 ↔ `v0.9.x`，收口时 bump 到 **v0.9.0**（同样属冻结期例外，需用户显式授权）。

---

## English

### 1. Scope

At the time (L2, `selfhost/src/**`) the compiler was a **line-rewriting** design. Phase 9 builds a real
**AST-based compiler** instead. This was already decided on 2026-10-17 ("the AST compiler becomes the
new mainline; the old L1 is archived by tag; the exit criterion changes from byte-identical to
behavioural equivalence"); Phase 9 gives that decision a phase, a design and a slice plan.

**Non-goals**: no language changes, no optimisations, no deletion of `ctc.c` / `selfhost/ctc.ct`
(frozen seeds), and no requirement of byte-identical output.

### 2. Fact baseline (v0.8.0, 2026-10-18)

- Capacity: `MAX_FUNCS 64` (~58 used in `src/**`), `MAX_STRUCT 32` (2 used), `MAX_TRAITS 16` (3),
  `MAX_METHOD 32` (`PipeOps` 31), `MAX_FIELDS 32` (`Pipe` 31/32), `MAX_UNITS 64`, `MAX_IMPORTS 16`.
- `typedef struct` does **not** count against `MAX_STRUCT`; `impl` methods do **not** count against
  `MAX_FUNCS` — the new tree must exploit both.
- Acceptance probes `p01`–`p17` + `ast_spike` + `ast_parse_spike` pass (19 / 1 pending / 0 regression),
  proving that trees, interface dispatch and recursive descent fit the current CT subset.
- Tag `pre-ast-mainline` marks the frozen boundary of the byte-identical era; Phase 9 starts at the
  v0.8.0 close.
- The bootstrap ladder grows one generation behind: the first AST compiler must fit the frozen
  L1's tables (32 structs / 16 traits / 64 signatures).

### 3. Decided (D28–D37, user-confirmed 2026-10-18)

| ID | Question | Decision |
| --- | --- | --- |
| D28 | Theme | ✅ **The AST compiler becomes the new mainline** |
| D29 | 9.1 exit | ✅ **A minimal end-to-end subset**: `int` functions, expressions, `return` and `printf`, enough to compile and run a hello-level program |
| D30 | Code location | ✅ **A new `selfhost/ast/**` tree built by L2, in parallel with the old pipeline**, which stays frozen and in place until behavioural equivalence, so the switch is reversible |
| D31 | Phase exit | ✅ **Self-compilation + behavioural equivalence** on `test/cases`, `examples` and `modules` |
| D32 | AST representation | ✅ **`typedef struct` data nodes + a `kind` tag** (`typedef struct` does not count against `MAX_STRUCT`), with a few traits (`NodeOps`) carrying the walker/emitter and one central `kind` dispatch; a new node kind touches one switch |
| D33 | Symbol tables / scopes | ✅ **Separate flat tables** for types (struct / trait / typedef), functions and variables; only the variable table pushes/pops scopes (record the length, roll back on exit). This matches C's namespaces, needs no cross-category collision rule, and lookup is linear within a bounded table; overflow `die`s |
| D34 | Equivalence test | ✅ **Same exit status + the generated C compiles warning-free with `cc -Wall -Wextra -std=c99` + the program output matches `*.expected.out`**; diagnostics and warnings are not compared |
| D35 | AST gate | ✅ **A new `selfhost/check-ast.sh`**, added to `check-all.sh` as a hard gate from 9.1 on; four states `PASS / NEW / PENDING / REGRESSION`, only `REGRESSION` is non-zero |
| D36 | Archiving the old pipeline | ✅ **After 9.6 self-compiles, run on to full equivalence at 9.7, then tag and archive** `selfhost/src/**` (frozen but present); the old line stays available for rollback until then |
| D37 | Capacity growth | ✅ **One generation behind**: each generation may raise only the new compiler's own `MAX_*`, and the new sources must still be compilable by the previous generation |

### 4. Decisions closed

D28–D37 are all settled; **nothing is open**. The section is kept as a placeholder — any new decision
starts at **D38**.

### 5. What "behavioural equivalence" means

For each input unit: (1) same exit status; (2) on success, the generated C compiles warning-free with
`cc -Wall -Wextra -std=c99` and the linked program's output matches `*.expected.out` byte for byte;
(3) on failure, both fail — the diagnostic text need not match; (4) warnings need not match (record any
one-sided warning as a known difference, not a regression); (5) the output contract is unchanged
(banner, naming rules, self-contained `.c`, types-only `.h`).

### 6. Layout (draft, subject to D32/D33)

```
selfhost/ast/
├── ast.h.ct        # node types and the few traits (exported)
├── lex.ct          # lexer
├── parse.ct        # recursive-descent parser (expression → statement → declaration)
├── emit.ct         # C emitter (banner / #line / naming rules)
└── main.ct         # driver: read → parse → emit (aligned with `ct build`)
```

Build with the existing `ct build`: `l2 build selfhost/ast/main.ct -o <dir>`. The gate artifact is
temporarily named `ct-ast` (like `ctc-l2`); the user-facing entry stays `ct` after the switch.

- **Node shape (D32)**: `ast.h.ct` carries only `typedef struct` nodes, the `kind` constants and the
  `NodeOps` trait; `parse.ct` builds nodes and `emit.ct` dispatches on `kind`. A new node = one `kind`
  plus one branch in that dispatch.
- **Symbol tables (D33)**: three flat tables (types / functions / variables); only the variable table
  pushes and pops scopes, and overflow `die`s.

### 7. Slices (9.1 → 9.7)

| Slice | Content | Exit |
| --- | --- | --- |
| 9.1 | Minimal end-to-end: lexer, expression/`return` parsing, C emission; `int main` + `printf` | ✅ **landed (2026-10-18)**: `selfhost/ast/main.ct` (one unit: lexer + recursive descent + `kind`-dispatched emission + banner/header); `test/ast/01_hello` and `02_expr` behavioural cases plus the `errors/missing_semi` negative; `selfhost/check-ast.sh` is gate 8 of `check-all.sh` |
| 9.2 | Statements and control flow: locals, assignment, `if` / `while` / `for`, calls | ✅ **landed (2026-10-18)**: locals/assignment, `if`-`else`, `while`, `for`, prototypes and parameters, `void` returns, comparisons and `%`, unary `-`/`!`, postfix `++`/`--`; D33's function table plus a scoped variable table are in place; `test/ast/03_control` and `04_void` are green (full corpus equivalence for `03_passthrough` waits for 9.3/9.4) |
| 9.3 | Declarations and types: `struct` / `typedef`, pointers, arrays, signatures | ✅ **landed (2026-10-18)**: type specifiers (`int`/`void`/`char`/`unsigned long`/`const`), `struct` definitions and `typedef` (including anonymous structs), pointers `*`/`&`, `.`/`->`/indexing, arrays, `static` functions and globals; `03_passthrough` now compiles through `ct-ast` and `cc -c`; brace initializers, casts and `sizeof` remain deferred (9.4/later) |
| 9.4a | Features: `trait` / `struct use` / `impl` and dispatch (value / pointer / `self` sibling calls) | ✅ **landed (2026-10-18)**: emits `<Trait>_vtbl` / `<Trait>_iface`, `__<trait>_vptr` fields, `<S>_<T>_<m>` methods and `<S>_<T>_vtable`; calls become `recv.__x_vptr->m(&recv, …)` / `recv->__x_vptr->m(recv, …)`; declarations get the vptr automatically (brace initializers are appended to). `01_trait_basic` is behaviour-equivalent (compiles, runs, same output); new `test/ast/09_methods` |
| 9.4b | Interface values and arrays: a trait as a type, boxing, runtime dispatch | ✅ **landed (2026-10-18)**: a trait used as a type emits `struct <T>_iface`; declarations, assignments, arguments and `return` box by static type as `(struct T_iface){ (void *)&x, &S_T_vtable }` (no `&` for a pointer); `g.m()` becomes `g.vt->m(g.self)`, and interface-array elements work too. `18_polymorphism` and `21_empty_init_iface` are behaviour-equivalent (including the empty `{}` initializer); new `test/ast/10_iface_array` |
| 9.5a | Modules: `import` / `pub` / `build` / `namespace` / `--ns-root` | ✅ **landed (2026-10-18)**: `build <inputs…> -o <dir> [-I <dir>] [--ns-root <dir>]` emits one `.c` + `.h` per unit; the import closure is parsed depth first, `a::b` resolving to `<root>/a/b.ct` or `a/b.h.ct` (the importing directory first); `pub` exports only traits / structs / typedefs / prototypes; `namespace A::B` prefixes type names with `A_B_`, and `--ns-root` validates the directory (D13-A). split / ns_dir / inc / hdr from `test/modules` are behaviour-equivalent; two negative cases exit non-zero |
| 9.5b | Metadata: `#line` and `--emit-map` | ✅ **landed (2026-10-18)**: lexer and nodes carry line numbers; `#line 1 "<input>"` is enabled by `--line` in compile mode and on by default in build mode (`--no-line` turns it off); `--emit-map <file|->` emits the old pipeline's JSON shape (compiler / file / traits / structs / functions / impls / calls), with lines and the call graph taken from parse time. New `test/ast/11_map`; `check-ast.sh` is green with 30 assertions |
| 9.6 | Self-compilation: the AST compiler compiles `selfhost/ast/**` into the next generation | ✅ **landed (2026-10-18)**: a fixpoint — the emitted compiler builds warning-free and reproduces its own output byte for byte. `check-ast.sh` grew a self-hosting section (31 assertions) |
| 9.7 | Full equivalence + mainline switch | ✅ **landed (2026-10-18)**: `test/cases` + `examples` + `modules` are behaviour-equivalent; the new corpus-equivalence section makes `check-ast.sh` **60 assertions green** (fixpoint included, dialect demos expanded first); the old pipeline `selfhost/src/**` is frozen and archived per D36 (tag `pre-ast-mainline`) and `selfhost/ast/**` is the only mainline; the phase closes with the bump to **v0.9.0** (authorised) |

Every slice keeps the seven existing gates regression-free and `check-ast.sh` green.

### 8. Risks

Capacity is the main risk: D32 already sidesteps `MAX_STRUCT` with `typedef struct`, leaving
`MAX_TRAITS 16`, `MAX_FUNCS 64` and `MAX_FIELDS 32` as the pressure points. Also: dual maintenance
during the parallel period; equivalence drift around warnings; AST memory management (`own`/Drop); and
the one-generation-lag constraint on capacity growth.
