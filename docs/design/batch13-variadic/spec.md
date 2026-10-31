# 第十三批特性：变参函数（2026-10-30）

> 锚点：`aae88ae`（第十二批收口），工作树干净。
> 本规格只做 C 的变参函数：参数表末尾的 `...`、`va_list` 声明与 `va_arg(ap, T)`。

## 1. 实测现状

- `int sum(int n, ...)` 报 `expected a type (tok 4 '.')`：词法器把 `.` 当单字符标点，
  `...` 是三个 `.` 记号，`parse_params` 在 `parse_type` 上失败。
- `va_list ap;` 也报 `expected a type`：`va_list` 不在 `is_type_word` 里。
- `va_arg(ap, int)` 的第二个实参是**类型**，普通调用解析会在 `int` 上失败。
- 函数的参数表在符号表里另存一份（`Func.ptype` / `nparams`），原型由 `emit_proto`
  单独发射——所以 `...` 必须同时记录到符号行，否则原型会丢掉它。

## 2. 决策

- **D-1 词法**：`...` 作为一个 `T_PUNCT` 记号（三连点）。它只可能出现在参数表里，
  不会与字段访问或浮点字面量混淆（ct 目前不解析浮点）。
- **D-2 语法**：`parse_params` 在循环开头认 `...`——必须已有至少一个具名参数
  （否则 `'...' needs a named parameter before it`），消费后结束参数表；
  `...` 不计入 `nparams`。
- **D-3 记录**：`Parser.variadic` 由 `parse_params` 设置；`parse_func` 把它写到
  符号行（`Func.variadic`，原型用）与函数节点（`c`，定义用）。两处都发 `, ...`。
- **D-4 trait 方法不变参**：vtable 槽位是固定的函数指针类型，`impl` 里出现 `...` 报
  `a trait method cannot be variadic`；trait 声明本身走另一条解析路径，`...` 会在
  `expected a type` 处失败（文档写明）。
- **D-5 `va_list`**：加入 `is_type_word`（与 `size_t` / `FILE` / `DIR` 同类），于是
  `va_list ap;` 是普通声明，原样发射。
- **D-6 `va_arg`**：它是 stdarg 里唯一「第二个实参是类型」的宏，因此按 `offsetof` 的
  方式做成内建：`N_VAARG`（53，`a` = 迭代器表达式，`text` = 类型），发射为
  `va_arg(ap, int)`；`expr_type` 返回 `text`。
- **D-7 `va_start` / `va_end` 是普通调用**：ct 不声明它们，与 `printf` 一样按未知
  被调函数发射，由 C 头文件校验。

## 3. 影响面

- 改：`frontend/lex/Lexer.h.ct`（`...` 记号）、`frontend/parse/Parser.h.ct`
  （`variadic` 字段、`parse_params`、`parse_func` 两处、`parse_impl` 的拒绝）、
  `frontend/sym/Symbols.h.ct`（`Func.variadic`）、
  `frontend/parse/Expr.h.ct`（`va_list` 类型词、`N_VAARG` 分支）、
  `frontend/type/TypeCheck.h.ct`（`expr_type`）、
  `backend/emit/Emitter.h.ct`（`N_VAARG`、`emit_proto`、`N_FUNC` 的 `, ...`）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/38_variadic`：原型带 `...` 再定义、`va_list` 局部、`va_arg` 求和、
  另一个取最大值、零个可变实参的调用。
- 新增两个负例：`variadic_no_named`、`variadic_impl`。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
