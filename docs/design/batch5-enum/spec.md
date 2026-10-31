# 第五批特性：`enum`、常量表达式与 `offsetof`（2026-10-29）

> 锚点：`7016872`（控制流批收口），工作树干净。
> 本规格只做 `enum`、`case` 标签可用的最小常量表达式、`offsetof` 内建；
> `union`、`goto` / 标签、匿名枚举声明符、`switch` 重复值检测留给后续批次。

## 1. 实测现状

ct-ast 实编实测（`/tmp/b4/ct-ast`，逐构造微探针）：

| 用法 | 现状 |
| --- | --- |
| `enum Color { RED, GREEN = 5, BLUE };` | ❌ `unexpected token`（列号落在 `{`） |
| `offsetof(struct S, b)` | ❌ `use of an undeclared variable`（列号落在字段名） |
| `case (1 + 2):` | ❌ `a case label must be an integer constant`（无常量折叠） |
| `c = 'a';`（字符字面量在表达式里） | ✅ 原样发射（词法器保留引号，`N_STR` 逐字打印） |
| `struct` / `typedef` / `switch` / `do-while` | ✅ |
| `union` | ❌（非目标） |

三条报错的机制都不是「不认识关键字」：

- `enum` 已经在 [is_type_word](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L128-L139) 的类型词表里，但 [parse_type](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L158-L215) 只对 `struct` 做了「吃掉标签」的分支，`enum` 走的是普通类型词路径，于是标签 `Color` 被当作下一个声明符，`{` 撞上 `expected a name` 之后的兜底路径；
- `offsetof` 不在符号表里，也不是全大写，[parse_primary](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L857-L1052) 走到「未声明变量」；
- `case` 的标签由 [parse_case_value](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Stmt.h.ct#L595-L626) 逐个 token 取值，只认 `数字` / 引号字面量 / 单个标识符，括号一来就报错。

## 2. 范围

| 编号 | 内容 | 归属 |
| --- | --- | --- |
| F1 | `enum Tag { A, B = <常量>, C };`（顶层，标签必填，允许尾逗号）与 `typedef enum [Tag] { … } Alias;` | `frontend/parse/Parser.h.ct`、`frontend/sym/Symbols.h.ct`、`backend/emit/Emitter.h.ct` |
| F2 | 枚举成员作为常量：裸名引用、命名空间 mangling、`pub enum` 进头文件、跨单元按常量表导入 | 同上 + `frontend/module/Module.h.ct` |
| F3 | `case` 标签接受整数常量表达式（`+ - * / % << >> \| & ^ ~`、括号、`!`、`sizeof`、`offsetof`、字符字面量、枚举成员、全大写宏名） | `frontend/parse/Stmt.h.ct`、`frontend/parse/Expr.h.ct`、`backend/emit/Emitter.h.ct` |
| F4 | `offsetof(struct S, f)` 内建（含字段有效性校验） | `frontend/parse/Expr.h.ct`、`backend/emit/Emitter.h.ct`、`frontend/type/TypeCheck.h.ct` |
| 配套 | 正例 / 负例 fixture、`check-ast.sh` 断言、`docs/language-spec.md` 中英对称 | `test/ast/**`、`selfhost/check-ast.sh`、`docs/` |

### 非目标

- 不做 `union`（含 `union` 的类型名、成员访问）。
- 不做 `goto` / 标签（另批）。
- 不做匿名枚举声明符 `enum { A, B } x;`（只支持带标签的声明与 `typedef` 形式）。
- 不做枚举前置声明（`enum E;`）、不做 `enum A::X` 限定类型名。
- 不做 `switch` 的重复 `case` 值检测（交给 C 编译器）。
- 不做 `case` 范围的 `...` 语法、不做 `case (int)1:` 之类含转换的常量表达式（`N_CAST` 不算常量）。
- 数组尺寸不扩展到一般常量表达式：仍只接受数字或单个名字（`[N]` / `[5]`），但名字改走 `var_cname` 取 C 拼写（见 D-9）。
- 不动 L0 / L1 / L2，不 bump `CTC_VERSION`，不改 `test/cases/**`、`examples/**` 的 golden。

## 3. 关键设计决策

### D-1 节点编号 45 / 46 / 47

现有最大结点号是语句层的 `N_DOWHILE 44`。新增

- `N_ENUM 45`：枚举声明；
- `N_ENUMVAL 46`：一个枚举成员；
- `N_OFFSETOF 47`：`offsetof` 表达式。

宏按「复制契约」分别写进用到的单元：`frontend/parse/Parser.h.ct`（45/46）、`frontend/parse/Expr.h.ct`（47）、`backend/emit/Emitter.h.ct`（45/46/47）、`frontend/module/Module.h.ct`（45/46）。

### D-2 `enum` 的两种形态与裸名类型

```
enum Tag { A, B = <常量>, C };              // 顶层；标签必填；允许尾逗号
typedef enum [Tag] { A, B } Alias;          // 有标签时 Tab 与 Alias 两个表项都登记
```

类型表新增 kind `5` = 枚举标签，与 struct 的 kind `1` 对等：

- [parse_type](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L158-L215) 遇到 `enum` 时**在类型词分支内**吃掉标签（与 `struct` 现有写法完全对称：`resolve_type` → `type_append` → `add_type(sname, 5)`）；
- 裸标签（`Color c;`）经 kind 5 补回 `enum ` 前缀，与 kind 1 补 `struct ` 同构；
- `typedef` 形式里 Alias 记 kind 2（同现有 typedef），因此 `Alias c;` 不加前缀。

标签缺失时沿用 `expected an enum name`（`struct` 的现有消息是 `expected a struct name`），只新增这一条。

### D-3 枚举成员是常量，复用变量表

成员要在表达式里当值用（`case RED:`、`x = RED + 1;`），而 [parse_primary](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L989-L1042) 的已声明名字路径已经会按 `var_cname` 取 C 拼写、按 `var_ambiguous` 做二义检查、并支持限定名 `a::b::RED`（`find_qualified_global`）。因此成员登记为「全局常量」：

- `struct Var` 新增 `int is_const;`（`declare_var` / `declare_global` 初始化为 0）；
- `SymbolOps` 新增 `declare_const(name, cname, ns, imported)`：内部等价于 `declare_global(name, "int", cname, ns, imported)` 再置 `is_const = 1`；
- 新增查询 `is_const_name(name)`，供常量表达式校验（D-6）区分「枚举成员」与普通变量。

命名空间 mangling 与全局变量同规则：`namespace a::b;` 里的成员 `RED` 以 `a_b_RED` 发射，`ns` 记 `a_b`（无尾下划线），裸名在**声明单元内**直接命中，跨单元走限定引用。

### D-4 成员初值不做折叠

`B = <expr>` 的表达式按普通表达式解析（`parse_expr`），校验为常量（D-6）后整棵树挂在成员节点上，发射时由 `emit_expr` 打印——`GREEN = RED + 1` 因此自然变成 `a_b_GREEN = a_b_RED + 1`。无初值的成员不发射 `= …`，自增语义交给 C 编译器（ct-ast 不保存常量值，也不做溢出 / 重复值判断）。

### D-5 节点布局

```
N_ENUM:   text  = 源里的名字（诊断用），text2 = 类型的 C 名（非 typedef 即标签；typedef 即别名），
          text3 = typedef 形式下的标签 C 名（无标签/非 typedef 为空），
          aux   = 1 表示 typedef 形式，d = pub 位，line = `enum` 所在行，a = 成员链
N_ENUMVAL:text  = 成员的 C 名，text2 = 成员的源名，a = 初值表达式节点（无初值为 -1），
          line = 成员所在行
```

`text2` 就是「这个类型对外叫什么」，所以 `decl_is_pub(N_ENUM, name)`（[Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L805-L815) 按 `text2` 匹配）与 Module 的裸名导出（按 `text2` 去前缀）都无需特殊判断。

### D-6 常量表达式的判据：`const_ok`

`ExprOps` 新增 `int const_ok(int n)`，按节点树判断「是不是整数常量表达式」：

| 节点 | 判据 |
| --- | --- |
| `N_NUM` | 是 |
| `N_STR` | 是，仅当字符串池里的字面量以 `'` 开头（字符字面量）；字符串 `"…"` 不是 |
| `N_RAW` | 是（全大写宏名，C 那边是常量） |
| `N_VAR` | 仅当 `is_const_name` 命中（枚举成员）；普通变量不是 |
| `N_UNARY` | `U_NEG` / `U_NOT` / `U_BNOT`，且操作数是常量 |
| `N_BIN` | 任一算符，且两侧都是常量（`&& \|\|` 与比较的整型结果在 C 里也合法） |
| `N_SIZEOF` | 是 |
| `N_OFFSETOF` | 是 |
| 其它（调用、成员访问、索引、三目、赋值、转换…） | 不是 |

调用方（`case` 标签）额外放行**整棵表达式就是一个名字**的情形（`case KIND_B:` / `case SOME_GLOBAL:`），保持第四批「单个标识符即常量名」的既有行为，不把已声明全局从标签里赶出去。

### D-7 `case` 标签改成表达式节点

`parse_label` 不再收集文本：`parse_case_value` 改为

```
e = ex->parse_expr();        // 语法错误、未声明变量照旧报
if (e < 0) return -1;
if (const_ok(e) == 0 && !(整棵树是单个 N_VAR / N_RAW))
    fail("a case label must be an integer constant");
N_CASE.b = e;  N_CASE.a 仍是「被守护的语句链」（D-3 of batch 4）
```

发射侧 `N_CASE` 改为 `case ` + `emit_expr(b)` + `:`（`default` 仍只打印 `default:`）。这样 `case 'a':`（字面量原样）、`case RED:`（按 C 名）、`case (1 << 2):`（保留括号，C 自己折叠）三种形态一条路径。

第四批的负例 `test/ast/errors/case_nonconstant.ct` 用的是 `case (1 + 2):`，本批它变成合法，因此该 fixture 改写为 `case key + 1:`（已声明变量出现在复合表达式里），注释同步更新。

### D-8 `offsetof` 是内建，不是宏

CT 没有预处理器，`offsetof` 只能由编译器自己认：

```
offsetof ( <type> , <field> )
```

在 `parse_primary` 的 `T_ID` 分支之前拦截（`toktext` 为 `offsetof` 且下一个 token 是 `(`），并用 `parse_type` 读类型（`struct S` 与 typedef 别名都行），再要求一个标识符字段：

- `parse_type` 后 `find_struct` 失败（去掉 `struct ` 前缀）→ `offsetof needs a struct type`；
- 结构体已定义（`structs[si].defined`）但没有该字段 → `struct '<S>' has no field '<f>'`；
- 前向声明的结构体（字段未知）放行，交给 C。

发射为 `offsetof(<type>, <field>)`。因为生成物只 `#include` 自己的头文件，**源文件必须自己写 `#include <stddef.h>`**——沿用 CT 的 `#include` 原样透传（`N_PP`）。文档里写明这一点。

### D-9 数组尺寸维持原样，名字改取 C 拼写

`parse_array_dims` 仍只接受数字 / 单个名字 / 空（`[]`），不引入一般常量表达式；但 `T_ID` 分支改成先 `var_cname` 再回退原样（与 `parse_case_value` 第四批的取法一致），这样命名空间里的 `int a[RED]` 会发射成 `int a[a_b_RED]`，不至于因为本批引入枚举常量而留下新的不一致。

### D-10 发射与导出

- `emit_type_decl`（[Emitter.h.ct](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L690-L765)）新增 `N_ENUM` 分支：`enum <text2> {` / `typedef enum <text3> {`，成员每行 `ind+1` 缩进，收尾 `};` 或 `} <text2>;`；
- `.c` 的私有类型循环（[1550-1557](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L1550-L1557)）与头文件的 `pub` 循环（[1624-1632](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emitter.h.ct#L1624-L1632)）都要把 `N_ENUM` 加进 `N_STRUCT || N_TYPEDEF` 的条件；
- `Module.h.ct` 的「依赖单元的裸名类型导出」循环（[386-399](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/module/Module.h.ct#L386-L399)）加上 `N_ENUM`；并新增一段：遍历依赖单元的 `N_ENUM` 成员，按 `d == 1` 逐个 `declare_const(name, cname, ns, 1)`，使导入单元的 `Red` 一类不加引号的名字也能解析（全大写宏名本来就走 `N_RAW`）。

### D-11 诊断原文

| 场景 | 消息 |
| --- | --- |
| `case` 值不是常量 | `a case label must be an integer constant`（沿用） |
| 重复的枚举标签 | `duplicate enum '<name>'` |
| 成员初值不是常量 | `an enum value must be an integer constant` |
| 枚举缺标签 | `expected an enum name`（沿用 struct 的写法） |
| `offsetof` 第一参数不是结构体 | `offsetof needs a struct type` |
| `offsetof` 字段不存在 | `struct '<S>' has no field '<f>'` |

全部带 `file:line:col:`。

## 4. 验收标准

| 项 | 验收 |
| --- | --- |
| F1 | 带显式值 / 自增 / 尾逗号的枚举声明、`typedef enum [Tag] { … } Alias;` 均编译通过；`enum Color c;` 与 `Color c;`（裸名）都能用 |
| F2 | `pub enum` 进头文件；同一命名空间内的成员引用发射为 mangled C 名；跨单元通过限定名与裸名都能取到成员 |
| F3 | `case (1 << 2):`、`case RED:`、`case 'a':`、`case KIND_B:`、`case -1:`、`case 1 + 2:`, 均编译运行正确；`case key + 1:` 仍报原文诊断 |
| F4 | `offsetof(struct S, b)` 求出正确的字节偏移并打印；`typedef` 别名作类型也可 |
| 诊断 | §3 D-11 的六条消息逐条按原文报出 |
| 回归 | `check-ast.sh` 全绿（自举 fixpoint 与语料等价段不变）；`check-warnings.sh` 零告警 |
| 文档 | `docs/language-spec.md` 新增枚举 / 常量表达式 / `offsetof` 章节，中英对称；顶部「其它 C 透传」表不再把 `enum` / `offsetof` 列为 ct-ast 缺口 |
| golden | `git status` 不出现 `test/cases/**`、`examples/**` 的 `.expected.*` 变化 |

## 5. 验证命令

```bash
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/ctc
bash selfhost/check-all.sh          # 期望 check-all: OK (9 hard gates green)
bash selfhost/check-warnings.sh     # 期望 exit 0
git status --short
```

手工探针（每片改完 ct-ast 后）：按 `docs/design/batch3-fnptr/spec.md` §5 的四层链配方重建
`/tmp/b5/ct-ast`（`/tmp/ctc` → `l1.c` → `l1 build l2` → `l2 build selfhost/ct-ast/main.ct`
**到全新目录**，避免增量缓存复用陈旧单元），再逐构造验证。

## 6. 出口条件

1. 九关全绿；`check-ast.sh` 通过计数只增不减。
2. 新增 fixture 的生成物零告警。
3. 文档没有「已实现却写成不支持」或反向的段落（重点是顶部透传表）。
4. 提交按规约拆分：`feat(codegen): add enums, constant expressions and offsetof`
   与 `docs(spec): record the enum forms` 分开；不 bump 版本、不动 golden。
