# 任务：逗号表达式（第二十三批）

依据：`docs/design/batch23-comma/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析与发射

- `Stmt.h.ct`：`B_COMMA 19`、`N_BIN 11`；`parse_expr_stmt_node` 把三处 early return
  收拢成一个结果，再接逗号循环；每个操作数递归走同一函数。
- `Emit.h.ct`：`B_COMMA`；`emit_node` 的语句分支接纳「`N_BIN` + `B_COMMA`」；
  `emit_inline` 打印 `(a, b)`。

## [x] T2 fixture、关卡、文档与提交

- `test/ast/48_comma`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：新增 §4.32（中英对称）并写明范围外的位置。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept a comma list in a full expression`、
  `docs(spec): record the comma operator`。不 bump 版本、不动 golden。
