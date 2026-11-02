# 检查清单：取值位置的逗号列表（第二十四批）

依据：`docs/design/batch24-comma-value/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 赋值右侧 `x = (i++, j * 2);` 取值正确（`value 8 4 4`）
- [x] 两个带副作用的调用作操作数（`bump 1 1 1`）
- [x] 实参里的括号逗号 `pair((i++, i + 1), 7)`（`arg 77 6`）
- [x] 条件里的括号逗号 `while ((i++, j > 8))`（`cond 3 0`）
- [x] 语句形式与 `for` 首句/步进的逗号（48_comma）输出不变
- [x] 普通括号表达式与既有 fixture 全部不受影响

## 诊断

- [x] 本批不新增诊断
- [x] `for (; a, b; )` 这种不带括号的取逗号仍按原行为报错（范围外，已写入 §4.32）
- [x] 括号内的赋值（`(i = 1, i)`）仍是既有范围外，未改变

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 273 passed, 0 failed（含 49_comma_value）
- [x] `bash selfhost/check-warnings.sh` → 139 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 探针

- [x] ct-ast 仍完整编译 `selfhost/l0/ctc.c`，无诊断

## 文档

- [x] `docs/language-spec.md` §4.32 扩写（中文 + 英文，不新增章节号）
- [x] 文档写明取值位置要加括号、操作数是普通表达式、以及仍不做的裸逗号

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式
