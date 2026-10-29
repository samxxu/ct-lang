# 任务：一条声明多个字段（第十八批）

依据：`docs/design/batch18-multi-field/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析（`frontend/parse/Parser.h.ct`）

- `N_FIELDS 56`。
- `parse_field_def` 改为「读一次类型，循环读声明符」：每个声明符建一个 `N_FIELD`
  （名字 / 维度 / 位宽 / 函数指针维度照旧）；第 2 个起自己数 `*` 并拼到基类型上；
  `,` 之后继续，`;` 结束。多个声明符时外面包一层 `N_FIELDS`（`text` = 第一个
  声明符的类型拼写）。
- 函数指针后跟 `,` 报 `a function pointer declares one name`。
- `register_field`：`N_FIELDS` 逐个展开登记。

## [x] T2 发射（`backend/emit/Emit.h.ct`）

- `N_FIELDS 56`；`emit_field` 打印共享类型一次，后续声明符各自补星号、维度、位宽。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/43_multi_field`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：新增 §4.27（中英对称），并修正 §4.17 里「一条声明只写一个位域」
  的说法。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): allow several declarators in one field declaration`、
  `docs(spec): record the multi-declarator field form`。不 bump 版本、不动 golden。
