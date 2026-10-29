# 任务：`case` 范围标签（第十六批）

依据：`docs/design/batch16-case-range/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析（`frontend/parse/Stmt.h.ct`）

- `Stmt` 加 `int case_hi;`。
- `parse_case_value`：开头置 `case_hi = -1`；读完第一个常量并通过检查后，若当前记号是
  `...`，消费它、解析第二个表达式、同样做常量检查（失败消息与单值相同），
  通过则记入 `case_hi`。
- `parse_label`：`parse_case_value` 之后把 `case_hi` 写到 `nodes[s].c`。

## [x] T2 发射（`backend/emit/Emit.h.ct`）

- `N_CASE` 分支：`c >= 0` 时在两端之间发 ` ... `。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/41_case_range`：见 spec §4。
- 负例：`case_range_nonconstant`；`check-ast.sh` 加精确消息断言。
- `docs/language-spec.md`：新增 §4.25（中英对称）；§4.13 的「不做范围语法」改为指向本节。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add case ranges`、
  `docs(spec): record the case-range form`。不 bump 版本、不动 golden。
