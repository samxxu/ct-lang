# 第八批特性：位域（2026-10-29）

> 锚点：`7940275`（第七批收口），工作树干净。
> 本规格只做**位域**（`unsigned a : 3;`）：记录文法里最后一块仍被 ct-ast 拒绝的字段形态。

## 1. 实测现状

- `struct Flags { unsigned a : 3; };` 在 ct-ast 里报
  `unexpected token`（列号落在 `:`）：`parse_field_def` 读完名字与数组维度后直接
  `expect(";")`。
- 字段链（`N_FIELD`）的三个文本槽是 `text`（类型）/ `text2`（名字）/ `text3`（数组维度），
  `a` 空着（字段没有初始化器），`aux` 空着（都是 0）。
- `structs[].fields[]` 的 `dims[0]` 非空被 TypeCheck 与 Init 当成「这是数组」
  （成员访问拒绝数组、vptr 初始化跳过数组），所以位宽**不能**塞进 `text3`。

## 2. 决策

- **D-1 复用 `N_FIELD`（23），不新增节点**。位域只多两个信息，正好落在两个空闲槽上：
  `aux = 1` 标记「这是位域」，`a` 存**宽度表达式节点**。于是宽度可以是 `(1 << 2)`、
  `sizeof(int) * 8` 或宏名，发射即 `emit_expr(a)`，不做折叠。
- **D-2 语法**：`<type> name : <宽度> ;`，且在 `parse_field_def` 里读，因此 struct、
  union、`typedef struct { … }` 的匿名体与 `pub` 版本自动都支持。
- **D-3 匿名位域**：`unsigned : 4;` 是填充位，允许（名字为空）。`text2` 空字符串进
  `structs[].fields[]`，成员查找按名字比较，空名永不命中，不影响其它字段。
- **D-4 宽度约束**：宽度是整数常量表达式——数字、字符字面量、枚举成员、宏名（`N_RAW`）、
  括号与算术 / 位运算、一元 `- ! ~`、`sizeof`、`offsetof`；普通变量报
  `a bit-field width must be an integer constant`。`unsigned a : ;` 报
  `expected a bit-field width`。
- **D-5 类型约束**：位域必须是整数类型。指针（类型里含 `*`，含函数指针）与显式
  `struct ` / `union ` 类型报 `a bit-field must have an integer type`；typedef 别名放行，
  交给 C 编译器判断。
- **D-6 不能是数组**：`int a[2] : 3;` 报 `a bit-field cannot be an array`（`text3` 已非空）。
- **D-7 发射**：字段仍走 `emit_inline`，位域分支发 `<type> <name> : <宽度>`
  （名字为空时只发 `<type> : <宽度>`）。`emit_type_decl` 的 `;\n` 照旧追加。
  位域**不**写 `structs[].fields[].dims`，因此 TypeCheck / Init 的数组判定不受影响。
- **D-8 范围外**：一条声明多个位域（`int a : 3, b : 4;`）不在子集内——字段解析一直是一条
  一个名字，保持现状；文档写明。位域上的 `offsetof` 是 C 的未定义行为，不做特殊处理。

## 3. 影响面

- 改：`frontend/parse/Parser.h.ct`（`parse_field_def` 的宽度分支与三条诊断、`N_VAR 10` 宏
  复制）、`backend/emit/Emit.h.ct`（`emit_inline` 的位域分支）。
- 不动：`frontend/sym/Symbols.h.ct`（字段表结构够用）、`frontend/type/TypeCheck.h.ct`、
  `backend/emit/Init.h.ct`、`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/33_bitfield`：位宽截断语义、匿名填充位、`typedef struct { … }` 匿名体、
  union 里的位域、`use` 的 vptr 追加在位域之后、常量表达式宽度（`(1 << 2)` 与宏名）、
  与普通字段混排、`sizeof` 体现打包。
- 新增四个负例：`bitfield_nonconstant`、`bitfield_missing_width`、`bitfield_array`、
  `bitfield_pointer`，在 `check-ast.sh` 里逐条 `grep` 精确消息。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
