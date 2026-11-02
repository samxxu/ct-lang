# 任务：数组长度表达式（第十九批）

依据：`docs/design/batch19-array-length/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 解析（`frontend/parse/Expr.h.ct`）

- `parse_array_dims`：记下 `[` 的源码位置；数字 / 单个名字 / 空 三条既有分支不变；
  读掉第一个 token 后若后继不是 `]`，或第一个 token 本就不是这三类，
  则按 D-2 从源码拷出 `[...]` 原文，重新定位词法器到 `]` 之后。

## [x] T2 fixture、关卡、文档与提交

- `test/ast/44_array_length`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：新增 §4.28（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept expressions as array lengths`、
  `docs(spec): record the array-length expression`。不 bump 版本、不动 golden。
