# ctc 内部架构

> 中文 · [English](#english)

面向要修改 `ctc.c` 的人/代理。读完本文应能定位「某个行为由哪个函数负责」以及「加新语法该动哪里」。

---

## 中文

### 1. 设计目标

| 目标 | 具体含义 |
| --- | --- |
| 单文件 | 全部实现放在 `ctc.c`，`gcc ctc.c -o ctc` 一步可构建 |
| 可通读 | 无第三方依赖、无自动生成代码、无构建系统；总量控制在千行量级 |
| 结构转换 | 只做「识别 + 重写」，不做类型检查、不做语义分析、不做优化 |
| 输出可读 | 生成结果是普通 C，命名可预测，缩进干净，可直接被人阅读和调试 |
| 失败要响 | 无法解析就带行列号报错退出，绝不静默生成坏代码（个别截断除外，见设计债） |

非目标：完整的 C 语法分析（不做 token 流、不做 AST）、错误恢复、多文件、跨平台构建系统。

### 2. 数据流

```
argv
 │
 ├─ read_file()           整文件读入 g_src（g_len），并归一化 CRLF → LF
 │
 ├─ write_guard()         写出 .h 的 include guard（guard 名存入 g_guard）
 │
 └─ 主循环 while (pos < g_len)
      │  取当前行首（跳过空格/制表符）得到 q
      │
      ├─ word_at(q,"trait")  且名字后有 '{'  → parse_trait()  ┐
      ├─ word_at(q,"impl")                    → parse_impl()   ├─ 内部直接 emit 到 g_out / g_hout
      ├─ word_at(q,"struct") 且名字后有 '{'  → parse_struct() ┘
      │
      └─ 其它 → emit_raw_line(ls, le)
                  │
                  ├─ 以 '#' 开头 → 原样写出
                  └─ transform_line()
                       ├─ try_var_decl()   声明改造：补 `struct`、追加 vptr 指定初始化、登记变量
                       └─ transform_calls() 调用重写：x.m(args) → x.__t_vptr->m(&x, args)

 循环结束 ─ fputs("#endif /* GUARD */") → 关闭两个文件
```

**单趟流式**是刻意的选择：源码顺序即输出顺序，因此生成物与手写代码的阅读顺序一致（`trait` 展开仍在 `struct` 之前、`impl` 的静态函数仍在 `main` 之前）。
代价是**无法前向引用** —— 由此产生了「trait 必须先于 struct 定义」「impl 必须先于调用它的函数」这些约束。

### 3. 函数分区（代码内保持同一顺序）

| 分区 | 函数 | 职责 |
| --- | --- | --- |
| 工具 | `xmalloc` `xstrndup` `is_ident_char` | 内存与字符判断，失败即退出 |
| | `die` | 唯一报错出口，把字节偏移换算成 `行:列` 后 `exit(1)` |
| | `trim` `trim_right_len` `to_lower` `set_cname` | 字符串杂务；`set_cname` 拼 `命名空间前缀 + 名字`（超长报错） |
| | `Buf` / `buf_init` / `buf_putn` / `buf_puts` / `buf_putc` | 动态字符串缓冲，行重写的主要输出载体 |
| 源扫描 | `word_at` | 词边界匹配，替代裸 `strncmp`，避免 `structx` 误判 |
| | `skip_literal` `skip_comment` `skip_ws_comments` | 跳过字符串/字符字面量与注释；保证不误改字面量内文本 |
| | `read_ident` `copy_ident` | 读 / 拷贝标识符；超过 `MAX_NAME` 即 `die`，不静默截断 |
| | `match_delim` | 在 `g_src` 上做括号配对，自动跳过字面量与注释 |
| | `line_of` | 字节偏移 → 1-based 源行号（带缓存，前向遍历保持线性） |
| 符号表 | `find_trait` `find_struct` `find_struct_c` `find_trait_c` `struct_uses` `find_var` | 线性查找（规模小，不引入哈希）；`find_trait` / `find_struct` 先查当前命名空间再回退顶层，`*_c` 按已修饰的 C 名精确查找 |
| | `resolve_method` | 按 struct 的 `use` 顺序找方法归属的 trait |
| 签名解析 | `is_type_keyword` `param_type_only` `parse_params` `split_decl` | 把 `int add(int a, int b)` 拆成 ret / name / params / 参数类型表 |
| | `last_ident` `last_qual_name` `qual_to_c` `span_qualified` | 取末尾标识符 / 命名空间路径 `A::B::Name`，并把它修饰成 C 名 `A_B_Name` |
| 生成器 | `emit_trait_def` `emit_struct_def` | 生成 vtable 类型与 struct 定义（同时写 `.c` 与 `.h`） |
| | `line_at` `line_break` | `#line` 发射（Phase 1.5）：仅在映射不连续时写 `#line <源行> "<.ct>"`（追踪 `.c`，不动 `.h`）；`line_break` 让下一行强制重发（生成块边界） |
| | `replace_self` | 方法体内 `self` → `_self`（token 级，跳过字面量与注释），并把 `self->m(...)` 重写为 `_self->__<trait>_vptr->m(_self, …)` |
| | `emit_body` | 去公共缩进 + 统一 4 空格重排方法体 |
| | `body_calls_sibling` | 探测方法体是否调用了兄弟方法（决定是否需要 vtable 前向声明） |
| 构造解析 | `parse_trait` `parse_struct` `parse_impl` | 三个顶层构造的识别、校验与生成 |
| 行重写 | `line_literal_end` `line_match_paren` `decl_end_is_bare` | 行内（栈上字符串）版本的字面量跳过、括号配对、声明尾部判定 |
| | `parse_func_sig` `analyse_param` | 识别普通函数定义/原型，限定签名里的 struct 类型，并在有函数体时登记参数 |
| | `parse_fields` `find_field` | 部分解析 struct 体：补 `struct ` 限定，并把嵌套 ct-struct 字段记进字段表 |
| | `put_own_vptr` `needs_nested_init` `put_nested_assignments` `put_heap_vpts` | 生成对象自身 vptr 的指定初始化项；递归生成嵌套字段的 vptr 赋值语句；为 `malloc` 得到的堆对象写 vptr（`->`） |
| | `try_delete` | `delete p;` → `if (p) free(p);`（Phase 1 起对任意指针生效，含 `char *`） |
| | `emit_qualified_type` `trait_has_method` `find_func` | 类型展开（`struct ` / `_iface` 后缀）、接口方法判定、函数签名表查询 |
| | `box_to_iface` `try_iface_decl` `try_iface_assign` `try_return` | 接口多态：装箱（复合字面量）、接口变量声明/赋值、接口返回值 |
| | `scope_track` | 花括号块作用域：每个 `{` 压栈 `g_nvars`，`}` 弹栈回滚；弹栈前检查关闭作用域内仍 owned 的堆对象（泄漏警告） |
| | `line_has_word` `line_assign_eq` `leak_observe` `warn_add` `leak_check_scope` | Phase 1.7 泄漏跟踪：行级推断 `delete` / `return` / 逃逸并清除 owned，作用域关闭时上报 `potential_leak` |
| | `transform_calls` | 单行内的方法调用重写状态机 |
| | `try_var_decl` `read_qual_ref` | 识别 `Type var = {...}`（含限定名 `A::B::Type`）并改造、登记变量 |
| | `transform_line` `emit_raw_line` | 串联上述两步并写出 |
| 驱动 | `usage` `default_output` `header_path` `write_guard` `read_file` `compile_range` `compile_file` `build_output` `file_exists` `collect_imports` `resolve_import` `unit_visit` `build_main` `compile_main` `main` | 命令行、路径推导、文件 I/O、主循环（`compile_range` 递归处理 `namespace`；`compile_file` 单次编译；`collect_imports`/`resolve_import`/`unit_visit` 做 `import` 的解析与依赖序；`build_main` 多文件驱动；`main` 分派子命令） |

### 4. 数据结构与符号表

```c
Method { ret, name, params(verbatim), ptypes[][](仅类型), nparams }
Trait  { name, cname, m[MAX_METHOD], nm }
Struct { name, cname, use_t[MAX_TRAITS][], use_i[MAX_TRAITS], nu }
Var    { name, s }              /* s 为 g_structs 下标 */
ImplMethod { name, params, bstart, blen }   /* 方法体只存 g_src 的偏移+长度，不复制 */
```

- 三个全局表：`g_traits` / `g_structs` / `g_vars`，容量见 `language-spec.md` 第 7 节。
- `cname` 是**命名空间修饰后的 C 名**（`namespace A::B` 内的 `Person` → `A_B_Person`；顶层即原名），
  生成器一律用它；`name` 保留短名用于查找与诊断，`use_i` 记所用 trait 的下标（不依赖当前命名空间）。
- **变量表是「名字 → struct 下标」的扁平表**，靠 `scope_track` 在 `{}` 处回滚 `g_nvars` 实现块作用域；跨行调用、登记前调用仍不重写。
- impl 方法体不复制，只记录 `g_src` 中的区间；只有真正要输出、需要改写 `self` 时才经 `Buf` 复制一次。

### 5. 关键算法

**括号配对（`match_delim`）**
从 `{` / `(` 出发做深度计数，遇到 `"` `'` 走 `skip_literal`，遇到 `//` `/*` 走 `skip_comment`，因此注释或字符串里的括号不会破坏配对。这是能安全跨越任意方法体的基础。

**签名抽取（`split_decl` + `parse_params` + `param_type_only`）**
- `split_decl`：以第一个 `(` 为界，左侧文本的**最后一个标识符**是方法名，其余是返回类型；再把括号内文本交给 `parse_params`；`(` 之后除空白外不允许有其它字符。
- `parse_params`：按**顶层**逗号切分（追踪 `()`、`[]` 深度）；整段等于 `void` 视为无参。
- `param_type_only`：去掉参数名得到 vtable 里的类型 —— 从尾部取标识符，若它是类型关键字（`void`/`unsigned`/`size_t` …）或以 `*` 结尾则保留，否则删掉。
  这是启发式：`unsigned int` 不会被误删，`char *name` 会正确变成 `char *`。

**方法体排版（`emit_body` + `replace_self`）**
先 `replace_self` 做 token 级替换（字符串/字符/注释内不动）：`self` → `_self`，且 `self->m(...)` 重写为 `_self->__<trait>_vptr->m(_self, …)`（`m` 需能解析为某 trait 的方法）；再按行扫描：跳过首尾空行，取所有非空行的**最小缩进**作为基准，输出时统一加上 4 空格前缀并裁掉基准缩进 —— 相对缩进（如嵌套 `if`）得以保留。若某方法体存在兄弟方法调用，`parse_impl` 会在方法函数之前先输出一行 vtable 前向声明。

**声明识别与改造（`try_var_decl`）**
要求整行以「已知 struct 名」或「`struct` + 已知 struct 名」开头（行首允许空格）；解析出变量名后：
- 若紧跟 `*` → 判定为指针声明，补 `struct` 限定符并保留类型名，同时把变量登记为**指针**（供 `p->m()` 重写；已经是 `struct X *p` 时原样返回但仍然登记）；
- 否则登记变量，并检查是否 `= { … }`：无论指定初始化、位置式还是空列表，都在 `}` 前插入 vptr 指定初始化项（由 `put_vptr_designators` 生成，多 trait 按 `use` 顺序）；若声明**无初始化式**（`Person p;`），则改写为 `= { <vptr> }`。

**调用重写（`transform_calls`）**
单行状态机，逐字符推进，遇到字面量/注释整体跳过；读到标识符时查变量表，命中后按变量类别改写：
- 非指针变量 + `.成员(` → `var.__<trait>_vptr->成员(&var[, 参数…])`；
- 指针变量 + `->成员(` → `var->__<trait>_vptr->成员(var[, 参数…])`（**不补 `&`**）；
- 参数为空 → 就地补 `)` 并把扫描位置推到配对右括号之后；
- 参数非空 → 只改写调用头部，扫描继续在参数内部进行（因此嵌套调用 `q.add(1, q.add(2,3))` 能递归处理）。

### 6. 头文件生成策略

`.h` 与 `.c` 由同一批 `emit_trait_def` / `emit_struct_def` 产出，因此两边类型定义一致。
当前 `.c` **不** `#include` 自己的 `.h`（保证单文件可独立编译，也与期望输出一致），`.h` 仅作为类型的独立产物存在。
做多文件编译时，正确做法是把类型定义只留 `.h`，并让生成的 `.c`（在 banner 之后）`#include "<out>.h"` —— 届时需删掉 `.c` 里的重复定义。

两者的首部都带溯源注释 `Generated by ctc v<CTC_VERSION> from <输入路径>`：`.c` 的 banner 由 `main` 在扫描前直接写出，`.h` 的版本注释由 `write_guard` 写出。
因此**改 `CTC_VERSION` 会让 `test/cases/**` 的全部 golden 失效**，必须一并重新生成。

### 7. 设计债与风险

| 项 | 说明 | 影响 |
| --- | --- | --- |
| 变量表无作用域/无类型 | 全局扁平表，按源码顺序登记 | 同名变量互相干扰；声明前出现的调用不重写 |
| 单测与实现耦合 | `test/unit` 直接 `#include ctc.c` 调 `static` 函数 | 改被覆盖函数的签名/命名必须同步改单测（见第 9 节） |
| 字面量跳过逻辑有两份 | `g_src` 版（`skip_literal`）与行缓冲版（`line_literal_end`） | 修改时需同步，易漏 |
| 主循环重复前瞻 | 主循环里先探一次 `struct` 是否带 `{`，`parse_struct` 里再解析一次 | 轻微冗余，暂可接受 |
| 报错定位粒度 | 语义类错误（如未实现的方法）定位到构造起始行 | 多方法文件里定位不够精确 |
| 参数表上限偏小 | `MAX_PARAM` 256、`MAX_PARAMS` 16 | 复杂签名一律 `die`（不截断） |

### 8. 扩展点（Phase 1 落点）

| 新特性 | 状态 / 主要改动位置 |
| --- | --- |
| namespace | ✅ 已落地（Phase 1.1）：`compile_range` 递归处理 `namespace A::B { … }`；`find_trait` / `find_struct` 先查当前命名空间再回退顶层；`Trait` / `Struct` 增 `cname`（修饰后的 C 名） |
| 变量作用域 | ✅ 已落地（0.1.9）：`scope_track` 在 `{}` 处压栈、`}` 处回滚 `g_nvars` |
| 多文件编译 | 见第 6 节：类型定义下沉到 `.h`，`.c` 改为 `#include` |
| 错误恢复 | 主循环在 `die` 处改为「跳到下一个行首/下一个 `}` 后继续」，需要引入错误计数 |
| 自动化回归 | 见 `roadmap.md` 的测试策略 |

### 9. 测试如何挂到这份代码上

- `test/unit/test_helpers.c` 用 `#define main ctc_main_unused_in_tests` 再 `#include "../../ctc.c"`，
  把整个编译器拉进同一个翻译单元，从而能直接调用 `static` 函数 —— 在「单文件 + 全部 static」的结构下，
  这是做白盒单测的唯一办法。被覆盖的纯函数清单就写在那个文件里。
- 因此：**重命名、改签名或删除被单测覆盖的 `static` 函数，必须同步改 `test/unit/test_helpers.c`**。
- `test/cases/*` 不走白盒路径，而是由 `test/run.sh` 调用真实 CLI（`ctc <case>.ct -o …`），
  所以它同时覆盖了 `main`、路径推导（`default_output` / `header_path` / `write_guard`）与文件写出。
- `examples/**` 同样走真实 CLI（run.sh 的 examples 层），但只断言「能生成、能编译、运行输出与
  `.expected.out` 一致」而不比对展开结果，因此示例可以随特性演进而重写，不像 golden 那样要求
  逐字节稳定。两者用途不同：golden 锁住展开细节，examples 保证示例始终可运行。

---

## English

### 1. Design goals

Single file — everything lives in `ctc.c` and `gcc ctc.c -o ctc` builds it in one step. Readable end
to end — no third-party dependencies, no generated code, no build system, kept within roughly a
thousand lines. Structure rewriting only — recognise and rewrite, with no type checking, no semantic
analysis and no optimisation. Readable output — plain C with predictable naming and clean
indentation, meant to be read and debugged by a human. Fail loud — unparseable input exits with a
line/column error and never silently produces bad code (a few truncations excepted, see §7).

Non-goals: full C parsing (no token stream, no AST), error recovery, multiple files, and a
cross-platform build system.

### 2. Data flow

`read_file()` loads the whole source into `g_src` (`g_len`), normalising CRLF to LF; `write_guard()`
emits the header guard (the guard name goes into `g_guard`); the main loop then walks the buffer.
Each iteration takes the start of the current line (skipping spaces and tabs) and checks whether it
opens a top-level construct (`trait`, `struct` followed by `{`, `impl`), dispatching to `parse_trait`
/ `parse_struct` / `parse_impl`, which emit straight into the output files. Everything else goes
through `emit_raw_line`, which passes `#` lines through untouched and otherwise runs `transform_line`
(`try_var_decl` for declarations, then `transform_calls` for method calls). A final
`#endif /* GUARD */` closes the header, and both files are closed.

Single-pass streaming is deliberate: output order equals source order, so the generated file reads
like the original (trait expansions still precede structs, and impl static functions still precede
`main`). The price is the absence of forward references, which is why traits must precede structs
and impls must precede the functions that call them.

### 3. Function sections (kept in the same order in the code)

| Section | Functions | Responsibility |
| --- | --- | --- |
| Utilities | `xmalloc` `xstrndup` `is_ident_char` | memory and character checks; failures exit immediately |
| | `die` | the single error exit: converts a byte offset into `line:col`, then `exit(1)` |
| | `trim` `trim_right_len` `to_lower` `set_cname` | string chores; `set_cname` builds `namespace prefix + name` (errors when overlong) |
| | `Buf` / `buf_init` / `buf_putn` / `buf_puts` / `buf_putc` | dynamic string buffer, the main output vehicle of line rewriting |
| Source scanning | `word_at` | word-boundary matching, replacing bare `strncmp`, so `structx` is not misread |
| | `skip_literal` `skip_comment` `skip_ws_comments` | skip string/char literals and comments; text inside literals is never rewritten |
| | `read_ident` `copy_ident` | read / copy an identifier; over `MAX_NAME` is a hard error, never a silent truncation |
| | `match_delim` | delimiter matching over `g_src`, automatically skipping literals and comments |
| | `line_of` | byte offset → 1-based source line (cached, so a forward walk stays linear) |
| Symbol tables | `find_trait` `find_struct` `find_struct_c` `find_trait_c` `struct_uses` `find_var` | linear lookups (the scale is small, so no hashing); `find_trait` / `find_struct` try the current namespace then fall back to top level, `*_c` look up an already-mangled C name exactly |
| | `resolve_method` | find the trait a method belongs to, following the struct's `use` order |
| Signature parsing | `is_type_keyword` `param_type_only` `parse_params` `split_decl` | split `int add(int a, int b)` into ret / name / params / a parameter-type table |
| | `last_ident` `last_qual_name` `qual_to_c` `span_qualified` | take the trailing identifier / namespace path `A::B::Name` and mangle it into a C name `A_B_Name` |
| Emitters | `emit_trait_def` `emit_struct_def` | generate vtable types and struct definitions (writing both `.c` and `.h`) |
| | `line_at` `line_break` | `#line` emission (Phase 1.5): write `#line <src line> "<.ct>"` only where the mapping diverges (tracks the `.c`, never the `.h`); `line_break` forces the next line to re-emit (at generated-block boundaries) |
| | `replace_self` | `self` → `_self` inside method bodies (token level, skipping literals and comments), rewriting `self->m(...)` into `_self->__<trait>_vptr->m(_self, …)` |
| | `emit_body` | strip the common indentation and re-layout method bodies on a uniform 4-space base |
| | `body_calls_sibling` | detect whether a body calls a sibling method (decides if a vtable forward declaration is needed) |
| Construct parsers | `parse_trait` `parse_struct` `parse_impl` | recognition, validation and generation of the three top-level constructs |
| Line rewriting | `line_literal_end` `line_match_paren` `decl_end_is_bare` | in-line (stack-string) versions of literal skipping, paren matching and declaration-tail detection |
| | `parse_func_sig` `analyse_param` | recognise ordinary function definitions/prototypes, qualify struct types in the signature and register parameters when a body follows |
| | `parse_fields` `find_field` | partial struct-body parsing: add `struct ` and record nested ct-struct fields in the field table |
| | `put_own_vptr` `needs_nested_init` `put_nested_assignments` `put_heap_vpts` | emit the object's own vptr designator; recursively emit vptr assignments for nested fields; write the vptrs (`->`) of a `malloc`ed heap object |
| | `try_delete` | `delete p;` → `if (p) free(p);` (since Phase 1 this holds for any pointer, `char *` included) |
| | `emit_qualified_type` `trait_has_method` `find_func` | type expansion (`struct ` / the `_iface` suffix), interface-method lookup, signature-table queries |
| | `box_to_iface` `try_iface_decl` `try_iface_assign` `try_return` | interface polymorphism: boxing (compound literal), interface declarations/assignments, interface returns |
| | `scope_track` | brace block scope: push `g_nvars` at every `{`, roll back at `}`; before rolling back it checks the closing scope for still-owned heap objects (leak warnings) |
| | `line_has_word` `line_assign_eq` `leak_observe` `warn_add` `leak_check_scope` | Phase 1.7 leak tracking: per-line `delete` / `return` / escape inference clears ownership; a scope exit reports `potential_leak` |
| | `transform_calls` | the single-line state machine that rewrites method calls |
| | `try_var_decl` `read_qual_ref` | recognise `Type var = {...}` (including the qualified `A::B::Type`), rewrite the declaration and register the variable |
| | `transform_line` `emit_raw_line` | chain the two steps above and write the line out |
| Driver | `usage` `default_output` `header_path` `write_guard` `read_file` `compile_range` `compile_file` `build_output` `file_exists` `collect_imports` `resolve_import` `unit_visit` `build_main` `compile_main` `main` | command line, path derivation, file I/O and the main loop (`compile_range` recurses into `namespace`; `compile_file` compiles one unit; `collect_imports`/`resolve_import`/`unit_visit` resolve `import`s and their dependency order; `build_main` is the multi-file driver; `main` dispatches subcommands) |

### 4. Data structures and symbol tables

```c
Method { ret, name, params(verbatim), ptypes[][](types only), nparams }
Trait  { name, cname, m[MAX_METHOD], nm }
Struct { name, cname, use_t[MAX_TRAITS][], use_i[MAX_TRAITS], nu }
Var    { name, s }              /* s is an index into g_structs */
ImplMethod { name, params, bstart, blen }   /* the body is stored as offset+length into g_src, never copied */
```

- Three global tables: `g_traits` / `g_structs` / `g_vars`; the capacities are listed in §7 of
  `language-spec.md`.
- `cname` is the **namespace-mangled C name** (`Person` in `namespace A::B` → `A_B_Person`; at top
  level it is just the name) and is what the emitters always use; `name` keeps the short form for
  lookup and diagnostics, and `use_i` records the index of each used trait (independent of the current
  namespace).
- The variable table is a flat name → struct-index map; block scope is provided by `scope_track`
  rolling `g_nvars` back at `}`, so multi-line calls and calls before registration are still not
  rewritten.
- Impl method bodies are not copied; only their range in `g_src` is recorded. The single copy through
  `Buf` happens only when the body is actually emitted and `self` has to be rewritten.

### 5. Key algorithms

- **Delimiter matching** (`match_delim`) counts nesting depth from a `{` / `(`, delegating `"` `'` to
  `skip_literal` and `//` `/*` to `skip_comment`, so brackets inside comments or strings never break
  pairing — which is what makes it safe to span arbitrary method bodies.
- **Signature extraction** (`split_decl` + `parse_params` + `param_type_only`): `split_decl` cuts at
  the first `(`, takes the last identifier on the left as the method name and the rest as the return
  type, and allows nothing but whitespace after the `(`; `parse_params` splits on top-level commas
  (tracking `()` and `[]` depth) and treats a lone `void` as no parameters; `param_type_only` derives
  the vtable type by dropping the trailing identifier unless it is a type keyword
  (`void`/`unsigned`/`size_t` …) or the text ends with `*` — a heuristic: `unsigned int` survives,
  `char *name` correctly becomes `char *`.
- **Body formatting** (`emit_body` + `replace_self`) runs `replace_self` first (token level; strings,
  chars and comments untouched): `self` → `_self`, and `self->m(...)` → `_self->__<trait>_vptr->m(_self, …)`
  when `m` resolves to a trait method. Then it scans line by line: leading and trailing blank lines are
  dropped, the minimum indentation of the remaining non-blank lines becomes the base, and each output
  line gets a uniform 4-space prefix with the base stripped — relative indentation (e.g. nested `if`s)
  is preserved. When a body calls a sibling method, `parse_impl` emits a vtable forward declaration
  before the method functions.
- **Declaration rewriting** (`try_var_decl`) requires the whole line to start with a known struct
  name, or `struct` plus a known struct name (leading spaces allowed). Once the variable name is
  parsed: if a `*` follows, it is a pointer declaration — the `struct` qualifier is added, the type
  name kept and the variable is **registered as a pointer** (so `p->m()` can be rewritten; an already
  qualified `struct X *p` is returned unchanged but still registered); otherwise the variable is
  registered and a `= { … }` list — designated, positional or empty — gets the vptr designated
  initialiser inserted before the closing `}` (built by `put_vptr_designators`, one per trait in `use`
  order). A declaration with **no** initialiser (`Person p;`) is rewritten into `= { <vptr> }`.
- **Call rewriting** (`transform_calls`) is a single-line state machine that advances character by
  character and skips literals and comments wholesale; when an identifier hits the variable table it is
  rewritten according to the variable's kind: a non-pointer variable followed by `.member(` becomes
  `var.__<trait>_vptr->member(&var[, args…])`, while a pointer variable followed by `->member(`
  becomes `var->__<trait>_vptr->member(var[, args…])` (**no `&` is added**). With empty arguments it
  inserts `)` in place and moves the scan past the closing paren; with non-empty arguments only the
  call head is rewritten and scanning continues inside the argument list, so nested calls like
  `q.add(1, q.add(2,3))` are handled recursively.

### 6. Header generation strategy

Both output files are produced by the same emitters (`emit_trait_def` / `emit_struct_def`), so their
type definitions always agree. The generated `.c` deliberately does not `#include` its own `.h` —
that keeps it self-contained (and consistent with the expected output), while the `.h` exists purely
as a standalone type artifact. When multi-file compilation arrives, the right move is to keep type
definitions only in the `.h` and have the generated `.c` `#include "<out>.h"` (after the banner),
dropping the duplicate definitions from the `.c`. Both files start with a provenance comment of the
form `Generated by ctc v<CTC_VERSION> from <input path>` — the `.c` banner is written by `main`
before the scan starts, the `.h` one by `write_guard` — so bumping `CTC_VERSION` invalidates every
golden under `test/cases/**` and they must be regenerated together.

### 7. Design debt and risks

| Item | Description | Impact |
| --- | --- | --- |
| Scope-less, type-less variable table | a global flat table, entries registered in source order | same-name variables interfere with each other; calls that appear before the declaration are not rewritten |
| Unit tests coupled to the implementation | `test/unit` `#include`s `ctc.c` directly to call `static` functions | renaming or re-signing a covered function requires updating the unit tests in sync (see §9) |
| Literal skipping exists in two copies | the `g_src` version (`skip_literal`) and the line-buffer version (`line_literal_end`) | the two must be updated together, which is easy to miss |
| Duplicate lookahead in the main loop | the main loop first probes whether `struct` is followed by `{`, then `parse_struct` parses it again | slight redundancy, acceptable for now |
| Coarse error positions | semantic errors (e.g. an unimplemented method) point at the start of the construct | imprecise locations in files with many methods |
| Small parameter limits | `MAX_PARAM` 256, `MAX_PARAMS` 16 | complex signatures always `die` (never truncate) |

### 8. Extension points (Phase 1 landing spots)

Namespaces **✅ landed (Phase 1.1)** — `compile_range` recurses into `namespace A::B { … }`, `find_trait`
/ `find_struct` try the current namespace then fall back to top level, and `Trait` / `Struct` gained a
`cname` (the mangled C name). Variable scopes **✅ landed (0.1.9)** — `scope_track` pushes at `{` and
rolls `g_nvars` back at `}`. Still to come: multi-file support (see §6: type definitions sink into the
`.h` and the `.c` switches to `#include`), error recovery (after `die`, skip to the next line start or
the next `}` and continue, which needs an error counter), and the automated regression suite described
in `roadmap.md`.

### 9. How the tests attach to this code

`test/unit/test_helpers.c` uses `#define main ctc_main_unused_in_tests` followed by
`#include "../../ctc.c"` to pull the whole compiler into a single translation unit — with a one-file,
all-`static` design this is the only way to call the helpers directly. The list of covered helpers
lives in that file, so **renaming, re-signing or removing a covered helper requires updating it too**.
The golden cases in `test/cases/*` do not use that trick: `test/run.sh` drives the real CLI
(`ctc <case>.ct -o …`), which also exercises `main`, the path derivation helpers
(`default_output`, `header_path`, `write_guard`) and file writing. The `examples/**` demos go through
the same real CLI in a separate layer, but they assert only that each demo generates, builds and
prints its `.expected.out` — they do not pin the expansion byte for byte, so examples may be rewritten
as the language evolves while the goldens stay frozen.
