# 任务：前缀 `++` / `--`（第二十批）

依据：`docs/design/batch20-pre-incr/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析与发射（`Expr.h.ct` / `Emitter.h.ct`）

- `N_PRE 57`；`parse_unary` 在 `-` `!` `~` 之前加前缀分支：读 `++`/`--`、再读一个
  `parse_unary`、建 `N_PRE`（`a` = 操作数、`aux` = `P_INC`/`P_DEC`）。
- `emit_expr`：`N_PRE` 先发运算符，再发操作数。

## [x] T2 fixture、关卡、文档与提交

- `test/ast/45_pre_incr`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：新增 §4.29（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add prefix increment and decrement`、
  `docs(spec): record the prefix increment form`。不 bump 版本、不动 golden。
