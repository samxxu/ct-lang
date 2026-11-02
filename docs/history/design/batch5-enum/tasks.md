# 任务：`enum`、常量表达式与 `offsetof`（第五批）

依据：`docs/design/batch5-enum/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 常量表（`frontend/sym/Symbols.h.ct`）

- `struct Var` 末尾新增 `int is_const;`，`declare_var` / `declare_global` 置 0。
- 新增 `declare_const(name, cname, ns, imported)`：`declare_global(name, "int", cname, ns, imported)` 后把 `is_const` 置 1；返回索引。
- 新增 `is_const_name(name)`：`find_var` 命中且 `is_const` 为 1 时返回 1。
- `SymbolOps` 补两个方法声明（注意 32 方法上限，先数再改）。

## [x] T2 枚举声明解析（`frontend/parse/Parser.h.ct`）

- 宏 `N_ENUM 45`、`N_ENUMVAL 46`。
- 新增 `parse_enum_def(int is_pub)`：
  - `enum` 之后读标签（缺标签 `expected an enum name`），`ns_decl_name` 求 qname，
    已存在同 kind 5 的类型时报 `duplicate enum '<name>'`，随后 `add_type(qname, 5)`；
  - `expect("{")`，循环读成员：`ID [= <常量表达式>]` + `,`（允许尾逗号）；
    成员节点 `N_ENUMVAL`（`text` = C 名 `ns+name`、`text2` = 源名、`a` = 初值节点或 -1），
    初值用 `ex->parse_expr()` 解析，`const_ok` 失败报 `an enum value must be an integer constant`；
    每个成员 `declare_const(source, cname, ns_underscore, 0)`；
  - `expect("}")`，返回 `N_ENUM` 节点（布局见 spec D-5）。
- `top_decl`：新增 `enum` 分支（在 `struct` 分支之前），`parse_enum_def(is_pub)` 成功后 `accept(";")`。
- `parse_typedef`：`struct` 分支之前新增 `enum` 分支——`parse_enum_def(0)`、读别名、`expect(";")`，
  置 `aux = 1`、`text2` = 别名 qname、`text3` = 标签 qname、`d = is_pub`、`add_type(alias, 2)`。
- 验收：`enum Color { RED, GREEN = 5, BLUE };` 与 `typedef enum Mode { Fast, Slow } Mode;` 能解析到 `enum` 节点。

## [x] T3 类型名（`frontend/parse/Expr.h.ct`）

- `parse_type` 的类型词分支：`enum` 与 `struct` 对称——`lex_next`、读标签、`resolve_type`、
  `type_append`、`add_type(sname, 5)`。
- 裸标签分支：`type_kind == 5` 时先补 `"enum"` 再补名字（与 kind 1 / 3 并列）。
- 验收：`enum Color c;`、`Color c;`、`enum Color *p;` 都解析成 `enum <qname>`。

## [x] T4 常量表达式判据（`frontend/parse/Expr.h.ct`）

- 新增 `ExprOps const_ok(int n)`，判据表见 spec D-6；`N_STR` 用字符串池首字符区分 `'` 与 `"`。
- `parse_array_dims` 的 `T_ID` 分支：先 `var_cname`，失败再回退原样（spec D-9）。
- 验收：`const_ok` 对 `1 + 2`、`(1 << 2)`、`'a'`、`RED`、`sizeof(int)` 为真；
  对 `f()`、`key + 1`、`a[0]`、`(int)1` 为假。

## [x] T5 `case` 标签改成表达式（`frontend/parse/Stmt.h.ct`）

- `parse_case_value` 改为返回表达式节点：`parse_expr()` → `const_ok`（整棵树是单个
  `N_VAR` / `N_RAW` 时放行）→ 失败报 `a case label must be an integer constant`。
- `parse_label`：把返回值存进 `N_CASE.b`，不再写 `text`。
- 验收：`case (1 << 2):`、`case 1 + 2:`、`case RED:`、`case 'a':`、`case -1:` 解析通过。

## [x] T6 `offsetof`（`frontend/parse/Expr.h.ct`、`backend/emit/Emitter.h.ct`、`frontend/type/TypeCheck.h.ct`）

- `N_OFFSETOF 47`（Expr / Emit 各写一份）。
- `parse_primary` 的 `T_ID` 分支之前拦截 `offsetof` + `(`：`parse_type`、`expect(",")`、
  读字段标识符、`expect(")")`，按 spec D-8 校验结构体与字段，生成 `N_OFFSETOF`（`text` = 类型、`text2` = 字段）。
- `Emitter.h.ct` 的 `emit_expr` 新增分支：`offsetof(<text>, <text2>)`。
- `TypeCheck.h.ct` 的 `expr_type` 把 `N_OFFSETOF` 当作 `size_t`（与 `N_SIZEOF` 同一处理）。

## [x] T7 发射（`backend/emit/Emitter.h.ct`）

- 宏 `N_ENUM 45`、`N_ENUMVAL 46`、`N_OFFSETOF 47`。
- `emit_type_decl` 新增 `N_ENUM` 分支（spec D-10 的排版）；成员一行的 ` = ` 走 `emit_expr(a)`。
- `N_CASE` 分支：`aux == 0` 时打印 `case ` + `emit_expr(b)` + `:`。
- `.c` 私有类型循环与头文件 `pub` 循环的条件加上 `N_ENUM`。
- 验收：`test/ast/30_enum` 的生成物零告警并通过 cc（含 `--line` 模式）。

## [x] T8 跨单元导出（`frontend/module/Module.h.ct`）

- 宏 `N_ENUM 45`、`N_ENUMVAL 46`。
- 裸名类型导出循环加入 `N_ENUM`。
- 新增循环：依赖单元里 `d == 1` 的 `N_ENUM`，其成员逐个 `declare_const(text2, C 名, ns, 1)`
  （C 名 = `units[dn].nsprefix + text2`，`ns` = 去掉尾下划线的前缀）。
- 验收：`test/ast/30_enum` 里制造一个 `pub enum` + 独立消费单元（若 fixture 体系只支持单文件，
  则在 `test/modules/` 下加一对最小单元并挂断言）。

## [x] T9 文档、门禁与提交

- `test/ast/30_enum/prog.ct` + `.expected.out`：枚举声明（显式值 / 自增 / 尾逗号）、
  `enum Color c` 与裸名 `Color c`、`switch` 里 `case (1 << 2):` / `case RED:` / `case 'a':` /
  `case -1:`、`offsetof(struct S, b)`（`#include <stddef.h>`）。
- 负例：新增 `enum_duplicate.ct`、`enum_bad_value.ct`、`offsetof_bad_field.ct`；
  改写 `case_nonconstant.ct`（`case (1 + 2):` 已合法 → 换成 `case key + 1:`，注释同步）。
- `selfhost/check-ast.sh`：补六条精确消息断言（spec D-11），并给 `30_enum` 挂生成 + 运行断言。
- `docs/language-spec.md`：类型 / 表达式章节新增枚举、常量表达式、`offsetof` 段，中英对称；
  顶部「其它 C 透传」表去掉 `enum` / `offsetof`，只留 `union` / `goto`。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add enums, constant expressions and offsetof`、
  `docs(spec): record the enum forms`。不 bump 版本、不动 golden。
