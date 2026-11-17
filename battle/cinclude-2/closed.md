# cinclude-2 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-17；EDITOR 判决 A′） |
| 争点 | 外部库/用户默认 strict；`.m.ct` 是否可 include；CT 核心豁免；strict 边界 |
| 结论 | `.m.ct` 可 include，作为显式映射边界；`.ct/.h.ct` 禁直接 include；CT 仓内 1.0 前代码豁免；外部默认 strict；吸收 B 的 `.h.ct` shim；strict 覆盖 raw/extern/函数式宏；包/CLI 默认 |
| 证据 | `battle/cinclude-2/verify.json`（29 evidence；`.m.ct` 直连实测、`.h.ct` shim 缺失、外部包迁移面） |
| 进入 | 另写 strict C boundary 提案/卡；不直接改代码 |
| 不修改 | 源码、规范、测试、外部包；只落判决 |
