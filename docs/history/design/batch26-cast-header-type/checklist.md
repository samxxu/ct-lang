# 检查清单：转换与 `sizeof` 里的头文件类型名（第二十六批）

依据：`docs/design/batch26-cast-header-type/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `t = (time_t)raw;` 正确（`cast 5 5`）
- [x] `ref = (time_t *)&t;` 正确（指针类型的转换）
- [x] `ticks = (clock_t)t;` 正确
- [x] `sizeof(time_t)` 与 `sizeof(time_t *)` 可用（比较结果为 1 1）
- [x] `(MAX) + 1` 仍是表达式（全大写宏常量否决）
- [x] `(a) * 2` 仍是表达式（变量否决）
- [x] `(g)(7)` 仍是调用（函数否决）
- [x] `sizeof(buf)` / `sizeof(*p)` 仍是表达式形式
- [x] 自编不动点全绿（第一版曾把 `(snprintf(…))` 误判为转换，已修）

## 诊断

- [x] 本批不新增诊断，也不放宽既有诊断

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 275 passed, 0 failed（含 51_cast_header_type）
- [x] `bash selfhost/check-warnings.sh` → 141 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `*.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 探针

- [x] ct-ast 仍完整编译 `selfhost/l0/ctc.c`，无诊断
- [x] L2 与 ct-ast 对 `(time_t)raw` / `sizeof(time_t)` 的行为已一致

## 文档

- [x] `docs/language-spec.md` §4.33 改写（中英对称）：判据三条、`(f(x))` 与 `(MAX) + 1`
- [x] 文档写明函数指针类型转换不在支持范围

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（与 L2 的行为差）与验证方式
