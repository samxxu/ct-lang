# 检查清单：内置类型词与 `inline`（第十四批）

依据：`docs/design/batch14-qualifiers/spec.md` / `tasks.md`
全部打勾才算收口。

## 类型词

- [x] `volatile int` 在全局、局部、参数、字段上都可用
- [x] `int *restrict p` 可用（`restrict` 进入类型字符串，原样发射）
- [x] `size_t` / `ssize_t` / `ptrdiff_t` / `wchar_t` 声明可用
- [x] `bool` / `_Bool` 可用（配 `<stdbool.h>` / `<stdint.h>`）
- [x] `int8_t`–`uint64_t` 声明与强制转换都可用
- [x] 类型集合与 L0 / L1 / L2 的 `is_type_keyword` 对齐（`restrict` 为 C 限定符额外补入）

## `inline`

- [x] `static inline int f(...)` 编译并运行正确
- [x] `inline static int f(...)`（顺序互换）同样正确
- [x] 发射为 `static inline ` / `inline `，生成的**原型不带** `inline`
- [x] `inline int value = 1;` 报 `'inline' can only declare a function`，位置指向 `inline`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 251 passed, 0 failed（含 39_builtin_types 与 batch 14 消息）
- [x] `bash selfhost/check-warnings.sh` → 129 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.23（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 列出完整类型词集合，并说明「原样发射、语义交给 C」
- [x] 文档写明范围外：`_Static_assert` / `_Alignas` / `_Generic` / `__attribute__`、浮点字面量

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（对齐 L2）与验证方式，不含无关改动
