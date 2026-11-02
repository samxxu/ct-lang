# 检查清单：`_Static_assert`（第十七批）

依据：`docs/design/batch17-static-assert/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 文件作用域 `_Static_assert(sizeof(int) == 4, "…");` 编译通过，发射同形
- [x] 文件作用域可以用 `sizeof(struct S)`（断言在类型之后发射）
- [x] 函数体内（`check`）与 `main` 里各一条也正确
- [x] 消息可以省略（只测解析，见文档）
- [x] 断言失败时由 C 编译器报错（`_Static_assert` 原样发射）

## 诊断

- [x] 条件非常量（`_Static_assert(limit == 4, …)`）报
      `a static assertion needs a constant condition`
- [x] 消息不是字符串字面量报 `a static assertion message must be a string literal`
- [x] 上述消息均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 262 passed, 0 failed（含 42_static_assert 与 batch 17 两条消息）
- [x] `bash selfhost/check-warnings.sh` → 132 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.26（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 顶部「分叉」表改写为「有意拒绝 / 仍未实现」两组，并说明理由（中英对称）
- [x] 文档写明顶层发射顺序与范围外项

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec、§4.26 与分叉表改写共用一个文档提交（同一文件的两处改动无法按文件拆分）
- [x] 提交正文说明动机与验证方式，不含无关改动
