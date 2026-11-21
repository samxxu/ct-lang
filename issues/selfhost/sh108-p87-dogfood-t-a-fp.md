# SH-108 · PH-87 dogfood 的 10 条 `T a[]` 误报（多维数组形参首维）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（A 检查器误报） |
| 定性 | bug（误报，不阻塞 PH-87 收口） |
| 严重度 | Medium |
| 锚点 | v0.87.0（2026-11-21）；A dogfood `--check-level=warn` |
| 文件 | [p87_dogfood.md](../../docs/design/p87_dogfood.md)、[PH-87 N-4](../../docs/reviews/2026-11-21-phase87-rev-verdict.md#L273) |
| 状态 | open |
| 处置证据 | **待办（DEV；A 机制误报收敛）** |

## 现象

对编译器自身跑 `--check-level=warn` 时，A 检查器报 10 条同一类误报：

```text
'T a[]' is deprecated; write 'T[]' for a slice or 'T a[N]' for an array
```

触发点是**多维数组形参/字段的首维**（如 `char x[][MAX]`），这是合法 C 的数组参数，
不是 CT 的 slice。诊断只应针对真正的 `T a[]` 声明。

证据：[p87_dogfood.md](../../docs/design/p87_dogfood.md) 的 1–10 行；
[PH-87 复核 N-4](../../docs/reviews/2026-11-21-phase87-rev-verdict.md#L273) 要求“按建议立 `SH-*`，
归 A 机制误报收敛”。

## 期望

- `T x[][N]` / 多维数组形参首维不再触发 `T a[]` 弃用警告；
- 真正的 `T a[]` 声明仍按既有文案警告；
- 对 ct-ast 自身 `--check-level=warn` 时该类别为 0 条；
- 补正负例：误报的 `char x[][MAX]` + 应报的 `int a[]`。

## 验收

- 新探针覆盖上述两例，挂 `check-ast`；
- `ct build --check-level=warn` 对 ct-ast 不再出现该 10 条；
- 既有 A 检查器负例与豁免不变。

## 关联

- [PH-87 卡](../../docs/design/phase87.md) §7.6、E87-5
- [p87_dogfood.md](../../docs/design/p87_dogfood.md)
- [v1-pre 证据](../../docs/history/v1-pre-evidence.md) 承接项 7
