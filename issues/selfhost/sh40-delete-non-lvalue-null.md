# SH-40 · 新增的置空让 `delete <非左值>` 生成非法 C（`get() = 0`）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（ct-ast 发射器） |
| 严重度 | Medium（既有可编译输入变为不可编译产物，退出码仍为 0） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [backend/emit/Emitter.h.ct:1935-1980](../../selfhost/ct-ast/backend/emit/Emitter.h.ct#L1935-L1980)（`N_DELETE` 的两条释放路径） |
| 状态 | 已修（2026-11-01）：`Emitter.h.ct` 的 `N_DELETE` 只在实参可赋值时追加 ` = 0; `，否则生成 `if (e) { …; }`；门禁正例 `bw_delete.ct` |

## 现象

SH-33 的修复给两条释放路径补上了置空，写法是对 `nodes[n].a` 再做一次 `emit_expr` 并追加 ` = 0;`：

```c
fputs("); ", self->out);
if (self->emit_expr(self->arena->nodes[n].a) != 0) return -1;
fputs(" = 0; }\n", self->out);
```

`delete` 的实参是任意表达式（`parse_stmt` 走 `parse_expr`），并不保证可赋值。函数调用、二元表达式等
都会拼出 `get() = 0` / `(p + 0) = 0` 这类非法左值，C 编译器直接报错，而 `ct-ast` 返回 0。

## 证据

```ct
#include <stdlib.h>
static int *get(void) { return 0; }
int main(void) {
    delete get();
    return 0;
}
```

```text
$ ./ct-ast g1.ct -o g1.c ; echo $?
0
$ sed -n '/int main/,/^}/p' g1.c
int main(void) {
    if (get()) { free(get()); get() = 0; }
    return 0;
}
$ cc -std=c99 -c g1.c
g1.c:10:37: error: expression is not assignable
```

修复前同一输入生成 `if (get()) free(get());`，可以编译。

## 建议

只在实参可赋值时置空——`N_VAR` / `N_MEMBER` / `N_ARROW` / `N_INDEX` / `N_DEREF` 五种
（`parse_stmt` 的赋值目标判定已在 [:1431](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L1431) 列过同一张清单，
可直接复用）；其它形态维持 `if (e) free(e);`。

顺带评估：置空会**再求值一次**实参，若实参含副作用（`delete pop();`）语义已变，这条也建议一并处理。

## 关联

- [SH-33](sh33-autodrop-return-no-inject.md)（置空的引入来源，已修）
