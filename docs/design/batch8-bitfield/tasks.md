# 任务：位域（第八批）

依据：`docs/design/batch8-bitfield/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 字段解析（`frontend/parse/Parser.h.ct`）

- 复制 `N_VAR 10`（`case` 的等价判断要用到）。
- `parse_field_def`：名字前若已是 `:`，名字留空（匿名填充位）；
- 读完维度后若当前记号是 `:`：
  - `text3` 非空 → `a bit-field cannot be an array`；
  - 类型含 `*` 或前缀 `struct ` / `union ` → `a bit-field must have an integer type`；
  - 消费 `:`；紧跟 `;` → `expected a bit-field width`；
  - `parse_expr`，非整数常量（`!const_ok && kind != N_VAR && kind != N_RAW`）→
    `a bit-field width must be an integer constant`；
  - `aux = 1`、`a = 宽度节点`。

## [x] T2 发射（`backend/emit/Emit.h.ct`）

- `emit_inline` 在 `N_DECL || N_FIELD` 共用分支之前加位域分支：
  发 `text`，名字非空时发 ` <name>`，再发 ` : ` 与 `emit_expr(a)`。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/33_bitfield`：见 spec §4。
- 负例：`bitfield_nonconstant`、`bitfield_missing_width`、`bitfield_array`、
  `bitfield_pointer`；`check-ast.sh` 加一组精确消息断言。
- `docs/language-spec.md`：新增 §4.17（中英对称），顶部「其它 C 透传」表去掉位域。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add bit-fields to the record grammar`、
  `docs(spec): record the bit-field form`。不 bump 版本、不动 golden。
