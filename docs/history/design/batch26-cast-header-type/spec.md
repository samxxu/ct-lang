# 第二十六批特性：转换与 `sizeof` 里的头文件类型名（2026-10-31）

> 锚点：`f739e77`（第二十五批收口），工作树干净。
> 来源：§4.33 明确留下的那条限制，实测确认是与 L2 的行为差：
> `(time_t)raw`、`sizeof(time_t)` 在 L2 下通过，在 ct-ast 下报
> `use of an undeclared variable`。

## 1. 实测现状

- 第二十五批让声明位置接受头文件里的 typedef；转换与 `sizeof` 的类型判定
  （`next_is_type_name`）仍只认内置类型词与已登记类型。
- 判据的难点是 `(NAME) + x`：`NAME` 既是宏常量的常见写法，也可能是没见过的类型名。

## 2. 决策

- **D-1 判据放在 `next_is_type_name`**：转换与 `sizeof` 共用它，一处改动两条路径同时生效。
- **D-2 未知名成为类型要同时满足三条**：
  1. 不是已声明的变量 / 函数（`(a) * 2`、`(g)(7)` 仍是表达式与调用）；
  2. 不是全大写宏常量（沿用 `parse_primary` 的约定，`(MAX) + 1` 仍是表达式）；
  3. 括号里这个名字后面必须紧跟 `)`，可隔着若干 `*`（`(time_t)`、`(time_t *)`）。
- **D-3 第三条是实测逼出来的**：第一版只查 1、2，自编立刻失败——`(snprintf(out, …) >= cap)`
  这种「括号包住的调用」被当成了转换。`(f(x))` 与 `(type)` 的区别就在 `)` 之前还有没有东西。
- **D-4 顺带修好状态还原**：`next_is_type_name` 现在可能多走几个记号，保存/恢复补上
  `tokstart` 与 `lstart`，避免把诊断列号留在前瞻位置上。
- **D-5 不含**：函数指针类型的转换（`(time_t (*)(void))`）不在支持范围。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（`next_is_type_name` 的未知名字分支与状态还原）。
- **impl 方法预算**：不新增方法（255/256），不新增节点编号。
- 不动：`Stmt` / `Emit` / `TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/51_cast_header_type`：`(time_t)raw`、`(time_t *)&t`、`(clock_t)t`、
  `sizeof(time_t)`、`sizeof(time_t *)`，并用 `sizeof(x) == sizeof(long)` 之类的比较避免
  平台相关输出。
- 回归探针：`(MAX) + 1`、`(a) * 2`、`(g)(7)`、`sizeof(buf)`、`sizeof(*p)` 全部保持原读法。
- 关卡：`check-ast.sh` → 275 passed；`check-warnings.sh` → 141 ok；
  `check-all.sh` → 9 hard gates green（含自编不动点）。
- 探针：ct-ast 仍完整编译 `selfhost/l0/ctc.c`。
