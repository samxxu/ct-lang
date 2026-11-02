# 检查清单：变参函数（第十三批）

依据：`docs/design/batch13-variadic/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `static int f(int n, ...);` 原型 + 定义都编译通过，发射为 `int f(int, ...)`
- [x] 定义处参数表发射 `int f(int n, ...)`
- [x] `va_list ap;` 作为普通声明可用（`va_list` 是内置类型词）
- [x] `va_arg(ap, int)` 可用，发射为同形调用，类型可用于算术
- [x] `va_start(ap, n)` / `va_end(ap)` 按未知被调函数发射，由 `<stdarg.h>` 提供声明
- [x] 零个可变实参的调用（`sum_all(0)`）正确
- [x] 多个变参求和的运行结果正确（0 / 7 / 10），取最大值正确（9 / 7）

## 诊断

- [x] `int f(...)` 报 `'...' needs a named parameter before it`
- [x] `impl` 里方法带 `...` 报 `a trait method cannot be variadic`
- [x] trait 声明里写 `...` 报 `expected a type`（既有路径，文档写明）
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 248 passed, 0 failed（含 38_variadic 与 batch 13 两条消息）
- [x] `bash selfhost/check-warnings.sh` → 128 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.22 变参函数（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 文档写明 `...` 的前置参数要求、`va_list` / `va_arg` / `va_start` 的处理方式
- [x] 文档写明 trait 方法不能变参（含 trait 声明侧的既有报错）

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
