# DOC-15 · issues / reports 仍大量指向已消失的 `selfhost/ast/**`、`selfhost/src/**`

| 项 | 值 |
| --- | --- |
| 模块 | docs |
| 严重度 | **Medium** |
| 锚点 | commit `4ef8b68`（2026-10-21） |
| 文件 | [issues/README.md:156](../../issues/README.md#L156)、[:165](../../issues/README.md#L165)、[:166](../../issues/README.md#L166)；[reports/phase9-review/phase9-review.md](../../reports/phase9-review/phase9-review.md) 多处 |
| 状态 | ✅ 已修复（2026-10-21；验证见 [issues/README.md](../README.md) 的「Phase 12 复审」一节） |

## 现象

- `issues/README.md` 的 Phase 9 复审段落引用 `selfhost/ast/main.ct#L821-L827`、`selfhost/ast/main.ct` 等路径；`reports/phase9-review/phase9-review.md` 全篇以 `selfhost/ast/main.ct`（约 4 536 行、单文件）为对象。
- 这些路径在目录重组后已不存在：当前主线是 `selfhost/ct-ast/**`（20 个单元、约 9 672 行），旧管线在 `selfhost/l2/**`。
- `issues/README.md:166` 把「驱动诊断前缀 `ct-ast:`」列为待修；实测出厂二进制已输出 `ctc:`（见 `issues/selfhost/ct-error-prefix.md` 的 SH-3 决策），该条目实际已关闭但未回填。

## 影响

历史结论无法回查（链接全 404）；已修复条目仍挂在"待修"语境里，会让维护者重复排查。

## 修复建议

保持历史正文不动，做两件事：

1. 在两个文件顶部加一行横幅：「历史快照（2026-10-21）：`selfhost/ast/**`、`selfhost/src/**` 已不存在，等价路径为 `selfhost/ct-ast/**` 与 `selfhost/l2/**`；条目状态未回填」；
2. 在 `issues/README.md` 的模块索引里，给 SH-3 / 前缀条目补「✅ 已关闭（前缀已为 `ctc:`）」。

## 验证

`grep -rn 'selfhost/ast/' issues reports | wc -l` 的命中处均处于带横幅的历史段落内；索引不再有"待修但实际已修"的条目。
