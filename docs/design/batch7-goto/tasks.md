# 任务：`goto` 与标签（第七批）

依据：`docs/design/batch7-goto/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 标签与 goto 的解析（`frontend/parse/Stmt.h.ct`）

- `N_LABEL 49`、`N_GOTO 50`；`MAX_LABELS 64`。
- 结构体字段：`label_names[64][160]` / `label_lines[64]` / `nlabels`、
  `goto_names[64][160]` / `goto_lines[64]` / `ngotos`。
- `trait StmtOps` 新增 `label_ahead`、`label_find`、`parse_named_label`、`parse_goto`、
  `func_begin`、`func_end`。
- `label_ahead()`：保存 / 恢复 lexer 九个字段的前瞻；
- `parse_stmt`：在 `case` / `default` 检查与 `own` 之后、声明判断之前加
  `goto` 分支与 `label_ahead()` 分支；
- `parse_named_label()`：重复标签 / 上限 / `expect(":")` / 链（遇到 `}`、`case`、`default`、
  另一个标签停止）/ 链空 / 声明跟随时各一条诊断；
- `parse_goto()`：读名字、上限、`expect(";")`，记录 goto 表；
- `parse_label`（case 的链）终止条件加 `label_ahead()`；
- `func_begin` / `func_end`：重置两张表；结束时逐条检查 goto 是否有同函数标签。

## [x] T2 函数边界接线（`frontend/parse/Parser.h.ct`）

- `parse_func` 的函数体与 `parse_impl` 的方法体：`parse_block()` 之前 `func_begin()`，
  之后（`b < 0` 检查之后）`func_end()`，失败即 `pop_scope` + 返回 -1。

## [x] T3 发射（`backend/emit/Emit.h.ct`）

- `N_LABEL 49`、`N_GOTO 50`（与 Stmt / Parser 各写一份）。
- `emit_node`：`N_GOTO` 发 `goto <text2>;`；`N_LABEL` 发 `<text2>:` 一行，再把 `a` 链逐条
  按 `ind + 1` 发射。

## [x] T4 fixture、关卡、文档与提交

- `test/ast/32_goto`：见 spec §4 的行为清单。
- 负例：`goto_undefined`、`label_duplicate`、`label_decl`、`label_no_statement`；
  `check-ast.sh` 加一组精确消息断言。
- `docs/language-spec.md`：新增 §4.16（中英对称），顶部「其它 C 透传」表去掉 `goto` / 标签。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add goto and labels`、`docs(spec): record the goto form`。
  不 bump 版本、不动 golden。
