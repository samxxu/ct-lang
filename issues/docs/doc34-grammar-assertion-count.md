# DOC-34 · 编辑器语法断言数仍写 27（实为 31），`check-all.sh` 第 8 关标签停在 12.1

| 项 | 值 |
| --- | --- |
| 模块 | docs / ci（门禁头部注释） |
| 严重度 | Low |
| 锚点 | commit `524ba99`（2026-10-31） |
| 文件 | [README.md:294](../../README.md#L294)、[AGENTS.md:179](../../AGENTS.md#L179)、[AGENTS.md:499](../../AGENTS.md#L499)、[selfhost/check-all.sh:16](../../selfhost/check-all.sh#L16)、[selfhost/check-all.sh:79](../../selfhost/check-all.sh#L79) |
| 状态 | 已修（2026-10-31）：文档已按建议更新（见 [issues/README.md](../README.md) 的 2026-10-31 处置表） |

## 现象

四处把编辑器语法测试的规模写成「27 项断言」，实际脚本输出 `== 31 checks, 0 failed ==`
（batch 35/36/38 陆续加入了 default 方法、`.m.ct`、`map … for type` 的断言）。

同时 `check-all.sh` 第 8 关的标签写「Phase 9.1–9.7 + 10.x + 11.x + 12.1」，
而该脚本现在覆盖 batch 13–39（trait 默认方法、`.m.ct`、shim、L0 种子关等）。

## 证据

```text
$ python3 editors/vscode/test/check-grammar.py | tail -1
== 31 checks, 0 failed ==

$ grep -c 'check(' editors/vscode/test/check-grammar.py
31
```

```text
$ grep -n '27' README.md AGENTS.md selfhost/check-all.sh | grep -i assert
README.md:294:python3 editors/vscode/test/check-grammar.py   # 27 项断言；退出码 0 = 通过
AGENTS.md:179:…（27 项断言，必须全绿）…
AGENTS.md:499:… and `python3 editors/vscode/test/check-grammar.py` (27 assertions) must be green …
selfhost/check-all.sh:16:#   6. editors/vscode/test/check-grammar.py      editor grammar (27 assertions)
```

## 建议

四处统一改为 31（或去掉数字，改为「以脚本末行为准」，与 roadmap 对 `check-ast` 的口径一致）；
把第 8 关标签改为覆盖范围式描述（如「Phase 9.1–12 + batch 13–39」），避免每批都要改。
