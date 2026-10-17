# CT 术语表 / CT Glossary

> 中文 · [English](#english)
>
> 本表是 `ct` 项目**命名与措辞的唯一对照表**：统一项目名、语言构造、编译器内部符号、测试与阶段用语。
> 与代码或规范冲突时，**以代码和 [language-spec](language-spec.md) 为准**（同 [AGENTS.md](../AGENTS.md) §5）。
> 术语在文档/提交信息/注释中首次出现时，优先使用本表的规范叫法。

---

## 中文

### 0. 命名硬约定（刻意不统一，不要"修正"）

| 规范术语 | 代码/CLI 形式 | 说明 |
| --- | --- | --- |
| ct（CT = *C with Traits*） | `ct`，源文件后缀 `.ct` | 语言/项目名 |
| ctc | `ctc` | 今天的编译器命令 |
| ct（最终单入口） | `ct` | 已定形态：单入口 `ct`，`ctc` 保留为兼容别名；**尚未落地** |
| ct-lang | 仓库名 `ct-lang` | **仅是 GitHub 仓库名**，不是语言/命令/后缀 |

> 禁止把 `ct` / `ctc` / `.ct` 写成 `ct-lang` / `ctlang` / `.ctlang`（AGENTS §7）。

### 1. 语言构造

| 术语 | 代码形式 | 说明 |
| --- | --- | --- |
| 特征（trait） | `trait T { void m(); };` | 一组方法签名；派生虚表类型 `<T>_vtbl` |
| 结构体（struct） | `struct S { … } use T;` | 数据字段 + `use` 子句 |
| 实现块（impl） | `impl T for S { … }` | 把 trait 的方法绑定到具体 struct |
| use 子句（use-clause） | `} use T, U;` | struct 声明它实现哪些 trait |
| self | `self`、`self->m()` | 方法体内指代自身；生成时展开为 `_self` |
| 命名空间（namespace） | `namespace A::B { … }` | 唯一可嵌套构造；符号加 `A_B_` 前缀。**已随 Phase 0.3 移出 L0，现由自举编译器 `selfhost/` 用 CT 重做** |
| 命名空间路径 | `A::B`、`A::B::Name` | `::` 分隔各段；访问成员/方法用末尾 `.` |
| 导入（import） | `import A::B;` | 编译单元依赖声明（`ct build`）。**已随 Phase 0.3 移出 L0，现由自举编译器 `selfhost/` 用 CT 重做** |
| 导出（pub） | `pub trait` / `pub struct` / `pub int f(…);` | 多文件模式下符号进 `.h`；前缀本身被剥离 |
| 私有（static） | `static` | 支持的可见性；符号只进 `.c` |
| 析构特征 Drop | `use Drop`、`impl Drop for S { … }` | **保留名**内置 trait；惰性生成释放函数 |
| 释放（delete） | `delete p;` | 对指针展开为 `free`；`use Drop` 时先递归 `drop()` |
| 自动释放（AutoDrop） | `own T *p = malloc(…);` | 作用域出口 / 行首 `return` 前自动 `drop()` + `free()` + 置空（Phase 5；仅 CT 线，L0 不识别） |
| 映射（map） | `map trait T for instance x { m() → CALL; }` | 把 trait 方法映射到 SDK 调用（**未实现**；自越位实现移出，排期 Phase 6，D8） |
| 接口值（interface value / iface） | `struct <T>_iface`、`T x = p;` | 胖指针：`void *self` + `struct <T>_vtbl *vt` |
| 虚表（vtable） | `struct <Trait>_vtbl` | 函数指针表 |
| 虚表指针（vptr） | `__<trait>_vptr` | struct 内字段，指向其 vtable |
| 装箱（boxing） | `Greeter g = p;` | 把 struct 变量/指针转成接口值 |
| 派发（dispatch） | `p.m()` → `p.__<t>_vptr->m(&p)` | 运行时经 vtable 调用 |
| 接收者（receiver） | `p.m()` 中的 `p` | 方法调用的主体 |
| 限定引用（qualified reference） | `A::B::S` | 跨命名空间按名引用类型 |
| 顶层（top level） | 无 `namespace` 的代码 | 不加前缀，产物与 Phase 0 逐字节相同 |
| 位置式初始化 | `Person p = { "Tom" };` | 按字段顺序 |
| 指定初始化 | `Person p = { .name = "Tom" };` | 按字段名 |
| 空初始化式 | `Person p = {};` | 只写 vptr |

### 2. 命名 / 修饰规则（已发布契约）

| 术语 | 代码形式 | 说明 |
| --- | --- | --- |
| 命名修饰（mangling） | `A::B::S` → `A_B_S` | 空/顶层命名空间**不加**前缀 |
| 修饰后的 C 名（cname） | `Trait.cname` / `Struct.cname` | 源码里的规范 C 符号名 |
| 虚表类型 | `<Trait>_vtbl` | |
| 接口值类型 | `<Trait>_iface` | |
| vptr 字段 | `__<trait>_vptr` | trait 名小写；字段名在 struct 内，**不加**命名空间前缀 |
| 方法函数 | `<Struct>_<Trait>_<method>` | |
| vtable 变量 | `<Struct>_<Trait>_vtable` | |
| 文件作用域构造器 | `__ct_init` | `static void __ct_init(void) __attribute__((constructor))`：在 `main` 前为文件作用域对象 / 数组写 vptr（D5=A） |

> 以上是**已发布命名规则**，除非用户明确要求，不得更改（AGENTS §2）。

### 3. 编译器实现

| 术语 | 代码形式 | 说明 |
| --- | --- | --- |
| 源到源编译器（source-to-source compiler） | `ctc.c` | 输入 `.ct`，输出纯 C |
| 单文件模式 | `ct compile` / `ctc <file>` | `.c` 自包含；Phase 0 行为 |
| 多文件模式 | `ct build <a.ct> … -o <dir>` | `.c` `#include` 自己的 `.h`。**已随 Phase 0.3 移出 L0，现由自举编译器 `selfhost/` 用 CT 重做** |
| 透传（pass-through） | 非构造行原样输出 | |
| 行重写（line rewriting） | `transform_line` 等 | 按行进行；构造与语句同行不重写 |
| 诊断退出 `die()` | `die(pos, fmt, …)` | 唯一错误出口：`file:line:col: error:` 后 `exit(1)` |
| 诊断格式 | `file:line:col: error: message` | 描述小写、无句号、标识符单引号 |
| 字符串缓冲（Buf） | `buf_init` / `buf_puts` / `buf_putc` / `buf_putn` | 不要用 `strcat` |
| 内存分配 | `xmalloc` / `xstrndup` | 失败即 `exit(1)` |
| 容量上限（capacity limit） | `MAX_*` 常量（文件头部） | 越界一律 `die`，**不静默截断** |
| 函数分区（partition） | 工具→源扫描→符号表→签名解析→生成器→构造解析→行重写→`main` | 新增函数放入对应分区 |
| 惰性生成（lazy generation） | drop 函数体 | 仅在被 `delete` 触达时生成，零开销。**已随 Phase 0.3 移出 L0；现由自举编译器 `selfhost/` 用 CT 重做** |
| 传递闭包（drop closure） | `mark_drop_closure()` | 被删除类型递归拉入其 Drop 值字段。**同上，已移出 L0** |
| 生成物 banner | 生成物首部 | 溯源注释 + **输出例外**声明，不得删除 |
| 自包含（self-contained） | 单文件 `.c` | 不 `#include` 生成的 `.h` |
| 头文件守卫（include guard） | `.h` 的 `#ifndef` … `#endif` | |
| 编译单元（unit） | 一个 `.ct` → 一对 `.c`/`.h` | `ct build` 中每单元只编一次。**已随 Phase 0.3 移出 L0；现由自举编译器 `selfhost/` 用 CT 重做** |
| 依赖顺序（dependency order） | 拓扑序 | import 的 DAG 拓扑排序。**同上，已移出 L0** |
| 驱动（driver） | `compile_range` / `compile_file` / `compile_main` | 编排，不碰解析/生成逻辑；L0 现在只做单文件 |
| `#line` 映射 | `#line <源行> "<.ct>"` | 多文件默认开、单文件默认关（D4=A）。**已随 Phase 0.3 移出 L0；现由自举编译器 `selfhost/` 用 CT 重做** |
| 行号发射 | `line_of` / `line_at` / `line_break` | 偏移→行号缓存 / 发射 / 生成块边界强制重发。**同上，已移出 L0** |
| 泄漏警告（leak warning） | `potential_leak` · `leak_check_scope` · `leak_check_return` | 保守：作用域结束仍 owned 报确定泄漏（kind 0）；条件 `return` 留下的未返回对象另报一次 `may leak on a return path`（kind 2，JSON 带 `path_line`）；Phase 6.2 起 `T *q = f();` 若 `f` 可能返回它自己的分配（`ret_owned`），`q` 也计为 owned。**已由 Phase 4/5/6 在 `selfhost/src/**` 实现** |
| owned（堆对象持有） | `Var.owned` / `own_line` / `autodrop` | 由 `T *p = malloc/calloc(...)` 在创建点标记；Phase 6.2 起 `T *q = f()`（`f` 的 `ret_owned` 为真且返回同一 struct 指针）也标记；`own` 另置 `autodrop`（Phase 5）。**在 `selfhost/src/**` 实现** |
| 错误恢复（error recovery） | `setjmp` 守卫 + `recover_pos` | `die` 报告后长跳到 `compile_range` 的守卫，并重同步到下一个 `}` 之后或下一行行首；上限 `MAX_ERRORS=20`，失败的编译删除产物并在末尾补 `ctc: N error(s) generated`。Phase 4 切片 3 **新增**（无 oracle） |
| 语义诊断（semantic check） | `duplicate trait/struct` · `signature_mismatch` | 重复定义按 cname 报错（namespace 隔离）；impl 的返回类型 / 参数个数与 trait 不符时告警（**不比参数类型**）。Phase 4 切片 4 **新增**（无 oracle） |

### 4. CLI 与产物

| 术语 | 形式 | 说明 |
| --- | --- | --- |
| 子命令 compile | `ct compile <in.ct> [-o out.c]` | 默认子命令（等价 `ctc <in.ct>`） |
| 子命令 build | `ct build <in.ct>… [-o <dir>]` | 多文件驱动；只出 `.c`/`.h`，打印建议 `cc` 命令。**已随 Phase 0.3 移出 L0，现由自举编译器 `selfhost/` 用 CT 重做** |
| 输出选项 | `-o <file\|dir>` | |
| `#line` 开关 | `--line` / `--no-line` | 覆盖默认 |
| 帮助/版本 | `-h`/`--help`、`-v`/`--version` | |
| JSON 诊断 | `--diagnostics=json` / `--diagnostics=text` | 警告格式：JSON 走 stdout（`ct compile`），text 为人可读 stderr（默认）；目前仅泄漏警告（Phase 1.7）。**已由 Phase 4 切片 2 在 `selfhost/src/**` 恢复** |
| 增量缓存（incremental cache） | `<outdir>/.ctcache/<unit>.key` | Phase 6.3：每个单元一枚键（路径 + `mtime.size` + 版本 + `--line`/`--diagnostics` + 依赖 digest），键一致且 `.c/.h` 在盘即跳过重生成。**缓存命中不重放 `#line` 与告警**；`--emit-map` 下不命中。重编译集 = `order` 前缀 ∪ 依赖闭包 |

### 5. 测试

| 术语 | 形式 | 说明 |
| --- | --- | --- |
| 测试套件（runner） | `./test/run.sh` | 退出码 0 = 全绿；`CC=gcc` 换编译器 |
| 层（layer） | build / unit / cases / errors / examples / limits / cli | `multifile` / `import` / `line` 三层已随 Phase 0.3 移除 |
| golden 基线（golden baseline） | `*.expected.c` / `.expected.h` / `.expected.out` | **只能重新生成**，禁止手写 |
| 用例（fixture） | `test/cases/*.ct`、`test/errors/*.ct` | |
| 正例（positive case） | `test/cases/` | 生成→逐字节比对→编译→运行 |
| 负例（negative case） | `test/errors/<name>.expected-err` | `ctc` 必须非 0 退出且带期望诊断 |
| 白盒单测（white-box unit test） | `test/unit/test_helpers.c` | `#include "../../ctc.c"` 以触达 `static` 函数 |
| 重新生成基线（regeneration） | `./ctc <case>.ct -o <case>.expected.c` | 行为变更后重生成并**人工核对 diff** |
| 语法冒烟测试 | `python3 editors/vscode/test/check-grammar.py` | 校验插件高亮，**不进** run.sh |
| 端到端（end-to-end） | examples 层 | 生成→构建→运行→比对 |

### 6. 阶段与路线

| 术语 | 形式 | 说明 |
| --- | --- | --- |
| 阶段（Phase） | Phase 0 / 0.1 / 0.2 / 0.3（剥离越位）/ 1（自举）/ 2–5（恢复 + 新增特性）/ 6（生态）/ 7（工具链） | 见 [roadmap](roadmap.md)；编号与版本一一对应（Phase *n* ↔ `v0.n.x`） |
| 子阶段（sub-phase） | 1.0–1.7 + 1.9（1.8 `map` 移至 Phase 6） | 越位实现期的落地顺序 |
| 出口标准（exit criteria） | 每阶段的验收清单 | |
| 设计决策 | D1–D8、D-A | 见 [design/restore.md](design/restore.md) §6 |
| 自举（bootstrap / self-hosting） | L0 → L1 → L2 | 用 CT 重写编译器 |
| 吃自己的狗粮（dogfooding） | — | 用 CT 写 CT 工具链 |
| 非目标（non-goal） | — | 明确不做的事 |
| 设计债（design debt） | architecture §7 | 已知取舍 |

### 7. 生态与嵌入式

| 术语 | 形式 | 说明 |
| --- | --- | --- |
| 平台映射头 | `ct_platform.h` | 厂商提供；宏只出现在这里 |
| 标准外设 trait | `Logger` / `Clock` / `Allocator` / `Readable` / `Writable` / `Random` / `Connectable` | 覆盖 80% 平台差异需求 |
| 绑定（bindings） | 每个库一个 `.h.ct` | 随 Phase 6 的 `map` 推进，**未实现** |
| 反向映射表（reverse mapping table） | sidecar `.ctmap.json` | 生成的 C 符号 ← CT 定义点；排期 Phase 6（D8） |

### 8. 许可

| 术语 | 形式 | 说明 |
| --- | --- | --- |
| 编译器许可 | GPL-3.0-or-later | `LICENSE` |
| 输出例外（output exception） | `LICENSE.EXCEPTION` | 生成物**不受** GPL 约束，声明随产物走 |
| 许可标识 | SPDX | `ctc.c` 顶部与生成物 banner 中保留 |

---

## English

### 0. Hard naming rules (deliberately not unified — do not "fix")

| Term | Code / CLI form | Notes |
| --- | --- | --- |
| ct (CT = *C with Traits*) | `ct`, source suffix `.ct` | the language / project |
| ctc | `ctc` | today's compiler command |
| ct (final single entry) | `ct` | decided shape: single-entry `ct`, `ctc` kept as a compatibility alias; **not implemented yet** |
| ct-lang | repository name `ct-lang` | **only the GitHub repository name**, not the language / command / suffix |

> Never write `ct` / `ctc` / `.ct` as `ct-lang` / `ctlang` / `.ctlang` (AGENTS §7).

### 1. Language constructs

| Term | Code form | Notes |
| --- | --- | --- |
| trait | `trait T { void m(); };` | a set of method signatures; yields the vtable type `<T>_vtbl` |
| struct | `struct S { … } use T;` | data fields + a `use` clause |
| impl | `impl T for S { … }` | binds a trait's methods to a concrete struct |
| use-clause | `} use T, U;` | the traits a struct implements |
| self | `self`, `self->m()` | the receiver inside a method body; expanded to `_self` |
| namespace | `namespace A::B { … }` | the only nestable construct; symbols get the `A_B_` prefix. **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| namespace path | `A::B`, `A::B::Name` | `::` separates segments; the trailing `.` accesses a member / method |
| import | `import A::B;` | a compilation-unit dependency (in `ct build`). **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| pub | `pub trait` / `pub struct` / `pub int f(…);` | in multi-file mode the symbol crosses into the `.h`; the prefix itself is stripped |
| static | `static` | a supported visibility; the symbol stays in the `.c` |
| Drop | `use Drop`, `impl Drop for S { … }` | a **reserved** built-in trait; the release function is emitted lazily |
| delete | `delete p;` | expands to `free` for a pointer; with `use Drop` it recurses `drop()` first |
| AutoDrop | `own T *p = malloc(…);` | releases at scope exit / before a line-initial `return`: `drop()` + `free()` + null (Phase 5; CT line only, L0 does not know it) |
| map | `map trait T for instance x { m() → CALL; }` | maps a trait method onto an SDK call (**not implemented**; moved off the self-hosting core, lands in Phase 6, D8) |
| interface value / iface | `struct <T>_iface`, `T x = p;` | a fat pointer: `void *self` + `struct <T>_vtbl *vt` |
| vtable | `struct <Trait>_vtbl` | a table of function pointers |
| vptr | `__<trait>_vptr` | the struct field pointing at its vtable |
| boxing | `Greeter g = p;` | turning a struct value / pointer into an interface value |
| dispatch | `p.m()` → `p.__<t>_vptr->m(&p)` | the run-time call through the vtable |
| receiver | the `p` in `p.m()` | the subject of a method call |
| qualified reference | `A::B::S` | referring to a type by name across namespaces |
| top level | code with no `namespace` | gets no prefix; output is byte-identical to Phase 0 |
| positional initialiser | `Person p = { "Tom" };` | in field order |
| designated initialiser | `Person p = { .name = "Tom" };` | by field name |
| empty initialiser | `Person p = {};` | writes only the vptr |

### 2. Naming / mangling rules (a published contract)

| Term | Code form | Notes |
| --- | --- | --- |
| mangling | `A::B::S` → `A_B_S` | the empty / top-level namespace adds **no** prefix |
| mangled C name (cname) | `Trait.cname` / `Struct.cname` | the canonical C symbol name |
| vtable type | `<Trait>_vtbl` | |
| interface value type | `<Trait>_iface` | |
| vptr field | `__<trait>_vptr` | lowercased trait name; the field is scoped to the struct, so **no** namespace prefix |
| method function | `<Struct>_<Trait>_<method>` | |
| vtable variable | `<Struct>_<Trait>_vtable` | |
| file-scope constructor | `__ct_init` | `static void __ct_init(void) __attribute__((constructor))`: writes file-scope objects' / arrays' vptrs before `main` (D5=A) |

> These are **published naming rules**; do not change them unless the user explicitly asks (AGENTS §2).

### 3. Compiler implementation

| Term | Code form | Notes |
| --- | --- | --- |
| source-to-source compiler | `ctc.c` | input `.ct`, output plain C |
| single-file mode | `ct compile` / `ctc <file>` | `.c` is self-contained; Phase 0 behaviour |
| multi-file mode | `ct build <a.ct> … -o <dir>` | the `.c` `#include`s its own `.h`. **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| pass-through | any non-construct line | copied verbatim |
| line rewriting | `transform_line` etc. | processed line by line; a construct and a statement sharing a line are not rewritten |
| `die()` | `die(pos, fmt, …)` | the only error exit: `file:line:col: error:` then `exit(1)` |
| diagnostic format | `file:line:col: error: message` | lowercase, no trailing period, identifiers in single quotes |
| Buf | `buf_init` / `buf_puts` / `buf_putc` / `buf_putn` | never `strcat` |
| allocation | `xmalloc` / `xstrndup` | fail fast with `exit(1)` |
| capacity limit | `MAX_*` constants (top of the file) | overflow is a hard `die` — **never a silent truncation** |
| partition | utilities → source scanning → symbol tables → signature parsing → emitters → construct parsers → line rewriting → `main` | new functions go into their partition |
| lazy generation | drop bodies | only types reached by `delete` get a body — zero overhead. **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| drop closure | `mark_drop_closure()` | a deleted type pulls in its Drop value fields recursively. **Same; moved out of L0** |
| output banner | top of every generated file | provenance comment + the **output exception**, never deleted |
| self-contained | the single-file `.c` | does not `#include` the generated `.h` |
| include guard | `#ifndef` … `#endif` in the `.h` | |
| unit | one `.ct` → a `.c`/`.h` pair | compiled once in `ct build`. **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| dependency order | topological order | the import DAG sorted. **Same; moved out of L0** |
| driver | `compile_range` / `compile_file` / `compile_main` | orchestration; touches no parsing / generation logic — L0 is single-file only now |
| `#line` mapping | `#line <src line> "<.ct>"` | on by default in multi-file, off single-file (D4=A). **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| line emission | `line_of` / `line_at` / `line_break` | offset→line cache / emit / force a re-emit at a block boundary. **Same; moved out of L0** |
| leak warning | `potential_leak` · `leak_check_scope` · `leak_check_return` | conservative: still owned at scope end is a definite leak (kind 0); a conditional `return` leaving a non-returned object behind reports once as `may leak on a return path` (kind 2, JSON carries `path_line`); since Phase 6.2 a `T *q = f();` whose callee may return its own allocation (`ret_owned`) counts `q` as owned too. **Implemented by Phases 4/5/6 under `selfhost/src/**`** |
| owned (heap-holding) | `Var.owned` / `own_line` / `autodrop` | marked at the creation site by `T *p = malloc/calloc(...)`; from Phase 6.2 also by `T *q = f()` when `f`'s `ret_owned` is set and it returns the same struct pointer; `own` additionally sets `autodrop` (Phase 5). **Implemented under `selfhost/src/**`** |
| error recovery | `setjmp` guard + `recover_pos` | `die` reports and longjmps back to `compile_range`'s guard, resyncing past the next `}` or the start of the next line; capped by `MAX_ERRORS=20`, and a failing compile drops its artifacts and closes with `ctc: N error(s) generated`. Added by Phase 4 slice 3 (**new**, no oracle) |
| semantic check | `duplicate trait/struct` · `signature_mismatch` | duplicate definitions are errors judged on the cname (namespaces stay isolated); a differing return type / parameter count between impl and trait is a warning (**parameter types are not compared**). Added by Phase 4 slice 4 (**new**, no oracle) |

### 4. CLI and output

| Term | Form | Notes |
| --- | --- | --- |
| the `compile` subcommand | `ct compile <in.ct> [-o out.c]` | the default subcommand (same as `ctc <in.ct>`) |
| the `build` subcommand | `ct build <in.ct>… [-o <dir>]` | the multi-file driver; emits `.c`/`.h` and prints the suggested `cc` command. **Moved out of L0 in Phase 0.3; now implemented in CT by the self-hosted compiler (`selfhost/`)** |
| output option | `-o <file\|dir>` | |
| `#line` switch | `--line` / `--no-line` | overrides the per-mode default |
| help / version | `-h`/`--help`, `-v`/`--version` | |
| JSON diagnostics | `--diagnostics=json` / `--diagnostics=text` | warning format: JSON to stdout (`ct compile`), text human-readable stderr (default); leak warnings only, for now (Phase 1.7). **Restored by Phase 4 slice 2 under `selfhost/src/**`** |
| incremental cache | `<outdir>/.ctcache/<unit>.key` | Phase 6.3: one key per unit (path + `mtime.size` + version + `--line`/`--diagnostics` + dependency digests); a matching key with the `.c/.h` still on disk skips regeneration. **A hit replays neither `#line` nor warnings**; `--emit-map` never hits. The recompile set is the `order` prefix plus the dependency closure |

### 5. Testing

| Term | Form | Notes |
| --- | --- | --- |
| test suite (runner) | `./test/run.sh` | exit 0 = all green; `CC=gcc` selects a compiler |
| layer | build / unit / cases / errors / examples / limits / cli | the `multifile` / `import` / `line` layers were removed with Phase 0.3 |
| golden baseline | `*.expected.c` / `.expected.h` / `.expected.out` | **regenerate only**, never hand-write |
| fixture | `test/cases/*.ct`, `test/errors/*.ct` | |
| positive case | `test/cases/` | generate → byte diff → compile → run |
| negative case | `test/errors/<name>.expected-err` | `ctc` must exit non-zero with the expected diagnostic |
| white-box unit test | `test/unit/test_helpers.c` | `#include "../../ctc.c"` to reach `static` functions |
| regeneration | `./ctc <case>.ct -o <case>.expected.c` | after an intended behaviour change, regenerate **and review the diff** |
| grammar smoke test | `python3 editors/vscode/test/check-grammar.py` | checks the editor grammar, **stays out of** run.sh |
| end-to-end | the examples layer | generate → build → run → compare |

### 6. Stages and roadmap

| Term | Form | Notes |
| --- | --- | --- |
| phase | 0 / 0.1 / 0.2 / 0.3 (strip the over-reach) / 1 (self-hosting) / 2–5 (restore + add features) / 6 (ecosystem) / 7 (toolchain) | see [roadmap](roadmap.md); numbers map one-to-one onto versions (Phase *n* ↔ `v0.n.x`) |
| sub-phase | 1.0–1.7 + 1.9 (1.8 `map` moved to Phase 6) | the over-reach phase's landing order |
| exit criteria | each phase's acceptance list | |
| design decisions | D1–D8, D-A | see [design/restore.md](design/restore.md) §6 |
| bootstrap / self-hosting | L0 → L1 → L2 | rewriting the compiler in CT |
| dogfooding | — | using CT to build CT's own toolchain |
| non-goal | — | something explicitly out of scope |
| design debt | architecture §7 | a known trade-off |

### 7. Ecosystem and embedded

| Term | Form | Notes |
| --- | --- | --- |
| platform mapping header | `ct_platform.h` | vendor-provided; macros appear only here |
| standard peripheral traits | `Logger` / `Clock` / `Allocator` / `Readable` / `Writable` / `Random` / `Connectable` | covering 80% of platform-difference needs |
| bindings | one `.h.ct` per library | lands with Phase 6's `map`; **not implemented** |
| reverse mapping table | a sidecar `.ctmap.json` | generated C symbol ← CT definition site; lands in Phase 6 (D8) |

### 8. Licensing

| Term | Form | Notes |
| --- | --- | --- |
| compiler licence | GPL-3.0-or-later | `LICENSE` |
| output exception | `LICENSE.EXCEPTION` | generated output is **not** covered by the GPL; the notice travels with the output |
| licence identifier | SPDX | kept at the top of `ctc.c` and in the generated banner |
