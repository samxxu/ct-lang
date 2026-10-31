# 任务：C11 对齐与泛型选择（第二十九批）

依据：`docs/design/batch29-c11-align-generic/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析

- `Expr.h.ct`：`parse_type` 增加 `_Alignas` 分支（原样追加到类型拼写）；
  `parse_unary` 让 `_Alignof` 与 `sizeof` 共用分支（`aux = 2`）；
  `parse_primary` 增加 `_Generic` 整段透传（`N_RAW` + 字符串池）；补 `T_EOF`。
- `Stmt.h.ct`：`is_decl_start` 接受以 `_Alignas` 开头的块作用域声明。

## [x] T2 发射

- `Emit.h.ct`：`N_SIZEOF` 分支按 `aux`（1 / 2）输出 `sizeof(…)` 或 `_Alignof(…)`。
  `_Alignas` 与 `_Generic` 走既有的类型字符串 / `N_RAW` 打印路径，无需改动。

## [x] T3 fixture、负例、关卡、文档与提交

- `test/ast/53_c11_align_generic`、`test/ast/errors/{alignas_no_paren,alignof_operand,generic_no_paren}.ct`。
- `check-ast.sh`：头注释两行 + batch 29 的精确消息断言块。
- `docs/language-spec.md`：新增 §4.35（中英对称），顶部「仍未实现」与 §4.23 / §4.26
  的两处「范围外」只保留 `__attribute__((…))`；README 中英各一处同步。
- `bash selfhost/check-all.sh` 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept the C11 alignment and generic forms`、
  `docs(spec): record the C11 alignment and generic forms`。不 bump 版本、不动 golden。
