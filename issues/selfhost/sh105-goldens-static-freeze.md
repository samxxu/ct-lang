# SH-105 · goldens 静态化（去 L1/L2 的前置）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（golden / oracle） |
| 定性 | 能力缺口（v1.0 去级前置） |
| 严重度 | High |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [v1-release-plan §1.5](../../docs/planning/v1-release-plan.md#L57-L71)、[check-goldens.sh](../../selfhost/check-goldens.sh) |
| 状态 | **待办（DEV 实现；REQ 定验收）** |
| 层级 | **Tier 1（`v1-PH-0` 入口）**，见 [battle/v1-readiness-1](../../battle/v1-readiness-1/verdict.md) |

## 现象

`check-goldens.sh` 目前以 L1/L2 为对照系；直接删除 L1/L2 会同时丢掉 oracle 与回归基线。

## 期望

1. 在删除 L1/L2 之前，把整套 golden 语料转为**静态期望文件**：
   - 每个用例的期望 C/H（或规范化摘要）入库；
   - `ct-ast vs 静态 golden` 成为独立门禁，不再依赖 L1/L2；
2. 覆盖现有全部语料与示例；未覆盖项列出清单，不得静默跳过；
3. 静态化的输入/生成命令与版本记录在文件头，保证可复现；
4. 静态化完成并全绿后，才允许 L1/L2 退役。

## 验收

- 新门禁在无 L1/L2 的树上可独立跑；
- 与静态化前的 L1/L2 对照结果一致（或差异逐条登记）；
- 回滚：保留旧 tag，静态文件可重新生成。

## 关联

- [v1 路线](../../docs/planning/v1-release-plan.md) §1.3/§1.5、[2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)
