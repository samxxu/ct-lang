# 任务：浮点字面量（第十五批）

依据：`docs/design/batch15-float-literal/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 词法（`frontend/lex/Lexer.h.ct`）

- `Lexer` 加 `int tokfloat;`；数字分支开头清零。
- 十进制分支：扫完整数位后，若 `.` 且下一个不是 `.`，或 `e`/`E`（可带符号）后接数字，
  则置 `isflt`，继续扫小数与指数，可选后缀 `f/F/l/L`；`isflt` 时把原文拷进 `toktext`、
  置 `tokfloat = 1`。
- 新增 `.digit` 分支（放在 `...` 之后）：扫 `.digits` + 可选指数 + 可选后缀，同样置
  `tokfloat`。

## [x] T2 解析与发射（`Expr.h.ct` / `Emitter.h.ct`）

- `N_FNUM 54`；`parse_primary` 的 `T_NUM` 分支按 `tokfloat` 分流：整数写 `num`，
  浮点写 `text`。
- `emit_expr`：`N_FNUM` 原样输出 `text`。

## [x] T3 fixture、关卡、文档与提交

- `test/ast/40_float_literal`：见 spec §4。
- 负例：`float_case`；`check-ast.sh` 加精确消息断言。
- `docs/language-spec.md`：新增 §4.24（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): lex floating-point literals`、
  `docs(spec): record the floating-point literal form`。不 bump 版本、不动 golden。
