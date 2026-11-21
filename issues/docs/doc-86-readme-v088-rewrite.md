# DOC-86 · README v0.88 大改 + §0.1 重测 + tutorial 联动

| 项 | 值 |
| --- | --- |
| 模块 | docs（门面） |
| 定性 | 文档重写（D1/D2/D3） |
| 严重度 | Medium（v1.0 前建议） |
| 锚点 | v0.88.0（2026-11-21） |
| 依据 | [外部评审与惯用卡评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md) §1 |
| 状态 | **待办（D1/D2 与 SH-110 修复进度绑定）** |

## 现象

- **D1**：README 能力清单缺 `String`/`Str`、切片、`ref`/`out`、`box`/`new`、ADT/`match`；
  §0 示例仍以 `char *` 旧风格为主；
- **D2**：§0.1 HTTP 目标链的断点表基线停在 0.44.1；期间 `$name`、String/Str、box、ADT 已落地，
  断点状态需重测；
- **D3**：tutorial 91KB 未逐字核；README 大改时叙事顺序（值→借用→句柄→ADT）需联动。

> 注：README 首行“`ct check` 只做受限语义检查”**不是事实错误**；`--types` 是可选子集。
> 可在该句后补“`--types` opt-in”，但不要改成“全量类型检查”。

## 期望

1. README 能力清单对齐 v0.88（五项新特性各一行，指向 spec 节号）；
2. §0 示例至少一个用 `String`/`Str`，一个用 `box`/`new`，一个用 ADT/`match`；
3. §0.1 断点表用 v0.88.0 重测；SH-73 已裁定为 bug（[SH-110](../selfhost/sh110-dynamic-dispatch-chain-fix.md)）：
   修复前写“动态派发链式当前被拒”，修复合入后改为“一行链可用”；静态宿主形态始终可跑；
4. tutorial 的叙事顺序与 README 同步；不重抄 spec；
5. 与 [DOC-85](doc-85-idiom-priority-card.md) 同批：README 的“先读”路径加 `idioms.md`。

## 验收

- README 中五项新特性各有可定位段落/示例；
- §0.1 每条断点有 v0.88.0 的命令/退出码；
- tutorial 的旧版本串清除；
- `check-docs` 绿；不引入未实现能力。

## 非目标

- 不在 SH-73 裁定前改“动态派发链式是否支持”的结论；
- 不重写整个 tutorial；只做与 README 冲突/过时的段落。

## 关联

- [评估](../../docs/reviews/2026-11-21-v088-external-review-eval.md)
- [SH-73](../selfhost/sh73-temp-receiver-dynamic-dispatch.md)
- [DOC-85](doc-85-idiom-priority-card.md)
- [v1-readiness-1](../../battle/v1-readiness-1/verdict.md)（非 Tier 1 门禁）
