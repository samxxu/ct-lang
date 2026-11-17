# cinclude-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-17；EDITOR 判决 B′） |
| 争点 | 是否默认禁止 `.ct` 直接 `#include` C 头，仅 `.shim.c/h` 可 include |
| 结论 | 不采纳语言默认禁止；默认保留 C 超集；新增包级/opt-in 完整 C 边界 strict，新包默认 strict；shim 扩展 + 构建部署 |
| 证据 | `battle/cinclude-1/verify.json`（31 evidence；688 文件/845 行；7 类绕过；L2/shim 阻塞） |
| 进入 | 需另写 strict C boundary 提案/卡；本判决不直接改代码 |
| 不修改 | 源码、规范、测试、包仓策略；只落判决 |
