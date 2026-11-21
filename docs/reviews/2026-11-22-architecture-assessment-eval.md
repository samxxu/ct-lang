# 对《CT-Lang 现代语言架构评估报告》的评估

> 评估对象：ChatGPT 架构评估报告，快照 **v0.88.3**（2026-11-22）。
> 本仓核对基线：评估当日工作树（`main.ct` 的 `CTC_VERSION "0.88.3"`），未改动源码。
> 评估性质：事实核对 + 处置建议；不替代 battle/ADR，也不把报告建议直接提升为 v1.0 工作。

## 1. 总评

**这是一份可信度较高的外部架构评审，不是逐行审计。** 它对项目定位（C 后端、C ABI 交付边界、
C Shim 一等模式）的判断与仓库实际一致；对证据等级（Renode ≠ 真板、issue 标题 ≠ 当前缺陷）
的自我约束也符合本项目自己的证据纪律。

主要价值在三处：

1. 把“生成 C”从宣传语拆成可验收的架构条件（语义一致、无隐藏分配、清理顺序、ABI、机器码证据）；
2. 明确指出 emitter 是语义泄漏点，建议 Typed/Lowered IR 与统一清理 CFG；
3. 把“能力矩阵 / 能力—规范—测试—issue 关联”提为治理基础设施。

主要局限：快照阅读、未重跑门禁；部分“建议建立”的东西仓库里已经存在；有一处 P0 的判断
需要改写为“口径不一致”而不是“机制缺失”。

**评估可信度：约 8/10。** 结论方向可用，但不能按报告的建议清单直接开新一批 v1.0 工作。

## 2. 事实核对：准确的断言

| 报告断言 | 仓库证据 | 判定 |
| --- | --- | --- |
| 版本 v0.88.3 | `selfhost/ct-ast/main.ct` 的 `CTC_VERSION` | ✅ |
| 常规 `ct build` 不默认跑完整类型检查 | [spec §1](../language-spec.md) 的 `--check-level=off\|warn\|error`：`off` 默认；PH-85 只交付机制 | ✅ |
| `--lib`/ABI 头与 `pub` 不是同一件事 | `--lib` 已实现并写 `.abi.h`；导出集只收**根单元**的 `pub` 函数，非 C 兼容类型硬错（`Module.h.ct` 的 `abi_exports` 构建段） | ✅（但措辞需校正，见 §3） |
| P39-1 否定“全量 `pub` 自动导出”的主张 | [p39-1 判决](file:///Users/samxx/dsh-ws/ct-lang/battle/p39-1/verdict.md)：`verdict: rejected`，C 方案待单方案评审 | ✅ |
| 内建单元判活仍靠源码文本 | `Driver.h.ct` 的 `src_has_word` / `src_has_prefix` / `src_has_box_type` 驱动 `builtin_live_for` | ✅（导入本身走语义单元表） |
| LANG-20 已判 rejected | [LANG-20](../../issues/lang/lang-20-container-method-args-unchecked.md)：真实错配由 `ct check --types` 报错 | ✅ |
| JSON 诊断 parse 通道仍回退文本 | [LANG-10](../../issues/lang/lang-10-machine-readable-diagnostics.md)：`deferred`，7b 未完成 | ✅ |
| DMA 真搬运 hardware-gated | [TEST-22](../../issues/testing/test22-dma-real-transfer-hardware-gated.md)：只验描述符寄存器 | ✅ |
| 没有 Typed IR / CFG；emitter 直接吃 AST | `backend/` 只有 `emit` 与 `mem`，无 IR 层 | ✅ |
| `borrow` 仍在语言里（旧指针层） | [spec §4.40](../language-spec.md) | ✅ |
| 默认构建与 strict 的边界需要产品契约 | 见 §3 第 4 条：机制已有，**我们自己的 plan 两处口径不一致** | ⚠ 部分准确 |

## 3. 需要校正或过时的判断

1. **“建议建立 capability registry”已经存在。** 仓库已有
   [capabilities.tsv](../capabilities.tsv)（20 项能力 → spec 节号）、
   [stable-subset.md](../stable-subset.md)（28 条冻结分档）、
   [J-6 证据台账](../planning/j6-evidence/ledger.md)（34 项）。真正的缺口不是“没有表”，
   而是“issue 状态 / 回归测试 / 首个支持版本”还没有并进同一张机器可读表；J-6 正在做前两项。

2. **“C ABI 尚未实现、只停留在讨论”不准确。** `--lib` 与 `.abi.h` 已经实现；当前实现是
   **根单元 `pub` 全收 + 非 C 兼容类型硬错**，导入/`extern` 的 `pub` 不计入导出面。
   所以问题不是“没有 ABI”，而是“**没有显式导出选择**”——报告引用的 P39-1 C 方案正是为此待评审。
   报告里“所有 `pub` 都算 ABI”应改为“根单元 `pub` 全收”。

3. **“文档一致性 7.0 / 维护者容易误读”部分成立，但低估了现有机器护栏。**
   现在 `check-docs` 已咬住：相对链接、门禁条数、能力→节号双向、稳定子集三档、
   三处兼容声明一致性、briefing 每条 `§N`、J-6 行状态。历史材料仍然多，但“静默漂移”
   的主要入口已被门禁覆盖；评分可视为快照判断，不代表当前。

4. **P0「默认构建与严格类型检查边界不清」应改写为「口径需要统一」。**
   机制与 CLI 契约都在（`off` 默认、`warn` 不阻断、`error` 阻断），但
   [v1-release-plan](../planning/v1-release-plan.md) 第 137 行写“v1-pre 窗口内默认 warn”，
   与“CLI 默认 off”读起来像两个默认值。正确表述应是：
   **CLI 默认 `off`；v1-pre 的 CI/发布门禁以 `warn` 跑；v1.1 S2 再把默认升为 `error`。**
   这是本轮评估里最值得马上修的一条内部一致性问题。

5. **“issue 台账需要状态 + 最后验证日期”**：状态闭集已由 CI-10/11 落地（G1/G6 + 首轮归一），
   但“最后验证日期”仍不是强制字段；这条建议可以作为 G6 的后续增强，而不是新问题。

6. **报告里的 `lib/std` 是快照事实**：本仓 Stage 1 已立项改 `lib/core`
   （[DOC-87](../../issues/docs/doc-87-lib-core-rename.md)），迁移卡已细化、待 DEV 窗口。
   评估结论中的路径引用不应被当作 v1.0 的最终拼写。

## 4. 建议处置

| 报告建议 | 处置 | 理由 |
| --- | --- | --- |
| 明确 `build/check/types/strict` 契约 | **接受，先修口径** | 机制已有；统一 CLI 默认与 v1-pre 门禁口径，不新增机制 |
| C Shim Contract 正式规范 | **已立项（v1.1）** | 已开 [DOC-91](../../issues/docs/doc-91-c-shim-contract.md)；不新增语言关键字 |
| C Interop Semantics Matrix | **已立项（v1.1）** | 已开 [DOC-92](../../issues/docs/doc-92-c-interop-semantics-matrix.md)；并入现有文档，不另起平行清单 |
| capability registry 关联 issue/测试/版本 | **已在做，扩展 J-6** | 不新开表；把 issue 状态与回归测试列补进 J-6 |
| 独立 ABI export 契约 | **已有 P39 C 方案，等待评审** | 不另开新设计；先完成 P39 C 的单方案评审 |
| 语义引用图替代文本判活 | **hw-2 C 方案内推进** | 文本判活是已知边界；不在 v1.0 重写依赖图 |
| Typed/Lowered IR + 统一清理 CFG | **v1.2 方向；v1.1 先做轻量不变量** | 完整 IR 属重写，不占 v1.0/v1.1；轻量规则见 [SH-111](../../issues/selfhost/sh111-lowering-invariants.md)，完整 IR 见 [SH-112](../../issues/selfhost/sh112-typed-ir-architecture.md) |
| 所有权 / 异步 / DMA 生命周期 | **并入 DOC-91 + TEST-22** | shim 契约硬条款（提交即转移、完成即归还、ISR 上下文）；语言层不新增关键字 |
| JSON 诊断全通道 | **v1.1 补 parse JSON；v1.2 code registry** | parse 7b 归 v1.1；稳定 code 归 v1.2（[LANG-10](../../issues/lang/lang-10-machine-readable-diagnostics.md) / [LANG-25](../../issues/lang/lang-25-diagnostic-code-registry.md)） |
| 真板 UART/RTOS/DMA | **TEST-22 既有 hardware-gated** | 证据等级已标注；真板属外部条件 |
| 包 conformance / 离线回放 | **PKG-17 既有** | vendored fixture + 三断言已立项 |
| formatter / LSP / debugger mapping | **v1 之后** | 不进入 v1.0 范围 |

**不建议照单全收的两项**：

- 把 strict 默认强制拉进 v1.0：与冻结期和现有 FP 证据冲突，已定 v1.1 S2；
- 在 v1.0 前引入 Typed IR：收益真实，但属于编译器重写，应作为 v2 架构议题立项，而不是 v1 门禁。

## 5. 对评分的意见

- **7.4/10 的综合分合理**，作为“工程化语言项目成熟度”而非“生产安全等级”是恰当的。
- **测试 8.5** 略乐观：本机 `check-ast` 仍有 1 项 Renode 环境性失败；
  但门禁层次与负例纪律确实强，8.0–8.5 都可接受。
- **文档一致性 7.0** 对快照成立；按当前机器护栏，实际应更高，但历史材料体量仍是真实负担。
- **所有权 5.8、嵌入式 6.5** 与仓库现状吻合：没有 Rust 式借用检查，真板证据仍缺。

## 6. 需要所有者裁决的两件事

1. **默认值口径**：是否按“CLI 默认 `off`；v1-pre 的 CI/发布门禁 `warn`；v1.1 S2 升 `error`”
   定稿，并据此修 v1-release-plan 第 137 行的表述？
2. **两张 v1.1 文档卡**：C Shim Contract 与 C Interop Semantics Matrix（并入现有文档）
   是否现在开卡？其余建议均已有归属，不新开。
