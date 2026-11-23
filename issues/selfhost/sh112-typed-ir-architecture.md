# SH-112 · v1.2 Typed/Lowered IR 架构议题

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（编译器架构） |
| 定性 | 架构方向（重写级） |
| 严重度 | Low（长期） |
| 锚点 | v0.88.3（2026-11-22，外部架构评估 P1） |
| 依据 | [SH-111](sh111-lowering-invariants.md)、[架构评估](../../docs/reviews/2026-11-22-architecture-assessment-eval.md) |
| 状态 | verified |
| 处置证据 | **设计阶段验收完成（2026-11-23）；实施 deferred 到 v1.2 `v1-PH-2`；仓库当前无 IR 代码** |

## 现象

`backend/` 只有 `emit` 与 `mem`，没有独立 IR；emitter 同时承担类型重猜、泛型实例化、
值类别与清理路径决策。随着语言能力组合增长，特殊分支会持续累积。

## 期望（v1.2，先设计后实施）

1. **Typed/Lowered IR**：表达式类型、值类别、泛型替换结果、临时值生命周期显式化；
2. **CFG 与统一清理**：`Drop`/`defer`/`errdefer` 在统一清理 CFG 中插入，
   `return`/`break`/`continue`/`goto` 生成清晰清理边；
3. **emitter 契约**：只消费已验证 IR，不再自行猜类型/实例化/生命周期；
4. **不变量验证器**：发射前检查 IR 不变量；失败给稳定诊断，不产出 C；
5. **迁移路径**：IR 落地前后生成 C 的兼容/回归策略，golden 与自举链的切换方案；
6. **语义依赖图**：内建单元/泛型实例化的语义引用图，替换文本判活（与 [SH-113](sh113-builtin-live-boundary.md) 边界测试衔接）。

## 非目标

- 不进入 v1.0 冻结期，也不作为 v1.1 发布门禁；
- 不做优化器、不改 C ABI、不改用户语法；
- 不以“重写”为由放宽既有行为等价要求。

## 验收（设计阶段）

- 独立 proposal：IR 形态、边界、迁移、回滚、成本；
- 至少一张“现状 AST→C”与“IR→C”对照表；
- 通过 battle/ADR 后再排实施；
- 实施后：既有语料生成 C 行为等价、自举不动点、golden 重基线有差异清单。

## 排期

v1.2（`v1-PH-2`）；先设计，不占 v1.0/v1.1。


## 处置（REQ，2026-11-22）：deferred

- 触发：**v1.2 架构设计窗口**
- 范围：Typed/Lowered IR 设计
- 依据：本卡「处置证据」已标 `v1.2` 立项、不阻塞 v1.0；v1.0/v1.1 冻结期不排工。
- 触发时：改回 `open`，按本卡验收执行；不提前扩围。

## 设计阶段验收（ARCH/REQ，2026-11-23）

- 提案：[typed-lowered-ir.md](../../docs/proposals/typed-lowered-ir.md) —— IR 形态（TIR/LIR）、
  CFG 与统一清理、emitter 契约、不变量验证器、迁移 / golden / 自举 / 回滚、语义依赖图，
  以及「现状 AST→C」与「IR→C」对照表（提案 §6）。
- 决策：[D-026](../../docs/decisions/D-026.md) —— 设计选择与被否方案、实施前置（v1.1 稳定、
  SH-111 剩余项、容量、seed/golden、施工卡）与不实施时点。
- 结论：**设计阶段验收通过；未实施**。仓库当前 `backend/` 仍只有 `emit` 与 `mem`，
  没有 TIR/LIR/IR verifier；本卡不改代码、不改版本号、不开施工卡。
- 实施时点：v1.2（`v1-PH-2`）。触发条件与前置见 D-026 §4/§6；不满足则继续 deferred。
- 验证：`tools/check.sh g0` / `g1` / `g4` 全绿（2026-11-23；原始输出见提交正文）；
  本卡仅改设计与台账，无代码。
- 状态：**保持 `deferred` 不变**；集成后由 REV 按设计验收标准复核。触发时改回 `open`，
  先开 `v1-PH-2` 卡再实施，不提前扩围。


## 复核（REV，2026-11-23）

设计阶段验收完成：`docs/proposals/typed-lowered-ir.md`（TIR/LIR 两层、非 SSA、统一清理、验证器、迁移/回滚、对照表）+ `docs/decisions/D-026.md`。仓库仍无 IR 代码，实施 deferred 到 v1.2 `v1-PH-2`；本卡按设计验收置 verified，实施另由 D-026 前置与施工卡跟踪。
