# DOC-77 · 能力标签与 spec 节号的一致性断言

| 项 | 值 |
| --- | --- |
| 模块 | docs（check-docs） |
| 定性 | 文档门禁缺口 |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [check-docs.py](../../test/docs/check-docs.py)、[language-spec.md](../../docs/language-spec.md) |
| 状态 | **已完成（2026-11-21：`capabilities.tsv` 20 项 + README 标记 + check-docs 断言）** |

## 进展（2026-11-21）

- 新增 [docs/capabilities.tsv](../../docs/capabilities.tsv)：20 行
  `id<TAB>能力名<TAB>spec 节号（逗号分隔）<TAB>implemented|planned`。
- README §3 的每条语言能力带 `<!-- cap:id -->` 标记，**只带 id、不重复节号**；
  「泛型 struct 与内置容器」一条挂 `generic-struct` 与 `containers` 两个标记。
  「诊断与工具」「明确不做」不是语言能力，不进表，也不挂标记。
- `check-docs` 新增 `check_capability_map`：
  - `implemented` 行的每个节号必须能在 spec 解析到标题（H2–H4）；
  - 状态只能 `implemented` / `planned`；id 唯一且为小写 slug；
  - README 的每个 `cap:` id 必须在表内且恰好出现一次；表内每个 id 必须在 README 出现。
- 负例自测三种都红：把 `4.70` 改成 `9.99`（节号不存在）、把 `cap:box` 改成 `cap:boxx`
  （未知 id）、以及由此产生的「box 缺标记」。
- 版本注入边界保持 DOC-63：spec 页首不钉版本；版本只出现在 README/生成物。

## 现象

能力标签（如 String/Str、切片、ref/out、box/new）与 spec 节号之间没有机器校验；
提案中的“页首版本注入”又与 DOC-63（spec 页首不钉版本）冲突。

## 期望

> D7 已定（2026-11-21）：版本注入范围只到 README/生成物，spec 页首保持 DOC-63。

1. **版本注入**：只注入生成物与 README 的版本行，**不注入 spec 页首**（DOC-63 保持）；
2. **能力→节号**：维护一张能力表（能力名 / spec 节号 / 是否已实现），check-docs 断言：
   - 标注“已实现”的能力必须能解析到存在的节号；
   - 节号不存在或能力未实现时报错；
3. 新特性（box/new 等）进表时同步更新。

## 验收

- check-docs 新增断言可正/负测试（删节号、改能力名都会红）；
- spec 页首仍不钉版本。

## 关联

- [v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)、[2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)
