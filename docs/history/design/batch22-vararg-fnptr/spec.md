# 第二十二批特性：变参函数指针（2026-10-30）

> 锚点：`222a6ca`（第二十一批收口），工作树干净。
> 变参**函数**本身第十三批已落地（`test/ast/38_variadic`）；本批补的是
> **函数指针声明**里的 `...`。

## 1. 实测现状

- 定义、原型、调用、`va_arg`、`va_list` 参数都工作（第 13 批），`38_variadic`
  与实测探针都通过。
- 但 `int (*log)(const char *fmt, ...)` 报 `expected a type (tok 4 '...')`：
  `parse_type` 的声明符参数循环只接受 `parse_type`，不认 `...`。于是
  typedef、结构体字段、函数指针数组、局部声明一律跟着失效。
- ctc.c 自身就用这种类型（`int (*cb)(void *)` 之外还有变参回调场景），
  普通 C 代码里也常见（日志器、`qsort` 风格的注入点）。

## 2. 决策

- **D-1 `...` 是签名拼写的一部分**：在声明符参数循环里识别 `...`，追加到
  `plist` 后结束参数表，类型写成 `int (*)(const char *, ...)`。这样
  typedef / 字段 / 指针数组 / 局部全部自动生效，无需逐个入口特判。
- **D-2 前面必须有具名参数**：与第 13 批的定义/原型规则一致。`(...)` 与
  `(void, ...)` 都拒绝（`void` 是空参数表，不是参数）。
- **D-3 新诊断**：`a variadic function pointer needs a named parameter before '...'`。
- **D-4 发射器不动**：`emit_type_name_dims` 只把名字插进 `(*)`，
  `...` 原样穿过；调用就是普通调用，多余实参直接透传。
- **D-5 预算**：不新增节点、不新增 impl 方法（255/256），不动类型推断。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（声明符参数循环）。
- 新增：`test/ast/47_vararg_fnptr`、`test/ast/errors/vararg_fnptr_{no_named,void}.ct`。
- 不动：`Emit` / `TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、
  `CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/47_vararg_fnptr`：typedef 变量、结构体字段调用、全局初始化器、
  函数指针数组、局部变量赋值，以及把 `va_list` 传给辅助函数。
- 两个负例走 `check-ast.sh` 的精确消息断言。
- `bash selfhost/check-ast.sh` → 271 passed；`check-warnings.sh` → 137 ok；
  `check-all.sh` → 9 hard gates green。
- ctc.c 探针不变（下一个缺口仍是 `for` 首句里的逗号表达式，留给后续）。
