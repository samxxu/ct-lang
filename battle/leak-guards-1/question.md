---
id: leak-guards-1
head: cec61c22
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/design/**, docs/roadmap.md
---

# battle/leak-guards-1 — 泄漏防护进 PH-82 前，三项未定口径

## 争点

《泄漏防护三板斧》已同意把可确定部分放进 PH-82。余下三项口径不一致，必须在开卡前定死：

1. **包级配置键**：新造窄键 `leaks = warn|error`，还是复用 `strict = on`（与 `c-boundary = strict` 冲突），还是不引入配置键；
2. **第三板斧（`--debug-leaks` 环扫描）**：按现稿降级、直接 descope，还是维持「从根集标记可达」；
3. **环豁免语法**：注释 pragma、属性式标记，还是不做豁免；
4. **直接环的默认级别与限深**：默认 warning 还是 error；限深 3 条边是否定稿。

## 背景与触发

- 触发：用户指令「可以确定的部分放入 phase82，不能确定的再 battle 一下决定」。
- 当前 HEAD：`cec61c22`。
- 提案：`docs/proposals/leak-guards.md`（草案，2026-11-20）。
- 既有裁定：[D-011](../decisions/D-011.md) J-4c；[phase81](../design/phase81.md) E81-5。
- 相关：[phase82](../design/phase82.md)（待建立）。

## 逐条判据（J-1…J-4）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 配置键与既有 manifest 不冲突、语义单一、默认不改变存量包 | `docs/package-guide.md` 对照 + 键名排他性检查 |
| J-2 | 第三板斧在「不枚举根」的前提下是否能可靠区分环；否则不得进入 PH-82 | 根集枚举能力审查 + D-011 J-4c 对照 |
| J-3 | 豁免语法在现有词法/语法内可实现，且 refactor 后不易静默丢失 | 词法/parser 能力对照 + 现有 pragma 先例 |
| J-4 | 默认级别与限深满足「误报可控、漏检有文档、可机械验收」 | 类型图可判定性 + 语料误报要求 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ |
| opposition | REVIEW |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/design/**`、`docs/roadmap.md` |

- 只写 `battle/leak-guards-1/`；不改卡、roadmap、源码。
- 证据按 §7.7 E1–E5；每轮至少新增 1 条 E1/E2。
