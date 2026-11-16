# hw-2 关闭

| 项 | 值 |
| --- | --- |
| 状态 | `closed`（2026-11-17；EDITOR 判决） |
| 争点 | `builtin_live` 的 `Str` 判据：文本近似 vs 符号级 |
| 结论 | 主张不成立（`rejected`）；出 C 方案（符号解析 + 词边界扫描，保留 Vec→Str） |
| 证据 | `battle/hw-2/verify.json`（双方反例均复现；3 条 `reproduced:false` 已记） |
| 决策 | [D-007](../../docs/decisions/D-007.md) |
| 承接 | [SH-87](../../issues/selfhost/sh87-builtin-str-live-false-negative.md)（P1 fix） |
| 不修改 | 源码、PH-64 卡原文、主规范；只写 `battle/hw-2/`、`docs/decisions/D-007.md`、`issues/**` |
