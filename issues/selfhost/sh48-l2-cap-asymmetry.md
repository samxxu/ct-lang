# SH-48 · 18.0 只解除了函数 / impl 上限，L2 的 struct / 字段 / 变量上限仍低于 ct-ast

| 项 | 值 |
| --- | --- |
| 模块 | selfhost |
| 严重度 | Info |
| 锚点 | commit `553d300`（2026-11-02，工作树 `v0.18.0`） |
| 文件 | [selfhost/l2/core.ct](../../selfhost/l2/core.ct)、[frontend/sym/Symbols.h.ct](../../selfhost/ct-ast/frontend/sym/Symbols.h.ct) |
| 状态 | 已处置（2026-11-02，`v0.18.0`）：短期项已做——`docs/design/phase18.md` 的 18.0 进展注明「只解除函数 / impl 两类上限」，并列出三项仍低于 ct-ast 的上限；中期抬值归入容量账本，触发条件与 SH-1 / TEST-9 一致 |

## 现象

18.0（`59f80e6`）把 L2 的 `MAX_FUNCS 128→256`、`MAX_MAP_IMPLS 256→512`，并把四张定长表改
`calloc`，消除了「再加一个函数 / impl 方法就失败」的瓶颈。但其余上限没有动，且仍低于 ct-ast：

| 上限 | L2（构建 ct-ast 的编译器） | ct-ast（编译用户代码） |
| --- | --- | --- |
| `MAX_FUNCS` | 256 | 256 |
| `MAX_MAP_IMPLS` | 512 | —（同族上限更宽） |
| `MAX_STRUCT` | 64 | `MAX_STRUCTS` 128 |
| `MAX_FIELDS` | 32 | 64 |
| `MAX_VARS` | 512 | 4096 |

## 证据

ct-ast 当前 30 个 struct 定义、18 个 trait；L2 的 struct 余量约 34 个。也就是说，
只要 ct-ast 继续新增 struct（生态期很可能继续），**L2 会比 ct-ast 自己先触顶**，
而 18.0 的验收口径是「L2 能编 ct-ast」，不是「L2 的上限 ≥ ct-ast 的上限」。

## 影响

不是当前缺陷：11 道门禁全绿，18.0 的边界探针（256 函数）也已通过。风险在于下一次功能开发
会被 `MAX_STRUCT 64` / `MAX_FIELDS 32` 挡住，且报错位置在 L2 而非业务代码处，容易误判为
ct-ast 的 bug。18.0 的「容量解除」标题也容易让人以为上限已对齐。

## 建议

- 短期：在 [docs/design/phase18.md](../../docs/design/phase18.md) 18.0 的进展里注明
  「只解除函数 / impl 两类上限，其余仍低于 ct-ast」，避免读者误解。
- 中期：纳入容量策略（与 SH-1 / TEST-9 同一账本），按实际增长率决定是否把 L2 的
  struct / fields / vars 抬到与 ct-ast 同值或改为动态增长。
