# DOC-22 · Batch 2 落地后残留的过时陈述（binding 注释、设计文档状态）

| 项 | 值 |
| --- | --- |
| 模块 | docs / bindings / test |
| 严重度 | Low |
| 锚点 | commit `224c08f`（Batch 2 收尾，2026-10-22） |
| 状态 | 已修（2026-10-22） |

## 现象

Batch 2 把「命名空间全局 mangling」与「跨单元装箱」都打通了，但有四处陈述仍停在 2a.1 之前：

| # | 文件 | 现文 | 实际 |
| --- | --- | --- | --- |
| 1 | [bindings/mock-hal/uart.ct](../../bindings/mock-hal/uart.ct#L8) | `v1 limitation: boxing a mapped instance is unit-private` | `pub` trait + `pub` 实例时 vtable 已导出（`test/modules/xunit_box`、消费者装箱实测通过） |
| 2 | [bindings/README.md](../../bindings/README.md#L192) | `mapped instance is unit-private anyway` | 同上；跨单元消费已可行 |
| 3 | [test/modules/map_ns/hal/uart.ct](../../test/modules/map_ns/hal/uart.ct#L3) | `Globals are not mangled by this compiler yet` | 全局已按命名空间 mangling 为 `hal_uart1`（`a758fa4`） |
| 4 | [docs/design/batch2-cross-unit-oo.md](../../docs/design/batch2-cross-unit-oo.md#L5) | `状态：已获用户批准…本文件是本批次的实现依据` | 本批次已实现并提交，状态应改为「已实现」并标注出口验证 |

`docs/design/phase12.md` 的两处 `unit-private` 属于**当时冻结设计**的历史陈述，可保留；
建议在文件头部加一行「跨单元装箱已由 Batch 2 解除」，避免读者把它当作现状。

## 影响

- 新用户读 binding 注释会误以为跨单元消费仍然不可用，从而把 binding 硬写成 self-contained，
  或退化成 `pub` 标量包装——这正是第三方最初的痛点。
- 设计文档写着「待实现」，实现却已在 `main` 上，下一轮评审会把它当成漂移重复报。

## 修复建议

1. 三处代码/文档注释改为现状：`pub trait` + `pub` 实例导出 vtable；未公开的一对保持 `static`。
2. 设计文档状态改为「已实现（Batch 2，2026-10-22）」，并在 §3 每个需求后标注对应的提交与
   验收用例；保留 §2 的 spike 记录作为历史证据。
3. `docs/design/phase12.md` 头部加一行状态注记（只加注记，不改冻结正文）。

## 验证

- `grep -rn "unit-private\|not mangled" bindings test/modules docs` 只应命中历史设计文档及其注记。
- 不触碰任何生成物与 golden；`bash selfhost/check-all.sh` 九关全绿。
