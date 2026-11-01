# DOC-43 · `MAX_NODES` 只存在于文档与注释里，代码中没有这个宏

| 项 | 值 |
| --- | --- |
| 模块 | docs / selfhost（容量上限口径） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [docs/language-spec.md:1419](../../docs/language-spec.md#L1419)、[:3089](../../docs/language-spec.md#L3089)、[runtime/arena/Arena.h.ct:48](../../selfhost/ct-ast/runtime/arena/Arena.h.ct#L48)、[:63](../../selfhost/ct-ast/runtime/arena/Arena.h.ct#L63)、[frontend/parse/Expr.h.ct:1604](../../selfhost/ct-ast/frontend/parse/Expr.h.ct#L1604) |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

language-spec §7 的注记用 `MAX_NODES` 131072 描述 ct-ast 的节点池上限，中英各一处。
但 `selfhost/ct-ast/**` 里没有 `#define MAX_NODES`——节点池容量是两处裸字面量 131072
（`struct Arena { struct Node nodes[131072]; }` 与 `if (self->nnode >= 131072)`），
`Expr.h.ct` 的注释还在引用 `MAX_NODES`。这与仓库「容量常量统一命名、集中在文件头」的约定不一致，
也让文档读者搜不到该符号。

## 证据

```text
$ grep -rn '#define MAX_NODES' selfhost/ct-ast
（无输出）
$ grep -rn '131072' selfhost/ct-ast
runtime/arena/Arena.h.ct:9:  * (131072 nodes, a 256 KiB string pool) …
runtime/arena/Arena.h.ct:48:    struct Node nodes[131072];
runtime/arena/Arena.h.ct:63:        if (self->nnode >= 131072) return -1;
```

## 建议

二选一，二者都是小改动：

1. 在 `Arena.h.ct` 头部加 `#define MAX_NODES 131072` 并用它替换两处字面量（`Expr.h.ct` 的注释随之成立）；
2. 文档改称「节点池 131072 个节点（`Arena.h.ct` 的数组容量）」，并删掉 `Expr.h.ct` 注释里的宏名。

若选 1，注意 AGENTS §2 的「宏不跨翻译单元」——`Expr.h.ct` 只需注释成立，不必真的引用该宏。
