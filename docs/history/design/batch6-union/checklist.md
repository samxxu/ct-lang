# 检查清单：`union`（第六批）

依据：`docs/design/batch6-union/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `union Tag { … };` 编译并运行正确，发射为 C 的 `union Tag { … };`
- [x] `typedef union Tag { … } Alias;` 与 `typedef union { … } Alias;` 两种写法都正确
- [x] `};` 与 `}` 都能收尾（顶层尾分号可省）
- [x] 裸标签 `Value v;` 与 `union Value v;` 等价（kind 6 补 `union` 前缀）
- [x] 源码里的 `union Value;` 前向声明被接受，生成物按类别发射 `union Value;`
- [x] `struct` 字段可以是 union 类型，`offsetof` 与该字段的链式访问正确
- [x] `union` 与 `struct` 共用同一张记录表，故前向声明 / `defined` 判定与字段校验一并复用
- [x] 前向声明按类别分流：union 发射 `union X;`（不是 `struct X;`）
- [x] 成员共享存储：没有 vptr 字段，也不允许 `use` 子句
- [x] 同一命名空间内的标签按 struct 规则 mangling；跨单元裸名可引用
- [x] `pub union` 出现在生成的头文件里，消费单元能直接用

## 诊断

- [x] 重复标签报 `duplicate union '<name>'`
- [x] `union … use Trait;` 报 `a union cannot use a trait`
- [x] 匿名 union（`union { int i; } u;`）报 `expected a union name`
- [x] `offsetof(union V, d)` 字段不存在报 `union '<V>' has no field '<d>'`；struct 侧消息不变
- [x] `offsetof` 第一参数是 union 时不再报 `offsetof needs a struct type`
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` 全绿（自举 fixpoint、语料等价、模块段不变）
- [x] `bash selfhost/check-warnings.sh` 零告警
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.15 `union`（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 顶部「其它 C 透传」表不再列 `union`（只剩 `goto` / 标签等）
- [x] 文中写到的每条语法都能在 `test/ast/31_union` 找到对应代码
- [x] 文档写明匿名成员不在支持子集内

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
