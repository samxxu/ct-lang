# 第十七批特性：`_Static_assert`（2026-10-30）

> 锚点：`8266628`（第十六批收口），工作树干净。
> 本规格只做 C11 的静态断言：文件作用域与函数体内两种位置。

## 1. 实测现状

- `_Static_assert(1 == 1, "ok");` 报 `expected a type (tok 1 '_Static_assert')`：
  它不是类型词，顶层走到 `parse_func` 的路径，语句层也没有分支。
- 发射侧没有承载它的节点；`emit_program` 只遍历类型、原型、全局、impl、`map` 与函数，
  任意其它顶层节点会被静默丢掉，所以必须在 `emit_program` / `emit_unit` 各加一个专门的循环。

## 2. 决策

- **D-1 解析放在语句层**：`parse_stmt` 认 `_Static_assert`（新节点 `N_SASSERT` 55，
  `a` = 条件、`text` = 消息字面量原文）。顶层由 `top_decl` 把关键字转回
  `self->st->parse_stmt()`，语法与常量检查只有一份实现。
- **D-2 条件必须是整数常量表达式**：沿用 `case` 标签的 `const_ok`，违反时报
  `a static assertion needs a constant condition`；消息位置必须是字符串字面量，
  否则报 `a static assertion message must be a string literal`。消息可以省略（C23 放宽）。
- **D-3 发射**：`_Static_assert(<cond>[, "<msg>"]);`，条件走 `emit_expr`，因此与源码同形；
  C11 才有的构造，但实测 `cc -Wall -Wextra -std=c99` 下 clang / gcc 都接受且不告警。
- **D-4 顶层顺序**：文件作用域的断言统一在「类型 → 原型」之间发射，晚于所有类型声明，
  因此断言里引用本单元上面定义过的 struct / enum 仍然成立；顺序差异只在断言引用
  **后面**才定义的类型时可见（文档写明）。
- **D-5 范围外**：`_Alignas`、`_Generic`、`__attribute__((…))` 仍不在子集内。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（`N_SASSERT`、`parse_stmt` 分支）、
  `frontend/parse/Parser.h.ct`（`top_decl` 的转发分支）、
  `backend/emit/Emit.h.ct`（`N_SASSERT` 的语句发射、`emit_program` 与 `emit_unit`
  各一个顶层循环）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`Expr` / `TypeCheck` / 符号表、`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/42_static_assert`：文件作用域三条（`sizeof(int)`、`sizeof(struct)`、
  `1 == 1`）、函数体内一条、`main` 里一条。
- 新增两个负例：`static_assert_nonconstant`、`static_assert_msg`。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
