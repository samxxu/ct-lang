# 任务：内置类型词与 `inline`（第十四批）

依据：`docs/design/batch14-qualifiers/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 类型词（`frontend/parse/Expr.h.ct`）

- `is_type_word` 补齐 L2 的集合：`_Bool` / `bool` / `volatile` / `ssize_t` / `wchar_t` /
  `ptrdiff_t` / `int8_t`–`uint64_t`，并加 `restrict`；注释说明这是对齐 L2 的
  `is_type_keyword`。

## [x] T2 `inline`（`frontend/parse/Parser.h.ct` / `backend/emit/Emitter.h.ct`）

- `top_decl` 的 `static` 分支：`static` 之后若是 `inline`，消费后仍按
  `parse_func(1, …)` 解析，成功时把函数节点 `num` 置 1。
- 新增 `inline` 分支：先记位置，消费 `inline`，若紧跟 `static` 也消费（`in_static`），
  按 `parse_func(in_static, …)` 解析，同样置 `num = 1`。
- 两处：结果不是 `N_FUNC` 时报 `'inline' can only declare a function`（用记下的位置）。
- `emit_node` 的 `N_FUNC`：`static` 之后按 `num` 发 `inline `。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/39_builtin_types`：见 spec §4。
- 负例：`inline_var`；`check-ast.sh` 加精确消息断言。
- `docs/language-spec.md`：新增 §4.23（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept the stdint/stdbool type words and inline`、
  `docs(spec): record the builtin type words and inline`。不 bump 版本、不动 golden。
