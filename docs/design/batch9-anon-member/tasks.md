# 任务：匿名成员（第九批）

依据：`docs/design/batch9-anon-member/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 记录体的字段登记（`frontend/parse/Parser.h.ct`）

- 结构体加 `char cur_record[MAX_TEXT]`：当前正在读的记录名，空串表示 `typedef` 的匿名体
  （字段进 `pend_fields`）。
- 新方法：`record_body_ahead`（前瞻 `struct` / `union` 后是否紧跟 `{`）、`register_field`
  （按 `cur_record` 选表；`aux == 2` 递归拍平，空名跳过，同名报 `duplicate member '<name>'`）、
  `parse_record_body`（`{` 字段链 `}`；`reg` 为 0 时只建树不登记，供匿名成员用）、
  `parse_anon_member`（建节点、读体、拒具名与空体、`;`）。
- `parse_record_def` 的字段循环替换为 `parse_record_body`，并在读体前设置 `cur_record`、
  结束后清空。

## [x] T2 发射（`backend/emit/Emitter.h.ct`）

- `EmitOps` / `Emitter` 新增 `emit_field(int n, int ind)`：`aux == 2` 的字段发
  `union {` / `struct {` + 内层逐条 + `}`；其余转给 `emit_inline`。
- `emit_type_decl` 的 N_STRUCT 与 N_UNION 字段循环改用它。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/34_anon_member`：见 spec §4。
- 负例：`anon_member_name`、`anon_member_dup`、`anon_member_empty`；
  `check-ast.sh` 加一组精确消息断言。
- `docs/language-spec.md`：新增 §4.18（中英对称），并把 §4.15 里「匿名成员不在子集内」
  改成指向 §4.18 的说明。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add anonymous record members`、
  `docs(spec): record the anonymous-member form`。不 bump 版本、不动 golden。
