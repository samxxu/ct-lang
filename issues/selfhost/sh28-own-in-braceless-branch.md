# SH-28 · 无花括号分支里的 `own` 既不 AutoDrop 也不告警，静默泄漏

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 语句解析 / 内存） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [frontend/parse/Stmt.h.ct:661-678](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L661-L678)（`parse_branch`）、对照 [:214-264](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L214-L264)（`parse_block`） |
| 状态 | 已修（2026-10-31）：`parse_branch` 无花括号也建 `N_BLOCK` 并追加 AutoDrop；探针 [test/ast/60_branch_autodrop](../../test/ast/60_branch_autodrop/) |

## 现象

带花括号的块走 `parse_block`：收尾时把本作用域的 `own` 按声明逆序追加 `delete`（:214-253），
并在 `pop_scope` 前调用 `leak_scope`（:261）。

无花括号分支走 `parse_branch`：`push_scope()` → `parse_stmt()`（`own` 分支登记 `mem->own_decl`
并置 `autodrop = 1`）→ `pop_scope()`。`pop_scope` 直接执行 `mem->nowner = own_base[nscope]`
（[ParseSupport.h.ct:194-199](../../selfhost/ct-ast/frontend/parse/ParseSupport.h.ct#L194-L199)），
这些登记被丢弃：既不生成 `drop` / `free`，也不会触发泄漏告警（`leak_scope` 只报
`owned && !autodrop` 的变量，而 `own` 变量 `autodrop = 1`）。

## 证据

```ct
#include <stdio.h>
#include <stdlib.h>
struct Box { int n; } use Drop;
impl Drop for Box { void drop() { printf("drop %d\n", self->n); } }
int main(void) {
    int c = 1;
    if (c) own Box *b = malloc(sizeof(struct Box));
    return 0;
}
```

```text
$ ./ct-ast own2.ct -o own2.c ; echo $?
0
# 生成的主函数（没有任何 drop / free，也没有告警）：
int main(void) {
    int c = 1;
    if (c) {
        struct Box * b = malloc(sizeof(struct Box));
    }
    return 0;
}
```

`while (c) own Box *b = …;` 同理。

## 建议

二选一：

1. 在 `parse_branch` 里复用 `parse_block` 的 AutoDrop 收尾（把单语句包成 `N_BLOCK` 后走同一路径）；
2. 明确拒绝：`own` 声明必须位于带花括号的块内，否则报
   `an own declaration needs a braced block`（与「`}` 必须在行首」同源的静态约束）。

无论选哪种，都应补一条 `test/ast` 正例（`{ }` 内正常释放）和一条负例（无花括号处报错）。
