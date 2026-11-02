# 第十二批特性：空语句与 `for` 首句的 `static`（2026-10-30）

> 锚点：`1a19596`（第十一批收口），工作树干净。
> 本规格收掉两个语句层的小缺口：空语句 `;` 与 `for (static int i = 0; …)`。

## 1. 实测现状

- `for (i = 0; i < 2; i++);` 报 `expected an expression`：`parse_stmt` 没有 `;` 分支，
  `parse_expr_stmt_node` 在空表达式上失败。
- `for (static int i = 0; …)` 报 `use of an undeclared variable`：`for` 的首句只认
  「普通声明」与「表达式」，`static` 落到表达式路径。
- 第十批已经让 `N_DECL.aux = 1` 在 `emit_inline` 里发 `static ` 前缀，`for` 的初始化子句
  也走 `emit_inline`，所以 `for` 首句的 `static` 只差解析这一段。

## 2. 决策

- **D-1 节点 52 `N_EMPTY`**：`parse_stmt` 在函数体第一层分支里认 `;`，消费后返回空语句节点。
  发射时**不输出任何字符**，因此 `if (c) ;` 的 `if (c) {` 之后直接收 `}`。
- **D-2 空语句是合法语句**，因此 `case 1: ;`、`done: ;` 这类「标签后必须有语句」的场景
  现在有了最省的写法；标签链的既有检查（标签后不能直接跟声明）不变。
- **D-3 `for` 首句的 `static`**：`for` 分支在「空初始化」与「普通声明」之间加一条
  `static` 分支——消费关键字、要求 `is_decl_start()`、置 `static_decl` 后复用
  `parse_decl_node()`。发射沿用 `emit_inline` 的 `static ` 前缀，无需改动。
- **D-4 语义**：`for (static int i = 0; …)` 的初始化只发生一次，`i` 跨调用保持；第二次调用
  直接以 `i` 的余值判断条件。这是 C 的规定，ct-ast 不做特殊处理（fixture 把这一点写进期望输出）。
- **D-5 无新诊断**：空语句与 `for` 首句的 static 都只在语义上扩展，不新增消息；
  `static` 后面不是声明时沿用第十批的 `expected a declaration after 'static'`。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（`N_EMPTY`、`parse_stmt` 的 `;` 分支、`for` 分支的 static
  子分支）、`backend/emit/Emitter.h.ct`（`N_EMPTY` 与一条空发射分支）。
- **impl 方法预算**：不新增任何方法（255/256）。
- 不动：`ParseSupport` / `Expr` / `TypeCheck` / `Memory`、`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/37_empty_stmt`：`for (...) ;`、`if (c) ; else …`、`while (c) ;`、
  `case 1: ;` 与 `done: ;`、`for (static int i = 0; …)` 跨调用保持。
- 无新增负例（本批不新增诊断）；`check-ast.sh` 的头注释补一行说明。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
