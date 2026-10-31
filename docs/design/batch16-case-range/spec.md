# 第十六批特性：`case` 范围标签（2026-10-30）

> 锚点：`2c8dd54`（第十五批收口），工作树干净。
> 本规格只做 `case <low> ... <high>:`（GNU / C23 的范围标签）。

## 1. 实测现状

- `case 1 ... 5:` 报 `unexpected token`：`parse_case_value` 只读一个表达式，
  随即 `expect(":")` 撞上 `...`。
- 第十批之后 `...` 已经是一个独立记号（变参用的那个），所以这里不需要再动词法器。
- `N_CASE` 的三个子槽目前只用了两个：`b` = 取值、`a` = guarded 语句链，
  `c` 空闲；`aux` 仍表示 `default`。

## 2. 决策

- **D-1 复用 `N_CASE`**：`c` 存范围的上界（`-1` 表示单值标签）。
  `Stmt` 加 `case_hi` 暂存区，`parse_case_value` 填它，`parse_label` 搬到节点上——
  与 `parse_init_raw` 那类「解析期临时量」同一手法。
- **D-2 语法**：`case <expr> ... <expr> :`。两端都按既有常量规则判定
  （`const_ok`，或整棵树是单个名字时放行），违反时都报
  `a case label must be an integer constant`。
- **D-3 发射**：`case <low> ... <high>:`，与单值标签同形，仅多三段字符；
  重复值、区间重叠仍原样发射，由 C 编译器判断。
- **D-4 与 `default` 的关系**：`default:` 不走这条路径（`aux` 分支），
  `case ... 5:`（缺下界）在 `parse_expr` 处报 `expected an expression`。
- **D-5 标准**：范围是 GNU 扩展、C23 正式化。实测 `cc -Wall -Wextra -std=c99`
  在 clang / gcc 下都不告警，因此关卡可以直接覆盖它；文档写明这层依赖。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（`case_hi` 字段、`parse_case_value` 的 `...` 分支、
  `parse_label` 的一行搬运）、`backend/emit/Emitter.h.ct`（`N_CASE` 的发射）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：词法器、`Expr`、`TypeCheck`、符号表、`ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/41_case_range`：数字区间、字符区间（`'a' ... 'z'`）、
  范围与单值标签混排、未命中落到 `default`。
- 新增负例：`case_range_nonconstant`（`case 1 ... (k + 2):`）。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
