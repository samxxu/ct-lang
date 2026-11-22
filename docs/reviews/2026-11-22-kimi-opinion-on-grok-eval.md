# 对 Kimi《对 Grok Bot 架构评估报告的评审意见》的评估

> 评估对象：Kimi 对 GrokBot v0.88.3 报告的元评审（2026-11-22）。
> 核对基线：本仓 `main`（v0.88.3）。只核对事实与行动项归属，不改代码。
> 结论先行：**方法得当、语气克制，但没有新的可执行发现**；两条事实错误，四个行动项里
> 两个已在仓库有归属/已开卡，另两个（定位表述、GPL 口径）属待裁决的文档措辞。

## 1. 事实核对

| Kimi 断言 | 仓库现状 | 结论 |
| --- | --- | --- |
| `test/run.sh` 在 Linux GCC 14 直跑 153/1/2，需在 test/README 补告诫 | 成立；但仓库已开 [TEST-26](../../issues/testing/test26-test-readme-gcc-caveat.md)（`open`，交 DEV 一行） | 方向对，**已不是“待核实”** |
| `lib/std` 与 `ct/std` 同名混淆 | [DOC-87](../../issues/docs/doc-87-lib-core-rename.md) 已排期：Stage 1 `lib/std → lib/core` + `CT_CORE_DIR`，Stage 2 `namespace core` / `core::*`；**2026-11-22 改判为当前 pre 窗口完成，不等 v1.0**；REQ 就绪，待 DEV | 正确（排期已提前） |
| `MAX_FUNCS=512`：SH-109 + LANG-24 入口判据 | 正确：[LANG-24](../../issues/lang/lang-24-box-pascalcase-rename.md) 的入口判据 1 要求开工前测 501/512 且新增 ≤ 余量；容量增长归 SH-109 | 正确 |
| SH-73 / SH-110“修复进行中，状态未翻转” | **不成立**：两张卡均为 `deferred`；[SH-110](../../issues/selfhost/sh110-dynamic-dispatch-chain-fix.md) 落 `v1-PH-0`，仓内没有修复提交或分支证据 | **事实错误** |
| 句柄层“冻结中”是 DOC-79 三档制 | [DOC-79](../../issues/docs/doc-79-stable-subset-freeze-list.md) 存在 | 正确 |
| `modern-oo-gap.md` 基线旧，报告未误当能力表 | 已加 Phase 30 基线提示，指向 capabilities/spec | 已处理 |
| 原报告“唯一新发现”是 test/run.sh | 我们独立发现了同一问题并开 TEST-26；不是该文档独有的发现 | 表述过强 |
| 第一份 Grok 报告“已驱动 7 项争议裁定” | 本仓记录的是 ChatGPT 架构评估与逐项裁决；没有“第一份 Grok 驱动 7 项”的可核记录 | 未核实 |

## 2. 四个行动项

| # | Kimi 建议 | 现状 | 处置 |
| --- | --- | --- | --- |
| 1 | test/README 补“勿直跑”告诫 | 已开 [TEST-26](../../issues/testing/test26-test-readme-gcc-caveat.md)，状态 `open` | 不重复开卡 |
| 2 | “更有结构的 C”写进 vision/patterns | [vision.md](../vision.md) 目前是“AI 时代最适合 C 开发的语言”，没有这句 | 待裁决；一句话改动，可并入文档批 |
| 3 | 原报告归档 docs/reviews/，限制声明立为模板 | 仓内归档的是**评估**（[GrokBot 评估核对](2026-11-22-grokbot-architecture-assessment-eval.md)），不是外部原文；本仓没有“原文必须入库”的先例 | 不按原建议执行；原文归档属治理政策 |
| 4 | GPL 口径在 vision.md 预置一句 | vision 没有许可段；许可口径属所有者/法务决策 | 待裁决，不擅自写 |

## 3. 可取之处

- 把 GrokBot 的“评估范围与限制”视为模板，这个方向对；本仓近几份评估已经按
  “对象 / 基线 / 方法 / 未核项”四段写，可继续沿用。
- “不是更简单的 Rust，是更有结构的 C”确实是比“C 超集”更准确的对外措辞；
  若采纳，应同时替换任何“C 超集”残留，避免两种口径并存。
- GPL 与总线因子两条是产品/治理风险，不是语言缺陷；归 vision 或 README 的“适用/不适用”
  段落比塞进 spec 合适。

## 4. 处置建议

1. **不新增卡**：TEST-26 已在；DOC-87 已覆盖 `lib/core` + `namespace core`；
   其余两项是措辞决策。
2. **纠正两处**：SH-110 不是“修复进行中”；“唯一新发现”改为“与内部独立发现重合”。
3. 若所有者要采纳 §2 的第 2、4 项，建议合并为一张 DOC 卡（vision 定位 + GPL 口径 +
   “非 Rust 替代”一句），一次改完，避免分三次动 vision。
4. 原文归档不照做：保留“外部报告 → 本仓评估”的现有模式；如要存原文，另定治理规则。

## 5. 关于 `lib/std → lib/core` 的说明

这条**没有被忽略**：DOC-87 的决策表同时写了两阶段——

- **Stage 1**：目录 `lib/std → lib/core`，`CT_STD_DIR → CT_CORE_DIR`（保留一个 MINOR 回退），
  9 个代码文件 + 21 个脚本 + 12 个活跃文档的替换清单与两条预写验收已就绪；
- **Stage 2**：内置层声明 `namespace core`，编译器解析改为 `core::Vec` / `core::String` /
  `core::box`，根命名空间别名/预导入保留一个 MINOR。

两张都未执行（`ls lib/core` 不存在、`CT_CORE_DIR` 0 命中），但**已排当前 pre 窗口**
（2026-11-22 所有者改判，不等 v1.0 窗口）。所以当前活跃文档仍必须写 `lib/std`；本轮已在
[glossary](../glossary.md#L21) 与 [DOC-93](../../issues/docs/doc-93-std-arena-doc-consistency.md)
补了指向 DOC-87 的说明，避免把“现行名”误读成“忽略迁移”。
