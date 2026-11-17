# defer-init-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-18；EDITOR 判决 B） |
| 争点 | `Some *s = defer Some::new()` 是否作为创建+清理简写 |
| 结论 | 拒绝 `defer expr`；保留块级 defer；Drop 用 `own`，非 Drop 用尾随块；要更短另立关键字 |
| 证据 | `battle/defer-init-1/verify.json`（23 evidence；A 误捕获合法 defer 标识符；尾随块已覆盖） |
| 进入 | 文档示例；若需新关键字另提案 |
| 不修改 | 源码、规范、测试；只落判决 |
