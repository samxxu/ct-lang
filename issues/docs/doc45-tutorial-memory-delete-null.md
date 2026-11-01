# DOC-45 · 教程 §8 自相矛盾且与实现不符：`delete` 已置空、`return` 已不再要求行首

| 项 | 值 |
| --- | --- |
| 严重度 | **High**（入门文档对最常用的两个释放语义给出错误结论，且同页自相矛盾） |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [tutorial.md:303](../../docs/tutorial.md#L303)、[:326-329](../../docs/tutorial.md#L326-L329)、[:775](../../docs/tutorial.md#L775)、[:799-803](../../docs/tutorial.md#L799-L803) |
| 状态 | 已修（2026-11-01）：`docs/tutorial.md` §8 中英的 `delete` 置空与 `own` 的 `}` / `return` 位置规则已改正 |

## 现象

§8 的代码块注释已被改成 `if (p) { Box_Drop_drop(p); free(p); p = 0; }`，但紧接其后的正文仍写「不置空」：

```text
- **`delete p;`** 立刻释放：有 `Drop` 就先调 `drop()`，再 `free`。**不置空**——`p` 仍是悬空指针，
  要继续用就先自己 `p = 0;`。
```

英文版（:799-800）同样：

```text
  **not** null the pointer — `p` is left dangling, so write `p = 0;` yourself before reusing it.
```

实现自本次工作树起对 `delete` 一律置空（`Emitter.h.ct:1955-1980`），
实测 `delete p; printf("%d", p == 0);` 输出 `1`。

同一段还写「`}` 与 `return` 必须位于**行首**」——ct-ast 只检查 `}` 的行首
（[Stmt.h.ct:489-500](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L489-L500)），
`return` 的位置从未检查，行内 `if (c) return 1;` 实测 exit 0 并在分支内正确注入释放
（`test/ast/61_autodrop_return` 的 `pick` 就是这种形态）。该要求只在 L2 的行重写管线里成立。

## 证据

```text
$ ./ct-ast d1.ct -o d1.c && sed -n '/int main/,/^}/p' d1.c
int main(void) {
    struct Box * p = malloc(sizeof(struct Box));
    p->n = 1;
    if (p) { Box_Drop_drop(p); free(p); p = 0; }      # ← 已置空
    printf("after %d\n", (p == 0));
    return 0;
}
$ ./d1
drop 1
after 1
```

```text
$ ./ct-ast m1.ct -o m1.c ; echo $?     # if (c) return 1;  —— 行内 return
0
$ sed -n '/^int pick/,/^}/p' m1.c
int pick(int c) {
    struct Box * b = malloc(sizeof(struct Box));
    b->n = c;
    if (c) {
        if (b) { Box_Drop_drop(b); free(b); b = 0; }   # ← 分支内注入，未报错
        return 1;
    }
    …
```

## 建议

1. 两处「不置空」改成「**会**置空（`p = 0;`），无需手工清空」；
2. §8 的「`}` 与 `return` 必须位于行首」改成「`}` 必须在行首；`return` 无位置要求（该要求只在冻结的 L2 上成立）」；
3. 若第 2 条按「保守建议」保留，需明确标注为**写法建议**而非编译期约束。

## 关联

- [DOC-46](doc46-readme-transform-table-stale.md)（README 变换表的同一类漂移）
- [DOC-47](doc47-memory-guide-stale.md)（`memory-guide.md` 整篇基于旧行为）
