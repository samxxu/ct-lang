# 第二十八批特性：表达式里的赋值（2026-10-31）

> 锚点：`9c97b02`（第二十七批收口），工作树干净。
> 实测缺口：`while ((c = getchar()) != -1)` 在 ct-ast 下报
> `unexpected token`，在 L2（回归 oracle）下通过。

## 1. 实测现状

- 赋值只在语句层解析（`parse_expr_stmt_node`），表达式链里没有赋值这一级，
  于是括号里、条件里出现 `=` 都被当成语法错误。
- 这是标准 C 的经典写法（`getchar` 循环、`if ((n = f()) > 0)`），不是新发明。
- 若把赋值直接塞进 `parse_expr` 并默认开启，语句层的赋值会变成「表达式赋值」，
  生成物会普遍多出括号，且 AutoDrop 的记账点会消失。

## 2. 决策

- **D-1 用开关而不是改默认**：`Expr` 增加 `assign_ok`；只有两处打开它——
  `parse_primary` 的括号分支，以及 `if` / `while` / `do … while` / `switch` /
  `for` 条件的解析。语句层的 `x = 1;` 仍走原路，生成物不变。
- **D-2 右结合**：赋值分支的 RHS 递归调用 `parse_expr`，因此 `a = b = 0` 自然成立；
  优先级放在 `?:` 之下，符合 C。
- **D-3 发射补括号**：`emit_expr` 新增 `N_ASSIGN` 一支，输出 `(lhs = rhs)`。
  节点已经不在语句位置，括号必须由发射端补，否则优先级会被改写。
- **D-4 目标检查复用**：变量 / 成员 / 下标 / 解引用之外仍报
  `assignment target is not assignable`。
- **D-5 `own` 目标拒绝**：所有权（AutoDrop / 泄漏分析）只在语句层通过
  `leak_assign` 记账，值位置的赋值会静默绕过它，因此报
  `an 'own' variable can only be assigned in a statement`，宁可拒绝也不漏跟踪。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（`N_ASSIGN`、`assign_ok`、`parse_expr` 的赋值一级、
  括号分支开关）、`frontend/parse/Stmt.h.ct`（五处条件的开关）、
  `backend/emit/Emit.h.ct`（`emit_expr` 的 `N_ASSIGN` 一支）。
- **impl 方法预算**：不新增方法（255/256），不新增节点编号。
- 不动：`TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/52_assign_value`：链式 `(a = b = 0)`、下标 `(arr[0] = 4) + 1`、
  成员 `(box.n = 7)`、复合 `(a += 2)`、与逗号混用 `((a = 9), a + 1)`、
  条件 `while ((c = next()) < 3)` 与 `if ((a = c) == 3)`。
- 负例 `test/ast/errors/assign_own_value.ct`：`own` 目标被拒绝，`check-ast.sh`
  精确断言消息。
- 回归：语句层赋值生成物不变（`n = 0;` 不带括号），`ctc.c` 探针与 L0 种子关卡仍通过。
- 关卡：`check-ast.sh` → 279 passed；`check-warnings.sh` → 142 ok；
  `check-all.sh` → 9 hard gates green。
