# 任务：复合字面量（第十一批）

依据：`docs/design/batch11-compound-literal/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 捕获逻辑上移（`ParseSupport.h.ct` / `Stmt.h.ct` / `Parser.h.ct`）

- `SupportOps` / `ParseSupport` 新增 `init_raw(char *out, int cap)`，函数体取自
  `Stmt::parse_init_raw`（逐字符扫描、字符串字面量不拆、结束时 `lex_next`）。
- `StmtOps` 的 `parse_init_raw` 删除，Stmt 内的调用点改 `self->sup->init_raw(...)`。
- `Parser` 的 `self->st->parse_init_raw` 改为 `self->sup->init_raw`。

## [x] T2 解析（`Expr.h.ct`）

- `N_COMPOUND 51`；结构体加 `int postfix_seed;`，`ct_expr_bind` 里置 -1。
- `parse_unary` 的 cast 分支：`)` 之后若当前是 `{`，捕获 `init_raw` 到 `N_RAW` 子节点、
  检查类型不以 `*` 结尾（否则 `a compound literal needs an object type`）、建 `N_COMPOUND`，
  置 `postfix_seed` 后 `return self->parse_postfix();`。
- `parse_postfix`：入口先取 `postfix_seed`，`>= 0` 时跳过 `parse_primary`。

## [x] T3 推断与发射（`TypeCheck.h.ct` / `Emit.h.ct`）

- `expr_type`：`N_COMPOUND` 返回 `text`。
- `Emit`：`N_COMPOUND 51`；`emit_raw_init(int raw, const char *type, int assign)`
  （`assign` 为真才发 ` = `），三个声明调用点传 1；`emit_expr` 新增
  `N_COMPOUND` 分支——`(` 类型 `)` 后复用 `emit_raw_init(…, 0)`。

## [x] T4 fixture、关卡、文档与提交

- `test/ast/36_compound_literal`：见 spec §4。
- 负例：`compound_pointer`；`check-ast.sh` 加一组精确消息断言。
- `docs/language-spec.md`：新增 §4.20（中英对称）。
- `bash selfhost/check-all.sh` → 九关全绿；`bash selfhost/check-warnings.sh` 零告警。
- 提交拆分：`feat(codegen): add compound literals`、
  `docs(spec): record the compound-literal form`。不 bump 版本、不动 golden。
