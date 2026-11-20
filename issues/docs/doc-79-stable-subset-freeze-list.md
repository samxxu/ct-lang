# DOC-79 · 稳定子集冻结清单成文

| 项 | 值 |
| --- | --- |
| 模块 | docs（语言承诺） |
| 定性 | 文档/治理缺口 |
| 严重度 | Medium |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [v1-release-plan](../../docs/planning/v1-release-plan.md)、[language-spec.md](../../docs/language-spec.md) |
| 状态 | **待办（REQ）** |

## 现象

v1.0 要冻结语言，但当前没有一份“稳定子集”清单，也没有改动授权级别；冻结与“可改”的边界不清。

## 期望

1. 三档清单：
   - **已冻结**：v1.0 后只允许兼容性修复；
   - **冻结中**：v1.0 前可改，需 ADR；
   - **1.0 前可改**：明确截止点；
2. 每档写明改动授权级别（谁批、是否要 battle/ADR、是否 bump MINOR/MAJOR）；
3. 进 check-docs 的断言：冻结项不得在无 ADR 的提交里改动（至少能检查清单存在与状态）。

## 验收

- 清单成文并被 spec / roadmap 引用；
- 改动授权路径明确，可审计。

## 关联

- [v1 路线 §1.5](../../docs/planning/v1-release-plan.md#L57-L71)
