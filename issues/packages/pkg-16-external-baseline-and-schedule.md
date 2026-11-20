# PKG-16 · 外部基线与跨仓时间表未核实

| 项 | 值 |
| --- | --- |
| 模块 | packages（跨仓需求） |
| 定性 | 需求缺口（提案事实未核实、跨仓无时间表） |
| 严重度 | Medium |
| 锚点 | v0.79.0（2026-11-20） |
| 文件 | [评估](../../docs/reviews/2026-11-20-pkg-contract-proposal-eval.md) §5/§7 |
| 状态 | **待办（REQ 向提案方索取）** |

## 现象

外部提案中的以下事实在本仓无法核实，且没有跨仓时间表：

- “20+ 个包”的清单与各包的索引字段分布；
- `ct-pkg/index` 现有脚本（`package-check.sh` / `gen-index.sh` / `refresh-index.sh` /
  `verify-index.sh`）的原文与边界；
- 五字段旧行清零的时间表；
- shell 侧废弃由谁、在哪个版本执行；
- push tag / 建仓库的凭据模型与最小权限。

## 期望

1. 提案方给出可核对的基线（包清单、字段分布、脚本清单）；
2. index 仓书面确认：五字段清零时间、CI 如何钉 `ct` 版本、shell 废弃条件；
3. 本仓把上述结论写进契约 §11 的归属与修订记录，不代替对方排期。

## 验收

- 契约 §6.1 的判据原文有稳定来源；
- [PKG-13](pkg-13-legacy-five-field-row-hard-error.md) 的发布前置有对方签字的时间点；
- [PKG-14](pkg-14-ph83-index-verify-and-binary.md) 的产物消费方式由 index 仓确认。

## 关联

- [评估](../../docs/reviews/2026-11-20-pkg-contract-proposal-eval.md)、[D-014](../../docs/decisions/D-014.md)
