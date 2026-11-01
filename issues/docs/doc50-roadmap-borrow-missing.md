# DOC-50 · roadmap 没有 `borrow` / `Handback` 的阶段与版本归属

| 项 | 值 |
| --- | --- |
| 严重度 | Low |
| 锚点 | commit `8b047f5`（2026-11-01）+ 工作树在途改动 |
| 文件 | [docs/roadmap.md](../../docs/roadmap.md)（全篇无 `borrow` / `Handback`）；规定见 [AGENTS.md:115](../../AGENTS.md#L115) |
| 状态 | 已修（2026-11-01）：`docs/roadmap.md` 的 v0.16.0 记录（版本表 / 批次记录 / 英文两处）与 `docs/glossary.md` 的 borrow / AutoDrop 措辞已与实现同步 |

## 现象

AGENTS §6 要求：改动 CT 线独有语法时，除了 `docs/language-spec.md`，还必须同步
`docs/roadmap.md` 的对应阶段与 `docs/design/**`，并在 `README.md` 标明适用编译器。

本轮 `borrow` / `Handback` 已：

- 写进 `docs/language-spec.md` §4.40 ✅
- 写进 `docs/design/borrow.md` ✅
- 写进 `README.md` 变换表并标注「仅 ct-ast」✅
- 写进 `docs/glossary.md` ✅
- **没有**写进 `docs/roadmap.md`（`grep -c borrow docs/roadmap.md` = 0）❌

同时 `CTC_VERSION` 仍是 `0.15.1`，roadmap 的「版本记录」也没有一条对应
「Phase 12 之后的能力补丁」条目——而 `v0.13.0` / `v0.14.0` / `v0.15.0` / `v0.15.1` 都是逐条登记的。

## 建议

二选一，并保持与既有约定一致：

1. 作为 Phase 5 的延续记到 Phase 5 行 + 一条版本记录（例如 `v0.16.0`：`borrow` / `Handback`），
   同时更新 glossary 的「能力补丁例外清单」；
2. 若不打算 bump 版本，至少在 roadmap 里加一行显式说明「`borrow` / `Handback` 属未编号的能力补丁，
   随下一次收口统一登记」，避免读者以为漏记。

顺带核对 `docs/glossary.md` 的「阶段」行：它写 borrow 属「Phase 5 续」，而 roadmap 完全没有这一说法，
两处应统一。
