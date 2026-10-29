# 检查清单：空语句与 `for` 首句的 `static`（第十二批）

依据：`docs/design/batch12-empty-stmt/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `for (i = 0; i < 3; i++) ;` 编译并运行正确（循环体为空，`i` 结束于 3）
- [x] `while (c) ;` 可用
- [x] `if (c) ; else …` 可用（空语句作为 then 分支）
- [x] `case 3: ;` 可用（标签后有语句，不再报 `a case label needs a statement`）
- [x] goto 标签后 `done: ;` 可用（不再报 `a label needs a statement`）
- [x] 空语句不发射任何字符，外层块的 `{` `}` 照常输出
- [x] `for (static int i = 0; …)` 可用，发射为 `for (static int i = 0; …)`
- [x] 语义正确：static 初始化只执行一次，第二次进入直接以余值判断条件（期望输出 2 / 0）

## 诊断

- [x] 本批不新增诊断
- [x] `static` 后面不是声明时仍报 `expected a declaration after 'static'`（第十批那条不变）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 243 passed, 0 failed（含新增 37_empty_stmt）
- [x] `bash selfhost/check-warnings.sh` → 127 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 未新增 impl 方法（预算 255/256 不变）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.21（中文）
- [x] 同节英文更新，与中文一一对应
- [x] §4.16 的「空语句不在子集内」改为指向 §4.21（中英对称）
- [x] §4.19 的「`for` 首句的 static 范围外」改为指向 §4.21（中英对称）
- [x] 章节序号连续（4.19 → 4.20 → 4.21）

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
