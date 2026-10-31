# 任务：C 兼容性收尾（第三十二批）

依据：`docs/design/batch32-c-compat/spec.md`
顺序即依赖顺序；每步完成后保持工作树可编译。

## [x] T1 整数字面量后缀

- `frontend/lex/Lexer.h.ct`：`toksuffix` 字段；整数分支收集 `[uUlL]`；每个 token 起始清空。
- `frontend/parse/Expr.h.ct`：`parse_primary` 校验（U ≤ 1、L ≤ 2、长度 ≤ 3）并把规范后缀
  写进 `N_NUM.text`。
- `backend/emit/Emit.h.ct`：`N_NUM` 打印 `%ld%s`。

## [x] T2 `add_func` 的 `ret` 先声明者胜

- `frontend/parse/ParseSupport.h.ct`：只在新建行时写 `ret`。

## [x] T3 `static_assert` 别名

- `frontend/parse/Stmt.h.ct`：语句形式接受两种拼写。
- `frontend/parse/Parser.h.ct`：文件作用域路由接受两种拼写。
- 发射保持 `_Static_assert` 不变。

## [x] T4 `__restrict` / `__restrict__`

- `frontend/parse/Expr.h.ct`：`is_type_word` 增加两个 GNU 拼写。

## [x] T5 fixture、负例、关卡与文档

- `test/ast/55_c_compat/{prog.ct,prog.expected.out}`。
- `test/ast/errors/{integer_suffix_lll,integer_suffix_uu}.ct`。
- `check-ast.sh`：头注释 + batch 32 的精确消息断言。
- `docs/language-spec.md`：新增 §4.37（中英对称），顶部覆盖说明加入整数字面量后缀。
- `docs/roadmap.md`：Post-Phase-12 补记第三十二批（中英）。
- README 中英能力说明同步。
- 提交拆分：`feat(codegen): finish the C compatibility list`、
  `docs(spec): record integer suffixes and the C-form close-out`。不 bump 版本。
