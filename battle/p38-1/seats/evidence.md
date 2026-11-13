# battle/p38-1 证据席

- 复现双方证据，不站边；产物：`battle/p38-1/verify.json`。
- 每条证据含 command / exit / output / reproduced；anchors 含 file / line；环境写 os、cc、binary 或 date。
- 工具缺失或无法实测时显式记 skip，不得默绿。
- 禁止修改源码、卡、主规范；预算 30 次工具调用 / 20 分钟。
