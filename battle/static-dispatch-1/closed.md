# static-dispatch-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-18；EDITOR 判决；1 轮 claim/counter/evidence） |
| 争点 | 外部提案 R1（非泛型 trait 派发静态化）/ R2（链式接收者）/ R3（1.0 前治理）是否成立、能否原样排期 |
| 结论 | **部分采信**：R1 只接受同单元子集；R2a 降级为文档/设计决策（悬垂已修）；R2b 仅作为重开 SH-73 决策的输入；R3a 接受为文档任务；R3b/R3c 不采纳（已被 1.16.0/PH-67 取代或属外部仓） |
| 证据 | [verify.json](verify.json)（10 条 evidence、14 条 anchor、8 条 checks）；探针在 `/tmp/ctbattle`，提案副本在 `/tmp/battle-static-dispatch-1` |
| 关键事实 | 同单元具体接收者仍走 vptr；跨单元方法符号 `static`，消费者必须走 vptr；SH-75 已修（`0 201`，但用 `malloc` 物化）；SH-73 对“方法结果”仍拒绝，自由函数/固有方法结果已可用；1.16.0 + `v1-PH-0` + PH-67 已取代旧偏移模型 |
| 采纳 | R1 同单元子集（夹具级判据，不做全 golden regex）；R3a 稳定子集清单（映射既有门禁） |
| 不采纳 | R2a 作为 P0 补丁；R2b 作为“补实现”；R3b；R3c |
| 下一步 | 提案方重基线到 v0.65.1/1.16.0；R1 单独立夹具与跨单元 ABI 决策；R2b 先出 superseding decision；R3a 转文档任务 |
| 不修改 | 不改 `selfhost/**`、`test/**`、`lib/**`、`docs/language-spec.md`、`install.sh`；未 bump、未打 tag、未 push |
