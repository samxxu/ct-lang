# ctc 内部架构

> 中文

面向要修改 `ctc.c` 的人/代理。读完本文应能定位「某个行为由哪个函数负责」以及「加新语法该动哪里」。

---

## 中文

### 1. 设计目标

| 目标 | 具体含义 |
| --- | --- |
| 单文件 | 全部实现放在 `selfhost/l0/ctc.c`，`gcc selfhost/l0/ctc.c -o ctc` 一步可构建 |
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
| | `trim` `trim_right_len` `to_lower` | 字符串杂务：裁剪空白、大小写归一 |
| | `Buf` / `buf_init` / `buf_putn` / `buf_puts` / `buf_putc` | 动态字符串缓冲，行重写的主要输出载体 |
| 源扫描 | `word_at` | 词边界匹配，替代裸 `strncmp`，避免 `structx` 误判 |
| | `skip_literal` `skip_comment` `skip_ws_comments` | 跳过字符串/字符字面量与注释；保证不误改字面量内文本 |
| | `read_ident` `copy_ident` | 读 / 拷贝标识符；超过 `MAX_NAME` 即 `die`，不静默截断 |
| | `match_delim` | 在 `g_src` 上做括号配对，自动跳过字面量与注释 |
| 符号表 | `find_trait` `find_struct` `struct_uses` `find_var` `new_var` | 线性查找（规模小，不引入哈希）；按 C 名精确匹配（`cname` 即原名），`new_var` 预留下一个变量槽、溢出即 `die` |
| | `find_field_ex` `find_iface_field` `resolve_method` `trait_has_method` `find_func` | 查找 struct / 接口字段并报告是否为指针；按 `use` 顺序找方法归属的 trait；判定 trait 是否声明某方法；查函数签名表 |
| 签名解析 | `is_type_keyword` `is_stmt_keyword` `param_type_only` `parse_params` `split_decl` | 把 `int add(int a, int b)` 拆成 ret / name / params / 参数类型表 |
| | `last_ident` `already_qualified` `analyse_param` | 取文本末尾的标识符；判断类型名是否已被 `struct` 限定；分析单个声明片段（参数 / 字段 / 返回类型） |
| 生成器 | `emit_trait_def` `emit_struct_def` | 生成 vtable / 接口类型与 struct 定义（同时写 `.c` 与 `.h`） |
| | `emit_hoisted` | 若上一行重写提升了临时接收者，先写出该声明（必须在重写行之前生效） |
| | `replace_self` | 方法体内 `self` → `_self`（token 级，跳过字面量与注释）；调用派发交给 `transform_calls` 处理 |
| | `emit_body` `register_body_params` | 去公共缩进 + 统一 4 空格重排方法体；把方法参数登记为变量 |
| | `body_needs_vtable` `is_any_trait_method` | 探测方法体是否含将变成 vtable 分发的调用（`is_any_trait_method` 供其查询已声明的 trait 方法），决定是否需要 vtable 前向声明 |
| 构造解析 | `parse_trait` `parse_struct` `parse_impl` | 三个顶层构造的识别、校验与生成 |
| 行重写 | `line_literal_end` `line_match_paren` `decl_end_is_bare` | 行内（栈上字符串）版本的字面量跳过、括号配对、声明尾部判定 |
| | `parse_func_sig` | 识别普通函数定义/原型，限定签名里的 struct 类型，并在有函数体时登记参数 |
| | `parse_fields` | 部分解析 struct 体：补 `struct` 限定，并把字段记进字段表 |
| | `put_own_vptr` `needs_nested_init` `put_nested_assignments` `put_heap_vpts` | 生成对象自身 vptr 的指定初始化项；递归生成嵌套字段的 vptr 赋值语句；为 `malloc` 得到的堆对象写 vptr（`->`） |
| | `try_delete` | `delete p;` → `if (p) free(p);`（Phase 1 起对任意指针生效，含 `char *`） |
| | `emit_qualified_type` `trait_has_method` `find_func` | 类型展开（`struct ` / `_iface` 后缀）、接口方法判定、函数签名表查询 |
| | `box_to_iface` `try_iface_decl` `try_iface_assign` `try_return` | 接口多态：装箱（复合字面量）、接口变量声明/赋值、接口返回值 |
| | `scope_track` | 花括号块作用域：每个 `{` 压栈 `g_nvars`，`}` 弹栈回滚（方法参数经 `g_body_pre` 单独还原） |
| | `line_assign_eq` | 定位行内顶层的赋值 `=`（跳过 `==` / `!=` / 复合赋值与字面量、注释），供接口赋值等判定 |
| | `walk_method` `walk_to_iface_field` `transform_calls` | 单行内的方法调用重写状态机（`walk_method` / `walk_to_iface_field` 分别处理方法链与接口字段链） |
| | `try_var_decl` | 识别已知 struct / trait 的 `Type var …` 声明（含 `static`、指针、`malloc` 堆对象）并改造、登记变量 |
| | `transform_line` `emit_raw_line` | 串联上述两步并写出 |
| 驱动 | `usage` `default_output` `header_path` `write_guard` `read_file` `compile_range` `compile_file` `compile_main` `main` | 命令行、路径推导、文件 I/O 与单文件驱动（`compile_range` 单趟扫描，命中 `namespace` / `import` / `pub` 即 `die`；`compile_file` 编译一个文件；`main` 识别 `compile` 子命令、`build` 直接报错） |

### 4. 数据结构与符号表

```c
Method { ret, name, params(verbatim), ptypes[][](仅类型), nparams }
Trait  { name, cname, m[MAX_METHOD], nm }
Struct { name, cname, use_t[MAX_TRAITS][], use_i[MAX_TRAITS], nu }
Var    { name, s }              /* s 为 g_structs 下标 */
ImplMethod { name, params, bstart, blen }   /* 方法体只存 g_src 的偏移+长度，不复制 */
```

- 三个全局表：`g_traits` / `g_structs` / `g_vars`，容量见 `language-spec.md` 第 7 节。
- `cname` 是**生成器使用的 C 名** —— 命名空间修饰已随 Phase 0.3 移出，故当前它只是 `name` 的原样拷贝；
  生成器一律用它，`name` 保留短名用于查找与诊断，`use_i` 记所用 trait 的下标。
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
- 否则登记变量，并检查是否 `= { … }`：无论指定初始化、位置式还是空列表，都在 `}` 前插入 vptr 指定初始化项（由 `put_own_vptr` 生成，多 trait 按 `use` 顺序）；若声明**无初始化式**（`Person p;`），则改写为 `= { <vptr> }`。

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

两者的首部都带溯源注释 `Generated by ct v<CTC_VERSION> from <输入路径>`：`.c` 的 banner 由 `main` 在扫描前直接写出，`.h` 的版本注释由 `write_guard` 写出。
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
| 嵌套初始化递归无显式深度守卫 | `put_nested_assignments`（L1441）对 `nu > 0` 的嵌套链在 L1461 短路，绕过 `needs_nested_init` 的 `MAX_DEPTH` 检查；递归深度只受 `MAX_STRUCT`(32) 间接约束 | 当前**不是**可复现崩溃——值互相引用在 CT 中无法表达，链必为无环有限；若将来支持前向声明，这里会变成无限递归，需补显式深度守卫（2026-10-16 审计结论，接受现状） |
| 诊断点的可达性分四类 | **真防御**：`expected struct name`（L1187）/ `expected '{' after struct`（L1189）——派发处已要求「名字 + `{`」才进 `parse_struct`。**可达·已覆盖**：`cannot open`（L2703）与 `short read`（L2711），由 `cli/cannot-open` / `cli/short-read` 钉住。**可达·已补**：`cannot create a temporary file`（L2837，`tmpfile()` 失败，macOS 遵循 `$TMPDIR`）与 `cannot read`（L2708，FIFO 等不可 seek 的输入），由 `cli/tmpfile-cannot-create` / `cli/cannot-read` 钉住。**未复现**：`put_heap_vpts` 版的 `nested field path too long`（L1491）——深链探针未命中，但「未复现」不等于「不可达」，保留为待复核项。**不可测**：`out of memory`（L158/L237） | 2026-10-17 审计逐个探针复核，结论见左列 |

### 8. 扩展点（Phase 1 落点）

| 新特性 | 状态 / 主要改动位置 |
| --- | --- |
| namespace | ⛔ 已随 Phase 0.3 移出 L0（命中即 `die`：`'namespace' is not supported by this compiler`）；Phase 2–5 用 CT（L1 / `selfhost/l2/**`）重做 |
| 变量作用域 | ✅ 已落地（0.1.9）：`scope_track` 在 `{}` 处压栈、`}` 处回滚 `g_nvars` |
| 多文件编译 | ⛔ 已随 Phase 0.3 移出 L0；Phase 2 起由 CT 层的多单元构建承载（L1 的 `build` + `import`，`selfhost/l2/**`） |
| 错误恢复 | ✅ Phase 4 已在 CT 侧落地（`setjmp` 守卫 + `recover_pos`，`MAX_ERRORS=20`），见 `roadmap.md` Phase 4；L0 仍是「一处错误即停」 |
| 自动化回归 | 见 `roadmap.md` 的测试策略 |

### 9. 测试如何挂到这份代码上

- `test/unit/test_helpers.c` 用 `#define main ctc_main_unused_in_tests` 再 `#include "../../selfhost/l0/ctc.c"`，
  把整个编译器拉进同一个翻译单元，从而能直接调用 `static` 函数 —— 在「单文件 + 全部 static」的结构下，
  这是做白盒单测的唯一办法。被覆盖的纯函数清单就写在那个文件里。
- 因此：**重命名、改签名或删除被单测覆盖的 `static` 函数，必须同步改 `test/unit/test_helpers.c`**。
- `test/cases/*` 不走白盒路径，而是由 `test/run.sh` 调用真实 CLI（`ctc <case>.ct -o …`），
  所以它同时覆盖了 `main`、路径推导（`default_output` / `header_path` / `write_guard`）与文件写出。
- `examples/**` 同样走真实 CLI（run.sh 的 examples 层），但只断言「能生成、能编译、运行输出与
  `.expected.out` 一致」而不比对展开结果，因此示例可以随特性演进而重写，不像 golden 那样要求
  逐字节稳定。两者用途不同：golden 锁住展开细节，examples 保证示例始终可运行。
