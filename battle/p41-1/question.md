---
id: p41-1
head: bd8b74f3
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/design/phase41-draft.md, docs/decisions/**
---

# battle/p41-1 — PH-41 原子能力的命名与 C 标准边界

## 争点

Phase 41 草案把 `atomic` 变成关键字，并把 `atomic_load` / `atomic_store` / `atomic_cas` 变成保留名；生成物统一 `_Atomic(T)`。独立评审发现这会破坏现有 `<stdatomic.h>` 用法（`atomic_int` + `atomic_load`）、同名用户函数，以及 C99 项目的严格编译契约。争论：在“语言层提供原子能力”这个目标下，名字和标准怎么定。

- **A（现草案）**：`atomic` 关键字 + `atomic_load/store/cas` 保留名 + `_Atomic(T)` + C11 扩展；保留名冲突记作 tradeoff。
- **B（上下文 + 前缀，主张）**：`atomic` 仅在后跟 4 个支持基类型时作为类型修饰；内建操作改为 `ct_atomic_load/store/cas`；`atomic_load` / `<stdatomic.h>` 名字保持普通调用；生成物 `_Atomic(T)`；显式 C11 构建。
- **C（上下文 + 按类型 fallback）**：保留 `atomic_load/store/cas`，但仅当第一实参静态类型是 CT 原子时拦截，否则回退普通调用；`atomic_int` 等未知 typedef 由 `<stdatomic.h>` 宏处理。
- **D（纯 C99）**：`atomic T` 映射为普通 `T`，只用 `__atomic_*` 助手；不改 C 标准，但直接访问不是原子。

## 判据

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | **不破坏现有 `<stdatomic.h>` 代码与同名声明**：`atomic_int` + `atomic_load` 仍可用；`int atomic_load(int*)` 不被拒 | 现有 bindings 正例和同名函数夹具；A 直接冲突 |
| J-2 | **保留解析期诊断**：by-value CAS、非原子第一实参、错误基类型仍需 `file:line:col` | 与 A 相同的负例；B/C 都能保留 |
| J-3 | **实现可审计**：类型/调用检查不依赖宏展开或 `_Generic`，名字冲突面可枚举 | 代码路径与夹具；C 的 fallback 需要类型归一化 |
| J-4 | **C 标准契约明确**：生成物在声明的 C 标准下严格编译；不能把 C11 扩展说成 C99 | `cc -std=c99 -pedantic-errors` 与 `cc -std=c11` 实测 |
| J-5 | **门禁/编辑器可覆盖**：pthread 夹具、TSan、tmLanguage、check-grammar 都有落点 | 现有 check-ast/test/run/grammar 锚点 |

## 背景与触发

- 触发：用户要求对 PH-41 评审后直接修改，并用 battle 解决无法机械决定的名字/标准争议。
- 独立评审：P0 1 条（保留名/关键字破坏面），P1 6 条（C99/C11、`atomic_load(p)`、pthread 门禁、类型诊断、TSan CI、编辑器）。
- 现有文档 [bindings-and-patterns.md](../../docs/bindings-and-patterns.md) 的 §7 正例使用 `atomic_int` + `atomic_load/store`；[phase41-draft.md](../../docs/design/phase41-draft.md) 当前 D41-2/D41-3 与本争点直接相关。

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ（主张 B） |
| opposition | REVIEW（主张 A，兼评 C/D） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/design/phase41-draft.md`、`docs/decisions/**`；只写 `battle/p41-1/` 与 `/tmp` |
