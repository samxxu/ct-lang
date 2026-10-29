# 第十一批特性：复合字面量（2026-10-30）

> 锚点：`0b89291`（第十批收口），工作树干净。
> 本规格只做 C99 的**复合字面量** `(type){ … }`（对象类型的临时值）。

## 1. 实测现状

- `(struct P){ 7 }` 报 `expected an expression`：`parse_unary` 的 cast 分支在 `)`
  之后直接 `parse_unary()`，`{` 不是表达式的开头。
- `{}` 初始化器的捕获逻辑只存在于 `Stmt::parse_init_raw`（语句层的 `T x = { … };`），
  表达式层拿不到（Stmt 依赖 Expr，反向 import 会成环）。
- 带 trait 的 struct 在声明里由 `Emit::emit_raw_init` 补 vptr 项（`.__x_vptr = &…_vtable`），
  这段逻辑对复合字面量同样需要。

## 2. 决策

- **D-1 节点 51 `N_COMPOUND`**：`text` = 类型（`struct Point` 这种完整拼写），
  `a` = 一个 `N_RAW` 子节点，装着原样的 `{ … }` 文本。
- **D-2 识别点**：`parse_unary` 的 cast 分支——`(type)` 之后若紧跟 `{`，就不是强制转换
  而是复合字面量。
- **D-3 捕获逻辑上移**：`Stmt::parse_init_raw` 移到 `ParseSupport`（`init_raw`），
  Stmt 与 Expr 都调用它；Stmt 侧删掉同名方法，因此 **impl 方法总数仍是 255**。
- **D-4 后缀**：复合字面量可以接 `.field`、`[i]`、`(args)`。`parse_postfix` 以
  `postfix_seed` 字段接收已解析好的主表达式（`>= 0` 时跳过 `parse_primary`），
  因此 cast 分支构造好节点后直接 `return self->parse_postfix();`，不新增方法。
- **D-5 发射**：`emit_raw_init` 增加 `assign` 参数（声明处传 1 发 ` = `，复合字面量传 0），
  于是 `(type){ … }` 与声明初始化器共用同一套 vptr 追加逻辑：
  带 trait 的 struct 自动得到 `, .__x_vptr = &….vtable`，空 `{ }` 也会被补全。
- **D-6 类型推断**：`expr_type(N_COMPOUND)` 返回 `text`，所以 `(struct P){ … }.y`、
  赋给同类型变量、作为 struct 实参都按普通 struct 值处理。
- **D-7 拒绝**：指针类型 `(struct P *){ … }` 报 `a compound literal needs an object type`。
- **D-8 范围外**：`(int[]){ … }`（数组类型）不在子集内——类型文法不读 `[]`，会在 `)` 处
  报 `unexpected token`；对复合字面量直接调 trait 方法（`((struct P){…}).m()`）也不支持，
  方法接收者的允许形态保持原样（变量 / 元素 / 调用 / 字段链），先赋给变量再调用。

## 3. 影响面

- 改：`frontend/parse/ParseSupport.h.ct`（`init_raw` 迁入）、
  `frontend/parse/Stmt.h.ct`（删掉 `parse_init_raw`，改调 `sup->init_raw`）、
  `frontend/parse/Parser.h.ct`（一处调用点改名）、
  `frontend/parse/Expr.h.ct`（`N_COMPOUND`、`postfix_seed`、cast 分支与 `parse_postfix`）、
  `frontend/type/TypeCheck.h.ct`（`expr_type` 一支）、
  `backend/emit/Emit.h.ct`（`N_COMPOUND`、`emit_raw_init` 的 `assign` 参数与三个调用点、
  `emit_expr` 一支）。
- **impl 方法预算**：+1（ParseSupport::init_raw）/ −1（Stmt::parse_init_raw），总数仍 255。
- 不动：`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden、`Symbols.h.ct`、`Memory.h.ct`。

## 4. 验证

- 新增 `test/ast/36_compound_literal`：赋值、作为实参、取成员（`(struct P){1,2}.y`）、
  指定初始化器、带 trait 的 struct（vptr 由编译器补）、`{ }` 空初始化、
  标量形式 `(int){ 42 }`。
- 新增负例：`compound_pointer`（指针类型）。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
