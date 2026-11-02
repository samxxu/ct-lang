# 任务：表达式里的赋值（第二十八批）

依据：`docs/design/batch28-assign-value/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析

- `Expr.h.ct`：`N_ASSIGN 13`、`int assign_ok`；`parse_expr` 在 `?:` 之后增加赋值一级
  （右结合、目标检查、`own` 拒绝）；`parse_primary` 的括号分支打开开关并在退出时还原。
- `Stmt.h.ct`：`if` / `while` / `do … while` / `switch` / `for` 条件五处打开开关。

## [x] T2 发射

- `Emitter.h.ct`：`emit_expr` 增加 `N_ASSIGN` 一支，输出 `(lhs = rhs)`（含复合赋值映射）。

## [x] T3 fixture、负例、关卡、文档与提交

- `test/ast/52_assign_value`、`test/ast/errors/assign_own_value.ct`。
- `check-ast.sh`：头注释一行 + batch 28 的精确消息断言块。
- `docs/language-spec.md`：新增 §4.34（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept an assignment used as a value`、
  `docs(spec): record value-position assignments`。不 bump 版本、不动 golden。
