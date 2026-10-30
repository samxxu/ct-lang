# 检查清单：变参函数指针（第二十二批）

依据：`docs/design/batch22-vararg-fnptr/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `typedef int (*logger_fn)(const char *fmt, ...);` 可用
- [x] 结构体字段 `logger_fn log;` 可调用，多余实参透传
- [x] 全局初始化器 `static logger_fn g_log = say;` 正确
- [x] 函数指针数组 `static logger_fn tbl[2] = { say, say };` 正确
- [x] 局部变量 `counter_fn local = counts;` 可赋值并调用
- [x] `va_list` 作为普通参数传给辅助函数（`vlog`）仍工作
- [x] 非变参函数指针（既有 27_fnptr_forms）输出不变

## 诊断

- [x] `(...)` 报 `a variadic function pointer needs a named parameter before '...'`
- [x] `(void, ...)` 报同一条消息（`void` 不是参数）
- [x] 原有的 `int f(...)` 诊断（`'...' needs a named parameter before it`）不变

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 271 passed, 0 failed（含 47_vararg_fnptr 与两个负例）
- [x] `bash selfhost/check-warnings.sh` → 137 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.31（中文 + 英文）
- [x] 文档写明 `...` 属于签名拼写、必须有具名参数、调用不检查实参类型

## 提交

- [x] 代码 + fixture + 负例 + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式
