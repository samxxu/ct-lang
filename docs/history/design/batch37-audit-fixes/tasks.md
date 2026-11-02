# 任务：审计问题处置（第三十七批）

依据：`docs/design/batch36-audit-fixes/spec.md`

## [x] T1 文档修复

- README（DOC-23 / 25 / 26 / 27 的测试树与告警描述）、tutorial（DOC-24）、
  test/README（DOC-27）、glossary + AGENTS（DOC-30）、roadmap（DOC-26）、
  batch 4 checklist（DOC-29）。

## [x] T2 代码修复

- `frontend/lex/Lexer.h.ct`：`toktrunc`；标识符超缓冲置位。
- `frontend/parse/ParseSupport.h.ct`：`lex_next` 把 `toktrunc` 变成
  `identifier is too long` 并停在 EOF。
- 新增 `test/ast/errors/identifier_too_long.ct`。

## [x] T3 门禁补强

- `check-ast.sh`：batch 37 的 13 条消息断言；5 条生成式上限；8 条 build CLI；
  8 个 build 模式镜像；`null_vtable_slot.ct` 改名同步。
- `check-warnings.sh`：扫描 `test/patterns/**`。
- 新增 `Makefile` 的 `check` 目标。

## [x] T4 处置记录与提交

- `issues/README.md` 与 18 个 issue 文件补处置结论。
- 提交：代码 + 测试 + 门禁一个提交；文档与处置记录一个提交。
