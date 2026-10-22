# 任务：函数指针补全（第三批）

依据：`docs/design/batch3-fnptr/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [ ] T1 维度基础设施与嵌套诊断

- `frontend/parse/Expr.h.ct`：
  - `struct Expr` 增加 `char fnptr_dims[160]`，与 `fnptr_name`、`fnptr_state` 一起在
    `parse_type` 入口清空；
  - 函数指针分支读完声明子名字后，接受零到多组 `[<数字>]` / `[<标识符>]` / `[]`，
    拼进 `fnptr_dims`，再 `)` + 参数表；
  - 吃掉 `(*` 后若当前 token 仍是 `*`（`int (*(*f)(void))(int)`），报
    `nested function pointers are not supported`。
- 验收：`check-ast.sh` 构建段能编过；`test/ast/21_fnptr`、`25_fnptr_libfn` 行为不变。

## [ ] T2 typedef 解析与类型表 kind 4

- `frontend/parse/Parser.h.ct` `parse_typedef`（约 795 行）：`parse_type` 返回后，
  若 `self->ex->fnptr_state` 为真，别名取 `fnptr_name`；类型串含 `(*` 时
  `add_type(qname, 4)`，否则仍为 kind 2；`fnptr_dims` 写进 `N_TYPEDEF.text3`。
- `frontend/sym/Symbols.h.ct:149`：`type_kind` 注释补 `4 = function-pointer typedef`。
- 验收：`typedef int (*BinOp)(int, int);` 编译通过。

## [ ] T3 发射器维度方法

- `backend/emit/Emit.h.ct`：
  - 新增 `emit_type_name_dims(type, name, dims)`：类型含 `(*)` 时维度进括号内
    （`int (*tbl[2])(int, int)`），否则接在名字后（与原行为逐字节一致）；
  - `emit_type_name(type, name)` 以 `dims = ""` 委托；
  - `N_TYPEDEF` 改走带维度版本并补 `;\n`；
  - `N_GLOBAL`、`N_DECL`/`N_FIELD`、impl 参数（约 538 行）、函数定义参数（约 894 行）
    改走带维度版本，删掉紧邻的 `fputs(text3)`。
- 验收：生成物含 `typedef int (*BinOp)(int, int);`；`07_typedef`、`17_param_array`、
  `18_struct_array_field` 的生成物逐字节不变。

## [ ] T4 声明入口传播维度

- `fnptr_dims` 写进节点 `text3` 后再调 `parse_array_dims`（后者只追加，不覆盖）：
  `Stmt.h.ct` `parse_decl_node`、`Parser.h.ct` `parse_func`（全局分支）、`parse_field_def`。
- `Parser.h.ct` `parse_params`：`fnptr_state && fnptr_dims[0]` 时报
  `function-pointer arrays are not supported as parameters`。
- 验收：全局 `static int (*tbl[2])(int, int) = { plus, minus };`、局部逐元素赋值、
  struct 字段 `int (*cb[2])(int)` 编译运行正确；`tbl[0](x)` 调用正确。

## [ ] T5 字段直调

- `frontend/parse/Expr.h.ct`：
  - `ExprOps` 增加 `int fnptr_field(const char *stype, const char *field);`
    （剥 `struct ` 与尾部 `*` → `find_struct` → 按名找字段 → 字段类型含 `(*`，
    或 `find_type(字段类型)` 的 kind 为 4）；
  - `parse_postfix` 的 `.name(` / `->name(` 分支：接口判定与 `method_trait` 都失败后，
    若 `fnptr_field` 为真，把已建好的 `N_MCALL` 原地改成
    `N_CALL(a = 实参链, b = 新建的 N_MEMBER/N_ARROW, aux = 2)`。
- 验收：`o.add(2, 3)`、`p->add(2, 3)`、`o.sub(2, 3)` 编译运行正确；
  trait 派发（`09_methods`、`11_map`、`14_map_dispatch`）行为不变。

## [ ] T6 全局与原型换位

- `backend/emit/Emit.h.ct` `emit_program`（约 289-303 行）拆三段：
  struct/typedef → `emit_proto` → global（`extern` 仍跳过）。
- `write_unit_file`（约 1493-1507 行）同样拆三段（`pub` struct/typedef 仍不进 `.c`）。
- 验收：`static int (*gp)(int, int) = plus;` 生成物零告警；全部既有 fixture 通过。

## [ ] T7 fixture 与关卡

- 新增 `test/ast/27_fnptr_forms/prog.ct` + `prog.expected.out`：typedef 声明/局部/字段、
  字段直调（`.` 与 `->`）、函数指针数组（全局初始化器 + 局部逐元素）、
  文件作用域指针初始化、`o.sub = f` 赋值；输出固定为若干整数。
- 新增负例 `test/ast/errors/fnptr_nested.ct`、`fnptr_array_param.ct`。
- `selfhost/check-ast.sh` 在负例段补两条精确消息断言。
- 验收：`check-ast.sh` 全绿；`check-warnings.sh` 零告警。

## [ ] T8 文档

- `docs/language-spec.md` §4.12（中英对称）：代码块补 typedef 与函数指针数组；
  补「typedef 指针可作类型」「函数指针字段可直接调用」「文件作用域初始化器可命名本单元函数」；
  限制段落改为「不返回函数指针、不嵌套、数组不能作参数（后两者有明确诊断）」。
- 验收：中英段落一一对应，无残留「不支持 typedef 函数指针」。

## [ ] T9 全量门禁与提交

- `bash selfhost/check-all.sh` → 九关全绿。
- 提交拆分：`feat(codegen): complete function pointers in ct-ast`（代码 + fixture + 关卡）、
  `docs(spec): record the function-pointer forms`（spec + language-spec）。
- 不 bump 版本、不动 golden。
