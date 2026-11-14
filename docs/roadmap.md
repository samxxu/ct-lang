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
| Phase 43 | 错误出口类型契约（`return err:` 载荷检查） | ✅ 完成 | v0.43.0 | [卡](design/phase43.md) |
| Phase 44 | `?` 错误传播运算符（后缀 `?`，同 `E`） | 🟨 实施中 | — | [卡](design/phase44.md) |
| Phase 45 | 类型契约一致性（闭包 `return` 与指针基类型判据） | ⬜ 已定稿 / 待实施 | — | [卡](design/phase45.md) |

> Phase 13–16 未使用；Phase 27–30 合并为 v0.30.0 发布，Phase 31–33 合并为 v0.33.0 发布（Phase 31 / 33
> 未单独 bump）。逐相细节与出口证据见 [流水账](history/phase-log.md#阶段总览详表)。

### 未排期（治理项）

- **增量编译基准**：build cache 已有（Phase 10.5 的 cold/warm 与依赖失效），先在 Phase 36 收口提交上测冷/热构建与内核规模语料，再决定是否立项。
- **稳定子集清单**：Z6 的 1.0 冻结原则已有，补 trait / Drop / arena 的具体清单，属文档治理，不占 Phase 编号。

### 外部计划

- **Agent 内核运行库（ct-pkg，外部）**：`arena` / `sync` / `callback` 今天可做，`result` / `string` 分别等 Phase 34 / 36，ABI 打包等 Phase 39；提案见 [proposals/ct-pkg-agent-runtime.md](proposals/ct-pkg-agent-runtime.md)。
- **ct-pkg Phase 2**：生态映射包，计划文档在同级 ct-pkg 仓库 `docs/phase2.md`。

### 已定决策与待定项

版本记录见 [流水账 §版本记录](history/phase-log.md#版本记录详表)；已定设计决策见
[流水账 §已定的设计决策](history/phase-log.md#已定的设计决策)；未定项见
[流水账 §决策待定项](history/phase-log.md#决策待定项)。
