# 检查清单：`enum`、常量表达式与 `offsetof`（第五批）

依据：`docs/design/batch5-enum/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `enum Tag { A, B = <常量>, C };` 编译并运行正确
- [x] 尾逗号 `enum Tag { A, B, };` 正确
- [x] 成员自增（无初值）与显式值混用，取值符合 C
- [x] `typedef enum [Tag] { … } Alias;` 两种写法都正确，`enum Tag` 与 `Alias` 都能作类型
- [x] `Color c;`（裸标签）与 `enum Color c;` 等价
- [x] 同一命名空间内的成员引用发射为 `ns_member`；跨单元限定名与裸名都能取到
- [x] `pub enum` 出现在生成的头文件里，消费单元能直接用
- [x] `case (1 << 2):`、`case 1 + 2:`、`case RED:`、`case 'a':`、`case -1:`、`case KIND_B:` 均正确
- [x] `offsetof(struct S, b)` 偏移值正确；typedef 别名作类型也正确
- [x] 生成物在 `--line` 模式下同样零告警

## 诊断

- [x] 非常量标签报 `a case label must be an integer constant`
- [x] 重复标签报 `duplicate enum '<name>'`
- [x] 成员初值非常量报 `an enum value must be an integer constant`
- [x] 枚举缺标签报 `expected an enum name`
- [x] `offsetof` 第一参数不是结构体报 `offsetof needs a struct type`
- [x] `offsetof` 字段不存在报 `struct '<S>' has no field '<f>'`
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` 全绿（自举 fixpoint、语料等价、模块段不变）
- [x] `bash selfhost/check-warnings.sh` 零告警
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增枚举 / 常量表达式 / `offsetof` 段（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 顶部「其它 C 透传」表只留 `union` / `goto` / 标签等仍未实现的项
- [x] 文中写到的每条语法都能在 `test/ast/30_enum` 找到对应代码
- [x] 文档写明 `offsetof` 需要源文件自带 `#include <stddef.h>`

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
