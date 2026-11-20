# DOC-76 · 兼容承诺“不再是 C 超集”未三处同步

| 项 | 值 |
| --- | --- |
| 模块 | docs（README / spec / roadmap） |
| 定性 | 文档缺口（v1.0 兼容承诺） |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [README.md](../../README.md)、[language-spec.md](../../docs/language-spec.md)、[roadmap.md](../../docs/roadmap.md) |
| 状态 | **待办（REQ）** |

## 现象

README / spec 目前没有明确写出“v1.0 起不再是 C 超集”的兼容承诺；用户仍可能按 C 超集理解。

## 期望

1. 三处同步同一口径：
   - 哪些 C 形态仍接受（pass-through / C 机制）；
   - 哪些不再承诺（旧内部语法、L1/L2 管线相关）；
   - 旧工程迁移建议（用 v0.x 编译器 / `ct migrate`）；
2. 措辞与 v1.0 退出条件一致，不承诺未实现能力；
3. 加一条 check-docs 断言，防止三处漂移。

## 验收

- 三处文本存在且语义一致；
- check-docs 能拦住“只改一处”。

## 关联

- [v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)、[2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)
