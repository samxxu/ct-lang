# 第十八批特性：一条声明多个字段（2026-10-30）

> 锚点：`23d4dfb`（第十七批收口），工作树干净。
> 由一次**实证探针**触发：用 ct-ast 编译仓库自己的 `selfhost/l0/ctc.c`（2930 行纯 C），
> 报错落在 `size_t bstart, blen;` —— 记录体的字段文法只认「一条一个名字」。

## 1. 实测现状

- `struct ImplMethod { char name[..]; size_t bstart, blen; };` 报 `unexpected token`：
  `parse_field_def` 读完一个名字后直接 `expect(";")`，撞上 `,`。
- 局部变量早已支持 `int a, b;`（`N_DECLS` 包装），只是字段文法没有对应物。
- 位域同样只能一条一个：`unsigned a : 3, b : 5;` 不支持（第八批文档写明）。

## 2. 决策

- **D-1 节点 56 `N_FIELDS`**：一条声明多个声明符时，外层是一个 `N_FIELDS`
  包装（`text` = 第一个声明符的类型拼写、`a` = 各 `N_FIELD` 的链），
  与局部的 `N_DECLS` 同构。单个声明符仍原样返回 `N_FIELD`，既有路径不变。
- **D-2 星号按声明符归属**：`int *data, count;` 里 `*` 只属于 `data`，`count` 是 `int`
  （与 C 一致，也与局部的既有规则一致）。实现上是把第一个声明符的类型整串记下来，
  后续声明符从去掉星号的基类型重新起算自己的星号。
- **D-3 位域可以成列**：`unsigned a : 3, b : 5;` 支持，每个声明符各自带宽度；
  宽度与位域类型的既有检查逐条生效。
- **D-4 函数指针仍是一个名字**：`int (*a)(int), (*b)(int);` 报
  `a function pointer declares one name`（沿用局部声明的既有消息）。
- **D-5 登记与发射**：`register_field` 展开 `N_FIELDS` 的每个名字（字段表、重名检查、
  匿名成员提升都不变）；`emit_field` 把共享类型打印一次，其余声明符各带自己的星号、
  维度与位宽。

## 3. 影响面

- 改：`frontend/parse/Parser.h.ct`（`N_FIELDS`、`parse_field_def` 的声明符循环、
  `register_field` 一支）、`backend/emit/Emit.h.ct`（`N_FIELDS`、`emit_field` 一支）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`Expr` / `TypeCheck` / `Init`（字段表早已拍平）、`ctc.c` / `l1` / `l2`、
  `CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/43_multi_field`：`int lo, hi;`、`char name[8]; unsigned len, cap;`、
  `int *data, count;`（星号只属于第一个）、位域成列 `unsigned a : 3, b : 5;`、
  结构体字段成列、`typedef struct { long x, y; }`、union 里 `int i, j; char c;`。
- 本批不新增诊断（函数指针那条沿用既有消息）。
- 探针复跑：`selfhost/l0/ctc.c` 的报错点从 127 行推进到 151 行
  （`static char g_guard[MAX_NAME * 2];` 的数组长度是表达式），留给下一批。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
