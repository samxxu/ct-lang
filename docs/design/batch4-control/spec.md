# 第四批特性：控制流补全（`switch` / `do-while`）（2026-10-29）

> 锚点：`bc35913`（函数指针批收口），工作树干净。
> 本规格只做 `switch` 与 `do-while`；`goto` / 标签、`enum` / `union` / `offsetof` 留给后续批次。

## 1. 实测现状

ct-ast 实编实测（`/tmp/b3/ct-ast`，逐构造微探针）：

| 用法 | 现状 |
| --- | --- |
| `switch (x) { case 1: … default: … }` | ❌ `unexpected token`（列号落在 `{`） |
| `do { … } while (c);` | ❌ `use of an undeclared variable`（列号落在 `{`） |
| `if` / `else` / `while` / `for` / `break` / `continue` | ✅ |
| `int a, b;`、`for (int i …)`、三目、自引用 struct | ✅ |
| `goto out;` / `out:` 标签 | ❌ 标签被当变量（本批不做） |
| `enum` / `union` / `offsetof` | ❌（另一批） |

两条报错的**机制**都不是「不认识关键字」——`switch` / `do` 都是普通标识符，寄存器里没有保留字表：

- `switch (x)` 被 [parse_stmt](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Stmt.h.ct#L221-L425) 的兜底路径当成**函数调用**解析成功，随后 `{` 撞上 `expect(";")` → `unexpected token`；
- `do` 走同一兜底路径进入表达式解析，[parse_primary](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/frontend/parse/Expr.h.ct#L1035-L1040) 按「未声明变量」报错，且诊断在 `lex_next()` 之后，列号指到下一个 token。

发射侧按节点 `kind` 分支（语句从 [N_BLOCK](file:///Users/samxx/vscspace/ct/selfhost/ct-ast/backend/emit/Emit.h.ct#L915-L921) 起，`N_BREAK` / `N_CONT` 在 959/964，`N_IF` / `N_WHILE` / `N_FOR` 在 1048–1068），所以新语句必须同时进解析与发射两侧。

## 2. 范围

| 编号 | 内容 | 归属 |
| --- | --- | --- |
| F1 | `switch (expr) { … }` 与 `case <常量>:` / `default:` | `frontend/parse/Stmt.h.ct`、`backend/emit/Emit.h.ct` |
| F2 | `do { … } while (cond);` | 同上 |
| F3 | 五条明确诊断（见 §4 表） | `frontend/parse/Stmt.h.ct` |
| 配套 | 正例 / 负例 fixture、`check-ast.sh` 断言、`docs/language-spec.md` 语句章节中英对称 | `test/ast/**`、`selfhost/check-ast.sh`、`docs/` |

### 非目标

- 不做 `goto` / 标签（另批）。
- 不做 `enum` / `union` / `offsetof`。
- 不做 `case 1 ... 5:` 范围语法、不做 `case` 重复值检测（后者交给 C 编译器，报 `duplicate case value`）。
- `case` / `default` 只允许出现在 `switch` 体的最外层；嵌套块里的 `case` 报错（见 F3）。
- `own` 不允许出现在 `switch` 体内（见 D-7）。
- 不动 L0 / L1 / L2，不 bump `CTC_VERSION`，不改 `test/cases/**`、`examples/**` 的 golden。

## 3. 关键设计决策

### D-1 节点编号 42 / 43 / 44

现有最大语句节点号是 `N_DELETE 41`。新增 `N_SWITCH 42`、`N_CASE 43`、`N_DOWHILE 44`，宏同时写进 `Stmt.h.ct` 与 `Emit.h.ct`（节点编号是两单元之间的复制契约，跨单元无共享宏）。

### D-2 `switch` 自建体内循环，不复用 `parse_block`

`parse_block` 只认语句，遇到 `case` 会落到兜底表达式路径。`switch` 体单独解析：

```
expect "(" ; cond = parse_expr ; expect ")" ; expect "{" ; push_scope
循环直到 "}"：
  - is_decl_start() 或 `own`  → 按声明节点收进体内（C 允许 switch 块内声明）
  - `case` / `default`        → parse_label()，其子语句递归进体内
  - 其它                       → parse_stmt()
expect "}" ; pop_scope
体内子节点串成链表，整体包成 N_BLOCK（沿用现有缩进与发射）
```

`N_SWITCH`：`a = 条件表达式`，`b = 体内 N_BLOCK`。

### D-3 标签与语句合并为 `N_CASE`

C 要求标签后面必须跟**语句**，因此一条标签与它修饰的那条语句合成一个节点，而不是独立标签节点：

```
N_CASE: text = 标签文本（数字 / 字符字面量 / 常量名），aux = 0 为 case、1 为 default，
        a = 被修饰的语句
```

连续标签（`case 1: case 2: stmt`）天然支持：`parse_label` 发现下一个 token 仍是 `case` / `default` 时递归一层，外层 `N_CASE` 的子节点即内层。

### D-4 标签之后必须是语句

`case 1: int x;` 是非法 C（标签不能修饰声明）。`parse_label` 在取完标签后若发现下一个是 `is_decl_start()` 或 `own`，报

`a declaration cannot follow a case label; wrap it in a block`

紧挨 `}` 时报 `a case label needs a statement`。

### D-5 `case` 的取值只接受三种形态

C 要求整型常量表达式，而 ct-ast 没有常量折叠。因此标签值只接受：

- 数字字面量（可带一个前置 `-`）；
- 字符 / 字符串字面量（词法器把 `'x'` 与 `"x"` 都归为 `T_STR`，原样发射）；
- 单个标识符（`#define` 常量或已声明全局；已知全局按 mangling 取 C 拼写，否则原样发射）。

其余（`case a + 1:`、`case f():` 等）报 `a case label must be an integer constant`。

### D-6 `do-while` 独立节点 `N_DOWHILE`

`a = 条件`，`b = 体`。体一律由 `parse_branch` 产出，而 `parse_branch` 对单语句也会包成 `N_BLOCK`，所以发射只有一条路径：

```
do {
    …
} while (cond);
```

发射时 `N_BLOCK` 的收尾 `}` 与 `while` 之间不换行（直接 `} while (`），避免 `}\nwhile` 的丑形态。`while (...)` 之后必须有 `;`，缺失报 `a do statement must be followed by while (...)`。

### D-7 `own` 在 `switch` 体内先拒绝

`switch` 可能跳过 case、也可能贯穿，现有按顺序块假设的所有权分析不再成立。本批在 `struct Stmt` 增加 `int switch_depth`，进入 `switch` 体自增、退出自减；`own` 分支在深度非零时报

`own is not supported inside a switch`

路径敏感的 switch 所有权分析留给后续批次。

### D-8 `case` / `default` 出现在别处要有名字

`parse_stmt` 增加 `case` / `default` 守卫：不在 `switch` 体内时（包括 `switch` 体里的嵌套块）报

`a case label is only allowed inside a switch`

否则这两个词会继续以「未声明变量」的形式报错，掩盖真实原因。

### D-9 发射缩进

`N_CASE` 的标签行与 `switch` 同级缩进（`emit_indent(ind)`），其子语句用 `ind + 1`；`N_SWITCH` 复用 `N_BLOCK`，因此体内声明、`break`、嵌套 `if` 的缩进与既有块一致。

## 4. 验收标准

| 项 | 验收 |
| --- | --- |
| F1 | `switch` 含多个 `case`、`default`、贯穿、`case` 内 `break`、嵌套 `if`、`case` 内块、`case` 内 trait 方法调用与函数指针字段直调，编译运行正确 |
| F2 | `do { … } while (cond);` 与单语句体（无花括号）均编译运行正确；循环体可含 `for` + `continue` |
| 标签值 | 数字、负数、`'a'`、`#define` 宏名四种标签值均编译通过 |
| 诊断 | 五条消息逐条按 §3 D-4/D-5/D-6/D-7/D-8 的原文报出，且带 `file:line:col:` |
| 回归 | `check-ast.sh` 全绿（自举 fixpoint 与语料等价段不变）；`check-warnings.sh` 零告警 |
| 文档 | `docs/language-spec.md` 语句章节中英对称，新增 `switch` / `do-while` 与限制段 |
| golden | `git status` 不出现 `test/cases/**`、`examples/**` 的 `.expected.*` 变化 |

## 5. 验证命令

```bash
gcc -Wall -Wextra -std=c99 selfhost/l0/ctc.c -o /tmp/ctc
bash selfhost/check-all.sh          # 期望 check-all: OK (9 hard gates green)
bash selfhost/check-warnings.sh     # 期望 exit 0
git status --short
```

手工探针（每片改完 ct-ast 后）：按 `docs/design/batch3-fnptr/spec.md` §5 的四层链配方重建 `/tmp/b3/ct-ast`，再用 /tmp 下的小文件逐构造验证。

## 6. 出口条件

1. 九关全绿；`check-ast.sh` 通过计数只增不减。
2. 新增 fixture 的生成物零告警。
3. 文档没有「已实现却写成不支持」或反向的段落。
4. 提交按规约拆分：`feat(codegen): add switch and do-while to ct-ast`（代码 + fixture + 关卡）
   与 `docs(spec): record the control-flow statements`（spec/文档）分开。
