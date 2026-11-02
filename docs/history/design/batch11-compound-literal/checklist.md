# 检查清单：复合字面量（第十一批）

依据：`docs/design/batch11-compound-literal/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `p = (struct Point){ 1, 2 };` 赋值并运行正确
- [x] 作为 struct 实参：`sum_point((struct Point){ 3, 4 })`
- [x] `return (struct Point){ x, y };` 返回临时对象
- [x] 后缀：`(struct Point){ 5, 6 }.y`、`((struct Point){ .y = 9, .x = 8 }).x`
- [x] 指定初始化器（`.y = 9`）原样发射
- [x] 带 trait 的 struct 自动补 vptr 项（`(struct Pair){ 10, 20 , .__named_vptr = &… }`）
- [x] 标量形式 `(int){ 42 }` 可用
- [x] `expr_type(N_COMPOUND)` 返回类型，故成员访问 / 赋值 / 实参的类型推断正常

## 诊断与交互

- [x] `(struct P *){ … }` 报 `a compound literal needs an object type`
- [x] 数组类型 `(int[]){ … }` 仍报 `unexpected token`（文档写明范围外）
- [x] 复合字面量上直接调 trait 方法仍按既有接收者规则拒绝（文档写明）
- [x] `init_raw` 上移后，声明初始化器的行为不变（既有 fixture 全绿）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 242 passed, 0 failed（含 36_compound_literal 与 batch 11 消息）
- [x] `bash selfhost/check-warnings.sh` → 126 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] impl 方法总数 255（`init_raw` +1 / `parse_init_raw` −1，预算未变）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.20 复合字面量（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 文中写到的形态都能在 `test/ast/36_compound_literal` 或负例里找到对应代码
- [x] 文档写明范围外：数组类型、直接调 trait 方法

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
