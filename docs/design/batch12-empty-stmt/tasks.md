# 任务：空语句与 `for` 首句的 `static`（第十二批）

依据：`docs/design/batch12-empty-stmt/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 语句层（`frontend/parse/Stmt.h.ct`）

- `N_EMPTY 52`。
- `parse_stmt` 最前面加 `;` 分支：`lex_next` 后建 `N_EMPTY` 返回。
- `for` 分支在「空初始化」与「普通声明」之间加 `static` 子分支：消费关键字、
  `is_decl_start()` 不成立报 `expected a declaration after 'static'`、置 `static_decl` 后
  `parse_decl_node()`，结束清零。

## [x] T2 发射（`backend/emit/Emit.h.ct`）

- `N_EMPTY 52`；`emit_node` 里直接 `return 0`（不输出字符）。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/37_empty_stmt`：见 spec §4。
- `check-ast.sh` 头注释补一行（batch 12 无新诊断）。
- `docs/language-spec.md`：新增 §4.21（中英对称）；同步修正 §4.16 的「空语句不在子集内」
  与 §4.19 的「`for` 首句的 static 范围外」。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add the empty statement and for-init statics`、
  `docs(spec): record the empty statement and for-init static`。不 bump 版本、不动 golden。
