# 第十四批特性：内置类型词与 `inline`（2026-10-30）

> 锚点：`c36e95c`（第十三批收口），工作树干净。
> 本批不是「新语法」，而是**消除与 L0 / L1 / L2 的分叉**：它们早就把这些词当类型关键字。

## 1. 实测现状

`is_type_word` 目前只认 `int / char / … / size_t / va_list / FILE / DIR`。实测报错：

| 写法 | 现状 |
| --- | --- |
| `volatile int x;` | ❌ `use of an undeclared variable` |
| `inline` 函数 | ❌ `expected a type (tok 1 'inline')` |
| `_Bool ok;` / `bool ok;` | ❌ `use of an undeclared variable` |
| `int *restrict p` | ❌ `unexpected token`（`restrict` 不是类型词） |
| `uint32_t v;` / `int8_t …` | ❌ 同上 |
| `wchar_t` / `ssize_t` / `ptrdiff_t` | ❌ 同上 |

对照 `selfhost/l2/core.ct` 的 `is_type_keyword`：`_Bool`、`bool`、`volatile`、`ssize_t`、
`wchar_t`、`ptrdiff_t`、`int8_t`–`uint64_t` 都在其中；`restrict` 与 `inline` 不在，但前者的
C 语义就是类型限定符，后者是函数说明符（L2 原样透传整行）。

## 2. 决策

- **D-1 类型词对齐 L2**：`is_type_word` 补 `_Bool`、`bool`、`volatile`、`ssize_t`、
  `wchar_t`、`ptrdiff_t`、`int8_t` / `int16_t` / `int32_t` / `int64_t` / `uint8_t` /
  `uint16_t` / `uint32_t` / `uint64_t`，并加 `restrict`（限定符）。声明原样发射，
  语义交给 C 与对应头文件；`DIR` 是 ct-ast 自己的补充，保留。
- **D-2 `volatile` / `restrict` 是类型的一部分**：出现在类型中间即进入类型字符串，
  因此 `volatile int x;`、`int *restrict p`、`volatile unsigned char *reg;` 都自然成立；
  字段、参数、返回值、全局同理。
- **D-3 `inline` 是函数说明符**：顶层接受 `static inline` 与 `inline static` 两种顺序；
  函数节点用 `num` 位标记（`aux` 仍表示 `static`），发射为 `static inline ` / `inline `。
  生成的**原型**不带 `inline`（C 允许原型与定义不同），由文档写明。
- **D-4 诊断**：`inline` 后面不是函数（`inline int value = 1;`）报
  `'inline' can only declare a function`，位置取 `inline` 记号本身。
- **D-5 范围外**：`_Static_assert(…)`、`_Alignas`、`_Generic`、`__attribute__((…))` 仍不在
  子集内；函数体内的 `inline`（无意义）不特殊处理；浮点字面量（`1.5`）仍不支持
  （词法器不扫小数点，属另一批）。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（`is_type_word`）、`frontend/parse/Parser.h.ct`
  （`top_decl` 的 `static` 分支与新增 `inline` 分支）、`backend/emit/Emitter.h.ct`
  （`N_FUNC` 的 `inline `）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden、符号表结构。

## 4. 验证

- 新增 `test/ast/39_builtin_types`：`volatile` 全局与局部、`int *restrict`、`size_t` /
  `ssize_t` / `ptrdiff_t` / `wchar_t` 声明、`bool` 与 `_Bool`、`int8_t`–`uint64_t`、
  `static inline` 与 `inline static` 两种顺序。
- 新增负例：`inline_var`。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
