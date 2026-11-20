# DOC-77 · 能力标签与 spec 节号的一致性断言

| 项 | 值 |
| --- | --- |
| 模块 | docs（check-docs） |
| 定性 | 文档门禁缺口 |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [check-docs.py](../../test/docs/check-docs.py)、[language-spec.md](../../docs/language-spec.md) |
| 状态 | **待办（REQ 定规则；DEV 接门禁）** |

## 现象

能力标签（如 String/Str、切片、ref/out、box/new）与 spec 节号之间没有机器校验；
提案中的“页首版本注入”又与 DOC-63（spec 页首不钉版本）冲突。

## 期望

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
