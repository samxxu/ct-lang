# SH-45 · `return <读取 own/borrow 变量>` 在求值前释放并置空 → 运行期段错误

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 内存分析） |
| 严重度 | **High**（编译器 exit 0，生成物释放后使用 / 解引用空指针，实测 `rc=139`） |
| 锚点 | commit `dab1b71`（`v0.16.2`，2026-11-02） |
| 文件 | [Stmt.h.ct:172-192](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L172-L192)、[:616-620](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L616-L620)、[Memory.h.ct:244](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L244) |
| 状态 | 已修（2026-11-02，`v0.16.3`）：`return` 读取仍待 AutoDrop 的变量时先求值到 `__ct_retN`，再释放，再返回临时变量；新增 `test/ast/63_own_return_field` / `64_borrow_return_field` |

## 现象

`own` / `borrow` 的出口释放被挂到 `return` 节点上，由 `retire_before_return` 生成**在 `return`
语句之前**执行的释放块。当返回表达式只是**读取**对象字段（`b->n`、`c->fd`）而不是移交所有权时，
释放会先执行并把指针置空，紧接着的 `return b->n;` 就读已释放内存 / 解引用 `NULL`。

## 证据

```c
#include <stdlib.h>
struct Box { int n; } use Drop;
impl Drop for Box { void drop() { } }
int f(void)
{
    own struct Box *b = malloc(sizeof(struct Box));
    return b->n;
}
int main(void) { return f(); }
```

```text
$ ct ret2.ct -o ret2.c ; echo $?
0
$ sed -n '/^int f/,/^}/p' ret2.c
int f(void) {
    struct Box * b = malloc(sizeof(struct Box));
    if (b) { Box_Drop_drop(b); free(b); b = 0; }   /* ← 在求值之前 */
    return b->n;                                   /* ← 读已释放 / 空指针 */
}
$ cc -std=c99 ret2.c -o ret2 && ./ret2 ; echo $?
139
```

`borrow` 局部同型：

```text
int f(void) {
    struct Conn * c = (&g);
    if (c) { Conn_Handback_handback(c); c = 0; }
    return c->fd;
}
$ ./hb2 ; echo $?
139
```

对照：移交所有权是正确的——`return b;` 不生成释放块，由调用方接管。

```text
struct Box * f(void) {
    struct Box * b = malloc(sizeof(struct Box));
    return b;
}
```

## 根因

- `retire_before_return` 把所有仍 `autodrop` 的变量按逆序挂到 `return` 节点的 `b` 槽，
  发射时就在 `return` 之前打印（[Stmt.h.ct:616-620](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L616-L620)）；
- `leak_return` 只对 `expr_returns` 为真的变量清 `autodrop`（[Memory.h.ct:244](../../selfhost/ct-ast/backend/mem/Memory.h.ct#L244)）；
- 于是 `b->n`（`expr_returns` 为假、`expr_mentions` 为真）保留了释放，而释放正是这条路径上最不该做的。

**这是 SH-36 修复的副作用。** 修复前 `leak_return` 用 `expr_mentions`，`return b->n;` 会取消释放
（安全但泄漏）；改为 `expr_returns` 后泄漏没了，却把释放挪到了求值之前。上一轮的建议只覆盖了
「是否移交」，漏了「求值顺序」。

## 修复建议（任选其一，推荐 1 或 3）

1. **先求值再释放**：当返回表达式提到任一 `autodrop` 变量且不是移交时，发射
   `T __ct_ret = <expr>;` → 释放块 → `return __ct_ret;`（C99 允许块中声明；名字可沿用
   `__<trait>_vptr` 的既有命名纪律）；
2. 若不想改生成形状：这类表达式**跳过** pre-return 释放（恢复 SH-36 之前的泄漏语义），
   并保留一条 `potential leak` 警告——安全但不优雅；
3. 只对「完全未被返回表达式提到」的变量做 pre-return 释放，提到但不移交的走第 1 条。

无论选哪条，`own` 与 `borrow` 两条路径都要同时覆盖（它们共用 `retire_before_return`）。

## 验收

- 上述两个最小用例：生成物不再出现「释放块在读取字段之前」，或出现临时变量；
  `cc -O1` 后运行 `exit 0`；
- 移交用例 `return b;` 仍不释放、调用方接管；
- 新增门禁正例：`bw_ret_field.ct`（`borrow` 局部 + `return c->fd;`）与
  `own_ret_field.ct`（`own` + `return b->n;`），断言运行输出而非只看退出码；
- `bash selfhost/check-all.sh` 九关全绿。

## 关联

- [SH-36](sh36-return-mention-cancels-autodrop.md)：本条是它的副作用，处置时应把该文件的结论改写成
  「`expr_returns` 只决定是否移交，不决定释放时机」
- [SH-33](sh33-autodrop-return-no-inject.md)：pre-return 注入的来源
- 第三方评估（`v0.16.2`）§3.4 仍把「`return c->field` 跳过归还」当成现状——该现象已不存在，
  但现在换成了更糟的释放顺序问题
