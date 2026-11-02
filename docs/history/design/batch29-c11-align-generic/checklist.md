# 检查清单：C11 对齐与泛型选择（第二十九批）

依据：`docs/design/batch29-c11-align-generic/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 文件作用域 `_Alignas(16) int g;` 生成物保留 `_Alignas ( 16 )`，地址 16 对齐
- [x] `static _Alignas(16) int g;`（说明符在前）可用
- [x] 块作用域 `_Alignas(16) int local;` 可用，地址 16 对齐
- [x] 字段 `_Alignas(8) int x;` 可用，影响 `_Alignof(struct …)`
- [x] 参数 / `typedef` 走同一个 `parse_type`，无需单独用例
- [x] `_Alignof(type)` 发射为 `_Alignof(…)`，与 `sizeof` 共用节点
- [x] `_Generic(…)` 按 `int` / `double` / typedef / 指针选到不同分支
- [x] `_Generic` 的分支不被 ct 重写（文档写明边界）

## 诊断

- [x] `_Alignas` 后不是 `(` → `expected '(' after _Alignas`
- [x] `_Alignof x` → `_Alignof needs a type in parentheses`
- [x] `_Generic` 后不是 `(` → `expected '(' after _Generic`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 288 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 143 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] clang 与 GNU GCC 16 都能零告警构建 fixture 生成物，输出一致
- [x] L0 种子关卡仍通过（ctc.c 全量解析、产物可编译、示例输出一致）
- [x] 未新增 impl 方法（预算 255/256）、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.35（中文 + 英文）
- [x] 「仍未实现」表与 `_Alignas` / `_Generic` 相关的「范围外」条目已更新
- [x] README 中英两处的能力说明已更新

## 提交

- [x] 代码 + fixture + 负例 + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明「优先透传、不建 AST」的取舍与验证方式
