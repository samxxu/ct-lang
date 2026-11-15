# 路线图

> 中文

本文只做**简要罗列**：阶段、主题、状态、收口版本、详情入口。逐相流水账、版本记录与已定决策见
[history/phase-log.md](history/phase-log.md)。当前已实现能力见 [README](../README.md) 与
[language-spec](language-spec.md)。

---

## 中文

### 阶段总览

| 阶段 | 主题 | 状态 | 收口版本 | 详情 |
| --- | --- | --- | --- | --- |
| Phase 0 | 完整 OO（trait/接口/派发） | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 0.1 | 缺陷修复与回归 | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 0.2 | 接口多态 | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 0.3 | 剥离越位特性 | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 1 | 自举（L1 逐字节一致） | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 2 | 模块化（namespace/import） | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 3 | 内存（Drop/delete） | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 4 | 诊断与溯源 | ✅ 完成 | v0.4.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 5 | AutoDrop/泄漏分析/目录即 namespace | ✅ 完成 | v0.5.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 6 | map/方言/增量缓存 | ✅ 完成 | v0.6.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 7 | 单入口 ct | ✅ 完成 | v0.7.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 8 | 包管理 ct-pkg | ✅ 完成 | v0.8.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 9 | AST 版编译器（新主线） | ✅ 完成 | v0.9.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 10 | 主线切换 ct-ast | ✅ 完成 | v0.10.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 11 | map 构造 | ✅ 完成 | v0.11.x | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 12 | bindings + 方言 | ✅ 完成 | v0.12.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 17 | 工程质量 + std/raw/文档门禁 | ✅ 完成 | v0.17.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 18 | 生态建设（ct-pkg 包族） | ✅ 完成 | v0.18.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 19 | 受限语义检查 | ✅ 完成 | v0.19.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 20 | 包支持 | ✅ 完成 | v0.20.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 21 | 非逃逸栈闭包 | ✅ 完成 | v0.21.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 22 | loop(n) | ✅ 完成 | v0.22.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 23 | loop(a..b) | ✅ 完成 | v0.23.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 24 | 数组 range 初值 | ✅ 完成 | v0.24.0 | [流水账](history/phase-log.md#阶段总览详表) |
| Phase 25 | 静态映射闭包实参 | ✅ 完成 | v0.25.0 | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase25.md) |
| Phase 26 | 泛型函数 | ✅ 完成 | v0.26.x | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase26.md) |
| Phase 27 | foreach | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase27.md) |
| Phase 28 | 约束泛型 | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase28.md) |
| Phase 29 | 泛型 struct + Vec/Map | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase29.md) |
| Phase 30 | into 块 | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase30.md) |
| Phase 31 | 容器能力补齐 | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) · [设计](history/design/phase31.md) |
| Phase 32 | `ct check --types` 类型安全检查网 | ✅ 完成 | v0.33.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase32-draft.md) |
| Phase 33 | 有界泛型 struct + 嵌套 impl | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase33-draft.md) |
| Phase 34 | pub 泛型 / 固有 impl / Option/Result | ✅ 完成 | v0.34.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase34-draft.md) |
| Phase 35 | 泛型 trait | ✅ 完成 | v0.35.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase35-draft.md) |
| Phase 36 | 泛型 Drop + Str | ✅ 完成 | v0.36.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase36-draft.md) |
| Phase 37 | trait 签名硬错 + runtime checks | ✅ 完成 | v0.37.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase37-draft.md) |
| Phase 38 | defer 块级清理 | ✅ 完成 | v0.38.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase38-draft.md) |
| Phase 39 | C ABI 导出面与库制品 | ✅ 完成 | v0.39.0 | [卡](design/phase39-draft.md) |
| Phase 40 | errdefer + err: 错误出口 + 尾随声明 | ✅ 完成 | v0.40.0 | [卡](design/phase40-draft.md) |
| Phase 41 | 原子并发能力（`atomic T` + 内建原子操作） | ✅ 完成 | v0.41.0 | [卡](design/phase41-draft.md) · [D-004](decisions/D-004.md) |
| Phase 42 | `impl` 方法可见性（方法级 `pub`，默认私有） | ✅ 完成 | v0.42.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](design/phase42-draft.md) |
| Phase 43 | 错误出口类型契约（`return err:` 载荷检查） | ✅ 完成 | v0.43.0 | [卡](history/design/phase43.md) |
| Phase 44 | `?` 错误传播运算符（后缀 `?`，同 `E`） | ✅ 完成 | v0.44.0 | [卡](history/design/phase44.md) |
| Phase 45 | 类型契约一致性（闭包 `return` 与指针基类型判据） | ✅ 完成 | v0.45.0 | [卡](history/design/phase45.md) |
| Phase 46 | `Map` 元素完整性（用户 struct 按值入 `Map`，`ct build` 可编译） | ✅ 完成 | v0.46.0 | [卡](history/design/phase46.md) |
| Phase 47 | 容器键协议（`Str` 键深拷贝；`put_owned` 已删） | ✅ 完成 | v0.47.0 | [卡](history/design/phase47.md) |
| Phase 48 | Drop 语义闭环（指针字段胶水 + 跨单元 Drop 体） | ✅ 完成 | v0.48.0 | [卡](design/phase48.md) |
| Phase 49 | `own` 所有权转移（初始化式接工厂返回值） | ✅ 完成 | v0.49.0 | [卡](design/phase49.md) |
| Phase 50 | 容器取用契约（`has` / `at`；出参形态已废） | ✅ 完成 | v0.50.0 | [卡](design/phase50.md) |
| Phase 51 | 指针接收者 `.` 调用的发射缺陷（链式前置） | ✅ 完成 | v0.51.0 | [卡](design/phase51.md) |
| Phase 52 | 自定义类型下标 `[]`（方案 A，只主张单层字符串键） | ✅ 完成 | v0.52.0 | [卡](design/phase52.md) |
| Phase 53 | 可选链 `?.`（指针 / map；值上取到的指针或 map 跳） | ✅ 完成 | v0.53.0 | [卡](design/phase53.md) · [记录](proposals/phase53-optional-chain-draft.md) |
| Phase 54 | ct-pkg 共享库包体系（工具侧：store / lock v2 / `ns-root`） | 🟨 实施中（S0–S3、S5/S6 仓内完成；S7 待兼容期） | v0.54.0–v0.58.0（S0–S3、S5/S6 各一个 MINOR；偏移见 AGENTS §0.3） | [卡](design/phase54.md) · [提案](proposals/ct-pkg-shared-store.md) · [需求](planning/ct-pkg-shared-store-requirements.md) |
| Phase 57 | 限定名与 namespace 常量（类型位置 `A::B`、值位置 `Type::Member`；SH-18 + LANG-15） | ⬜ 规划中（未开卡） | v0.59.0 | [重排](planning/post-58-plan.md) |
| Phase 59 | 模型导出 `--emit-model`（S0：无 import 单单元端到端） | ⬜ 规划中 | v0.60.0 | [卡](design/phase59.md) · [提案](proposals/ct-model-export-proposal.md) · [决策](design/static-mapping-feasibility.md) · [重排](planning/post-58-plan.md) |
| Phase 60 | 视图节点注记（`view` 子句） | ⬜ 待确认消费者（无消费者则不立相） | 条件位 v0.61.0（跳过则不占位） | [提案](proposals/ct-view-annotation-proposal.md) · [重排](planning/post-58-plan.md) |
| Phase 62 | 容器下标可写与嵌套链（吸收 PH-61） | ⬜ 规划中（仅提案） | v0.62.0（PH-60 跳过时 v0.61.0） | [提案](proposals/ct-writable-subscript-proposal.md) · [重排](planning/post-58-plan.md) · [序列](planning/post-58-phase-sequence.md) |

> Phase 13–16 未使用；Phase 27–30 合并为 v0.30.0 发布，Phase 31–33 合并为 v0.33.0 发布（Phase 31 / 33
> 未单独 bump）。逐相细节与出口证据见 [流水账](history/phase-log.md#阶段总览详表)。
>
> **Phase 45–52 已收口**（v0.45.0–v0.52.0）；Phase 50–52 的卡面、修法与判据按
> [裁决记录](reviews/phase46-52-freeze-verdict.md)改定（73 条输入：采纳 67 / 部分 6 / 不采纳 1），
> 五条待裁项全部按建议值签字。总排期与依赖见 [phase46-52-plan.md](design/phase46-52-plan.md)，
> 施工入口见 [phase46-52-handoff.md](design/phase46-52-handoff.md)。
> 45–49 的流程缺口（无 T-7 红证父提交、正文 `red: n/a`）已在
> [plan §13.1](design/phase46-52-plan.md) 登记，不补造红证；
> 数字下标（`v[0]`）的参数类型匹配登记为 [REQ-JSACCESS-1](planning/requirements-pool.md)，
> 属「JS 风格访问」长期目标，**不占相号、不得砍掉**。
> `?.` 可选链经第二轮 battle 定稿为 **Phase 53 施工**：只收指针 / map，struct 值接收者拒绝；
> 切词按 parser 组合识别（`c?.5 : 1.0` 保持三目），见 [施工卡](design/phase53.md)。
> 原记录保留为设计依据；其余候选（DF-1/2/3、REQ-JSACCESS-1 等）留需求池或后续相，不占 PH-53。

### ct-pkg 共享库包体系（Phase 54，S0–S7）

契约变更：以 `ct.pkg` 的 `ns-root` 取代「包根 = 单元根」的隐含约定，`ct install` 的 `-I vendor/<name>` 输出契约作废。判据见[需求定稿](planning/ct-pkg-shared-store-requirements.md)，条款见[提案](proposals/ct-pkg-shared-store.md)。

| 切片 | 主题 | 版本位 | 前置 | 退出判据 | 回滚 |
| --- | --- | --- | --- | --- | --- |
| S0 | 观测：lock 格式识别、`ct pkg check` 只读骨架、现状文档与缺陷落库 | v0.54.0 ✅ | 无 | [phase54.md](design/phase54.md) §4 J1–J8 全绿 | `git revert` 单提交 |
| S1 | 工具最小可用：`publisher`/`ns-root` 解析、store 落盘、lock v2、按 lock 生成 `-I` | v0.55.0 ✅ | S0 收口 | SP-001/002/003/004/005/007/014/017/019/020 全绿 | 关闭 store 写路径，恢复 vendor 写 |
| S2 | 编译读 lock：默认读、`--locked`、dev override 留痕、同名/裸名硬错 | v0.56.0 ✅ | S1 收口 | SP-006/008/009/010/011/013/015 全绿 | 去掉 `--locked` 与自动 `-I`，保留显式 `-I` |
| S3 | 校验与迁移：`ct verify` 校 store、`ct migrate`、`--strict` | v0.57.0 ✅ | S2 收口 | SP-016/029 全绿 | 恢复 vendor 读路径 |
| S5 | 消费端与门禁切换（仓内）：`test/pkg` 共享库用例、双 HOME 复现性、安装脚本提示 | v0.58.0 ✅ | S3 收口 | SP-028 告警落地；本仓无手算 `-I` | 恢复旧构建脚本 |
| S6 | 文档改写与 errata | v0.58.0（公开文档 ✅；历史 errata 待办） | S5 | SP-030 现行文档通过（历史 errata 待办） | 回滚文档提交 |
| S7 | 删除 `vendor/` 支持 | 待定（收口时实算） | **仓内自证（三条可执行）**：① `test/pkg` 的 v1 / 无 lock 工程 `ct build` RC=0，stderr 含 `is read from vendor/ (v1)`；② `ct install` 对每个 v1 包只告警一次；③ `ct migrate` 后移走 `vendor/` 仍可 build | 本仓无 vendor 读写；v1 lock 只报错 | 恢复 S3 读路径一个 minor |

> 包仓对齐（原 S4：std / ct-http / ct-fsguard / ct-json / ct-sse / ct-token / ct-process / ct-llm-sse）归各包仓，不属于本 phase；本仓只提供工具与判据，移交清单按仓分发。
>
> 包仓迁移状态（是否已迁移、`ct migrate` 是否覆盖其全部包、PK-6/12 是否绿）是**外部登记项**，
> 由各包仓自行维护；CT 不追踪、不判定、不代为登记，也不进入本 phase 的完成判据。

### v0.58.0 之后的排期（2026-11-15 重排）

逐项证据、依赖与放弃/合并理由见 [post-58-plan.md](planning/post-58-plan.md)；
可直接照着走的施工顺序见 [post-58-phase-sequence.md](planning/post-58-phase-sequence.md)。顺序：

1. **静默错误 patch**：PKG-5（缓存键裸名）→ LANG-9（字段可见性）→ LANG-4（下标类型错配）
   → LANG-17（预处理行截断）→ LANG-5 字段形态 / LANG-11。
2. **诊断与工具**：LANG-16 / LANG-8 / LANG-7 / LANG-3（Lexer 与 Expr 族串行）、SH-76；SH-79 只挡 PH-59 M2。
3. **文档收口**：PH-54 S6 历史 errata、issue 状态回填、过时提案退役（不占版本位）。
4. **PH-57 限定名**（SH-18 + LANG-15）→ **v0.59.0**：无前置、无卡，先开卡即可开工。
5. **PH-59 M1 模型导出** → **v0.60.0**：真实前置是 LANG-10 7c（`Field` 补行列），不是不存在的「PH-58」。
6. **PH-60 视图注记** → 条件位 **v0.61.0**：等 PH-59 schema 冻结且确认真实消费者；无消费者则**不立相**，PH-62 顺延到 v0.61.0，不留空号。
7. **PH-62 可写下标**（吸收 PH-61）→ **v0.62.0**：方向已通过研判，先开卡，再按 S0–S3 切片。
8. **PH-54 S7 删除 vendor**：最后做，前置是 S6 errata 完成与 S7 仓内自证三条全绿。

> 版本位按 AGENTS §0.3 的相位表：PH-54 已占 v0.54.0–v0.58.0，后续从 v0.59.0 起按下一个空位连续分配。
> PH-60 为条件相位：无消费者则不立相，PH-62 与 PH-63 依次顺延，不空占版本位。`v0.58.x` 只收 fix。

编号说明：Phase 55 / 56 / 58 不再作为 phase 存在（分别并入 PH-62、放弃、拆成 patch + 前置任务）；
PH-61 已被 PH-62 吸收。**本轮不重排既有编号**；版本位与 phase 号的偏移问题见
[post-58-plan.md](planning/post-58-plan.md) §8，待裁定。

### 未排期（治理项）

- **增量编译基准**：build cache 已有（Phase 10.5 的 cold/warm 与依赖失效），先在 Phase 36 收口提交上测冷/热构建与内核规模语料，再决定是否立项。
- **稳定子集清单**：Z6 的 1.0 冻结原则已有，补 trait / Drop / arena 的具体清单，属文档治理，不占 Phase 编号。

### 外部计划（不在本仓）

- 包仓计划（Agent 内核运行库、ct-pkg Phase 2 等）归各包仓，不属于本仓任何 phase；按仓分发的移交清单见包外册。

### 已定决策与待定项

版本记录见 [流水账 §版本记录](history/phase-log.md#版本记录详表)；已定设计决策见
[流水账 §已定的设计决策](history/phase-log.md#已定的设计决策)；未定项见
[流水账 §决策待定项](history/phase-log.md#决策待定项)。
