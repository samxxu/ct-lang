# 检查清单：位域（第八批）

依据：`docs/design/batch8-bitfield/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `unsigned a : 3;` 编译并运行正确，发射为同形的 `<type> <name> : <宽度>;`
- [x] 宽度可以是常量表达式（`(2 + 2)`）或宏名（`NIBBLE` 展开为 `(1 << 2)`），原样发射不折叠
- [x] 无名位域 `unsigned : 4;` 作为填充位被接受
- [x] `union` 里的位域被接受
- [x] `typedef struct { … }` 的匿名体里的位域被接受（字段进别名表）
- [x] `use` 的 struct 里，vptr 字段排在所有位域之后
- [x] 位域与普通字段混排，成员访问（`f.a`、`self->hi`）的类型推断正常
- [x] `sizeof` 体现打包：`struct Flags` 的 24 位字段落在 4 字节里

## 诊断

- [x] 宽度表达式含变量报 `a bit-field width must be an integer constant`
- [x] 缺宽度报 `expected a bit-field width`
- [x] 数组位域报 `a bit-field cannot be an array`
- [x] 指针位域报 `a bit-field must have an integer type`
- [x] 以上均带 `file:line:col:`

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` → 227 passed, 0 failed（含 33_bitfield 与 batch 8 四条消息）
- [x] `bash selfhost/check-warnings.sh` → 123 ok, 0 failed
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` 新增 §4.17 位域（中文）
- [x] 同节英文更新，与中文一一对应
- [x] 顶部「其它 C 透传」表不再列位域
- [x] 文中写到的形态都能在 `test/ast/33_bitfield` 或负例里找到对应代码
- [x] 文档写明范围外：一条声明多个位域、`offsetof` 取位域

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
