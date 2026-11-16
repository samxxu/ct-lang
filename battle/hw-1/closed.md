# hw-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-16；EDITOR 判决） |
| 争点 | 两份硬件提案合并：P0 顺序、freestanding 边界、const vtable、pilot 定位 |
| 结论 | P0 → PH-64 → pilot；freestanding 用“每单元 `nm -u` ⊆ 允许集”，不按容器名单；const 全量；pilot 不占 phase |
| 证据 | `battle/hw-1/verify.json`（25 evidence、40 anchors） |
| 进入 | `docs/planning/hardware-readiness-requirements.md`（REQ-HW-*） |
| 不修改 | 源码、两份提案原文、PH-64 卡；只落判决与需求文档 |
