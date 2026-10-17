# Phase 5 设计（已冻结）：新增特性（AutoDrop / 路径敏感泄漏分析 / 目录 = namespace）

> 中文 · [English](#english)
>
> **状态：设计已冻结（2026-10-17）。** D9–D14 均按推荐项拍板（见第 6 节）。Phase 5 的出口是
> 「**设计先行 → 冻结 → 新用例 → `run.sh` 全绿**」，且明确**不追求** byte-identical（无归档 oracle
> 可对差）。本文只补**实现层面**的设计；语言层面的既有语法以 [language-spec](../language-spec.md)
> 为准，阶段规划以 [roadmap](../roadmap.md) 为准。
>
> **AST 主线不在 Phase 5 提前**：可行性骨架 `ast_parse_spike` 已通过（见 roadmap「三处表达力缺口与
> AST 主线」），但按原计划推进，Phase 5 三项仍落在逐行实现上。

---

## 中文

### 1. 范围与出口

Phase 5 只做 roadmap 列出的三项：

1. **AutoDrop**：被标记的变量在作用域结束时自动 `drop()`。
2. **路径敏感泄漏分析**：分析所有 `return` 路径，标出「某些路径上未释放」。
3. **目录 = namespace 强制绑定**。

三项都属**新增**，没有归档 oracle。出口：

- 设计冻结（本文件 + 用户拍板 D9–D14）；
- 每项配新用例（`test/cases` 或 `test/modules` 的 designed 组），`./test/run.sh` 与
  `bash selfhost/check-all.sh` 全绿；
- 既有语料（`check-goldens.sh` 的 25 例、`check-archive.sh` 的归档与 designed 组）**零回归**；
- 阶梯 **M6** 在此收口。
- 版本在阶段**完成时** bump 到 `v0.5.0`（不在开工时 bump）。

### 2. 可复用的现状与硬约束

| 现状 | 位置 | Phase 5 如何用 |
| --- | --- | --- |
| `Var.owned` / `own_line` | [core.ct](../../selfhost/src/core.ct) | AutoDrop 复用同一套「谁持有堆对象」的登记 |
| `new_var` 复用槽位时清 ownership | `SymTabOps::new_var` | 新增的 autodrop 标记也必须清零 |
| `scope[]` / `nscope` 按 `}` 回滚 `nvars` | `RewriteOps::scope_track` | AutoDrop 的「作用域归属」直接以 `scope[top]` 为边界 |
| `leak_check_scope` / `leak_observe` | `SymTabOps` | 路径敏感分析只改这两个方法的判定，不新增 AST |
| `try_delete` 的 Drop 分流 | `RewriteOps::try_delete` | AutoDrop 的生成动作直接复用其文本形状 |
| hoist 缓冲 + `emit_hoisted` | `PipeOps` | 注入的 drop 行走 hoist，`#line` 才能正确重锚 |
| `MAX_FUNCS` 余量 **1** | `core.ct` | 新逻辑**一律写成 impl 方法**，禁止加顶层函数 |
| `PipeOps` 31/32、`RewriteOps` 20/32 | trait 定义 | AutoDrop 的改写方法放 `RewriteOps`；诊断方法放 `SymTabOps` |

### 3. AutoDrop

#### 3.1 语法

在**声明行**加前缀关键字 `own`：

```c
own Person *p = malloc(sizeof(Person));
```

- 只在 `try_var_decl` 的声明位置识别（与 `static` 同一处），因此 `own` 在其它位置仍是普通标识符。
- 与 `static` 可叠加，顺序固定为 `own static`；反序不识别（保持最小语法）。
- 仅支持**结构体指针**声明；接口值、数组、非指针声明在 v1 不识别（见 3.5）。

#### 3.2 语义（v1）

- `own` 表示「这个变量持有对象的生命周期」：声明时必须由 `malloc` / `calloc` 初始化，且类型必须
  `use Drop`（否则 `die`：`own requires a Drop type`）。
- 变量离开**声明它的作用域**时，编译器插入释放语句；同一作用域内的多个 `own` 变量按**声明逆序**
  释放（后声明先释放）。
- 每条 `return` 之前也插入同一组释放语句（覆盖提前返回）。
- 一旦变量被 `delete`、被重新赋值、或被当作右值赋给别的对象（逃逸），编译器**取消**它的 autodrop
  标记——所有权已经转移或已释放，不能再由作用域兜底。

#### 3.3 发射形状

与 `delete` 完全同构，保证用户心智一致：

```c
if (p) { Person_Drop_drop(p); free(p); p = 0; }
```

`p = 0;` 是新增的一步：作用域闭合处的注入与提前 `return` 处的注入可能同时存在，置空后
`if (p)` 保证不会二次释放。

注入走 `Pipe.hoist`（`transform_line` 把语句写进 hoist、原行照常返回）：

- 闭合 `}`：drop 行在 `}` **之前**；
- `return`：drop 行在 `return` **之前**；
- `#line`：`emit_hoisted` 已经会 `line_break()` + 重新锚定，不必另写映射逻辑。

#### 3.4 与既有机制的交互

| 机制 | 行为 |
| --- | --- |
| 泄漏警告 | `own` 变量在作用域闭合时由生成代码释放，`leak_check_scope` **跳过** autodrop 变量 |
| `delete p;` | 既有的 `owned = 0` 之外再清 `autodrop`，避免闭合处重复释放 |
| `return` | `leak_observe` 对 autodrop 变量不做「逃逸」推断（它本来就会被兜底释放） |
| 逃逸赋值 | `p = q;` / `obj.f = p;` 清 `autodrop`（v1 不追踪所有权转移，只保证不误释放） |
| `break` / `continue` / `goto` | **不插入**（不离开作用域）；`goto` 跳出作用域属 v1 限制（3.5） |

#### 3.5 明确的 v1 限制（写进 language-spec）

1. `own` 只支持「`own T *p = malloc|calloc(...);` 一行完成声明与初始化」。
2. 声明所在作用域的闭合 `}` 必须**是该行第一个非空白字符**；`return` 也必须位于行首
   （`if (!p) return;` 这种行内条件返回不允许）。否则编译期报错，**不静默跳过**。
   理由：注入走 hoist（整行之前），行内的 `}` / `return` 无法安全地放到条件分支内部。
3. `goto` 跳出声明作用域不会触发释放。
4. 重新赋值后不再兜底释放（所有权语义在 v1 只覆盖「声明后一直持有到作用域结束」）。
5. 「逃逸」按**保守**处理：变量出现在带 `=` 的行上、或出现在 `return` 行上，即取消 autodrop
   （宁可漏放，不可错放）。

### 4. 路径敏感泄漏分析

现有实现是**路径不敏感**的：`leak_observe` 看到任何 `return` 就把该行提到的 owned 变量标记为
「已释放」，因此「只有某个分支 return」会掩盖真实泄漏。v1 只做**分支敏感的 return 判定**，不建 AST：

#### 4.1 判定「条件 return」

一条 `return` 是**条件**的，当且仅当满足其一：

- 它所在行的首个非空白字符不是 `return`（例如 `if (!p) return;`）；或
- 它出现在函数体顶层的花括号深度之外（`self->nscope > 0`，即位于 `if` / 循环 / 嵌套块内）。

否则视为**无条件 return**（函数体顶层、整行只有 `return …`）。

#### 4.2 行为

| return 形态 | owned 标记 | 诊断 |
| --- | --- | --- |
| 无条件 | 清空（与现状一致） | 不报 |
| 条件 | **保留** | 对每个仍 owned 的非 autodrop 变量记一条 `kind = 2` 警告 |

`kind = 2` 复用人可读与 JSON 两条通道：文本为
`<file>:<line>: warning: '<var>' may leak on a return path (line <n>)`，JSON 为
`"type": "potential_leak"` 且带 `"path_line": <n>`。作用域闭合时的原有警告**跳过**已发过
`kind = 2` 的变量，避免同一对象报两次。

#### 4.3 边界

- 只在**函数体**内生效（文件作用域没有 `return`）。
- 不做分支合并、不做循环归纳、不判断「所有路径都泄漏」——只回答「**某些**路径上未释放」。
- 完整的路径敏感数据流需要 AST，明确推迟（roadmap 的 Phase 6「跨函数分析」再议）。

### 5. 目录 = namespace 强制绑定

现状：namespace 只由显式 `namespace A::B { … }` 语法决定，`build` 的 import 解析只看路径，
不校验目录名。Phase 5 增加绑定，但**两种语义差别很大**，需用户选：

| 方案 | 含义 | 代价 |
| --- | --- | --- |
| **A 校验式（推荐）** | 文件若声明了 `namespace`，其路径（相对 root）必须与 namespace 一致；不声明则不受影响 | 零产物变化；不合规即报错 |
| **B 推导式** | 目录**隐式**决定 namespace（没写 `namespace` 也自动加前缀），写了则必须一致 | 产物命名会变；既有语料若放进子目录会失效 |

推荐 **A**：它满足「强制绑定」的字面要求（目录与 namespace 不许各说各话），且不改变任何既有产物。
root 的确定：

- 新增 `--ns-root <dir>`（单次，默认 = 命令行第一个输入单元所在目录）；
- 单元路径相对 root 去掉文件名后的目录分量即 namespace（`hal/uart.ct` → `hal`）；
- 经 `import a::b;` 解析到的单元，namespace 必须等于 `a::b` 的目录部分；
- 不合规即 `die`：`namespace 'X' does not match directory 'a::b'`。

只在 `build` 模式生效；单文件 `compile` 不做目录校验（那里没有 root 概念）。

### 6. 决策点（2026-10-17 已拍板，均取推荐项）

| 编号 | 问题 | 决定 | 备选 |
| --- | --- | --- | --- |
| **D9** | AutoDrop 的标记语法 | ✅ **`own` 前缀**（`own T *p = malloc(...)`） | `T *own p` / `/* @own */` 注释 |
| **D10** | AutoDrop 的释放动作 | ✅ **`drop` + `free` + 置空**（与 `delete` 一致） | 仅 `drop`（roadmap 字面「不 free」） |
| **D11** | 闭合 `}` 不在行首时 | ✅ **编译期报错** | 静默跳过 + 文档限制 |
| **D12** | 路径敏感深度 | ✅ **条件 return 检查**（无 AST 可做） | 完整路径数据流（需 AST，推迟） |
| **D13** | 目录 = namespace | ✅ **A 校验式** | B 推导式 |
| **D14** | 推进顺序 | ✅ **AutoDrop → 路径分析 → 目录绑定** | 目录绑定优先 |

> D10 说明：roadmap 原文「不 `free`，只释放其持有的资源」若按字面执行，堆对象本身会永久泄漏，
> 与 Phase 3 的 `delete` 语义割裂。已拍板：把「不 free」理解为「不释放变量本身（值对象）」，
> 指针型 `own` 仍按 `delete` 处理。

### 7. 实现顺序与测试

| 切片 | 内容 | 新用例 |
| --- | --- | --- |
| 5.1 | `own` 声明 + 作用域闭合注入 + `return` 注入 | `test/modules/autodrop/`：正常闭合、提前 return、嵌套作用域逆序 |
| 5.2 | 负例与限制 | `autodrop` 无 Drop 类型、`}` 不在行首、`own` 后重新赋值 |
| 5.3 | 路径敏感 return 判定 | `test/modules/leak_path/`：条件 return 告警 + 无条件 return 不告警 |
| 5.4 | 目录 = namespace 校验 | `test/modules/ns_dir/`：匹配通过、不匹配报错、import 目录匹配 |
| 5.5 | 文档 + `v0.5.0` + M6 收口 | language-spec / roadmap / AGENTS 版本行 |

每个切片后跑：`./test/run.sh`、`bash selfhost/check-all.sh`、手工三件套。

### 8. 非目标（Phase 5 不引入）

- **类型检查**：会要求 AST，编译器性质改变，与「逐行扫描」的定位冲突。
- **泛型**：需要 `.c` 侧单态化展开，收益与成本不匹配。
- **生成物可读性的硬指标**（嵌套缩进上限、命名长度上限）：属工程约束，不是语言特性。

---

## English

### 1. Scope and exit criteria

Phase 5 covers exactly the three items in the roadmap: **AutoDrop**, **path-sensitive leak analysis**,
and **mandatory directory = namespace binding**. All three are *new* features, so there is no archived
oracle: the exit is **design frozen → new cases → `./test/run.sh` and `bash selfhost/check-all.sh`
green**, with **no regression** in the existing corpus. Rung **M6** closes here, and the version is
bumped to `v0.5.0` **when the phase completes**, not when it starts.

### 2. AutoDrop (D9–D11)

**Syntax**: a declaration prefix, `own T *p = malloc(...);`. It is recognised only where declarations
are parsed (the same place as `static`), so `own` stays an ordinary identifier elsewhere. It may be
combined as `own static`; only struct-pointer declarations are accepted in v1, and the struct must
`use Drop`.

**Semantics**: the marked variable owns its object until its declaring scope ends. The compiler emits,
in reverse declaration order, the same shape as `delete`:

```c
if (p) { Person_Drop_drop(p); free(p); p = 0; }
```

at every `}` that closes the declaring scope and before every `return`; `p = 0;` prevents a double
release when both injections are present on the same path. The injected statements go through
`Pipe.hoist`, so `#line` re-anchors correctly via `emit_hoisted`.

**Interactions**: the leak checker skips autodrop variables; `delete p;`, a reassignment, or an escape
assignment clears the autodrop flag (ownership moved or already released).

**v1 limits** (documented in language-spec): the closing `}` **and** `return` must be the first
non-blank token of their line, otherwise the compiler **dies** rather than silently skipping (the
hoist-based injector cannot place a release inside a conditional); `goto` out of the scope does not
release; a reassigned variable is no longer released automatically; escaping is treated
conservatively (a variable mentioned on a line with `=` or on a `return` line stops being auto-dropped).

### 3. Path-sensitive leak analysis (D12)

The current checker is path-insensitive: any `return` marks every owned object mentioned on that line
as released, so a conditional return hides real leaks. v1 only distinguishes **conditional** from
**unconditional** returns, without an AST:

- a return is *conditional* when it is not the first non-blank token of its line, or when
  `nscope > 0` (inside a block);
- an unconditional return clears ownership as today;
- a conditional return keeps ownership and records a `kind = 2` warning per still-owned, non-autodrop
  variable: text `'<var>' may leak on a return path (line <n>)`, JSON `"type": "potential_leak"` with
  `"path_line"`. The scope-close warning skips variables already reported this way.

No branch merging, no loop induction, no "all paths" analysis — the question answered is exactly
"does *some* path leak". Full data flow needs an AST and is deferred to Phase 6.

### 4. Directory = namespace (D13)

Two candidate readings; option **A is recommended**:

- **A (validation)**: a unit that declares a `namespace` must have a path (relative to `--ns-root`,
  default: the directory of the first input unit) matching it; units without a declaration are
  unaffected. No generated output changes for conforming code.
- **B (derivation)**: the directory implicitly provides the namespace, and an explicit declaration must
  agree. This changes generated names and invalidates existing corpus files placed in subdirectories.

Validation runs in `build` mode only; a mismatch is a hard `die`
(`namespace 'X' does not match directory 'a::b'`).

### 5. Decisions (frozen 2026-10-17, all recommendations accepted)

| Id | Question | Decision | Alternative |
| --- | --- | --- | --- |
| D9 | AutoDrop marker | ✅ **`own` prefix** | `T *own p` / comment marker |
| D10 | Release action | ✅ **`drop` + `free` + null** (as `delete`) | `drop` only |
| D11 | Closing brace not at line start | ✅ **positional error** | skip silently + document |
| D12 | Analysis depth | ✅ **conditional-return check** | full data flow (needs AST) |
| D13 | Directory = namespace | ✅ **A validation** | B derivation |
| D14 | Order | ✅ **AutoDrop → path analysis → directory binding** | directory binding first |

### 6. Non-goals

Type checking, generics, and hard readability metrics on generated code are **out of scope**: they
either change what the compiler is (a line scanner becomes an AST-based checker) or impose
non-linguistic constraints.
