# Phase 9 设计（草案）：AST 版编译器（新主线）

> 中文 · [English](#english)
>
> **状态：设计草案（2026-10-18），未实现。** 主题与五项决策（D28–D33）已由用户定案；
> 其余决策标为**待定**，实现前必须逐条拍板并按本文件更新状态。**不要**照本文件创建
> `selfhost/ast/**` 或任何实现文件——`docs/design/` 是草案，不是实现依据（AGENTS §2）。
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
| 归档点 | tag `pre-ast-mainline`（2026-10-17） | 旧管线的 byte-identical 出口到此为止 |
| 自举阶梯 | 新编译器的表容量由**上一代**编译器决定，增长一代滞后 | 第一代 AST 编译器必须落在 32 struct / 16 trait / 64 签名内 |

### 3. 已定决策（D28–D33，2026-10-18 用户确认）

| 编号 | 问题 | 结论 |
| --- | --- | --- |
| D28 | Phase 9 主题 | ✅ **AST 版编译器作新主线** |
| D29 | 9.1 首个里程碑出口 | ✅ **最小端到端子集**：`int` 函数 + 表达式 + `return` + `printf` 调用，能编并跑通一个 hello 级程序；先把「词法 → AST → 发射 C」管道打通 |
| D30 | 代码落点 | ✅ **新目录 `selfhost/ast/**`，与旧管线并行**：由 L2 构建，旧 `selfhost/src/**` 原地冻结但保留；行为等价后再切主线，可回退 |
| D31 | Phase 9 最终出口 | ✅ **自编 + 行为等价**：AST 编译器能编自己，且对 `test/cases` + `examples` + `modules` 的编译成功性与程序输出与旧管线等价 |
| D32 | AST 节点表示 | ✅ **`typedef struct` 数据节点 + `kind` 判别字段**（`typedef struct` 不计 `MAX_STRUCT`），遍历/发射由少量 trait（如 `NodeOps`）承载，内部按 `kind` 分派；分派逻辑集中在一处，新增节点只改那一处 |
| D33 | 符号表与作用域 | ✅ **分类扁平表**：类型（struct / trait / typedef）、函数、变量各一张；只有变量表压/弹作用域（进入记录长度、退出回滚）。与 C 的名字空间语义一致，不自造跨类冲突规则；查找线性，容量内成本可忽略；越界即 `die`，不静默截断 |

### 4. 待定决策（实现前必须拍板）

| 编号 | 问题 | 推荐方案 | 代价 / 说明 |
| --- | --- | --- | --- |
| D34 | 行为等价的验收口径 | **退出码一致 + 成功产物可编译 + 程序输出一致；诊断文本与告警不要求逐字一致** | 若要求告警一致，等于要求复刻行重写的启发式，违背「新主线」初衷 |
| D35 | 新门禁形态 | **新增 `selfhost/check-ast.sh`**，9.1 起纳入 `check-all.sh`；七道旧关卡保持不变 | 双轨期多一道门禁；旧关卡继续钉住旧管线 |
| D36 | 旧管线归档时点 | **9.7 行为等价全绿后打 tag 归档**，`selfhost/src/**` 冻结但保留 | 归档后 `check-goldens` / `check-archive` 的语义需要重写为「对 AST 编译器」 |
| D37 | 容量增长 | **一代滞后**：9.x 每代只提高新编译器自己的 `MAX_*`，且仍须由上一代编得过 | 提高过快会让「上一代编下一代」断链 |

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
| 9.1 | 最小端到端：词法 + 表达式/`return` 解析 + 发射 C；`int main` + `printf` 调用 | 新验收探针 `ast_compile_min`：编一个 hello 级 `.ct`、gcc 零警告、输出符合预期；`check-ast.sh` 上线 |
| 9.2 | 语句与控制流：局部声明、赋值、`if` / `while` / `for`、函数调用（含前置声明） | `test/cases` 的 `03_passthrough` / `04_signatures` 类用例行为等价 |
| 9.3 | 声明与类型：`struct` / `typedef`、指针、数组、函数签名（含 `static`） | 无 trait 的用例全部行为等价 |
| 9.4 | 特性子集：`trait` / `struct use` / `impl` 与派发；接口值与接口数组 | `01_trait_basic` 等 trait 用例行为等价 |
| 9.5 | 模块与元数据：`import` / `pub` / `build` / `namespace` / `#line` / `--emit-map` | `test/modules/**` 行为等价；`ct build` 可切换 |
| 9.6 | 自编：用 AST 编译器编 `selfhost/ast/**` 自身，产出下一代 | 不动点：AST 编译器编出的自己再编同一批语料，行为仍等价 |
| 9.7 | 全量行为等价 + 切主线 | `test/cases` + `examples` + `modules` 全绿；旧管线打 tag 归档；版本收口 v0.9.0 |

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
- `pre-ast-mainline` 是 byte-identical 口径的终点；此后新能力只落 `selfhost/ast/**`。
- 版本：Phase 9 ↔ `v0.9.x`，收口时 bump 到 **v0.9.0**（同样属冻结期例外，需用户显式授权）。

---

## English

### 1. Scope

The current compiler (L2, `selfhost/src/**`) is a **line-rewriting** design. Phase 9 builds a real
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
- Tag `pre-ast-mainline` marks the last byte-identical state.
- The bootstrap ladder grows one generation behind: the first AST compiler must fit the frozen
  L1's tables (32 structs / 16 traits / 64 signatures).

### 3. Decided (D28–D33, user-confirmed 2026-10-18)

| ID | Question | Decision |
| --- | --- | --- |
| D28 | Theme | ✅ **The AST compiler becomes the new mainline** |
| D29 | 9.1 exit | ✅ **A minimal end-to-end subset**: `int` functions, expressions, `return` and `printf`, enough to compile and run a hello-level program |
| D30 | Code location | ✅ **A new `selfhost/ast/**` tree built by L2, in parallel with the old pipeline**, which stays frozen and in place until behavioural equivalence, so the switch is reversible |
| D31 | Phase exit | ✅ **Self-compilation + behavioural equivalence** on `test/cases`, `examples` and `modules` |
| D32 | AST representation | ✅ **`typedef struct` data nodes + a `kind` tag** (`typedef struct` does not count against `MAX_STRUCT`), with a few traits (`NodeOps`) carrying the walker/emitter and one central `kind` dispatch; a new node kind touches one switch |
| D33 | Symbol tables / scopes | ✅ **Separate flat tables** for types (struct / trait / typedef), functions and variables; only the variable table pushes/pops scopes (record the length, roll back on exit). This matches C's namespaces, needs no cross-category collision rule, and lookup is linear within a bounded table; overflow `die`s |

### 4. Open decisions (must be settled before implementation)

| ID | Question | Recommendation |
| --- | --- | --- |
| D34 | Equivalence definition | **Same exit status + generated C compiles + identical program output**; diagnostics and warnings need not match |
| D35 | New gate | **`selfhost/check-ast.sh`**, added to `check-all.sh` from 9.1 on; the seven existing gates stay |
| D36 | Archiving the old pipeline | **Tag and archive after 9.7**; `selfhost/src/**` stays frozen but present |
| D37 | Capacity growth | **One generation behind**: each 9.x generation may raise only the new compiler's own `MAX_*`, and must still be compilable by the previous generation |

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
| 9.1 | Minimal end-to-end: lexer, expression/`return` parsing, C emission; `int main` + `printf` | New probe `ast_compile_min` compiles a hello-level `.ct`, `cc` is warning-free, output matches; `check-ast.sh` goes live |
| 9.2 | Statements and control flow: locals, assignment, `if` / `while` / `for`, calls | Behavioural equivalence for `03_passthrough` / `04_signatures`-style cases |
| 9.3 | Declarations and types: `struct` / `typedef`, pointers, arrays, signatures | Every trait-free case is equivalent |
| 9.4 | Features: `trait` / `struct use` / `impl` and dispatch; interface values and arrays | Trait cases such as `01_trait_basic` are equivalent |
| 9.5 | Modules and metadata: `import` / `pub` / `build` / `namespace` / `#line` / `--emit-map` | `test/modules/**` is equivalent; `ct build` can switch over |
| 9.6 | Self-compilation: the AST compiler compiles `selfhost/ast/**` into the next generation | A fixpoint: the AST compiler's own output still behaves equivalently on the same corpus |
| 9.7 | Full equivalence + mainline switch | `test/cases` + `examples` + `modules` all green; the old pipeline is archived by tag; version closes at v0.9.0 |

Every slice keeps the seven existing gates regression-free and `check-ast.sh` green.

### 8. Risks

Capacity is the main risk: D32 already sidesteps `MAX_STRUCT` with `typedef struct`, leaving
`MAX_TRAITS 16`, `MAX_FUNCS 64` and `MAX_FIELDS 32` as the pressure points. Also: dual maintenance
during the parallel period; equivalence drift around warnings; AST memory management (`own`/Drop); and
the one-generation-lag constraint on capacity growth.
