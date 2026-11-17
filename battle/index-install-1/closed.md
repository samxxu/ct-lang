# index-install-1 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-18；EDITOR 判决 B） |
| 争点 | install.sh 默认拉 index + ct pkg 执行发布脚本 |
| 结论 | 不默认 clone；索引显式/pin/原子/签名；发布留 index CI；消费端可读本地索引但不自动联网 |
| 证据 | `battle/index-install-1/verify.json`（25 evidence；官方索引五字段、无签名；std/std 失败；ct pkg 无 index 子命令） |
| 进入 | 索引仓修复 + 可选 `--with-index` 提案；不直接改 install.sh |
| 不修改 | 源码、install.sh、索引仓；只落判决 |
