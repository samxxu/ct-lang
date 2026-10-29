# 任务：变参函数（第十三批）

依据：`docs/design/batch13-variadic/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 词法与参数表（`Lexer.h.ct` / `Parser.h.ct`）

- 词法器：`.` 且后两个字符都是 `.` 时产出 `...` 记号，`pos += 3`。
- `Parser`：加 `int variadic;`；`parse_params` 开头清零，循环首部认 `...`
  （无具名参数时报 `'...' needs a named parameter before it`，否则置位并 `break`）。

## [x] T2 记录与拒绝（`Parser.h.ct` / `Symbols.h.ct`）

- `Func` 加 `int variadic;`。
- `parse_func`：原型路径与定义路径都在 `add_func` 之后写 `funcs[fi].variadic`；
  定义节点 `nodes[f].c = self->variadic`。
- `parse_impl`：`parse_params` 之后若 `variadic` 成立，报
  `a trait method cannot be variadic`（先 `pop_scope`）。

## [x] T3 `va_list` 与 `va_arg`（`Expr.h.ct` / `TypeCheck.h.ct`）

- `is_type_word` 加入 `va_list`。
- `N_VAARG 53`；`parse_primary` 在 `offsetof` 分支之后加 `va_arg` 分支：
  `(` 表达式 `,` 类型 `)`，节点 `a` = 表达式、`text` = 类型。
- `expr_type`：`N_VAARG` 返回 `text`。

## [x] T4 发射（`Emit.h.ct`）

- `N_VAARG 53`；`emit_expr` 发 `va_arg(<expr>, <type>)`。
- `emit_proto` 与 `emit_node` 的 `N_FUNC`：参数表末尾按 variadic 标志补 `, ...`。

## [x] T5 fixture、关卡、文档与提交

- `test/ast/38_variadic`：见 spec §4。
- 负例：`variadic_no_named`、`variadic_impl`；`check-ast.sh` 加一组精确消息断言。
- `docs/language-spec.md`：新增 §4.22（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add variadic functions`、
  `docs(spec): record the variadic form`。不 bump 版本、不动 golden。
