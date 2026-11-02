# 检查清单：逗号表达式（第二十三批）

依据：`docs/design/batch23-comma/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 语句级 `i = 1, j = 2;` 两个赋值都生效（`pair 1 2`）
- [x] `for (i = 0, j = 10; …)` 首句两赋值都生效
- [x] 步进 `i++, j--` 正确（`step 3 7 27`）
- [x] 步进 `i++, j = j + 2` 正确（`loop 0 0` / `loop 1 2`）
- [x] 纯调用操作数 `bump(&i), bump(&j)` 正确（`bump 1 1`）
- [x] `last = i, last = last + 1;` 按 `(last = i), (last = last + 1)` 求值（`last 2`）
- [x] 既有语句与 `for` 形状输出不变（全套 fixture 全绿）

## 诊断

- [x] 本批不新增诊断
- [x] 范围外的值位置（`x = (a, b);`、`for` 条件、实参）仍报既有 `unexpected token`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 272 passed, 0 failed（含 48_comma）
- [x] `bash selfhost/check-warnings.sh` → 138 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 探针

- [x] ct-ast 完整编译 `selfhost/l0/ctc.c`（2930 行），无诊断
- [x] 生成的 C 通过 `cc -Wall -Wextra -std=c99`（仅源文件自身的 C23 label 提示）
- [x] 产物当 ctc 跑通 `examples/01_greeter`，输出与 `.expected.out` 一致

## 文档

- [x] `docs/language-spec.md` 新增 §4.32（中文 + 英文）
- [x] 文档写明接受的位置、右结合只是解析产物、以及范围外的值位置

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（ctc.c 探针）与验证方式
