# 任务：`static` 局部变量（第十批）

依据：`docs/design/batch10-static-local/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 语句层（`frontend/parse/Stmt.h.ct`）

- 结构体加 `int static_decl;`。
- `parse_stmt`：`own` 分支之后加 `static` 分支——消费关键字、拒绝 `own`
  （`a static local cannot be 'own'`）、`is_decl_start()` 不成立报
  `expected a declaration after 'static'`、置位后调用 `parse_decl_node()`、`;`。
- `parse_decl_node`：`static_decl` 为真时给每个 `N_DECL` 置 `aux = 1`，并跳过 `leak_decl`。
- `parse_label` / `parse_named_label` 的链循环：判定「声明」时把 `static` 也算上，
  维持既有 `a declaration cannot follow a case label; …` / `a declaration cannot follow a label; …`。

## [x] T2 发射（`backend/emit/Emit.h.ct`）

- `emit_inline` 的 `N_DECL` 分支：`aux == 1` 时先发 `static `。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/35_static_local`：见 spec §4。
- 负例：`static_own`、`static_no_decl`；`check-ast.sh` 加一组精确消息断言。
- `docs/language-spec.md`：新增 §4.19（中英对称）；§4.9 的约束列表补一条「static 局部不能是 own」。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add static locals`、`docs(spec): record the static-local form`。
  不 bump 版本、不动 golden。
