# 第二十三批特性：逗号表达式（2026-10-31）

> 锚点：`db5629f`（第二十二批收口），工作树干净。
> ctc.c 探针的第五个缺口：`for (i = lpo + 1, end = rp; i < end; )`（第 2483 行）。

## 1. 实测现状

- 表达式语句、`for` 的首句与步进子句共用 `parse_expr_stmt_node`；它先解析一个表达式、
  再看是否跟着赋值运算符，因此在 `,` 处直接报 `unexpected token`。
- `parse_expr` 不能简单地接受 `,`：函数实参也用它，`,` 在那里是分隔符。
- 探针自第 21 批起就卡在这一行；这是 ctc.c 全线通过前最后一个语法缺口。

## 2. 决策

- **D-1 建在 `parse_expr_stmt_node`**：逗号列表只在该入口处理，于是表达式语句、
  `for` 首句、`for` 步进三处同时获得支持；`parse_expr` 保持无逗号。
- **D-2 操作数按赋值表达式**：每个操作数递归走 `parse_expr_stmt_node`，所以
  `i = 1, j = 2` 是 `(i = 1), (j = 2)`，与 C 的读法一致（不会把整句变成一次赋值）。
- **D-3 表示**：`N_BIN` + 新运算符 `B_COMMA 19`（不新增节点编号）。
- **D-4 发射**：`emit_inline` 打印 `(a, b)`，操作数复用同一写入器（`N_ASSIGN` /
  `N_EXPR` / `N_POST` 都支持）；`emit_node` 把「`N_BIN` + `B_COMMA`」纳入语句分支。
- **D-5 范围外**：`for` 条件、函数实参、括号内的逗号值表达式（`x = (a, b);`）不在本批，
  仍报 `unexpected token`——它们是值位置，需要另一套发射与类型处理。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（`B_COMMA` / `N_BIN`、`parse_expr_stmt_node` 重构）、
  `backend/emit/Emit.h.ct`（`B_COMMA`、语句分派、`emit_inline` 一支）。
- **impl 方法预算**：不新增方法（255/256），不新增节点编号。
- 不动：`Expr` / `TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/48_comma`：语句级 `i = 1, j = 2`、`for` 首句两赋值、步进 `i++, j--`
  与 `i++, j = j + 2`、纯调用操作数 `bump(&i), bump(&j)`。
- 本批不新增诊断。
- 关卡：`check-ast.sh` → 272 passed；`check-warnings.sh` → 138 ok；
  `check-all.sh` → 9 hard gates green。
- **探针终点**：ct-ast 现在能完整编译 `selfhost/l0/ctc.c`（2930 行）。生成的 C 用
  `cc -Wall -Wextra -std=c99` 通过（唯一提示是源文件自身「label 在块尾」的 C23 扩展
  告警），并且把产物当 ctc 跑通了 `examples/01_greeter`（两行输出正确）。
