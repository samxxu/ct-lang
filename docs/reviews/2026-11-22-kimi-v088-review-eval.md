# 对 Kimi《ct-lang v0.88.0 全面评审报告》的评估

> 评估对象：Kimi 外部评审（基线 v0.88.0，2026-11-21；含 2026-11-22 附录修订）。
> 核对基线：本仓 `main`（本轮 `46838951`）。只核对事实与时效，不改代码。
> 结论先行：**这不是对 GrokBot 报告的评阅**——全文没有引用 GrokBot 的任何断言，也没有逐条回应；
> 它是一份独立的 v0.88.0 全面评审。作为后者，文档面定位准、四项修正正确；但 **附录有 3 处引用
> 未落地、1 处旧数字未回改**；CLI 默认一项已被所有者裁决提前采纳（见 §5）。

## 1. 与 GrokBot 报告的关系

用户的目标若是“Kimi 评 GrokBot”，本文**答非所问**：

- 正文与附录均未出现 GrokBot、其快照 `c993f41`、或它的三条可争议结论
  （内置层是否占 `MAX_FUNCS`、`atomic` 分类、issues 计数）；
- 它评的是 v0.88.0 的治理/文档/缺陷面，GrokBot 评的是 v0.88.3 的架构与成熟度；
- 两者唯一重叠的是「默认检查、`MAX_FUNCS`、SH-73/110」几个信号，Kimi 的版本还把
  `MAX_FUNCS` 写成了旧数（见 §3）。

因此：**要判断 GrokBot 报告准不准，应看 [GrokBot 评估核对](2026-11-22-grokbot-architecture-assessment-eval.md)；
本文只回答“Kimi 这份 v0.88.0 评审本身是否准确”。**

## 2. 事实核对（v0.88.0 基线 → 当前）

| Kimi 条目 | 基线是否成立 | 当前状态 | 结论 |
| --- | --- | --- | --- |
| D1 README 能力清单缺 String/Str、切片/ref-out、box/new、ADT/match | **部分成立**：缺前两项与 ADT（3 项）；`box/new` 在 §3 已有「单对象句柄」 | 五项全部在 §3；新增 §0.5 句柄速览 | 有效，已基本闭环 |
| D1 README 首行「`ct check` 只做受限语义检查」过时 | **不成立**：该句对 `ct check` 仍准确；问题是没提 `--types` | 已补 `ct check --types` 指针 | 表述改为“缺指针”更准 |
| D1 §0 示例全 `char *` 旧风格 | 成立 | 已加 §0.5 三个句柄小程序；§0.1 仍是旧形态 | 部分闭环 |
| D2 §0.1 基线停在 0.44.1，需重测 | 成立 | 仍为 0.44.1；唤醒条件 = SH-110 合入后 48h | **仍开放**，已排期 |
| D3 tutorial 未逐字核 | 自述限制 | 未复核 | 不影响主结论 |
| D4 patterns「语言没有动态容器」 | 成立（v0.88.0 原文） | 已改为“`Vec`/`Map` 是内建动态容器，接口数组仍固定容量” | 已闭环 |
| D5 package-guide 标签滞后 | 成立（仅 `Phase 18.1`） | 已补 2026-11-21 按 v0.88.1 复核；未再出现 `v0.58.0` | 已闭环 |
| D6 memory-guide 缺范围声明 | 成立 | 已加“新代码先读 guide-for-c-programmers；本文保留指针层” | 已闭环 |
| D7 spec 巨石是否拆 | 成立 | [DOC-88](../../issues/docs/doc-88-spec-split-decision.md) 已定 A+（不拆、节索引、行号锚点 ratchet），v1.1 执行 | 与现行决策一致 |
| D8 / A1 `lib/std` → `lib/core` | 所有者已定 | [DOC-87](../../issues/docs/doc-87-lib-core-rename.md) REQ 就绪，待 DEV 窗口 | 一致 |
| A3 SH-73「修/不修冲突」 | 成立（当时的账面冲突） | 已消解：SH-73 裁定 bug，修复由 [SH-110](../../issues/selfhost/sh110-dynamic-dispatch-chain-fix.md) 承接，落 `v1-PH-0` | 附录正确 |
| §6 四条对外文档修正 | 全部成立 | 与 spec §4.68 / §4.69 / §4.73 / §4.71 逐条一致 | 可采信 |

## 3. 明确错误或过期

| # | Kimi 原文 | 实际 | 影响 |
| --- | --- | --- | --- |
| 1 | §1「`MAX_FUNCS` 余量 **475/512**（仅剩 37 槽）」 | PH-88 后实测 **501/512、余 11**；我们已在 [2026-11-21 外部评估](2026-11-21-v088-external-review-eval.md) 与 [full-review 处置](2026-11-21-full-review-v0.88.0-disposition.md) 中勘误过 | 旧数复现；附录称“已修订”却未回改此条 |
| 2 | §1「selfhost 40+ 条记录」 | v0.88.0 基线已有 **106** 个 selfhost 卡；当前 114 | 低估台账规模 |
| 3 | §2.1「文档 README 新增**七条**机器校验约定」 | 基线 7 条成立；当前已扩到 **8 条**（briefing↔spec 同步） | 只是时效，不属错误 |
| 4 | 附录「**v1.0 CLI 默认 warn**（用户批准 11-22）」 | **方向被接受、时点提前**：下一 v0.x 起 CLI 默认 `warn`（SH-115）；v1.1 S2 升 `error` | 已按 §5 落库，不再是冲突 |
| 5 | 附录「Grok v2 零代码补足清单 12 条」「ct-gen 独立项目」 | 仓内没有对应文件（`docs/planning/**`、`issues/**` 均无） | 未落地，不能引用 |
| 6 | 附录「节点转换协议 v1.0 一步到位 W0–W5，待转 DeepSeek」 | 已被所有者裁决取代：[LANG-26](../../issues/lang/lang-26-binding-site-conversion.md)（v1.1 ADR）+ [PKG-24](../../issues/packages/pkg-24-json-node-arena.md)（包侧、v1.0 前） | 过期；W1 不进 v1.0 |
| 7 | 附录「SH-110（修复中）」 | 卡面状态是 `deferred`（排 `v1-PH-0`，未实现） | 小误差，避免写成“进行中” |

另有内部一致性问题：附录声称“取代正文中已被覆盖的判断”，但 §1 的 475/512、
§7 的批 1–批 4 排期都没有回改；正文与附录并存时读者会得到两套口径。

## 4. 可取之处

- **文档面定位准**：D4/D5/D6 三条都是“小改但真实”的漏洞，且已被逐条修掉；
  D1 把 README 门面问题拆成“能力清单 / 示例 / §0.1 基线”三层，比笼统说“README 过时”有用。
- **A3 的前置判据建议正确**：先做求值顺序与临时值生命周期判据，再动发射器；这条已被
  SH-110 的卡面吸收（求值顺序、只求值一次、golden 重跑）。
- **§6 四条修正全部与 spec 对齐**：`out` 的 trivial/owning 初始化差异、`T a[] = {...}`
  保留、ADT 限定名与 `_` 末位、box 双指针 16 字节；可直接用作对外速览的勘误。
- **总评口径成立**：“治理成熟度显著高于代码规模”“剩余工作可枚举”“无架构级 v1.0 阻断”。
  这与 GrokBot 的“无新架构项”结论一致；但要注意 Kimi 没展开 AST→C 无 IR 的实现债，
  这部分仍由 SH-111/SH-112 承接。

## 5. 所有者裁决（2026-11-22）

Kimi 附录第 1 条「v1.0 CLI 默认 `warn`」方向被接受，但**时点提前**：所有者裁定“要强化类型检测，
不能等 v1-pre 就要实现”。落点：

| 项 | 现行口径 |
| --- | --- |
| CLI 默认 | **下一 v0.x 起 `warn`**（与 [SH-115](../../issues/selfhost/sh115-b-plus-strengthening.md) 同批；`--check-level=off` 保留逃生） |
| 强化范围 | SH-60 的 1a/1b/2b、函数指针字段残留、泛型/ADT/字段初值可判定错配 |
| 发布门禁 | FP=0 前 `warn`，FP=0 后 `error`；FP=0 仍是 v1.0 硬门禁 |
| v1.1 S2 | CLI 默认升 `error`；未达标回退“可用不默认” |

已同步：[spec §1](../language-spec.md#L62-L78)、[v1-release-plan §2.4](../planning/v1-release-plan.md#L129-L151)、
[stable-subset](../stable-subset.md#L50)、[SH-115](../../issues/selfhost/sh115-b-plus-strengthening.md)。

## 6. 处置建议

1. **除 SH-115 外不新增卡**：D4/D5/D6 已闭环；D1 剩余项（§0.1 重测）由 SH-110 唤醒；
   D2/D3 已在 plan 或自述限制内；类型检测强化由 [SH-115](../../issues/selfhost/sh115-b-plus-strengthening.md)
   单卡承接。
2. **不采用附录的 3 条旧口径**（Grok v2 清单、ct-gen、节点协议 v1.0 一步到位），
   对外引用以本仓当前 spec/plan 与 [LANG-26](../../issues/lang/lang-26-binding-site-conversion.md) /
   [PKG-24](../../issues/packages/pkg-24-json-node-arena.md) 为准；CLI 默认一项按 §5 的提前版落地。
3. **Kimi 若作为“GrokBot 评阅”使用，应退回重做**：需要逐条回应 GrokBot 的三处可争议结论
   （见 [GrokBot 评估核对](2026-11-22-grokbot-architecture-assessment-eval.md) §2），本文没有做。
4. **§6 四条勘误可保留**为对外速览的修正依据，无需改 spec。
