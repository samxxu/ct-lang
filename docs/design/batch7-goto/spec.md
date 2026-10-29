# 第七批特性：`goto` 与标签（2026-10-29）

> 锚点：`f0b4107`（第六批收口），工作树干净。
> 本规格只做 `goto` / `标签:`：它是语句层最后一块仍被 ct-ast 拒绝的构造
> （L2 原样透传，ct-ast 落进表达式路径后报 `unexpected token`）。

## 1. 实测现状

- `goto name;` 在 `parse_stmt` 里没有分支，`goto` 被当作普通标识符走表达式语句，
  `goto` 未声明、`name` 后面紧跟 `;` → 报错。
- `name:` 同样走表达式路径，`:` 不是表达式的合法后继，报 `unexpected token`。
- 语句层已有 `case` 标签的「链」模型（`N_CASE` 拥有从自身到下一个标签的语句）、
  块作用域与 AutoDrop 注入，它们都不枚举语句种类，故新增节点不需要别的层配合。
- 词法器只有 `next()`，没有 `peek`；`::` 是一个单独的 `T_PUNCT` 记号。

## 2. 决策

- **D-1 节点 49 `N_LABEL`、50 `N_GOTO`**。`N_LABEL`：`text2` = 标签名、`a` = 语句链；
  `N_GOTO`：`text2` = 目标名、行号由 `new_node` 记在 `goto` 所在行。
- **D-2 标签前瞻**。`label_ahead()` 保存 lexer 的九个状态字段（`pos` / `bol` / `tok` /
  `toktext` / `toknum` / `line` / `tokline` / `tokstart` / `lstart`），读下一个记号后判定是否为
  `:`，再原样恢复。`::`（命名空间限定）不是单个 `:` 记号，所以 `A::f();` 仍按表达式语句。
  `case` / `default` 的检查排在前瞻之前，避免把 `default:` 当成 goto 标签。
- **D-3 标签拥有语句链**，规则与 `case` 相同：从标签到下一个标签（goto 标签 / `case` /
  `default`）或 `}` 之间的语句都属于它，发射时整条链缩进一级。连续的标签（`again: done:`）
  允许：第一条标签拥有第二条，语义不变。链为空报
  `a label needs a statement`：C99 不允许标签直接碰 `}`（空语句 `;` 也不在支持的子集内，
  把标签写在一条真实语句前即可，例如 `done: return r;`）。
- **D-4 标签后不能直接跟声明**：`a declaration cannot follow a label; wrap it in a block`，
  与 case 同因（C 的标签不构成作用域）。
- **D-5 函数作用域校验**。标签表与 goto 表按函数重置（`func_begin` / `func_end`，
  由 Parser 在函数体与方法体前后各调用一次）。同一函数内重复标签在第二次出现时报
  `duplicate label '<name>'`（位置指向标签名）；函数解析结束时仍有 goto 找不到同函数内的标签，
  报 `label '<name>' is not defined`（位置取 goto 所在行）。跨函数同名标签互不影响。
- **D-6 上限**：一个函数最多 64 个标签、64 个 goto；超出报
  `too many labels in one function` / `too many gotos in one function`。
- **D-7 发射**：`<name>:` 单独一行，其链逐条缩进一级；`goto <name>;`。标签是函数内作用域，
  名字不做命名空间 mangling。
- **D-8 允许跳入 / 跳出块与循环**（C 允许）。跳出 `own` 的声明作用域不触发释放（§4.9 的既有约定）。
- **D-9 已知边界**：`out:` 直接接 `case 2:` 不支持——标签链在 `case` / `default` 处停止，
  链空即按 D-3 报 `a label needs a statement`。

## 3. 影响面

- 改：`frontend/parse/Stmt.h.ct`（节点宏、`label_ahead` / `parse_named_label` / `parse_goto` /
  `func_begin` / `func_end` / `label_find`、标签表与 goto 表字段、`parse_label` 的链终止条件）、
  `frontend/parse/Parser.h.ct`（函数体与方法体前后各一次 `func_begin` / `func_end`）、
  `backend/emit/Emit.h.ct`（两个节点宏与两条发射分支）。
- 不动：`ctc.c` / `l1` / `l2`（L2 仍原样透传）、`CTC_VERSION`、`test/cases/**` 与 `examples/**`
  的 golden。

## 4. 验证

- 新增 `test/ast/32_goto`：`goto` 跳出双层循环、向后 `goto` 成环、`goto` 跳入块、
  标签在嵌套块里、与 `switch` 混用（`case` 里 `goto` 出去）、两个函数用同名标签、
  表达式语句以标识符开头（前瞻不误判）。
- 新增四个负例：`goto_undefined`、`label_duplicate`、`label_decl`、`label_no_statement`，
  在 `check-ast.sh` 里逐条 `grep` 精确消息。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
