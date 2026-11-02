# 任务：长初始化器（第二十一批）

依据：`docs/design/batch21-long-init/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 池化写入与读取

- `N_RAW` 约定：`aux = 1` 表示文本在 arena 字符串池，`num` 存偏移；`aux = 0`
  表示拼写就在 `text` 里。
- 三个捕获点（`Parser` 全局、`Stmt` 局部 `static`、`Expr` 复合字面量）改为写入池，
  捕获 4 KiB / 重写 16 KiB / 单项 4 KiB。
- `Emit` 的 `emit_raw_init` 与 `emit_expr` 的 `N_RAW` 分支按 `aux` 选来源。

## [x] T2 fixture、关卡、文档与提交

- `test/ast/46_long_init`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：新增 §4.30（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): lift the length cap on initialiser lists`、
  `docs(spec): record the initialiser length limits`。不 bump 版本、不动 golden。
