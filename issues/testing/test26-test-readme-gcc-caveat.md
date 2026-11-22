# TEST-26 · `test/README` 缺 Linux GCC 直跑前提

| 项 | 值 |
| --- | --- |
| 模块 | testing（文档） |
| 定性 | 文档缺口（外部可复现性） |
| 严重度 | Low |
| 锚点 | v0.88.3（2026-11-22） |
| 依据 | [GrokBot 评估核对](../../docs/reviews/2026-11-22-grokbot-architecture-assessment-eval.md) §3 |
| 状态 | open |
| 处置证据 | **accepted（待 DEV 一行补齐；`test/**` 不由 REQ 直接改）** |

## 现象

[test/README.md](../../test/README.md) 的「当前实测」写 `sh test/run.sh` → `156 passed, 0 failed`，
但没有写前提：在 Linux GCC ≥ 8 上直接跑会因 `-Wformat-truncation` 出现 1 项失败
（`selfhost/l0/ctc.c must be warning-free`）。

`check-all.sh` 检测到 GCC 时会自动包一层
`-Wno-format-truncation -Wno-implicit-fallthrough`，[selfhost/README.md](../../selfhost/README.md)
§「已知差异」也已说明；只有 `test/README.md` 没有这条口径，外部评估者按字面直跑会误判为红。

## 期望

在 `test/README.md` 的「当前实测」引用块里补一行：

> 在 Linux GCC ≥ 8 上直接跑 `sh test/run.sh` 可能因 `-Wformat-truncation` 报 1 项失败
> （L0 warning-free）；以 `selfhost/check-all.sh` 为准，它会自动加 `-Wno-format-truncation`。

## 验收

- 该行落在 `test/README.md` 的「当前实测」块内，措辞与 `selfhost/README.md` 一致；
- `python3 test/docs/check-docs.py` 仍绿；
- 不改任何测试行为与计数。
