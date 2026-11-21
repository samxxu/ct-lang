# battle: PH-86 S86c 的 `?`/errdefer 与引导链约束

- 日期：2026-11-21
- 状态：**open（待 REVIEW/EDITOR 判决）**
- 关联：[phase86 卡](../../docs/design/phase86.md) §2 S86c、[D-017](../../docs/decisions/D-017.md)、
  [D-018](../../docs/decisions/D-018.md)、[p85_spike](../../docs/design/p85_spike.md) §3、
  [p86_errors.md](../../docs/design/p86_errors.md)。

## 争点

卡 §2 要求 S86c 做 `?`/errdefer 改造（`p86_errors`）。但 ct-ast 由 L2 引导构建，
L2 不实现 PH-40 `errdefer` 与 PH-44 后缀 `?`；把这两个构造写进 ct-ast 源码，
L2 会原样输出、`cc` 失败（`test/probes/p86_bootstrap_evidence.txt`）。

## 候选

| # | 方案 | 代价 |
| --- | --- | --- |
| A | 本卡不改造，交付错误出口清单 + 345 条诊断逐字对照；把 `?`/errdefer 的适用性登记为限制，移交 PH-87/88 开卡前裁定 | 卡 §2 的字面要求未做；需 REVIEW 在 §7 认账 |
| B | 先给 L0/L1/L2 补 PH-40/PH-44，再在 PH-86 用 `?`/errdefer | 改冻结层、跨 phase，远超本卡预算；会改 L2 产物与 golden |
| C | 只在测试夹具里用 `?`/errdefer 冒充改造 | 不改变编译器错误路径，等于假绿 |

## 待判

选 A 是否成立；若选 A，PH-87/88 的同名判据是否同步降级，由 REQ 在开卡前裁定。
