# 检查清单：控制流补全（第四批）

依据：`docs/design/batch4-control/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [ ] `switch (x) { case 1: … default: … }` 编译并运行正确
- [ ] 多 `case` 贯穿（无 `break` 落入下一分支）行为与 C 一致
- [ ] `case` 内 `break`、嵌套 `if`、嵌套块均正确
- [ ] `case` 内 trait 方法调用与函数指针字段直调正确
- [ ] 标签值支持数字、负数、字符字面量、`#define` 宏名
- [ ] `switch` 体内声明（`case` 之前的 `int y;`）正确
- [ ] `do { … } while (c);` 与单语句体 `do stmt; while (c);` 均正确
- [ ] `switch` 体外的普通 `while` / `for` / `if` 行为不变

## 诊断

- [ ] 标签后紧跟声明报 `a declaration cannot follow a case label; wrap it in a block`
- [ ] 标签后紧挨 `}` 报 `a case label needs a statement`
- [ ] 非常量标签报 `a case label must be an integer constant`
- [ ] `do` 缺 `while` 报 `a do statement must be followed by while (...)`
- [ ] `switch` 体外（含体内嵌套块）的 `case` 报 `a case label is only allowed inside a switch`
- [ ] `switch` 体内 `own` 报 `own is not supported inside a switch`
- [ ] 以上均带 `file:line:col:`

## 回归与关卡

- [ ] `bash selfhost/check-ast.sh` 全绿（自举 fixpoint、语料等价、模块段不变）
- [ ] `bash selfhost/check-warnings.sh` 零告警
- [ ] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [ ] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [ ] `CTC_VERSION` 未变

## 文档

- [ ] `docs/language-spec.md` 语句章节中文更新
- [ ] 同节英文更新，与中文一一对应
- [ ] 顶部「其它 C 透传」表不再把 `switch` / `do-while` 列为 ct-ast 缺口
- [ ] 文中写到的每条语法都能在 `test/ast/28_switch`、`29_do_while` 找到对应代码

## 提交

- [ ] 代码 + fixture + 关卡一个提交
- [ ] spec 与文档一个提交
- [ ] 提交正文说明动机与验证方式，不含无关改动
