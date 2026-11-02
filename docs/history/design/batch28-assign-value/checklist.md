# 检查清单：表达式里的赋值（第二十八批）

依据：`docs/design/batch28-assign-value/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] 链式 `got = (a = b = 0);` 右结合（`chain 0 0 0`）
- [x] 下标目标 `got = (arr[0] = 4) + 1;`（`index 4 5`）
- [x] 成员目标 `got = (box.n = 7);`（`member 7 7`）
- [x] 复合赋值 `got = (a += 2);`（`compound 7 7`）
- [x] 与逗号混用 `((a = 9), a + 1)`（`mix 9 10`）
- [x] 条件 `while ((c = next()) < 3)` 与 `if ((a = c) == 3)` 正确
- [x] 语句层赋值生成物不变（`n = 0;` 不带括号）
- [x] 无括号的 `if (x = f())` 也接受（条件里同样打开开关）

## 诊断

- [x] 目标不是变量 / 成员 / 下标 / 解引用 → `assignment target is not assignable`
- [x] `own` 目标 → `an 'own' variable can only be assigned in a statement`（负例精确断言）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 279 passed, 0 failed
- [x] `bash selfhost/check-warnings.sh` → 142 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] L0 种子关卡仍通过（ctc.c 全量解析、产物可编译、示例输出一致）
- [x] 未新增 impl 方法（预算 255/256）、未新增节点编号
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.34（中文 + 英文）
- [x] 文档写明语句层不变、右结合、目标检查与 `own` 拒绝的原因

## 提交

- [x] 代码 + fixture + 负例 + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机（getchar 惯用法、与 L2 的行为差）与验证方式
