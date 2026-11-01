# DOC-46 · README 变换表三行过期：`delete` 已置空，`own` / `borrow` 的注入位置也不再是「行首 `return`」

| 项 | 值 |
| --- | --- |
| 严重度 | Medium |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [README.md:132](../../README.md#L132)、[:133](../../README.md#L133)、[:134](../../README.md#L134)、[:161](../../README.md#L161)、[:603](../../README.md#L603)、[:604](../../README.md#L604)、[:655](../../README.md#L655) |
| 状态 | 已修（2026-11-01）：`README.md` 中英变换表的 `delete` / `own` / `borrow` 行已同步（含非左值只释放） |

## 现象

README 的「源码形态 → 展开」是读者查语法的第一站，三行与当前实现不符：

| 行 | 现文 | 实际 |
| --- | --- | --- |
| :132 / :603 | `delete q;` → `if (q) free(q);` | `if (q) { free(q); q = 0; }`（`Emitter.h.ct:1972-1980`） |
| :133 / :604 | `own …` 在「闭合 `}` / **行首 `return`**」前插入 | 每个 `return` 前都插入（`retire_before_return`，[Stmt.h.ct:172-195](../../selfhost/ct-ast/frontend/parse/Stmt.h.ct#L172-L195)），位置不限 |
| :134 | `borrow …` 同样写「行首 `return`」 | 同上；且当前**文件作用域不报错**（见 [SH-34](../selfhost/sh34-file-scope-borrow.md)） |
| :161 / :655 | 散文句里又重复一次 `delete q;` 展开为 `if (q) free(q);` | 同上 |

`own` 行里的 `p = 0;` 与实现一致（本次修复补齐），不必改；需要改的是**注入条件**的描述。

## 证据

```text
$ ./ct-ast g1.ct -o g1.c && sed -n '/int main/,/^}/p' g1.c
int main(void) {
    if (p) { free(p); p = 0; }        # delete 已置空
    return 0;
}
```

`own` / `borrow` 在 `if (c) return 1;` 这类行内、嵌套 `return` 上也会注入（见
[DOC-45](doc45-tutorial-memory-delete-null.md) 的 `m1.c` 证据）。

## 建议

- `delete` 两行改成 `if (q) { free(q); q = 0; }`（`Drop` 形态同步）；
- `own` / `borrow` 两行的「行首 `return`」改成「每个 `return` 之前（含分支内与行内）」；
- 若希望保留「建议把 `return` 写独立一行」的工程约定，放到 §7 已知限制里，别写进展开规则。
