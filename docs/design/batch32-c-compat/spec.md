# 第三十二批：C 兼容性收尾（2026-10-31）

> 锚点：`5e336c3`（第三十一批收口），工作树干净。
> 实测缺口（ct-ast）：
> - `1U` / `1L` / `1LL` / `1UL` / `1ULL` / `0xFFU` 一律 `unexpected token`；
> - `_Noreturn void f(void);` 后接 `void f(void) {}`，生成物丢掉 `_Noreturn`；
> - C23 拼写 `static_assert(...)` 报 `expected a name`；
> - `int *__restrict p` 报错（`restrict` 可用，GNU 拼写不可用）。
> L0 / L1 / L2 不受影响（词法与语法各自独立）。

## 1. 现状

- 词法器整数分支（`Lexer.h.ct`）只写 `toknum`，不写 `toktext`：整数 token 的
  `toktext` 是脏值，后缀也不可能留在拼写里。
- `parse_primary` 把整数建成 `N_NUM`，值进 `num`；`Emit.h.ct` 用 `%ld` 打印 `num`。
  `N_NUM` 的 `text` 没有任何读者，是空槽。
- `add_func` 命中既有行时无条件覆盖 `ret`：原型先写 `_Noreturn void`，定义再写
  `void`，后者胜出，`_Noreturn` 静默丢失。
- `_Static_assert` 在 `Stmt.h.ct` 与 `Parser.h.ct` 按字面匹配；`static_assert` 是
  C23 / `<assert.h>` 的别名，同一构造的另一种拼写。
- `is_type_word` 含 `restrict`，不含 GNU 的 `__restrict` / `__restrict__`。

## 2. 决策

- **D-1 后缀由词法器收集，规范化后存进 `Lexer.toksuffix`**：整数分支结束后读取
  `[uUlL]` 连续字符（十进制 / 十六进制 / 八进制同路径），按「有 U 则先 U，再 1/2 个 L」
  规范化（`uLL` / `LLu` / `lL` 都成 `ULL` / `ULL` / `LL`），每个 token 起始清空。
  后缀不参与数值计算，`toknum` 的行为不变。
- **D-2 合法性在 `parse_primary` 判定**（不新增 impl 方法）：U 至多一个、L 至多两个、
  总长至多 3；否则报 `an integer suffix may be U, L or LL`。合法时把规范后缀写进
  `N_NUM.text`，`Emit.h.ct` 的整数分支由 `%ld` 改为 `%ld%s`。
- **D-3 `add_func` 的 `ret` 先声明者胜**：只在新建行时写 `ret`；命中既有行时保留原值。
  原型 / 定义同签名时其余字段（`cname`、`is_static`、`nparams`、形参表）行为不变。
- **D-4 `static_assert` 作为 `_Static_assert` 的别名**：`parse_stmt` 与 `top_decl` 两处
  匹配同时接受两种拼写，统一发射 `_Static_assert`（C 编译器在 C11 起识别）。
- **D-5 `__restrict` / `__restrict__` 进类型词表**：与 `restrict` 同等对待，原样写进
  类型拼写。

## 3. 边界

- 整数值仍是 `long`：后缀被保留，但超过 `LONG_MAX` 的 `ULL` 字面量（如
  `0xFFFFFFFFFFFFFFFFULL`）的值仍会按 `long` 回绕。这是既有容量边界，不在本批扩大。
- 不引入 `1z`（C23 `size_t` 后缀）、`_BitInt`、十六进制浮点；它们仍按原样报错。
- `_Noreturn` 的 *位置* 仍由第一处声明决定；定义在前、原型在后的顺序不追补。

## 4. 影响面

- 改：`frontend/lex/Lexer.h.ct`（`toksuffix`）、`frontend/parse/Expr.h.ct`
  （`parse_primary` 后缀校验与存储、`is_type_word`）、
  `frontend/parse/ParseSupport.h.ct`（`add_func` 的 `ret`）、
  `frontend/parse/Stmt.h.ct` / `frontend/parse/Parser.h.ct`（`static_assert` 别名）、
  `backend/emit/Emit.h.ct`（`N_NUM` 打印后缀）。
- 不新增 impl 方法（预算 256 已满）；不改节点编号，不 bump `CTC_VERSION`，
  不动 L0 / L1 / L2，既有 golden 零改动。

## 5. 验证

- 新增 `test/ast/55_c_compat`：`U` / `L` / `UL` / `LL` / `ULL` 的十进制、十六进制、
  八进制与大小写混写；打印值与 `sizeof`（后缀不改变值）；`_Noreturn` 原型 + 定义；
  `static_assert` 两种拼写；`int *__restrict` / `int *__restrict__`。
- 负例：`integer_suffix_lll.ct`（`1LLL`）、`integer_suffix_uu.ct`（`1UU`），
  `check-ast.sh` 精确断言。
- clang 与 GNU GCC 16 零告警构建生成物，输出一致。
- 关卡：`check-ast.sh`、`check-warnings.sh`、`check-all.sh` 如实记录数字。
