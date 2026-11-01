# DOC-39 · glossary 把节点池模块指成 `backend::mem::Memory`

| 项 | 值 |
| --- | --- |
| 模块 | docs（术语表） |
| 严重度 | Medium |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [docs/glossary.md:122](../../docs/glossary.md#L122)（中文）、[:354](../../docs/glossary.md#L354)（英文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

两处都把「节点池（arena）」的模块写成 `backend::mem::Memory`：

> 节点池（arena） ｜ `backend::mem::Memory` ｜ 一次性分配的节点与字符串池；不回收，随编译结束释放

节点与字符串池属于 `runtime::arena::Arena`（`namespace runtime::arena;`，`struct Node` / `struct Arena`）；
`backend::mem::Memory` 是 AutoDrop 与泄漏分析对象。

## 证据

```text
$ sed -n '13,20p;47,49p' selfhost/ct-ast/runtime/arena/Arena.h.ct
namespace runtime::arena;
pub struct Node …
pub struct Arena …

$ sed -n '31p;48p' selfhost/ct-ast/backend/mem/Memory.h.ct
namespace backend::mem;
pub struct Memory { …
```

术语表上一行（:121）自己引用的 `self->arena->nodes[n]` 也是 `runtime::arena::Arena` 的字段；
AGENTS §2 的单元职责表把 `backend/mem/` 记为「AutoDrop 与泄漏分析」。

## 建议

中文与英文两行都改为 `runtime::arena::Arena`（或写 `selfhost/ct-ast/runtime/arena/**`），
并把「节点池 / 字符串池」与「内存分析」明确区分开。
