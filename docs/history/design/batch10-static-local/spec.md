# 第十批特性：`static` 局部变量（2026-10-30）

> 锚点：`a544921`（第九批收口），工作树干净。
> 本规格只做函数体内的 `static <type> name [= init];`（静态存储期的局部变量）。

## 1. 实测现状

- `static int n = 0;` 在语句位置报 `use of an undeclared variable`：`static` 不是类型词，
  `parse_stmt` 走到表达式路径，把 `static` 当变量名。
- 文件作用域的 `static` 早已支持（`parse_func` 的 `is_static`），本批只补函数体内一条路径。
- 所有局部声明的发射都汇聚到 `emit_inline` 的 `N_DECL` 分支（普通、malloc 指针、数组、
  `N_DECLS` 多声明符都先走它），因此加前缀只有一处。

## 2. 决策

- **D-1 复用 `N_DECL`，`aux = 1` 标记 static**（`N_DECL` 的 `aux` 此前未使用）。
  `parse_stmt` 在 `own` 分支之后加 `static` 分支：消费关键字 → 拒绝 `own` → 要求
  `is_decl_start()` → 置 `static_decl` 后调用同一个 `parse_decl_node()`。
- **D-2 发射**：`emit_inline` 的 `N_DECL` 分支在最前面发 `static `。多声明符只给第一个加前缀
  （其余是裸名字），与 C 同形。
- **D-3 类型与初始化器照旧**：`declare_var` 照常登记，所以成员访问、数组下标、方法调用都不变；
  初始化器不做折叠，是否常量交给 C 编译期判断（`initializer element is not constant`）。
- **D-4 与 AutoDrop / 泄漏分析的交互**：`static own …` 直接报
  `a static local cannot be 'own'`（静态对象的生命期不归作用域管）；static 声明**不**进入
  泄漏分析（`leak_decl` 跳过），因此 `static T *p = malloc(...)` 这种刻意的单例不会报泄漏，
  也不会被当成 owned。
- **D-5 诊断**：`static;` / `static x = 1;`（后面不是声明）报
  `expected a declaration after 'static'`；`static own …` 报上面那条。
- **D-6 范围外**：`for (static int i = 0; …)` 不在子集内（for 的首句只认普通声明或表达式）；
  `static` 直接跟在 `case` / goto 标签之后仍按「声明不能跟在标签后」拒绝（沿用既有消息）。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（结构体字段 `static_decl`、`parse_stmt` 的 static 分支、
  `parse_decl_node` 的标记与 `leak_decl` 跳过、两处标签链的声明判定加上 `static`）、
  `backend/emit/Emitter.h.ct`（`emit_inline` 的 `N_DECL` 分支加前缀）。
- **impl 方法预算**：L2 的 `MAX_MAP_IMPLS` 是 256，当前 255。本批不新增任何 impl 方法
  （全部内联进既有方法）。
- 不动：`frontend/sym/Symbols.h.ct`、`frontend/type/TypeCheck.h.ct`、`backend/mem/Memory.h.ct`、
  `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/35_static_local`：计数器跨调用保持、块内 static、未初始化的 static（零初始化）、
  static 数组初始化器、static struct（带 trait，vptr 初始化器是常量）调用方法、
  static 字符串指针。
- 新增两个负例：`static_own`、`static_no_decl`，在 `check-ast.sh` 里逐条 `grep` 精确消息。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
