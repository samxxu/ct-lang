# 任务：取值位置的逗号列表（第二十四批）

依据：`docs/design/batch24-comma-value/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析与发射

- `Expr.h.ct`：`B_COMMA 19`；`parse_primary` 的括号分支在第一个表达式之后按 `,` 循环，
  建 `N_BIN` + `B_COMMA`。
- `Emitter.h.ct`：`emit_expr` 在通用 `N_BIN` 之前加逗号一支，打印 `(a, b)`。

## [x] T2 fixture、关卡、文档与提交

- `test/ast/49_comma_value`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：扩写 §4.32（中英对称），把「取值位置」从范围外改为支持，
  并保留「`for` 条件里不带括号的逗号仍不支持」。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept a comma list in a value position`、
  `docs(spec): record the value-position comma`。不 bump 版本、不动 golden。
