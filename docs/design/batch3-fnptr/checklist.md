# 检查清单：函数指针补全（第三批）

依据：`docs/design/batch3-fnptr/spec.md` / `tasks.md`
全部打勾才算收口。

## 语法与语义

- [x] `typedef int (*BinOp)(int, int);` 编译通过，生成物为 `typedef int (*BinOp)(int, int);`
- [x] typedef 别名可作局部变量、参数、struct 字段
- [x] `o.add(2, 3)`（`.` 直调字段）编译并运行正确
- [x] `p->add(2, 3)`（`->` 直调字段）编译并运行正确
- [x] typedef 形态的字段直调 `o.sub(2, 3)` 编译并运行正确
- [x] 全局 `static int (*tbl[2])(int, int) = { plus, minus };` 编译并运行正确
- [x] 局部函数指针数组逐元素赋值 + `tbl[i](x)` 调用正确
- [x] struct 字段 `int (*cb[2])(int)` 编译通过
- [x] 文件作用域 `static int (*gp)(int, int) = plus;` 生成物零告警并通过 cc
- [x] 普通函数指针形态（`test/ast/21_fnptr`、`25_fnptr_libfn`）行为不变

## 诊断

- [x] 嵌套函数指针报 `nested function pointers are not supported`，带 `file:line:col:`
- [x] 函数指针数组作参数报 `function-pointer arrays are not supported as parameters`
- [x] trait 方法调用失败仍是原消息（`cannot resolve the method trait`）

## 回归与关卡

- [x] `bash selfhost/check-ast.sh` 全绿（含自举 fixpoint、语料等价、模块段）
- [x] `bash selfhost/check-warnings.sh` 零告警
- [x] `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`
- [x] 普通数组与参数维度的生成物输出逐字节不变（`17_param_array`、`18_struct_array_field`）
- [x] `git status` 无 `test/cases/**`、`examples/**` 的 `.expected.*` 变化
- [x] `CTC_VERSION` 未变

## 文档

- [x] `docs/language-spec.md` §4.12 中文更新
- [x] 同节英文更新，与中文一一对应
- [x] 限制段落不再写「不支持 typedef 函数指针」
- [x] 文中写到的每条语法都能在 `test/ast/27_fnptr_forms` 找到对应代码

## 提交

- [x] 代码 + fixture + 关卡一个提交
- [x] spec 与文档一个提交
- [x] 提交正文说明动机与验证方式，不含无关改动
