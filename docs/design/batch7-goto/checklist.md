# 检查清单：`goto` 与标签（第七批）

依据：`docs/design/batch7-goto/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `goto <label>;` 编译并运行正确，发射为同形的 `goto <label>;`
- [x] `<label>:` 编译并运行正确，发射为独占一行的 `label:`
- [x] `goto` 可以向前跳出双层循环，也可以向后跳成环（`test/ast/32_goto` 两种都覆盖）
- [x] 标签可以出现在嵌套块里，`goto` 可以跳入该块
- [x] 连续标签（`again: done:`）允许，发射为嵌套标签，语义不变
- [x] 标签与 `switch` 混用：`case` 里的 `goto` 跳出 `switch`，标签在 `switch` 之后
- [x] 两条语句以标识符开头（`r = 0;`）不会被前瞻误判为标签
- [x] `A::f();` 这类限定名仍走表达式语句（`::` 不是单个 `:`）
- [x] 不同函数可以复用同名标签（`scan` / `shared` 都用 `done`）

## 诊断

- [x] 同一函数内重复标签报 `duplicate label '<name>'`，位置指向第二个标签
- [x] `goto` 目标不在同函数内报 `label '<name>' is not defined`，位置指向那条 `goto`
- [x] 标签后直接跟声明报 `a declaration cannot follow a label; wrap it in a block`
- [x] 标签直接碰 `}` 报 `a label needs a statement`
- [x] `goto` 缺少名字报 `expected a label name`
- [x] 一个函数超过 64 个标签 / 64 条 `goto` 报 `too many labels in one function` /
      `too many gotos in one function`
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` 全绿（自举 fixpoint、语料等价、模块段不变）
- [x] `bash selfhost/check-warnings.sh` 零告警
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.16 `goto` 与标签（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 顶部「其它 C 透传」表不再列 `goto` / 标签
- [x] 文中写到的语法形态都能在 `test/ast/32_goto`、负例或既有模块用例里找到对应代码
- [x] 文档写明已知边界（标签直接接 `case`、空标签、标签后接声明）

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
