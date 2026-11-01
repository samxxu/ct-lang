# DOC-42 · README 英文版称 `test/ast/errors/` 只按退出码断言

| 项 | 值 |
| --- | --- |
| 模块 | docs（README） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [README.md:779-780](../../README.md#L779-L780)（英文）；对照 [README.md:266](../../README.md#L266)（中文） |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

英文目录树注释：

> `ast/` … `errors/` holds bare negatives
> (asserted on exit code by check-ast.sh, no .expected-err)

中文对应行写的是「errors/ 为裸负例（**多数钉死消息文本**）」。脚本事实是：
通用循环除退出码外还要求 `^[^:]+:[0-9]+:[0-9]+: error: `（带位置），随后大段 `"fixture|message"` 表逐条钉死文本。

## 证据

```text
$ sed -n '1508,1518p' selfhost/check-ast.sh
for f in test/ast/errors/*.ct; do … elif grep -Eq '^[^:]+:[0-9]+:[0-9]+: error: ' … ok …
$ sed -n '1524,1526p' selfhost/check-ast.sh
for pair in \
    "case_outside_switch|a case label is only allowed inside a switch" \
…
```

统计：72 个负例全部钉死消息（63 个在 `"fixture|message"` 表，9 个独立 `grep -q`）。

## 建议

英文改为 "bare negatives; every one must exit non-zero with a positioned diagnostic, and all of them
also pin the message text (no `.expected-err` file)"，与中文 :266 对齐。
