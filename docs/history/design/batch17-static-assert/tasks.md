# 任务：`_Static_assert`（第十七批）

依据：`docs/design/batch17-static-assert/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析（`frontend/parse/Stmt.h.ct` / `Parser.h.ct`）

- `N_SASSERT 55`。
- `parse_stmt` 最前面加分支：`_Static_assert` → `(` → `parse_expr` → `const_ok` 检查 →
  可选 `,` + 字符串字面量 → `)` → `;`，节点 `a` = 条件、`text` = 消息。
- `top_decl` 加转发分支：关键字命中时 `n = self->st->parse_stmt();`。

## [x] T2 发射（`backend/emit/Emitter.h.ct`）

- `N_SASSERT 55`；`emit_node` 发 `_Static_assert(<cond>[, "<msg>"]);`。
- `emit_program` 与 `emit_unit` 各加一个顶层循环，在原型之后发射这些断言。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/42_static_assert`：见 spec §4。
- 负例：`static_assert_nonconstant`、`static_assert_msg`；`check-ast.sh` 加精确消息断言。
- `docs/language-spec.md`：新增 §4.26（中英对称），并把顶部「其它 C 透传」一行改写成
  「有意拒绝 / 仍未实现」两张表。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept _Static_assert`、
  `docs(spec): record the static assertion`、`docs(spec): separate the deliberate
  divergences from the missing forms`。不 bump 版本、不动 golden。
