# 检查清单：数组长度表达式（第十九批）

依据：`docs/design/batch19-array-length/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 全局 `static int g_tbl[WIDTH * 2];` 编译并运行正确
- [x] 字段 `int cells[SLOTS];`（宏）正确
- [x] 字段 `char name[(1 << 3)];`（位移 + 括号）正确
- [x] 字段 `short pairs[WIDTH + 1];`（求和）正确
- [x] 局部 `int local[WIDTH + 1];` 正确
- [x] `sizeof` 交叉验证长度（8 / 8 / 5）
- [x] 数字、单个名字、空维度三条既有路径不受影响（既有 fixture 全绿）
- [x] 单个枚举成员的归一化仍在（多 token 表达式原样保留）

## 诊断

- [x] 本批不新增诊断
- [x] 无法闭合的方括号仍报 `expected an array length`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 264 passed, 0 failed（含 44_array_length）
- [x] `bash selfhost/check-warnings.sh` → 134 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.28（中文 + 英文）
- [x] 文档说明原文捕获、枚举归一化只作用于单名字、VLA 交由 C

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（ctc.c 探针）与验证方式
