# Phase 1 设计草案：模块化（namespace / 多文件 / import / pub / Drop）

> 中文 · [English](#english)
>
> **状态：设计草案，当前未实现。** 本文描述 Phase 1 的语义、展开规则、载体与落地顺序，
> 对应 [roadmap](../roadmap.md) 的 Phase 1。
>
> 语言层面的**语法决策已在 roadmap「已定的设计决策」中冻结**（`::` 路径规则、`import`、
> `.h.ct` + `pub`、Drop/delete、`map`、JSON 诊断），本文不重复，只补**实现层面**的设计。
> 第 6 节列出**仍需用户拍板**的决策点（D1–D8）。
>
> **落地进度（2026-10-11）**：**1.0**（CLI 子命令 `compile` + `argv[0]` 分派）、**1.1**（namespace，
> 含限定引用 `A::B::Name`）与 **1.2**（多文件：`ct build` 驱动、`.c` 含自己的 `.h`、`pub` 路由）已实现，
> 测试全绿（`./test/run.sh` 31/31、`check-grammar.py` 16/16）；1.3（import）与 1.4（堆/Drop）未实现。
> 落地时采用 **D2 = 是**（struct tag 加命名空间前缀）、**D3 = 是**（顶层不加前缀），且 **D-A = 方案 A**
> （`ct build` 只产出 `.c`/`.h` 并打印建议的 `cc` 命令，**不**自己调用 `cc`，见第 6 节新条目）。**D6 的
> banner/改名暂缓**：`ctc`→`ct` 的改名与 banner 变更留到后续一次性完成。D1 / D4 / D5 / D7 / D8 仍待定。

---

## 中文

### 1. 目标与出口标准

Phase 1 的主题是**模块化**：把 Phase 0 的「单文件、`.c` 自包含」推进到「多文件、有命名空间
与可见性边界、可跨编译单元引用」。它同时是「用 CT 重写编译器」的开路阶段——见
[roadmap](../roadmap.md#自举前置条件清单) 的自举前置清单 1–5。

**出口标准**：

1. 能用 `import` + `namespace` + `pub` 写一个**多文件** OO 程序，`ct build` 一次编到可执行；
2. 堆对象有**语言级创建入口**（不再手写 vptr），`delete` + `Drop` 能正确释放；
3. 生成物带 `#line`，报错能映回 `.ct` 源码行；
4. 文件作用域可声明对象数组；
5. 既有 Phase 0 用例（`examples/**`、`test/cases/**`）**逐字节不变**，仍全绿。

第 5 条是硬约束：Phase 1 只能**扩展**命名与产物规则，不得改动顶层（无 namespace）代码的产物
（呼应 [AGENTS.md](../../AGENTS.md) §2「不改变已发布产物的命名规则」）。

### 2. 与 Phase 0 的差异：两种编译模式

Phase 1 新增**多文件模式**，与 Phase 0 的**单文件模式**并存：

| 模式 | 触发条件 | `.c` 自包含 | `.h` 内容 | 产物 |
| --- | --- | --- | --- | --- |
| 单文件 | `ct compile` / `ctc <file>` | ✅ 保持 | 仅类型（现状） | `<in>.c` + `<in>.h` |
| 多文件 | `ct build` 驱动 | ❌ `.c` `#include` 自己的 `.h` | 类型（`pub`）+ `pub` 函数原型 | 每 unit 一对 `.c`/`.h`，再链接 |

判定规则（**已实现**）：**由 CLI 触发**——只有 `ct build` 进入多文件模式，`ct compile` / `ctc <file>` 恒为单文件模式。源码内容（是否含 `namespace`）**不再**决定模式，这样单文件里的 namespace 代码也保持 `.c` 自包含。

> 这是 Phase 1 唯一的破坏性点：多文件模式下 `.c` 不再自包含。roadmap
> 「包管理的前置条件」已记录此事。

### 3. 子阶段与依赖

```
1.0 工具链 / CLI / 驱动骨架
      │
      ├─▶ 1.1 namespace（解析 + 符号修饰 + 限定查找）      ← 单文件即可测
      │        │
      │        └─▶ 1.2 多文件 + .h.ct 拆分 + pub           ← 模块表 / 依赖 / 拓扑 / 头生成
      │                 │
      │                 └─▶ 1.3 import（路径解析）         ← 依赖模块表
      │
      └─▶ 1.4 堆对象创建 + delete 放宽 + Drop
               │
               ├─▶ 1.5 #line
               ├─▶ 1.6 文件作用域对象数组
               └─▶ 1.7 泄漏警告 + JSON 诊断
                        │
                        └─▶ 1.8 map + 反向映射表

(可选) 1.9 一般接收者（自举前置 #6：make().m() / ps[i].m() / a.next->m()）
```

1.1–1.3（模块化链）与 1.4（内存链）互不依赖，可并行；1.5–1.8 各依赖其上游。

### 4. 各子阶段设计

#### 1.0 工具链 / CLI / 驱动骨架 ✅ 已完成

- **目标**：落地单入口 `ct` 与子命令；搭出多文件驱动的骨架。
- **CLI**（对齐 roadmap 落地清单）：
  - `ct compile <in.ct> [-o out.c]`：单文件，等价今天的 `ctc`；`compile` 为**默认子命令**。
  - `ct build <root.ct> -o <exe>`：多文件，解析 `import` → 拓扑编译 → 链接。
  - `ctc …`：识别 `argv[0]`，等价 `ct compile …`（兼容别名，软链）。
- **改动**：`main` 拆为 `parse_args` + 子命令分派；新增 `driver` 分区（编排，不碰已有解析/生成逻辑）。
- **风险**：生成物 banner 由 `ctc` 改 `ct` → **全部 golden 失效**（roadmap 落地清单第 3 条），属一次性重生成。
- **验收**：`ct --version` 与 `ctc --version` 都可用；单文件路径产物除 banner 外与 Phase 0 逐字节一致。

#### 1.1 namespace ✅ 已完成（含限定引用）

- **语法**：`namespace A::B { … }`（顶层；`::` 分隔各段，与访问路径规则一致，允许显式嵌套）。
- **符号修饰（契约，先冻结）**：C 只有一层全局命名空间，须靠前缀消解。**空/顶层 namespace
  不加前缀**，因此顶层代码与 Phase 0 命名逐字节相同：

  | CT | C |
  | --- | --- |
  | namespace `A::B` | 前缀 `A_B_` |
  | `struct S` | `struct A_B_S`（**tag 也要加前缀**） |
  | `trait T` | `struct A_B_T_vtbl` / `struct A_B_T_iface` |
  | vptr 字段 | `__t_vptr`（**不加**前缀；字段名作用域在 struct 内，无冲突） |
  | vtable 变量 | `A_B_S_T_vtable` |
  | 方法 | `A_B_S_T_m` |
  | 静态函数 | `A_B_fn` |

- **查找**：`find_trait` / `find_struct` 增加 namespace 维度。未限定名先在当前 namespace 找，
  再回退顶层；同时命中多个 → `die`（不猜）。
- **改动**：新增 `namespace` 分区（修饰 + 限定查找）；`Trait` / `Struct` / `Method` 增加所属
  namespace 字段。
- **风险**：修饰规则一经发布即契约，必须先冻结（roadmap 已注）；tag 前缀（D2）是跨单元
  struct 重名能否避免的关键。
- **验收**：单文件里用 `namespace A { … }` 包裹后产物带 `A_` 前缀且能编译运行；顶层代码产物不变。

#### 1.2 多文件 + `.h.ct` 拆分 + `pub` ✅ 已完成（多文件 + `pub`；`.h.ct` 的文件名约定与 `import` 归 1.3）

> **落地说明**：本轮实现的是「多文件驱动（`ct build`）+ `.c` 含自己的 `.h` + `pub` 路由（`pub trait`/`pub struct`/`pub` 函数原型进 `.h`）」。**未**实现：`foo.h.ct` 的文件名区分、`pub` vtable 的 `extern` 跨单元装箱——它们与 1.3（`import` / 跨单元类型引用）一起做，因为跨单元**类型**引用本身就需要 1.3。


- **语法**：文件命名约定（`foo.ct` / `foo.h.ct`）+ `pub` / `static` / `pub readonly`（roadmap 已冻结）。
- **`.h` 内容**：`#ifndef` 守卫；`pub trait` → vtbl 结构 + 方法原型 typedef；`pub struct` → tag 定义；
  `pub trait` → iface 结构；`pub` 函数原型；`pub` vtable 的 `extern` 声明。
- **`.c` 内容**：`#include "<own>.h"`；实现；`static` 私有符号（不进 `.h`）。
- **关键点**：**跨单元装箱要求 `pub` vtable 非 `static`**（Phase 0 里是 `static`）。装箱发生在
  使用方（`Greeter g = p;` → `&Person_Greeter_vtable`），故 `pub` struct 的 vtable 必须 `extern`
  可见。这是相对 Phase 0 生成器的一处实质变化。
- **改动**：`driver` 建模块表（namespace → unit）、依赖 DAG、拓扑序；每 unit 一套源缓冲与符号表；
  生成器按 `pub` 决定符号归属 `.h` / `.c`。
- **架构风险（Phase 1 最大）**：现有 `g_src` / `g_len` / `g_path` 与
  `g_traits` / `g_structs` / `g_vars` / `g_funcs` 都是**进程级单例**。多文件需要**每 unit 上下文**
  ＋**跨 unit 的限定符号索引**。建议：新增 `Unit` 结构承载 per-unit 数据，全局保留「当前 unit」
  指针 + 一张跨 unit 的限定符号表；不做推倒重写（保持单文件、最小改动，见 §5）。
- **验收**：`foo.h.ct` + `bar.ct` 两单元，`bar` 用 `foo` 的 `pub` struct 与 trait，`ct build`
  编到可执行并运行正确。

#### 1.3 import

- **语法**：`import A::B;`（`::` 分隔模块路径，与 namespace 声明、访问路径规则一致）。
- **解析**：`A::B` → 路径 `A/B.ct` 或 `A/B.h.ct`（`::` 段映射为目录层级），相对导入文件所在目录搜索，或 `-I <dir>` 指定的根
  （见 D7）。大小写按原样。
- **驱动**：扫全部相关 `.ct` → 建模块表 → 解析 `import` 成 DAG → 拓扑序 → 逐单元编译 → 链接 `.o`。
- **风险**：**目录 = namespace 是 Phase 2 才强制**，Phase 1 只按 `import` 路径解析，不校验目录名。
- **验收**：被 `import` 的单元自动编入，无需手工列出全部文件。

#### 1.4 堆对象创建 + `delete` 放宽 + Drop（"对象住哪儿"）

- **堆创建入口（决策 D1）**：
  - A. 识别 `T *p = malloc(sizeof(struct T));`（含 `calloc`）→ 自动写 vptr（含嵌套字段）。
    **零新语法**，最贴合「不要乱添加」。
  - B. 内置 `T::create()` 构造表达式（roadmap 示例中出现过）→ `malloc` + 写 vptr。
  - C. 维持现状（手写 `q->__<trait>_vptr = &…;`）。
  - 推荐 **A**，B 作为 A 不适用的补充；**需用户拍板**。
- **`delete` 放宽（自举前置 #4）**：
  - `delete p;` 对任意**已登记的指针变量**生效：
    - 指向的类型 `use Drop` → `if (p) { <S>_Drop_drop(p); free(p); }`
    - 其它（含 `char *` 等基本类型指针）→ `if (p) free(p);`（归约为 `free`）
  - `delete[] p;` → 对每个元素 `drop()`，再 `free`。
  - 维持 Phase 0 的词边界 + 形态判定，普通 C 里叫 `delete` 的标识符不受影响。
- **Drop**：内置 `Drop` trait（保留名，用户不得定义同名 trait），规则见 roadmap：
  - 递归 `drop()` **值字段**中类型也 `use Drop` 者；基本类型与裸指针不处理；
  - 用户可 `impl Drop for T { void drop() { … } }` 自定义；否则生成默认体
    `static void <S>_Drop_drop(void *_self)`；
  - **未调用不生成代码**：整个项目从未对某类型走到 `delete` / `drop`，则不生成其 drop 函数体，零开销。
- **改动**：新增 `drop` 分区（默认体生成 + 调用点展开）；`delete` 展开逻辑扩展；1.6 起
  `parse_fields` 的字段表已足够支撑递归。
- **风险**：用户 `impl Drop` 与默认体的合并语义需定死（建议：有 `impl` 则**完全以用户体为准**，
  默认体不再生成）；`delete` 的目标类型需可静态判定，否则 `die`。
- **验收**：`T *p = <堆创建>; p->m(); delete p;` 正确运行且无泄漏；含 Drop 值字段的 struct
  递归释放正确（用计数或 valgrind 佐证）。

#### 1.5 `#line`

- **设计**：`.c` 中**源自源文件**的输出行前插 `#line <源行> "<源路径>"`；仅当行号不连续时输出
  （连续段省略，减小体积）；生成的样板行（vtable 定义、vptr 写入循环）用**触发点**的源行号。
- **开关（决策 D4）**：建议单文件模式**默认关**（保 Phase 0 golden 不变），多文件模式**默认开**，
  `--line` / `--no-line` 覆盖。
- **风险**：与 golden 的交互；`#line` 会改变 `__LINE__` 的取值（对调试有利，对依赖行号的宏需注意）。
- **验收**：在 `.ct` 里制造一个 gcc 层面的错误（如调用不存在的 libc 函数），gcc 报出的行号与
  `.ct` 行号一致。

#### 1.6 文件作用域对象数组 + 文件作用域嵌套对象

- **问题**：0.1.6 / 0.1.7 要求「含嵌套对象 / 数组的对象必须在函数内声明」，因为文件作用域放不下
  「写 vptr 的语句」。
- **设计（决策 D5）**：为每个 unit 生成 `static void <unit>_init(void)`（写所有文件作用域对象与
  数组元素的 vptr），用 `__attribute__((constructor))` 在 `main` 前自动调用；若不用该属性，则退化为
  要求在 `main` 首行显式调用 `<unit>_init();`。
- **风险**：`__attribute__((constructor))` 非标准 C，但 gcc / clang 均支持，且与本项目
  「以 gcc / clang 为宿主」的定位一致（见 bootstrap 草案）。
- **验收**：`Person ps[2];` 在文件作用域可声明，元素 vptr 正确，`main` 里 `ps[0].greet()` 正常。

#### 1.7 泄漏警告（简单版）+ JSON 诊断

- **泄漏（简单版）**：由 1.4 的创建点标记**局部 owned 堆对象**；`delete` / `return` / 逃离作用域
  （赋给字段或全局）即清除；函数结束（对应 `}` 的作用域回滚）仍 owned → 警告（**不终止**）。
  抑制：`#[allow(leak)]`。路径敏感版归 Phase 2。
- **JSON**：`--diagnostics=json`（或 `-fdiagnostics-json`）输出 error / warning 列表（schema 见
  roadmap）、符号表、调用图；默认仍为人可读 stderr。
- **改动**：诊断层引入「错误计数 + 继续」，但 **error 仍终止**（Phase 0 语义不变）；warning 走独立通道。
- **风险**：warning 依赖「不终止」的诊断能力，需与既有 `die`（立即退出）并存而不混淆。
- **验收**：一个泄漏例子产生且仅产生 1 条 warning，退出码仍为 0；JSON 可被 `jq` 解析。

#### 1.8 `map` + 反向映射表

- **语法**：roadmap 已冻结（`map trait T for instance x { m(…) → CALL; }`）。
- **生成**：为实例 `x` 生成 vtable，使 `x` 可作为接口值使用（`Greeter g = x;`）。
- **反向映射表**：编译期内部表（生成的 C 符号 ← CT 定义点），用于诊断回溯、插件「跳转到定义」、
  反编译恢复语义；输出为 sidecar `<out>.ctmap.json`，**不进 `.c`**。
- **风险**：`→` 箭头的词法（非 ASCII）；`for instance` 的解析形态。
- **验收**：`map` 后的实例能作为接口值传入 `announce(T)` 并派发到映射的 SDK 调用。

#### （可选）1.9 一般接收者

自举前置 #6：`make().m()`、ps[i].m()（**变量**下标）、`a.next->m()`（指针字段链）目前原样透传。
它是一类独立问题，可单做（不阻塞其它子阶段）。建议拆为：变量下标、指针字段链先行，rvalue
（`make().m()`）单独设计（需临时变量提升）。

### 5. 数据模型改动（`ctc.c`）

| 现状（进程级单例） | 多文件所需 |
| --- | --- |
| `g_src` / `g_len` / `g_path` | 移入 `Unit`；全局保留「当前 unit」指针 |
| `g_traits` / `g_structs` / `g_vars` / `g_funcs` | 每 unit 一套 **＋** 一张跨 unit 的**限定符号表**（namespace 限定名 → 定义位置） |

- 新增分区：`driver`（CLI / 多文件编排）、`module`（模块表 / DAG / 拓扑序）、`namespace`（修饰 / 限定查找）、
  `drop`（Drop 生成）。
- **保持单文件、最小改动**（[AGENTS.md](../../AGENTS.md) §1/§2）：不建目录、不拆文件。
- **落地顺序建议**：先 1.0 驱动骨架 + 1.1 修饰层，把 `Unit` 引入并让「当前 unit」指针生效，
  再逐项迁移全局量——避免一次性大改。

### 6. 待用户拍板的决策点

| # | 问题 | 选项（推荐加粗） | 影响 |
| --- | --- | --- | --- |
| D1 | 堆对象的创建入口 | **A 识别 `malloc`（零新语法）** / B `T::create()` / C 维持手写 | 决定 1.4 形态与是否新增语法 |
| D2 | struct **tag** 是否加 namespace 前缀 | **加**（C tag 空间扁平，跨单元必需） / 不加 | 跨单元 struct 重名能否避免 |
| D3 | 顶层（无 namespace）符号 | **保持 Phase 0 名字（无前缀）** / 也加前缀 | 是否为破坏性变更 |
| D4 | `#line` 默认开关 | 单文件关、多文件开 / 全开 / 全关 | 既有 golden 是否变动 |
| D5 | 文件作用域对象初始化 | **`__attribute__((constructor))`** / 显式 `<unit>_init()` | 便利 vs 可移植性 |
| D6 | 单入口 `ct` 落地时机 | **Phase 1 起步** / 与 1.2 一起 / 更晚 | 何时一次性重生成全部 golden |
| D7 | `import` 的路径根 | **导入文件目录 + `-I`** / 仅 `-I` | 目录约定 |
| D8 | `map` 是否属 Phase 1 | 是（roadmap 已列） / **推迟到 Phase 1 末尾** | 1.8 排期 |
| D-A | `ct build` 是否自己调用 `cc` | **A：只产出 `.c`/`.h` 并打印建议的 `cc` 命令** / B：调用 `cc` 出可执行 | **已定 A**（用户 2026-10-11 确认）：保持 `ctc` 零依赖，不违背 AGENTS §2「不引入构建系统」 |

### 7. 测试策略

- **单文件回归**：`examples/**` 与 `test/cases/**` 必须**逐字节**保持（仅 D4 / D6 会触发一次性重生成）。
- **多文件新增**：`test/multifile/**`，每个特性一组「源 + `.expected.out`」，走 `ct build`
  端到端（生成 → 构建 → 运行 → 比对）。
- **负例**：`import` 不存在、跨 namespace 越权访问 `static`、命名歧义、Drop 循环等，均须带
  `file:line:col: error:` 前缀。
- `test/run.sh` 增加 `build` 与 `multifile` 两层（现有五层之上，不削弱）。

### 8. 非目标（Phase 1 不做）

- 类型检查、优化；**错误恢复**（1.7 只为 warning 引入「不终止」，error 仍立即终止）。
- 泛型、继承（永久非目标）。
- 目录 = namespace 强制绑定（Phase 2）。
- AutoDrop、路径敏感泄漏分析（Phase 2）。
- 包管理器本体（`import` 的模块解析属 Phase 1，registry / 安装不在内）。

---

## English

### 1. Goal and exit criteria

Phase 1 is about **modularity**: moving from Phase 0's "one file, a self-contained `.c`" to
"multiple files, with namespace and visibility boundaries, referencing across compilation units".
It is also the opening stage for rewriting the compiler in CT — see prerequisites 1–5 of the
bootstrap checklist in [roadmap](../roadmap.md).

**Exit criteria:**

1. a **multi-file** OO program written with `import` + `namespace` + `pub` builds to an executable
   in one `ct build`;
2. heap objects have a **language-level creation entry** (no more hand-written vptr), and
   `delete` + `Drop` release correctly;
3. generated C carries `#line`, so errors map back to `.ct` source lines;
4. object arrays can be declared at file scope;
5. every existing Phase 0 case (`examples/**`, `test/cases/**`) stays **byte-identical** and green.

Criterion 5 is a hard constraint: Phase 1 may only **extend** the naming and output rules, never
change the output of top-level (non-namespaced) code ([AGENTS.md](../../AGENTS.md) §2, "do not change
published naming rules").

### 2. Difference from Phase 0: two compilation modes

Phase 1 adds a **multi-file mode** alongside Phase 0's **single-file mode**:

| Mode | Trigger | `.c` self-contained | `.h` contents | Output |
| --- | --- | --- | --- | --- |
| Single-file | source has **no** `namespace` / `import` | ✅ kept | types only (as today) | `<in>.c` + `<in>.h` |
| Multi-file | source **has** `namespace` / `import`, or `ct build` drives it | ❌ `.c` `#include`s its own `.h` | types + `pub` prototypes + `extern` | one `.c`/`.h` pair per unit, then link |

Rule: **present ⇒ multi-file mode.** A single source may not mix the two modes (mixing is an error,
never guessed).

> This is Phase 1's only breaking point: in multi-file mode the `.c` is no longer self-contained
> (already recorded under "What package management needs first" in the roadmap).

### 3. Sub-phases and dependencies

```
1.0 Toolchain / CLI / driver skeleton
      │
      ├─▶ 1.1 namespace (parsing + symbol mangling + qualified lookup)   ← testable single-file
      │        │
      │        └─▶ 1.2 multi-file + .h.ct split + pub                    ← module table / deps / topo / headers
      │                 │
      │                 └─▶ 1.3 import (path resolution)                 ← needs the module table
      │
      └─▶ 1.4 heap creation + delete relaxation + Drop
               │
               ├─▶ 1.5 #line
               ├─▶ 1.6 file-scope object arrays
               └─▶ 1.7 leak warnings + JSON diagnostics
                        │
                        └─▶ 1.8 map + reverse-mapping table

(optional) 1.9 general receivers (prerequisite #6: make().m() / ps[i].m() / a.next->m())
```

The modularity chain (1.1–1.3) and the memory chain (1.4) are independent and can proceed in
parallel; 1.5–1.8 each depend on their upstream.

### 4. Sub-phase designs

#### 1.0 Toolchain / CLI / driver skeleton ✅ done

- **Goal**: land the single-entry `ct` with subcommands; scaffold the multi-file driver.
- **CLI** (per the roadmap migration checklist):
  - `ct compile <in.ct> [-o out.c]`: single file, equivalent to today's `ctc`; `compile` is the
    **default subcommand**.
  - `ct build <root.ct> -o <exe>`: multi-file — resolve `import`, compile in topological order, link.
  - `ctc …`: dispatch on `argv[0]`, equivalent to `ct compile …` (compatibility alias, a symlink).
- **Change**: split `main` into `parse_args` + subcommand dispatch; add a `driver` partition
  (orchestration only, touching none of the existing parsing/generation logic).
- **Risk**: the generated banner changes from `ctc` to `ct` → **every golden breaks** (roadmap
  migration checklist item 3); a one-off regeneration.
- **Acceptance**: `ct --version` and `ctc --version` both work; the single-file path's output is
  byte-identical to Phase 0 apart from the banner.

#### 1.1 namespace ✅ done (qualified references included)

- **Syntax**: `namespace A::B { … }` at top level (`::` separates segments, matching the access-path
  rule; explicit nesting is allowed).
- **Symbol mangling (a contract, frozen up front)**: C has one global namespace, so a prefix is
  required. **The empty / top-level namespace adds no prefix**, so top-level code keeps Phase 0
  names byte for byte:

  | CT | C |
  | --- | --- |
  | namespace `A::B` | prefix `A_B_` |
  | `struct S` | `struct A_B_S` (**the tag is prefixed too**) |
  | `trait T` | `struct A_B_T_vtbl` / `struct A_B_T_iface` |
  | vptr field | `__t_vptr` (**no** prefix; the field name is scoped inside the struct) |
  | vtable variable | `A_B_S_T_vtable` |
  | method | `A_B_S_T_m` |
  | static function | `A_B_fn` |

- **Lookup**: `find_trait` / `find_struct` gain a namespace dimension. An unqualified name is looked
  up in the current namespace, then at top level; more than one hit → `die` (no guessing).
- **Change**: a new `namespace` partition (mangling + qualified lookup); `Trait` / `Struct` /
  `Method` gain an owning-namespace field.
- **Risk**: the mangling rules become a contract the moment they ship, so they must be frozen first
  (already noted in the roadmap); the tag prefix (D2) decides whether cross-unit struct name clashes
  can be avoided.
- **Acceptance**: wrapping a single-file program in `namespace A { … }` prefixes its output with
  `A_` and still compiles/runs; top-level output is unchanged.

#### 1.2 Multi-file + `.h.ct` split + `pub` ✅ done (multi-file + `pub`; the `.h.ct` naming convention and `import` move to 1.3)

> **What landed**: the multi-file driver (`ct build`) + `.c` including its own `.h` + `pub` routing
> (`pub trait` / `pub struct` / `pub` function prototypes into the `.h`). **Not** implemented: the
> `foo.h.ct` filename distinction and `extern` vtable export for cross-unit boxing — those go with
> 1.3 (`import` / cross-unit type references), since cross-unit **type** references need 1.3 anyway.



- **Syntax**: the file-naming convention (`foo.ct` / `foo.h.ct`) + `pub` / `static` / `pub readonly`
  (frozen in the roadmap).
- **`.h` contents**: `#ifndef` guard; `pub trait` → vtbl struct + method-prototype typedef;
  `pub struct` → tag definition; `pub trait` → iface struct; `pub` function prototypes; `extern`
  declarations for `pub` vtables.
- **`.c` contents**: `#include "<own>.h"`; implementations; `static` private symbols (kept out of `.h`).
- **Key point**: **cross-unit boxing requires `pub` vtables to be non-`static`** (they are `static`
  in Phase 0). Boxing happens at the *use* site (`Greeter g = p;` → `&Person_Greeter_vtable`), so a
  `pub` struct's vtable must be `extern`-visible. This is a real change to the Phase 0 emitter.
- **Change**: the `driver` builds the module table (namespace → unit), the dependency DAG and the
  topological order; each unit gets its own source buffer and symbol tables; the emitter routes
  symbols to `.h` / `.c` according to `pub`.
- **Architectural risk (the biggest in Phase 1)**: today `g_src` / `g_len` / `g_path` and
  `g_traits` / `g_structs` / `g_vars` / `g_funcs` are **process-wide singletons**. Multi-file needs a
  **per-unit context** plus a **cross-unit qualified symbol index**. Recommendation: add a `Unit`
  struct holding per-unit data, keep a global "current unit" pointer plus one cross-unit qualified
  symbol table; do not rewrite from scratch (stay single-file, minimal diff — see §5).
- **Acceptance**: `foo.h.ct` + `bar.ct` where `bar` uses `foo`'s `pub` struct and trait;
  `ct build` produces a working executable.

#### 1.3 import

- **Syntax**: `import A::B;` (`::` separates the module path, matching the namespace declaration and
  access-path rules).
- **Resolution**: `A::B` → the path `A/B.ct` or `A/B.h.ct` (`::` segments map to directory levels),
  searched relative to the importing file's directory or a root given by `-I <dir>` (see D7). Case is
  preserved.
- **Driver**: scan all relevant `.ct` files → build the module table → resolve `import`s into a DAG →
  topological order → compile each unit → link the `.o`s.
- **Risk**: **directory = namespace only becomes mandatory in Phase 2**; Phase 1 resolves purely from
  the `import` path and does not check directory names.
- **Acceptance**: an `import`ed unit is compiled in automatically, with no need to list every file by hand.

#### 1.4 Heap creation + `delete` relaxation + Drop ("where objects live")

- **Heap creation entry (decision D1)**:
  - A. Recognise `T *p = malloc(sizeof(struct T));` (and `calloc`) → write the vptr automatically
    (nested fields included). **Zero new syntax**, closest to "don't add things".
  - B. A built-in `T::create()` constructor expression (it appeared in a roadmap example) → `malloc`
    + vptr write.
  - C. Status quo (hand-written `q->__<trait>_vptr = &…;`).
  - Recommend **A**, with B as a fallback where A does not apply; **needs the user's sign-off**.
- **`delete` relaxation (prerequisite #4)**:
  - `delete p;` works on any **registered pointer variable**:
    - type `use Drop` → `if (p) { <S>_Drop_drop(p); free(p); }`
    - otherwise (including `char *` and other scalar pointers) → `if (p) free(p);` (reduced to `free`)
  - `delete[] p;` → `drop()` each element, then `free`.
  - Keep the Phase 0 word-boundary + shape checks, so a plain-C identifier called `delete` is unaffected.
- **Drop**: a built-in `Drop` trait (a reserved name; users may not define a trait with it), rules per
  the roadmap:
  - recurse into **value fields** whose type also `use Drop`; scalars and raw pointers are left alone;
  - a user may write `impl Drop for T { void drop() { … } }`; otherwise generate the default body
    `static void <S>_Drop_drop(void *_self)`;
  - **no call, no code**: if the project never reaches `delete` / `drop` for a type, its drop body is
    never generated — zero overhead.
- **Change**: a new `drop` partition (default-body generation + call-site expansion); `delete`
  expansion extended; the field table from 1.6 already suffices for recursion.
- **Risk**: the merge semantics of a user `impl Drop` and the default body must be pinned down
  (recommendation: when an `impl` exists, it is **exactly** the user's body and no default is
  generated); `delete`'s target type must be statically determinable, else `die`.
- **Acceptance**: `T *p = <heap creation>; p->m(); delete p;` runs correctly with no leak; a struct
  with Drop-carrying value fields releases recursively (evidenced by counts or valgrind).

#### 1.5 `#line`

- **Design**: emit `#line <src line> "<src path>"` before each output line **originating in the
  source**; only when the line number is discontinuous (continuous runs are omitted to shrink the
  output); generated boilerplate lines use the source line of their **trigger point**.
- **Switch (decision D4)**: recommend **off** by default in single-file mode (keeps Phase 0 goldens
  unchanged) and **on** by default in multi-file mode, overridable with `--line` / `--no-line`.
- **Risk**: interaction with goldens; `#line` changes what `__LINE__` yields (good for debugging,
  noteworthy for macros that depend on line numbers).
- **Acceptance**: manufacture a gcc-level error in a `.ct` file (e.g. call a nonexistent libc
  function); gcc's reported line matches the `.ct` line.

#### 1.6 File-scope object arrays + file-scope nested objects

- **Problem**: 0.1.6 / 0.1.7 require "an object with nested objects or arrays must be declared inside
  a function", because file scope cannot hold the vptr-writing statements.
- **Design (decision D5)**: generate `static void <unit>_init(void)` per unit (writing the vptrs of
  every file-scope object and array element) and call it automatically before `main` with
  `__attribute__((constructor))`; without that attribute, degrade to requiring an explicit
  `<unit>_init();` as `main`'s first line.
- **Risk**: `__attribute__((constructor))` is not standard C, but gcc / clang both support it and it
  fits this project's "hosted by gcc / clang" positioning (see the bootstrap draft).
- **Acceptance**: `Person ps[2];` works at file scope, element vptrs are correct, and `ps[0].greet()`
  in `main` behaves.

#### 1.7 Leak warnings (simple version) + JSON diagnostics

- **Leak (simple version)**: mark **local owned heap objects** at 1.4's creation points; `delete` /
  `return` / escaping the scope (assignment to a field or a global) clears the mark; still owned at
  function end (the matching `}` scope rollback) → a warning (**non-fatal**). Suppression:
  `#[allow(leak)]`. The path-sensitive version is Phase 2.
- **JSON**: `--diagnostics=json` (or `-fdiagnostics-json`) emits the error / warning list (schema in
  the roadmap), the symbol table and the call graph; the default stays human-readable stderr.
- **Change**: the diagnostic layer gains "error count + continue", **but an error still terminates**
  (Phase 0 semantics unchanged); warnings travel on a separate channel.
- **Risk**: warnings need non-fatal diagnostics, which must coexist with the existing `die` (immediate
  exit) without confusion.
- **Acceptance**: a leaking example produces exactly one warning and still exits 0; the JSON parses
  with `jq`.

#### 1.8 `map` + reverse-mapping table

- **Syntax**: frozen in the roadmap (`map trait T for instance x { m(…) → CALL; }`).
- **Generation**: build a vtable for the instance `x` so `x` can be used as an interface value
  (`Greeter g = x;`).
- **Reverse-mapping table**: a compile-time internal table (generated C symbol ← CT definition site)
  for diagnostic provenance, the extension's "go to definition", and recovering CT semantics when
  decompiling; emitted as a sidecar `<out>.ctmap.json`, **not** into the `.c`.
- **Risk**: the non-ASCII `→` arrow in the lexer; the shape of `for instance`.
- **Acceptance**: a `map`ped instance can be passed as an interface value to `announce(T)` and
  dispatches to the mapped SDK call.

#### (optional) 1.9 General receivers

Prerequisite #6: `make().m()`, `ps[i].m()` (**variable** subscript) and `a.next->m()` (pointer field
chain) are all passed through verbatim today. It is one class of problem and can be done on its own
(blocking nothing else). Suggested split: variable subscripts and pointer field chains first; rvalue
receivers (`make().m()`) designed separately (they need temporary-variable promotion).

### 5. Data-model changes (`ctc.c`)

| Today (process-wide singletons) | What multi-file needs |
| --- | --- |
| `g_src` / `g_len` / `g_path` | moved into `Unit`; a global "current unit" pointer remains |
| `g_traits` / `g_structs` / `g_vars` / `g_funcs` | one set per unit **plus** a cross-unit **qualified symbol table** (qualified name → definition site) |

- New partitions: `driver` (CLI / multi-file orchestration), `module` (module table / DAG / topo
  order), `namespace` (mangling / qualified lookup), `drop` (Drop generation).
- **Stay single-file, minimal diff** ([AGENTS.md](../../AGENTS.md) §1/§2): no directories, no file splits.
- **Suggested order**: do 1.0's driver scaffold + 1.1's mangling layer first, introducing `Unit` and
  making the "current unit" pointer work, then migrate the globals item by item — avoiding one large
  rewrite.

### 6. Decisions awaiting the user

| # | Question | Options (recommendation in bold) | Effect |
| --- | --- | --- | --- |
| D1 | Heap-object creation entry | **A recognise `malloc` (zero new syntax)** / B `T::create()` / C keep hand-written | shapes 1.4 and whether syntax is added |
| D2 | Prefix struct **tags** with the namespace | **yes** (C's tag space is flat, needed across units) / no | whether cross-unit struct clashes can be avoided |
| D3 | Top-level (non-namespaced) symbols | **keep Phase 0 names (no prefix)** / prefix them too | whether this is a breaking change |
| D4 | `#line` default | off single-file, on multi-file / always on / always off | whether existing goldens change |
| D5 | File-scope object initialisation | **`__attribute__((constructor))`** / explicit `<unit>_init()` | convenience vs portability |
| D6 | When the single-entry `ct` lands | **at the start of Phase 1** / with 1.2 / later | when every golden is regenerated once |
| D7 | `import` path root | **importing file's directory + `-I`** / `-I` only | directory convention |
| D8 | Whether `map` belongs to Phase 1 | yes (roadmap lists it) / **defer to the end of Phase 1** | 1.8 scheduling |
| D-A | Does `ct build` invoke `cc` itself | **A: emit `.c`/`.h` only and print the suggested `cc` command** / B: run `cc` to produce an executable | **A decided** (user, 2026-10-11): keeps `ctc` dependency-free, honouring AGENTS §2 ("no build systems") |

### 7. Test strategy

- **Single-file regression**: `examples/**` and `test/cases/**` must stay **byte-identical** (only
  D4 / D6 trigger a one-off regeneration).
- **New multi-file suite**: `test/multifile/**`, one "sources + `.expected.out`" group per feature,
  exercised end to end through `ct build` (generate → build → run → compare).
- **Negatives**: missing `import`, cross-namespace access to a `static`, ambiguous names, Drop
  cycles, … all carrying the `file:line:col: error:` prefix.
- `test/run.sh` gains `build` and `multifile` layers (on top of today's five, weakening none).

### 8. Non-goals (not in Phase 1)

- Type checking, optimisation; **error recovery** (1.7 introduces "continue" only for warnings;
  errors still terminate immediately).
- Generics, inheritance (permanent non-goals).
- Mandatory directory = namespace binding (Phase 2).
- AutoDrop, path-sensitive leak analysis (Phase 2).
- The package manager itself (Phase 1 covers `import`'s module resolution; the registry / install
  does not).
