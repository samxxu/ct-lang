# SH-33 · AutoDrop 只在 `}` 注入：含 `return` 的函数静默泄漏，且生成死代码、不置空

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 语句解析 / 内存 / 发射） |
| 严重度 | **High** |
| 锚点 | commit `524ba99`（2026-10-31，`v0.15.1`） |
| 文件 | [frontend/parse/Stmt.h.ct:210-253](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L210-L253)（唯一的注入点）、[:313-346](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L313-L346)（`return` 分支，无注入）、[backend/emit/Emitter.h.ct:1798-1819](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1798-L1819)（`N_DELETE` 不置空） |
| 对照 | `selfhost/l2/core.ct` 的 `autodrop_before`（[:4936-4964](../../selfhost/l2/core.ct#L4936-L4964)）与 `emit_drops`（[:4903-4928](../../selfhost/l2/core.ct#L4903-L4928)） |
| 状态 | 已修（2026-11-01）：`return` 的两条出口在 `leak_return` 之后注入本作用域仍存活的释放（`retire_before_return`，挂在 `N_RET` 的 `b` 槽、发射在 `return` 之前），`N_DELETE` 两条路径补齐 `p = 0;`。探针 [test/ast/61_autodrop_return](../../test/ast/61_autodrop_return/)，门禁断言在 `check-ast.sh` 的 `sh33` 段 |

## 现象

`own` 的 AutoDrop 只在**块闭合 `}`** 处追加释放节点（`parse_block:214-253`），`parse_stmt` 的
`return` 分支（`:313-346`）不做任何注入。因此块内只要有 `return`，释放语句就落在 `return` **之后**：

- 该路径永远执行不到（生成 C 里是死代码）；
- 对象既不会 `drop` 也不会 `free`，**且没有任何泄漏告警**（`leak_return:293-319` 对
  `autodrop` 变量直接 `continue`，假定 `}` 处的注入会执行）。

凡是「函数体内声明 `own` + 任意 `return`」都命中——也就是几乎每个非 `void` 函数。

第二个偏差：ct-ast 的 `N_DELETE` 只发 `if (p) { …; free(p); }`，**不置空**；L2 发
`…; p = 0; }`。`README.md:133`、`docs/language-spec.md:378` 写的都是 L2 的形状
（「`}` / 行首 `return` 前插入 … `p = 0;`」），在 ct-ast 上两条都不成立。

## 证据

```ct
#include <stdio.h>
#include <stdlib.h>

struct Box { int n; } use Drop;

impl Drop for Box {
    void drop() { printf("dropped %d\n", self->n); }
}

int f(void) {
    own Box *p = malloc(sizeof(struct Box));
    p->n = 7;
    printf("using %d\n", p->n);
    return 1;
}
```

```text
# ct-ast（主线）
$ ct-ast body.ct -o body.c ; echo $?
0
$ cc -Wall -Wextra -std=c99 body.c -o body && ./body
using 7                          # 没有 "dropped 7"
# stderr：无告警
$ awk '/^int f\(void\)/,/^}/' body.c
int f(void) {
    struct Box * p = malloc(sizeof(struct Box));
    p->n = 7;
    printf("using %d\n", p->n);
    return 1;
    if (p) { Box_Drop_drop(p); free(p); }      /* return 之后的死代码 */
}

# L2（回归 oracle，同一输入）
$ l2 body.ct -o body2.c
body.ct:13: warning: potential leak: 'p' (Box*) allocated but never deleted
$ awk '/^int f\(void\)/,/^}/' body2.c
int f(void) {
    struct Box *p = malloc(sizeof(struct Box));
    p->n = 7;
    printf("using %d\n", p->n);
    if (p) { Box_Drop_drop(p); free(p); p = 0; }
    return 1;
}
```

嵌套/无花括号分支里的 `return`（`if (k > 0) return 1;`）同样漏（生成物里
`return 0;` 之后仍是死代码），实测运行输出只有 `using …`，无 `dropped`。

## 为什么没被门禁发现

- ct-ast 的生成 C **没有逐字节 oracle**（TEST-7 / D34 只比行为：退出码 + 零警告 + 程序输出）。
- `test/modules/autodrop`、`test/ast` 现有语料里没有一个「函数体内 `own` + 提前/末尾 return」的形状
  （`test/modules/autodrop/prog.ct` 只在 `{ }` 或 `impl` 内用 `own`，都不带 `return`）。
- 释放缺失不改变程序输出（`drop` 只打印），因此行为判据也看不见。

## 建议

1. `parse_stmt` 的 `return` 分支：在发 `N_RET` 之前，把当前可见、仍 `autodrop` 的变量按**逆序**
   插入释放节点（复用 `:224-253` 的构造）；函数体顶层的 return 释放后清 `autodrop`，
   嵌套/无花括号分支保留标记，供 fall-through 路径在 `}` 处释放。
2. `Emitter.h.ct` 的 `N_DELETE` 两条路径补 `p = 0;`，与 L2 对齐（与 `README.md:133`、
   `language-spec.md:378` 的描述一致）。
3. 补正例：`test/ast/<空号>_autodrop_return/`（`prog.expected.out` 必须出现 drop 打印），
   并把「return 之后不得再有 `free(p)`」写进人工核对步骤。
4. 落地后回改 `docs/tutorial.md:305` / `:775`（DOC-19 曾因 ct-ast 不置空而删掉 `p = 0`，
   需随第 2 条恢复）。

## 关联

- 同源形状：SH-28（无花括号分支的 `own` 静默泄漏）——第 1 条的「无花括号 return」与它同根，
  建议一并处理或至少共用同一段注入逻辑。
- 该缺陷直接决定 [`borrow` / `Handback` 提案](../../docs/history/design/borrow.md) 能否
  「复用 `own` 的注入基础设施」：`borrow` 若照搬，泄漏的是池槽位（池耗尽是可见故障）。
