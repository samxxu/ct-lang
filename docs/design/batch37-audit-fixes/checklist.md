# 检查清单：审计问题处置（第三十七批）

依据：`docs/design/batch36-audit-fixes/spec.md` / `tasks.md`

## 修复

- [x] DOC-23 / 24 / 25 / 26 / 27 / 29 / 30
- [x] TEST-8 / 10 / 11 / 12 / 13
- [x] SH-23（ct-ast 拒绝 >159 字符标识符）

## 部分处置

- [x] TEST-9：5 个生成式上限用例（params / methods / funcs / scopes / vars）
- [x] CI-4：`Makefile` 的 `make check`（不加云端 workflow，理由见 spec）

## 不采纳

- [x] TEST-7（完整逐字节 golden）：理由记入 spec §3
- [x] SH-24（合并两套 CLI 解析器）：理由记入 spec §3

## 验证

- [x] `check-ast.sh` → 351 passed, 0 failed
- [x] `check-warnings.sh` → 152 ok, 0 failed
- [x] `check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未改生成物、golden、`CTC_VERSION`；L0 / L1 / L2 未动

## 记录与提交

- [x] `issues/README.md` 与 18 个 issue 文件补处置结论
- [x] 代码 + 测试 + 门禁一个提交；文档与处置记录一个提交
