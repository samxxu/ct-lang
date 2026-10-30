# 第二十五批特性：头文件里的类型名（2026-10-31）

> 锚点：`8589c6a`（第二十四批收口），工作树干净。
> 来源：用 ct-ast 编译仓库里的普通 C 源码时实测到的**能力倒退**——
> `time_t now;` 在 L2（回归 oracle）下原样通过，在 ct-ast 下报
> `use of an undeclared variable`。

## 1. 实测现状

- ct 不展开 `#include`，所以头文件里的 typedef（`time_t`、`clock_t`、`pthread_t`……）
  对解析器都是未知名字。
- ct-ast 的 `is_decl_start` 只认内置类型词与已登记类型，`parse_type` 也在未知名字处停下，
  于是这类声明被当成表达式语句 → 报 `use of an undeclared variable`。
- L2 是行重写器，不解析声明，因此原样通过。这是 ct-ast 相对 oracle 的缺口，而不是新特性。

## 2. 决策

- **D-1 声明位置的形状判据**：当前 token 是未知标识符时，看它的后继——直接是声明的名字
  （`time_t now`）或隔着若干 `*` 之后是名字（`time_t *t`）→ 视为声明。实现是在
  `is_decl_start` 里做一次完整词法状态保存/恢复的前瞻。
- **D-2 符号表否决**：该名字若已经是变量或函数，就不是类型，`a * b;` 仍是表达式。
- **D-3 语句关键字否决**：`return found;`、`goto done;`、`own Box *b`、`sizeof x` 等
  关键字后面同样跟名字，必须显式排除（实测中正是这两条否决避免了 32_goto 与
  own_in_switch 两个回归）。
- **D-4 解析**：`parse_type` 在「一个类型词都还没读到」且名字未知时按原样收下，
  后续 `*` 与非类型名照旧结束类型；声明、原型、字段、参数四条路径因此同时可用。
- **D-5 不动产**：转换与 `sizeof` 的类型判定（`next_is_type_name`）保持保守——
  `(NAME) + x` 与宏常量无法区分，`(time_t)x`、`sizeof(time_t)` 仍按表达式解析。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（`is_decl_start` 的前瞻与两道否决）、
  `frontend/parse/Expr.h.ct`（`parse_type` 的未知名字一支）。
- **impl 方法预算**：不新增方法（255/256），不新增节点编号。
- 不动：`Emit` / `TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/50_header_type`：全局 `time_t`、字段 `time_t`、参数 `time_t`、
  局部 `time_t` 与 `time_t *`、`clock_t`，并用 `i * j` 锁定「变量相乘仍是表达式」。
- 本批不新增诊断，也不放宽任何既有诊断。
- 关卡：`check-ast.sh` → 274 passed；`check-warnings.sh` → 140 ok；
  `check-all.sh` → 9 hard gates green。
- 探针：ct-ast 仍完整编译 `selfhost/l0/ctc.c`。
