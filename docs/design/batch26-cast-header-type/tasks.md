# 任务：转换与 `sizeof` 里的头文件类型名（第二十六批）

依据：`docs/design/batch26-cast-header-type/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 `next_is_type_name` 的未知名字判据

- 未知名 + 非变量/函数 + 非全大写 → 再前瞻一个记号：跳过 `*` 后必须是 `)`。
- 保存/恢复补上 `tokstart` 与 `lstart`。

## [x] T2 fixture、回归、关卡、文档与提交

- `test/ast/51_cast_header_type`：见 spec §4。
- 回归探针：`(MAX) + 1`、`(a) * 2`、`(g)(7)`、`sizeof(buf)`、`sizeof(*p)`。
- `check-ast.sh` 头注释补一行（本批无新诊断）。
- `docs/language-spec.md`：把 §4.33 的「不做」改写为已支持的判据（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): accept a header's type name in a cast or sizeof`、
  `docs(spec): record header type names in casts`。不 bump 版本、不动 golden。
