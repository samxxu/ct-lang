# 任务：控制流补全（第四批）

依据：`docs/design/batch4-control/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [ ] T1 节点编号与 `parse_stmt` 分发

- `frontend/parse/Stmt.h.ct` / `backend/emit/Emit.h.ct`：新增 `N_SWITCH 42`、`N_CASE 43`、
  `N_DOWHILE 44`（两单元各写一份）。
- `Stmt.h.ct` `parse_stmt`：在 `for` 之后增加 `switch` / `do` 分支骨架；
  `case` / `default` 守卫（不在 switch 体内时报
  `a case label is only allowed inside a switch`）。
- `Stmt.h.ct` `struct Stmt` 增加 `int switch_depth`。

## [ ] T2 `switch` 体解析

- 新增 `parse_switch_body()`：体内循环（声明 / 标签 / 语句三类）、`push_scope` /
  `pop_scope`、串链后包成 `N_BLOCK`；`N_SWITCH` 的 `a = 条件`、`b = 体`。
- 验收：`switch (x) { case 1: return 1; default: return 0; }` 解析通过（发射见 T5）。

## [ ] T3 `case` 取值与标签诊断

- `parse_label()`：标签值接受数字（可带前置 `-`）、`T_STR`、单个标识符（已知全局按
  `find_global` 的 C 拼写，否则原样）；其余报 `a case label must be an integer constant`。
- 标签后紧跟声明 / `own` 报 `a declaration cannot follow a case label; wrap it in a block`；
  紧挨 `}` 报 `a case label needs a statement`；连续标签递归支持。

## [ ] T4 `do-while` 解析

- `do` 分支：`parse_branch()` 取体，`expect("while")`、`(`、条件、`)`、`;`；
  缺 `while` 报 `a do statement must be followed by while (...)`。
- 验收：`do { i = i + 1; } while (i < 3);` 与 `do i = i + 1; while (i < 3);` 均解析通过。

## [ ] T5 发射三个节点

- `Emit.h.ct`：
  - `N_SWITCH`：`switch (` cond `) ` + `emit_node(b, ind)`（体内是 `N_BLOCK`）；
  - `N_CASE`：`emit_indent(ind)` + `case <text>:` 或 `default:`，子语句 `ind + 1`；
  - `N_DOWHILE`：`do {` + 子语句 + `} while (` cond `);`（`}` 与 `while` 不换行）。
- 验收：`test/ast/28_switch`、`29_do_while` 的生成物零告警并通过 cc。

## [ ] T6 `own` 拒绝

- `parse_stmt` 的 `own` 分支：`switch_depth > 0` 报 `own is not supported inside a switch`；
  进入 / 离开 `switch` 体时增减深度（异常路径也要还原）。

## [ ] T7 fixture 与关卡

- 新增 `test/ast/28_switch/prog.ct` + `.expected.out`：多 `case`、`default`、贯穿、
  `case` 内 `break`、嵌套 `if`、`case` 内块、字符 / 负数 / 宏名标签、case 内 trait 方法调用。
- 新增 `test/ast/29_do_while/prog.ct` + `.expected.out`：累加循环、单语句体、体内 `for` + `continue`。
- 新增负例 `test/ast/errors/case_outside_switch.ct`、`case_after_decl.ct`、
  `case_nonconstant.ct`、`do_missing_while.ct`、`own_in_switch.ct`。
- `selfhost/check-ast.sh` 补五条精确消息断言。

## [ ] T8 文档、门禁与提交

- `docs/language-spec.md` 语句章节：`switch` / `case` / `default` / `do-while` 与限制段，
  中英对称，并补进顶部「其它 C 透传」表的行文（`switch` / `do-while` 不再是缺口）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add switch and do-while to ct-ast`、
  `docs(spec): record the control-flow statements`。不 bump 版本、不动 golden。
