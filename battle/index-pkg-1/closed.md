# index-pkg-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-18；EDITOR 判决 B′） |
| 争点 | ct pkg 作为 index package.sh 的透传捷径 |
| 结论 | 拒绝透传；ct pkg 保持 install/check；仅接受显式、pin/原子/验签的 ct pkg init 拉索引；发布留 CI |
| 证据 | `battle/index-pkg-1/verify.json`（30 evidence；package.sh 未提交/644/STAGING；ct pkg check 冲突；index 五字段） |
| 进入 | 索引修复 + 可选 ct pkg init 提案；不改 install.sh/源码 |
| 不修改 | 源码、install.sh、索引仓；只落判决 |
