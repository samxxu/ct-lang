# 第二十四批特性：取值位置的逗号列表（2026-10-31）

> 锚点：`88ae04c`（第二十三批收口），工作树干净。
> 第二十三批把逗号列表放进表达式语句与 `for` 首句/步进；本批补上**值位置**：
> `x = (a, b);`、`f((a, b))`、`while ((a, b))`。

## 1. 实测现状

- 括号表达式走 `parse_primary`，它只调用一次 `parse_expr`，遇到 `,` 直接 `expect(")")`
  报 `unexpected token`，所以 `x = (a, b);` 不可用（§4.32 已把这一点写成范围外）。
- 发射端同样没有取值位置的逗号分支：`N_BIN` 的默认运算符是 `+`，直接把 `B_COMMA`
  送进去会静默生成错误的 C。

## 2. 决策

- **D-1 解析在括号分支**：`parse_primary` 的 `(` 分支在第一个 `parse_expr` 之后循环吃
  `,`，建 `N_BIN` + `B_COMMA`（与语句形式同一个节点形态）。括号内含逗号的地方因此都能用：
  赋值右侧、调用实参、条件。
- **D-2 操作数是普通表达式**：括号里的赋值仍不在表达式文法里（`(i = 1, i)` 不支持，
  与本批之前一致），所以操作数直接由 `parse_expr` 得到，发射用 `emit_expr`。
- **D-3 发射**：`emit_expr` 在通用 `N_BIN` 分支之前加一支，打印 `(a, b)`；语句形式的
  操作数是 `N_ASSIGN` / `N_EXPR` / `N_POST`，仍由 `emit_inline` 打印，两条路径互不重叠。
- **D-4 不做**：`for` 条件里**不带括号**的逗号（`for (; a, b; )`）。实参之间的 `,` 永远是
  分隔符，取值逗号必须加括号。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（`B_COMMA`、括号分支的循环）、
  `backend/emit/Emitter.h.ct`（`emit_expr` 的逗号一支）。
- **impl 方法预算**：不新增方法（255/256），不新增节点编号。
- 不动：`Stmt` / `TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/49_comma_value`：赋值右侧 `(i++, j * 2)`、两次带副作用的调用
  `(bump(&i), bump(&j))`、实参里 `pair((i++, i + 1), 7)`、条件 `while ((i++, j > 8))`。
- 本批不新增诊断（与 §4.32 共用一条说明，不新增章节号）。
- 关卡：`check-ast.sh` → 273 passed；`check-warnings.sh` → 139 ok；
  `check-all.sh` → 9 hard gates green。
- 探针：ct-ast 仍能完整编译 `selfhost/l0/ctc.c`。
