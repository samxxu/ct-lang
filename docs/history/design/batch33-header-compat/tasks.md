# 任务：真实头文件兼容（第三十三批）

依据：`docs/design/batch33-header-compat/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 `attr_pool` 搬家

- `frontend/parse/ParseSupport.h.ct`：`SupportOps::attr_pool`（实现从 Parser 原样搬入，
  补 `T_ID` / `T_NUM` 常量）。
- `frontend/parse/Parser.h.ct`：从 `ParseOps` 删除声明与实现；九处调用改为
  `self->sup->attr_pool`。

## [x] T2 `_Atomic(type)`

- `frontend/parse/Expr.h.ct`：`parse_type` 的 `_Alignas` / `_Atomic` 分支（括号可选）；
  `next_is_type_name` 识别 `_Atomic(…)`。
- `frontend/parse/Stmt.h.ct`：`is_decl_start` 接受 `_Atomic`。

## [x] T3 `_Alignas` 在存储类之前

- `frontend/parse/Expr.h.ct`：`decl_prefix` 字段；`parse_type` 入口前置并清空。
- `frontend/parse/Parser.h.ct` / `frontend/parse/Stmt.h.ct`：声明开头捕获 `_Alignas(…)`
  到 `decl_prefix`，递归走普通声明分支；重复报 `duplicate _Alignas on one declaration`。

## [x] T4 声明符前的属性

- `frontend/parse/Parser.h.ct`：`pending_attr`；`top_decl` 捕获并递归；`parse_func`
  与尾部属性合并；未消费则报 `an attribute must prefix a declaration`。
- `frontend/parse/Stmt.h.ct`：`decl_attr`；`parse_stmt` 捕获并递归；
  `parse_decl_node` 写到每个 `N_DECL.attr`，并接受尾部属性。

## [x] T5 fixture、负例、关卡与文档

- `test/ast/56_header_compat/{prog.ct,prog.expected.out}`。
- `test/ast/errors/{atomic_unterminated,attribute_misplaced,attribute_duplicate_local,alignas_duplicate}.ct`。
- `check-ast.sh`：头注释 + batch 33 的精确消息断言。
- `docs/language-spec.md`：新增 §4.38（中英对称）。
- `docs/roadmap.md`：Post-Phase-12 补记第三十三批（中英）；记录容量策略 A 与回访条件。
- README 中英能力说明同步。
- 提交拆分：`feat(parse): accept the header-order C spellings`、
  `docs(spec): record the header-order forms`。不 bump 版本。
