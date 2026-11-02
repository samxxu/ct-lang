# 第二十批特性：前缀 `++` / `--`（2026-10-30）

> 锚点：`859df6c`（第十九批收口），工作树干净。
> ctc.c 探针的第三个缺口：`while (n && isspace((unsigned char)s[n - 1])) s[--n] = 0;`

## 1. 实测现状

- 词法器把 `++` / `--` 收成单记号，但解析器只在**后缀**位置处理它们
  （`parse_postfix` 建 `N_POST`），`parse_unary` 没有前缀分支，于是 `s[--n]`
  在表达式位置报 `expected an expression`。

## 2. 决策

- **D-1 节点 57 `N_PRE`**：`a` = 操作数、`aux` = `P_INC` / `P_DEC`（与 `N_POST` 同一套标记）。
- **D-2 结合力**：前缀形式与其它一元运算符同级——在 `parse_unary` 里、`-` `!` `~` `&` `*`
  之前处理，操作数是再一个 `parse_unary`。因此 `s[--n]`、`*--p`、`--n;` 都按 C 的读法成立。
- **D-3 语义**：值是**更新后**的值（与后缀相反），由 C 保证；ct-ast 只按原顺序发射
  `++`/`--` 与操作数。
- **D-4 不需要类型推断**：前缀表达式只出现在取值位置（或作为语句），与 `N_POST` 的处境相同；
  `TypeCheck` 不为它加分支。
- **D-5 范围外**：无（前缀与后缀同一个词法基础，没有额外限制）。

## 3. 影响面

- 改：`frontend/parse/Expr.h.ct`（`N_PRE`、`parse_unary` 的前缀分支）、
  `backend/emit/Emitter.h.ct`（`N_PRE` 一支）。
- **impl 方法预算**：不新增方法（255/256）。
- 不动：`TypeCheck` / `Symbols` / `ctc.c` / `l1` / `l2`、`CTC_VERSION`、golden。

## 4. 验证

- 新增 `test/ast/45_pre_incr`：`j = ++i` 与 `k = i++` 的取值差异、`s[--n]` 的
  `while` 收缩（ctc.c 的同形写法）、`a[--i] = 7`、指针上的 `*(--p)`。
- 本批不新增诊断。
- 探针复跑：ctc.c 的报错点推进到 446 行（一个超长初始化器触发
  `initializer is too long`，属 `MAX_TEXT` 容量问题），留给后续。
- `bash selfhost/check-ast.sh` / `check-warnings.sh` / `check-all.sh` 全绿。
