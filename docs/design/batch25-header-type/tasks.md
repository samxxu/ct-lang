# 任务：头文件里的类型名（第二十五批）

依据：`docs/design/batch25-header-type/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 声明判定与类型解析

- `Stmt.h.ct`：`is_decl_start` 在「未知名字」分支做词法状态保存/恢复的前瞻
  （未知名 + 名字，或未知名 + `*`… + 名字）；用符号表否决变量/函数，用关键字表否决
  语句关键字。
- `Expr.h.ct`：`parse_type` 在 `n == 0` 时把未知名字按原样收下。

## [x] T2 fixture、关卡、文档与提交

- `test/ast/50_header_type`：见 spec §4。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：新增 §4.33（中英对称），写明判据与不做转换/`sizeof`。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept a header's type name in a declaration`、
  `docs(spec): record header type names`。不 bump 版本、不动 golden。
