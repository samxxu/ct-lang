# Phase 35 锚点勘误补充（r6 收口轮请顺带修复）

- 来源：看护会话独立只读评审（评审基准 `67abdb0..bd1df0a`，核验时点 2026-11-11 22:50 前后）
- 性质：Medium，1 条 + Low 附带；未覆盖于 `phase34-36-review-r6.md`（该报告判 P35 GO，未列此条）
- 只读评审，未改动任何卡片文件

## A-1（Medium）`emit_defs` 符号不存在，实为 `emit_trait_range`

锚点要求「符号名 + 文件全路径」，但卡内引用的符号名全仓不存在：

| 位置 | 现文 | 证据 | 修法 |
|---|---|---|---|
| `phase35-draft.md:130`（§3.2.4 第 1 点） | `emit_defs`（`Emitter.h.ct:2023-2031`） | `grep -rn 'emit_defs' selfhost/ct-ast/backend/emit/Emitter.h.ct` 无结果；`emit_trait_range` 定义于 `selfhost/ct-ast/backend/emit/Emitter.h.ct:2014`，`struct %s_vtbl {` 发射段正是 2023–2031 | 符号名改 `emit_trait_range`，路径补全 `selfhost/ct-ast/backend/emit/Emitter.h.ct`（行号 2023–2031 实测吻合，保留） |
| `phase35-draft.md:132`（第 3 点） | `emit_defs` 按 `traits[]` 注册序输出 | 同上 | 同上 |
| `phase35-draft.md:192`（S5b1） | `emit_defs` 子 vtable 加父首成员 | 同上 | 同上 |

技术实质不受影响：父 vtable 作首成员、拓扑排序等主张均落在 `emit_trait_range` 上成立。

## A-2（Low）links 数字出处标注（若 r6 收口未覆盖则一并校准）

- `phase34-draft.md:76`、`phase35-draft.md:39`、`phase36-draft.md:45` 标「1070 links/185 files」，其中 P36 混用「v0.30.0」标注；v0.30.0 实测 984/179（roadmap 行 45），当前 HEAD 实测 `check-docs: OK (1069 relative links in 185 files, v0.30.0, …)`（2026-11-11 实跑）。
- 修法：改标「最近实测 2026-11-11：1069/185」，或删除数字仅保留 S0 回填要求；P36 处统一为单一标注口径。

## 与 r6 报告的关系

r6 报告的 P36 NO-GO（H-1/H-2/M-1..M-3）与 P34 M-1 不在本补充范围，以 `phase34-36-review-r6.md` 为准；本补充仅为 P35 锚点勘误 + 数字出处，供同一收口提交顺带处理，避免多一轮往返。
