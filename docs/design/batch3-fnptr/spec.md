# 第三批特性：函数指针补全（2026-10-22）

> 锚点：`756be11`（SH-20 收口），工作树干净。文中行号是该提交的快照。
> 本规格只做函数指针；`switch` / `enum` / `offsetof` / 声明表等留给后续批次。

## 1. 实测现状

四层链（L0 → L1 → L2 → ct-ast）实编实测：

| 用法 | 现状 |
| --- | --- |
| `int (*p)(int)` 声明 / 参数 / 字段 / 赋值 / 调用 | ✅ 已可用（§4.12，`test/ast/21_fnptr`） |
| `p = strcmp;`（C 库函数作右值） | ✅ 已可用（SH-21，`test/ast/25_fnptr_libfn`） |
| `typedef int (*BinOp)(int, int);` | ❌ `error: expected a typedef name` |
| `typedef` 出来的指针类型作局部 / 字段 | ❌ 随上一条，无法开始 |
| `o.add(2, 3)` / `p->add(2, 3)` 直接调用字段 | ❌ `error: cannot resolve the method trait (unknown receiver type)` |
| 文件作用域 `int (*gp)(int, int) = plus;` | ❌ 发射顺序把全局放到函数原型之前，cc 报 `use of undeclared identifier 'plus'` |
| `int (*tbl[2])(int, int);`（含初始化器） | ❌ `error: unexpected token`（位置正确，但只是解析器撞墙） |
| 返回函数指针 / 嵌套函数指针 | ❌ 被拒，嵌套只报「declarator 里没名字」 |

表中前两行已可用；其余的 typedef、字段直调、全局初始化顺序、函数指针数组是能力缺口，
最后一行是诊断质量问题——本批一并收口。

## 2. 范围

| 编号 | 内容 | 归属 |
| --- | --- | --- |
| F1 | 函数指针 `typedef`（含 typedef 一个函数指针数组） | `frontend/parse/Parser.h.ct`、`frontend/parse/Expr.h.ct`、`frontend/sym/Symbols.h.ct` |
| F2 | 函数指针字段直接调用 `o.f(x)` / `p->f(x)` | `frontend/parse/Expr.h.ct` |
| F3 | 函数指针数组：局部、全局、struct 字段、`{ plus, minus }` 初始化 | `frontend/parse/**`、`backend/emit/Emit.h.ct` |
| F4 | 文件作用域全局初始化器可命名本单元的函数（原型先于全局） | `backend/emit/Emit.h.ct` |
| F5 | 精确诊断：嵌套函数指针 | `frontend/parse/Expr.h.ct` |
| 配套 | 正例 / 负例 fixture、`check-ast.sh` 断言、§4.12 中英对称文档 | `test/ast/**`、`selfhost/check-ast.sh`、`docs/language-spec.md` |

### 非目标

- **不支持返回函数指针**（`int (*pick(void))(int, int)`）与**嵌套函数指针**，保持拒绝；
  嵌套的诊断改为 `nested function pointers are not supported`。
- **函数指针数组不能作参数**（`void f(int (*tbl[2])(int));`）：C 会把它调整成指向指针的指针，
  与原型发射的抽象声明子形态冲突，直接报
  `function-pointer arrays are not supported as parameters`。
- 不做函数指针的签名 / 参数个数校验（与 C 一致，交给 C 编译器）。
- 不改 `map`、trait 派发、vtable、AutoDrop 的任何语义。
- 不动 L0 / L1 / L2，不 bump `CTC_VERSION`，不改 `test/cases/**`、`examples/**` 的 golden。

## 3. 关键设计决策

### D-1 typedef 复用 `fnptr_state`

`parse_type` 已把声明子 `(*Name)(params)` 吃进类型串，名字放在 `fnptr_name`。
`parse_typedef`（`Parser.h.ct:795`）无条件再要一个标识符，于是撞上 `;`。
改为：`parse_type` 返回后若 `fnptr_state` 为真，别名取 `fnptr_name`，不再读标识符。
类型串保持 `int (*)(int, int)`，与 C 的抽象声明子一致。

### D-2 类型表新增 kind 4（函数指针 typedef）

`Symbols.type_kind` 现有 1（struct tag）/ 2（typedef）/ 3（trait）。typedef 只记名字、不记底层类型，
`parse_type` 遇到 kind 2 原样使用别名——这对发射正确，但字段直调无法判断 `BinOp op;` 是不是函数指针。
新增 **kind 4 = 函数指针 typedef**：

- 写入：`parse_typedef` 在类型串含 `(*` 时 `add_type(qname, 4)`；
- `parse_type` 无需改动（kind 4 与 kind 2 同走「原样使用别名」）；
- 读取：字段直调判定（D-4）用 `find_type + type_kind == 4` 识别别名形态。

### D-3 typedef 发射走 `emit_type_name`

`Emit.h.ct:723` 现为 `typedef %s %s;`，对 `int (*)(int, int)` 会拼出非法 C。
改为经 `emit_type_name`（含 D-6 的维度版本）发射，得到 `typedef int (*BinOp)(int, int);`。
头文件与 `.c` 共用 `emit_type_decl`，一处修复覆盖两条路径。

### D-4 字段直调改写为 `N_CALL(aux = 2, b = 成员节点)`

`parse_postfix` 遇到 `.name(` / `->name(` 一律先建 `N_MCALL`，trait 解析失败即报
`cannot resolve the method trait`。修改为：接口判定与 `method_trait` 都失败后，
若接收者的结构体里 `name` 字段是函数指针（类型含 `(*`，或别名的 kind 为 4），
把同一个节点改成 `N_CALL`：

```c
kind = N_CALL
a    = 实参链（无参为 -1）
b    = 新建的 N_MEMBER / N_ARROW（接收者 + 字段名）
aux  = 2
```

这与既有「通过指针表达式调用」的约定一致（`aux = 2` 时发射 `emit_expr(b) + "("`），
发射器无需改动。不用 `a` 存接收者：`a` 在 `N_CALL` 里是实参槽，`hoist_scan` 也把它当子槽遍历。

### D-5 函数指针数组：维度随类型走

数组维度写在声明子内部（`int (*tbl[2])(int, int)`），而 ct-ast 的数组维度落在节点 `text3`。
做法：

- `struct Expr` 增加 `char fnptr_dims[160]`，与 `fnptr_name` 一起在 `parse_type` 入口清空；
- `parse_type` 的函数指针分支读完名字后，接受零到多组 `[<数字>]` / `[<标识符>]` / `[]`，
  拼进 `fnptr_dims`，然后才 `)` + 参数表；
- 四个声明入口（局部 `parse_decl_node`、全局 `parse_func`、struct 字段 `parse_field_def`、
  `parse_typedef`）在取名字之后先把 `fnptr_dims` 写进 `text3`，再调 `parse_array_dims`
  （后者只做追加，遇到 `;` 时不会覆盖）；
- 发射新增 `emit_type_name_dims(type, name, dims)`：类型含 `(*)` 时把维度放进括号内
  （`int (*tbl[2])(int, int)`），否则接在名字后（与原行为逐字节一致）。
  `emit_type_name(type, name)` 以 `dims = ""` 委托给它；
- 局部/全局声明、struct 字段、typedef、impl 参数与函数定义的参数这五处把 `text3` 交给新方法，
  不再单独 `fputs(text3)`。

`tbl[0](2, 3)` 不需要改：`parse_postfix` 的 `[` 与 `(` 已经能组合出 `N_INDEX` + `N_CALL(aux=2)`，
发射为 `tbl[0](2, 3)`，是合法 C。`{ plus, minus }` 初始化器经 `rewrite_init_text` 原样透传
（类型不是 struct，`init_item_text` 不做改写）。

参数位置拒绝（见非目标）：`parse_params` 在 `fnptr_state && fnptr_dims[0]` 时报错，
避免原型里出现 `int (*)(int)[2]` 这种非法抽象声明子。

### D-6 全局与原型换位（编译模式与 build 模式一致）

`emit_program`（`Emit.h.ct:289-296`）按源码顺序一次性发射 struct / typedef / global，之后才发射原型；
文件作用域初始化器一旦命名函数，C 就看不到声明。改为三段：

1. `N_STRUCT` / `N_TYPEDEF`（按源码顺序）；
2. 全部函数原型（`emit_proto`）；
3. `N_GLOBAL`（跳过 `extern`，按源码顺序），仍在 `emit_impls` 与函数体之前。

`write_unit_file`（`Emit.h.ct:1493-1504`）做同样拆分。globals 的 vptr 初始化仍安全：
vtable 的 tentative definition 已在 `emit_vtable_fwd` 出现。

### D-7 嵌套函数指针的精确诊断

`parse_type` 吃掉 `(*` 后若当前 token 仍是 `*`（`int (*(*f)(void))(int)`），
报 `nested function pointers are not supported`，不再落到「declarator 里没名字」。

## 4. 验收标准

| 项 | 验收 |
| --- | --- |
| F1 | `typedef int (*BinOp)(int, int);` 编译通过，生成物含 `typedef int (*BinOp)(int, int);`；别名可作局部、参数、struct 字段 |
| F2 | `o.add(2, 3)`、`p->add(2, 3)`、typedef 字段 `o.sub(2, 3)` 三种形态编译并运行出正确结果 |
| F3 | 全局 `static int (*tbl[2])(int, int) = { plus, minus };`、局部逐元素赋值、struct 字段 `int (*cb[2])(int)` 均编译运行正确；`tbl[0](x)` 调用正确 |
| F4 | 文件作用域 `static int (*gp)(int, int) = plus;`（`plus` 在本文件中定义）生成物零告警并通过 cc |
| F5 | `test/ast/errors/fnptr_nested.ct` 报 `nested function pointers are not supported`，带 `file:line:col:` |
| 参数限制 | `fnptr_array_param.ct` 报 `function-pointer arrays are not supported as parameters` |
| 回归 | `check-ast.sh` 全绿（含自举 fixpoint 与语料等价段）；`check-warnings.sh` 零告警 |
| 文档 | §4.12 中英对称：typedef、字段直调、数组形态、全局初始化顺序；限制段落同步 |
| golden | `git status` 不出现 `test/cases/**`、`examples/**` 的 `.expected.*` 变化 |

## 5. 验证命令

```bash
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/ctc
bash selfhost/check-all.sh          # 期望 check-all: OK (9 hard gates green)
bash selfhost/check-warnings.sh     # 期望 exit 0
git status --short
```

手工四层链（每步改完 ct-ast 后）：

```bash
mkdir -p /tmp/b3 && /tmp/ctc selfhost/l1/ctc.ct -o /tmp/b3/l1.c \
  && gcc -Wall -Wextra -std=c99 /tmp/b3/l1.c -o /tmp/b3/l1 \
  && mkdir -p /tmp/b3/l2 /tmp/b3/ast \
  && /tmp/b3/l1 build selfhost/l2/driver.ct -o /tmp/b3/l2 \
  && gcc -Wall -Wextra -std=c99 /tmp/b3/l2/*.c -o /tmp/b3/l2bin \
  && /tmp/b3/l2bin build -I selfhost/ct-ast selfhost/ct-ast/main.ct -o /tmp/b3/ast \
  && gcc -Wall -Wextra -std=c99 /tmp/b3/ast/*.c -o /tmp/b3/ct-ast
```

## 6. 出口条件

1. 九关全绿；`check-ast.sh` 的通过计数只增不减。
2. 新增 fixture 的生成物零告警。
3. 文档没有「已实现却写成不支持」或反向的段落。
4. 提交按规约拆分：`feat(codegen): complete function pointers in ct-ast`（代码 + fixture + 关卡）
   与 `docs(spec): record the function-pointer forms`（spec/文档）分开。
