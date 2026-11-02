# 任务：变参函数指针（第二十二批）

依据：`docs/design/batch22-vararg-fnptr/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 声明符参数循环接受 `...`

- `Expr.h.ct`：在函数指针声明符的参数循环里识别 `...`，追加 `, ...` 后结束
  参数表；`plist` 为空或只有 `void` 时拒绝。
- 新诊断：`a variadic function pointer needs a named parameter before '...'`。

## [x] T2 fixture、负例、关卡、文档与提交

- `test/ast/47_vararg_fnptr`：typedef / 字段 / 全局初值 / 指针数组 / 局部 / `va_list` 传递。
- `test/ast/errors/vararg_fnptr_no_named.ct`、`vararg_fnptr_void.ct`。
- `check-ast.sh`：头注释补一行 + batch 22 的精确消息断言块。
- `docs/language-spec.md`：新增 §4.31（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): allow a variadic function pointer`、
  `docs(spec): record the variadic function-pointer form`。不 bump 版本、不动 golden。
