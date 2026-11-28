# 路线图

> 中文

本文只做**简要罗列**：阶段、主题、状态、收口版本、详情入口。逐相流水账、版本记录与已定决策见
[history/phase-log.md](history/phase-log.md)。当前已实现能力见 [README](../README.md) 与
[language-spec](language-spec.md)。语言稳定性分档与改动授权见 [stable-subset](stable-subset.md)。

**兼容承诺**：v1.0 起不再自称 C 超集；仍接受 C 核心，不承诺全集。弃用窗口见 [spec §1.2](language-spec.md)。
<!-- ct-compat: not-c-superset claim=v1.0-not-c-superset spec=1.2 -->

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
| Phase 7 | 单入口 `ct` | ✅ 完成 | v0.7.0 | [流水账](history/phase-log.md#阶段总览详表) |
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
| Phase 25 | 静态映射闭包实参 | ✅ 完成 | v0.25.0 | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-25/card.md) |
| Phase 26 | 泛型函数 | ✅ 完成 | v0.26.x | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-26/card.md) |
| Phase 27 | foreach | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-27/card.md) |
| Phase 28 | 约束泛型 | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-28/card.md) |
| Phase 29 | 泛型 struct + Vec/Map | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-29/card.md) |
| Phase 30 | into 块 | ✅ 完成 | v0.30.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-30/card.md) |
| Phase 31 | 容器能力补齐 | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) · [设计](phases/v0-PH-31/card.md) |
| Phase 32 | `ct check --types` 类型安全检查网 | ✅ 完成 | v0.33.0（合并） | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-32/card.md) |
| Phase 33 | 有界泛型 struct + 嵌套 impl | ✅ 完成 | — | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-33/card.md) |
| Phase 34 | pub 泛型 / 固有 impl / Option/Result | ✅ 完成 | v0.34.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-34/card.md) |
| Phase 35 | 泛型 trait | ✅ 完成 | v0.35.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-35/card.md) |
| Phase 36 | 泛型 Drop + Str | ✅ 完成 | v0.36.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-36/card.md) |
| Phase 37 | trait 签名硬错 + runtime checks | ✅ 完成 | v0.37.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-37/card.md) |
| Phase 38 | defer 块级清理 | ✅ 完成 | v0.38.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-38/card.md) |
| Phase 39 | C ABI 导出面与库制品 | ✅ 完成 | v0.39.0 | [卡](phases/v0-PH-39/card.md) |
| Phase 40 | errdefer + err: 错误出口 + 尾随声明 | ✅ 完成 | v0.40.0 | [卡](phases/v0-PH-40/card.md) |
| Phase 41 | 原子并发能力（`atomic T` + 内建原子操作） | ✅ 完成 | v0.41.0 | [卡](phases/v0-PH-41/card.md) · [D-004](decisions/D-004.md) |
| Phase 42 | `impl` 方法可见性（方法级 `pub`，默认私有） | ✅ 完成 | v0.42.0 | [流水账](history/phase-log.md#阶段总览详表) · [卡](phases/v0-PH-42/card.md) |
| Phase 43 | 错误出口类型契约（`return err:` 载荷检查） | ✅ 完成 | v0.43.0 | [卡](phases/v0-PH-43/card.md) |
| Phase 44 | `?` 错误传播运算符（后缀 `?`，同 `E`） | ✅ 完成 | v0.44.0 | [卡](phases/v0-PH-44/card.md) |
| Phase 45 | 类型契约一致性（闭包 `return` 与指针基类型判据） | ✅ 完成 | v0.45.0 | [卡](phases/v0-PH-45/card.md) |
| Phase 46 | `Map` 元素完整性（用户 struct 按值入 `Map`，`ct build` 可编译） | ✅ 完成 | v0.46.0 | [卡](phases/v0-PH-46/card.md) |
| Phase 47 | 容器键协议（`Str` 键深拷贝；`put_owned` 已删） | ✅ 完成 | v0.47.0 | [卡](phases/v0-PH-47/card.md) |
| Phase 48 | Drop 语义闭环（指针字段胶水 + 跨单元 Drop 体） | ✅ 完成 | v0.48.0 | [卡](phases/v0-PH-48/card.md) |
| Phase 49 | `own` 所有权转移（初始化式接工厂返回值） | ✅ 完成 | v0.49.0 | [卡](phases/v0-PH-49/card.md) |
| Phase 50 | 容器取用契约（`has` / `at`；出参形态已废） | ✅ 完成 | v0.50.0 | [卡](phases/v0-PH-50/card.md) |
| Phase 51 | 指针接收者 `.` 调用的发射缺陷（链式前置） | ✅ 完成 | v0.51.0 | [卡](phases/v0-PH-51/card.md) |
| Phase 52 | 自定义类型下标 `[]`（方案 A，只主张单层字符串键） | ✅ 完成 | v0.52.0 | [卡](phases/v0-PH-52/card.md) |
| Phase 53 | 可选链 `?.`（指针 / map；值上取到的指针或 map 跳） | ✅ 完成 | v0.53.0 | [卡](phases/v0-PH-53/card.md) · [记录](proposals/phase53-optional-chain-draft.md) |
| Phase 54 | ct-pkg 共享库包体系（工具侧：store / lock v2 / `ns-root`） | ✅ 完成（S0–S7） | v0.54.0–v0.58.0（S0–S3、S5/S6 各一个 MINOR；偏移见 AGENTS §0.3） | [卡](phases/v0-PH-54/card.md) · [提案](proposals/ct-pkg-shared-store.md) · [需求](planning/ct-pkg-shared-store-requirements.md) |
| Phase 57 | 限定名与 namespace 常量（类型位置 `A::B`、值位置 `Type::Member`；SH-18 + LANG-15） | ✅ 完成 | v0.59.0 | [卡](phases/v0-PH-57/card.md) · [重排](planning/post-58-plan.md) |
| Phase 59 | 模型导出 `--emit-model`（S0：无 import 单单元端到端） | ✅ 完成 | v0.60.0 | [卡](phases/v0-PH-59/card.md) · [提案](proposals/ct-model-export-proposal.md) · [决策](design/static-mapping-feasibility.md) · [重排](planning/post-58-plan.md) |
| Phase 60 | 视图节点注记（`view` 子句） | ⏭️ 跳过（无消费者，[D-006](decisions/D-006.md)） | 不占位 | [提案](proposals/ct-view-annotation-proposal.md) · [决策](decisions/D-006.md) |
| Phase 62 | 容器下标可写与嵌套链（吸收 v0-PH-61） | ✅ 完成 | v0.61.0 | [卡](phases/v0-PH-62/card.md) · [提案](proposals/ct-writable-subscript-proposal.md) · [研判](review/ct-writable-subscript-proposal-review.md) |
| Phase 63 | 删除 `vendor/` 支持（v0-PH-54 S7） | ✅ 完成 | v0.62.0 | [卡](phases/v0-PH-63/card.md) · [提案](proposals/ct-pkg-shared-store.md) |

| Phase 64 | 裸机生成契约（`--freestanding` / 按需单元 / `--alloc` / const vtable） | ✅ 完成 | v0.63.0 | [卡](phases/v0-PH-64/card.md) · [需求](planning/hardware-readiness-requirements.md) |
| Phase 65 | 严格 C 边界（外部库/用户默认 strict；`.m.ct` 映射例外；Ct 仓内 1.0 前代码豁免） | ✅ 完成 | v0.64.0 | [卡](phases/v0-PH-65/card.md) · [battle](../battle/cinclude-2/verdict.md) |
| Phase 66 | libc I/O 内置例外（按调用补头；空程序零系统头） | ✅ 完成 | v0.65.0 | [卡](phases/v0-PH-66/card.md) · [D-008](decisions/D-008.md) · [SH-89](../issues/selfhost/sh89-libc-io-auto-include.md) |
| Phase 67 | 无真机硬件能力扩展（PLL / nRF52840 / FreeRTOS / DMA / GDB） | ✅ 完成 | v0.66.0 | [卡](phases/v0-PH-67/card.md) · [TEST-21](../issues/testing/test21-baremetal-renode-stm32f4.md) |
| Phase 68 | 类型核心（`ct check --types`；修 234 误报） | ✅ 完成 | v0.67.0 | [卡](phases/v0-PH-68/card.md) · [方案](planning/typecheck-semantic-plan.md) · [battle](../battle/typecheck-1/verdict.md) |
| Phase 69 | 跨单元/泛型/trait 类型检查 | ✅ 完成 | v0.68.0 | [卡](phases/v0-PH-69/card.md) · [方案](planning/typecheck-semantic-plan.md) |
| Phase 70 | CFG/定值/控制流语义检查 | ✅ 完成 | v0.69.0 | [卡](phases/v0-PH-70/card.md) · [方案](planning/typecheck-semantic-plan.md) |
| Phase 71 | own/borrow/Drop + 包级 strict | ✅ 完成 | v0.70.0 | [卡](phases/v0-PH-71/card.md) · [方案](planning/typecheck-semantic-plan.md) |
| Phase 72 | 静默错误与诊断批（LANG-3 / LANG-4 / LANG-11 / LANG-16+DF-1 / SH-76 / SH-18+LANG-15） | ✅ 完成 | v0.71.0 | [卡](phases/v0-PH-72/card.md) · [post-58 评估](planning/post-58-plan.md) · [issues](../issues/) |
| Phase 73 | 字段可见性与 ABI（LANG-9：`pub` 决定头文件导出面） | ✅ 完成 | v0.72.0 | [卡](phases/v0-PH-73/card.md) · [LANG-9](../issues/lang/lang-9-struct-field-visibility-abi.md) |
| Phase 74 | 模型导出（v0-PH-59 M1/M2；J11 行列；SH-79 两 facet） | ✅ 完成 | v0.73.0 | [卡](phases/v0-PH-74/card.md) · [SH-79](../issues/selfhost/sh79-build-lib-emit-map-silent.md) |
| Phase 75 | 闭包作方法实参（SH-65 / SH-67 同族） | ✅ 完成 | v0.74.0 | [卡](phases/v0-PH-75/card.md) · [SH-65](../issues/selfhost/sh65-closure-as-method-arg.md) · [SH-67](../issues/selfhost/sh67-closure-method-arg-silent-invalid-c.md) |
| Phase 76 | 链中 inline 物化 `$name`（最小 A′：声明即可、多变量、链尾） | ✅ 完成 | v0.76.0 | [卡](phases/v0-PH-76/card.md) · [battle](../battle/inline-materialize-2/verdict.md) |
| Phase 77 | 官方包身份与解析契约（`ct/std`；裸名限官方；`ct get` 展示 `url@version`；旧锁自动迁移） | ✅ 完成 | v0.77.0 | [卡](phases/v0-PH-77/card.md) · [D-010](decisions/D-010.md) · [契约](planning/ct-pkg-get-contract.md) |
| Phase 78 | `ref` / `out` 参数（S2；上下文关键字、调用点 lvalue、`out` 定值） | ✅ 完成（S2a–S2c / E78-1–E78-6；REV fix v0.78.1） | v0.78.0（fix v0.78.1） | [卡](phases/v0-PH-78/card.md) · [安排](planning/pointer-free-phase-plan.md) · [提案](proposals/pointer-free-v2.md) |
| Phase 79 | 切片 `T[]`（S3；`T[]` 唯一、带检查 place、`const T[]`） | ✅ 完成（S3a–S3e / E79-1–E79-6） | v0.79.0 | [卡](phases/v0-PH-79/card.md) · [安排](planning/pointer-free-phase-plan.md) · [提案](proposals/pointer-free-v2.md) |
| Phase 80 | `String` / `Str`（S5；UTF-8/UTF-16 双类型、L1 字面量、std 迁移） | ✅ 完成（v0.80.4；SH-102 verified，D-015） | v0.80.4 | [卡](phases/v0-PH-80/card.md) · [安排](planning/pointer-free-phase-plan.md) · [提案](proposals/pointer-free-v2.md) |
| Phase 81 | `Box<T>` + `new`（S1；共享句柄协议、`new` 仅具名 struct） | ✅ 完成（v0.81.0；P-7.5 + S1a/S1b/S1c，E81-1…6 通过） | v0.81.0 | [卡](phases/v0-PH-81/card.md) · [安排](planning/pointer-free-phase-plan.md) · [提案](proposals/pointer-free-v2.md) |
| Phase 82 | 泄漏防护（`leaks` 两档 `warn` / `error`；`Box` 字段直接环告警；树模式文档） | ✅ 完成（v0.82.1；E82-1…8 通过，D-012；SH-103 Linux 字段表修复） | v0.82.1 | [卡](phases/v0-PH-82/card.md) · [提案](proposals/leak-guards.md) · [判决](../battle/leak-guards-1/verdict.md) · [D-012](decisions/D-012.md) |
| Phase 83 | 包管理契约 v1 与索引校验（只读 `ct index verify`；Linux x64 产物；conformance） | ✅ 完成（v0.83.0；E83-1…8 通过，D-014；PKG-14 fixed v0.83.1；Linux 默认索引路径 fix v0.83.2） | v0.83.0（fix v0.83.1 / v0.83.2） | [卡](phases/v0-PH-83/card.md) · [评估](reviews/2026-11-20-pkg-contract-proposal-eval.md) · [契约](planning/ct-pkg-get-contract.md) · [D-014](decisions/D-014.md) |
| Phase 84 | 最小 ADT / `match`（名义和类型 + 负载 + 穷尽检查 + 变量绑定；D3）+ **S84e 文档一致性（B 判决，最小集）** | ✅ 完成（S84a–S84e，v0.84.0；E84-1…9 通过；v0.84.1 为 REV F1/F2 修复；A 的全量审计归 DOC-77/78/79） | v0.84.0（fix v0.84.1） | [卡](phases/v0-PH-84/card.md) · [battle doc-consistency-1](../battle/doc-consistency-1/question.md) · [LANG-21](../issues/lang/lang-21-minimal-adt-match.md) |
| Phase 85 | v1-pre：inventory + 单切片 spike（门）+ M0 粗切 + A 机制接线（`off/warn/error`） | ✅ 完成（v0.85.0；**E85-2 有条件通过（D-018）**，其余 E85 通过；spike 只证结构等价，整子系统重写门不通过、移交 v0-PH-86 per-function，见卡 §8） | v0.85.0 | [卡](phases/v0-PH-85/card.md) · [v1 路线 §2.3/§2.4/§2.7](planning/v1-release-plan.md) · [D-017](decisions/D-017.md) |
| Phase 86 | v1-pre：词法器重写（零拷贝 token 视图；NUL/长度契约） | ✅ 完成（v0.86.0；S86a–S86d，E86-1…8 通过；S86c 的 `?`/errdefer 按 battle/p86-errorpath 采 A：词法器无错误通道 + L2 引导链不支持，改为错误出口清单 + 345 条诊断逐字对照） | v0.86.0 | [卡](phases/v0-PH-86/card.md) · [battle](../battle/p86-errorpath/verdict.md) · [度量](design/p86_metrics.md) · [v1 路线 §2.3](planning/v1-release-plan.md) |
| Phase 87 | v1-pre：解析器 + 检查器重写（按 kind 切片 / 单判别式；`switch→match` 字面项移交 v0-PH-88） | ✅ 完成（v0.87.0；S87a–S87d，E87-1…8 见卡 §7；13 + 15 个切片，语料逐字节 + 345 诊断逐字 + 自举不动点通过；`switch→match` 按 battle/p87-kind-match 移交 v0-PH-88） | v0.87.0 | [卡](phases/v0-PH-87/card.md) · [battle](../battle/p87-kind-match/verdict.md) · [度量](design/p87_metrics.md) · [dogfood](design/p87_dogfood.md) · [v1 路线 §2.3](planning/v1-release-plan.md) |
| Phase 88 | v1-pre：发射器重写 + 扩展自举回环（轮数参数化） | ✅ 完成（v0.88.0；S88a–S88d，E88-1…8 见卡 §7；发射器 76 个 kind 切片 + 判别式单读；fixpoint 日常 2 / tag 前 3 轮；字面 `match` 按 battle/p88-emit-match 承接 `v1-PH-0` seed cutover） | v0.88.0 | [卡](phases/v0-PH-88/card.md) · [battle](../battle/p88-emit-match/verdict.md) · [度量](history/p88_metrics.md) · [v1-pre 证据](history/v1-pre-evidence.md) · [v1 路线 §2.3](planning/v1-release-plan.md) |
| `v1-PH-0` | v1.0 收口（ct-ast 构建/安装改走 **seed = 冻结 ct-ast 生成的 C**，D-022 已定；L1/L2 降为回归 oracle、v1.0 不删；**A 证据 FP=0 硬门禁**；前置 goldens 静态化 + J-6 台账；在 v0-PH-88 之后） | ✅ 完成（v1.0.0；seed cutover + 字面 match + 13 门） | v1.0.0（MAJOR） | [卡](phases/v1-PH-0/card.md) · [D-022](decisions/D-022.md) · [v1 路线](planning/v1-release-plan.md) · [编号提案](proposals/phase-numbering-major-reset.md) |
| `v1-PH-1` | v1.1：S1 M1 精细切分 + SH-94 → S2 LANG-26 剩余 / **ADT-match 完整化（LANG-29）** → S3 A 默认 `error` + TEST-23 → S4 删 `box` 别名与收口 | ✅ 完成（v1.1.0；S0–S4） | v1.1.0 | [卡](phases/v1-PH-1/card.md) · [DOC-99](../issues/docs/doc-99-v11-prework-tracker.md) · [v1 路线](planning/v1-release-plan.md) |
| `v1-PH-2` | v1.2：**容量上限放开 → SH-94 单元收敛 → LIR 先行**（S1a-0→S1a-1→S1b 总闸）+ 历史欠账清零（小欠账、下标协议、函子、ADT 模式、检查器、**源码狗粮化**、**样例/文档去指针化**、**全局默认 strict**）；单卡 S0–S10，只 bump 一次 MINOR | 🟨 进行中（2026-11-28：S0–S10 已提交，**`v1.2.0` 未打 tag**；收口后补 I1 常量键折叠与 I2 接口值下标（[CR-V3-2](phases/v1-PH-2/card.md#8-判据变更记录)）；另 S8b 剩余、E-V3-9b 部分，见[卡 §6/§8](phases/v1-PH-2/card.md)） | v1.2.0 | [卡](phases/v1-PH-2/card.md) · [提案](proposals/typed-lowered-ir.md) · [D-026](decisions/D-026.md) · [需求池](planning/requirements-pool.md) · [容量清单](planning/capacity-limits.md) · [狗粮化](planning/dogfooding.md) · [TEST-27](../issues/testing/test27-feature-examples-pointer-free.md) |
| `HW-1` | **真板 pilot**（REQ-HW-020：真实板卡 + 厂商 HAL + RTOS；含 [TEST-22](../issues/testing/test22-dma-real-transfer-hardware-gated.md) DMA 真实搬运） | ⬜ 外部依赖（无硬件，不阻塞开发） | — | [需求](planning/hardware-readiness-requirements.md) · [TEST-22](../issues/testing/test22-dma-real-transfer-hardware-gated.md) |
| `HW-2` | **第二厂商真板**（nRF52840 / RP2040 的烧录、调试与电气验证） | ⬜ 外部依赖（无硬件，不阻塞开发） | — | [v0-PH-67 卡](phases/v0-PH-67/card.md) · [TEST-21](../issues/testing/test21-baremetal-renode-stm32f4.md) |

> 硬件类工作统一排在最后（`HW-*`）：无真机时不阻塞、不伪造；模拟器侧能力已在
> v0-PH-64 / v0-PH-67 交付。TEST-22 归入 `HW-1`。phase-ID 迁移（`v0-PH-*`）是横切任务，
> 不占 phase 号，见 [blockers](planning/phase-migration-blockers.md)。

> **指针退场（v0.78–v0.82）**：v0-PH-78 S2 `ref/out` → v0-PH-79 S3 切片 → v0-PH-80 S5 `String/Str`
> → v0-PH-81 S1 `Box/new`；S2 ∥ S3 可并行准备，单卡纪律先开 S2；S4 函子并入 `v1-PH-2` S3
> （原定 v1.1+ Wave 2；2026-11-25 所有者改判：不单开 phase）。
> v0-PH-78 已收口（v0.78.0 / fix v0.78.1），v0-PH-79 已收口（v0.79.0）；
> v0-PH-80 已收口（v0.80.4；S5a 内建层 + S5b 删旧 `str` 与消费者迁移，E80-7 通过；SH-102 自动 retain R1–R7 修复，D-015 口径）；
> v0-PH-82 已收口（v0.82.0；`leaks` 两档、直接环告警、`allow-cycle`、树模式；E82-1…8）；v0-PH-83 已收口（v0.83.0；契约 v1 / `ct index verify` / conformance / Linux x64 产物，E83-1…8；D-014）。
> J-6 全量仍未过；v1.0 顺延到 v0-PH-82 之后。
> v0-PH-82 见 [phase82](phases/v0-PH-82/card.md) / [D-012](decisions/D-012.md)。
> 详见 [pointer-free-phase-plan](planning/pointer-free-phase-plan.md)。

> **包管理契约 v1（v0-PH-83，v0.83.0，已收口）**：不属于指针退场，排在 v0-PH-82 与 v1.0 之间；
> 只做只读 `ct index verify`、Linux x64 产物与 conformance；发布/索引生成仍留在 index CI
> （[D-014](decisions/D-014.md) · [评估](reviews/2026-11-20-pkg-contract-proposal-eval.md) ·
> [卡](phases/v0-PH-83/card.md)）。

> **ADT/match 与 v1-pre（D1/D3 已定）**：v0-PH-84 最小 ADT/match（名义和类型 + 负载 +
> 穷尽检查 + 变量绑定）→ v0-PH-85 inventory+spike 门 + **A 机制接线**（`off/warn/error`）
> → v0-PH-86 词法 → v0-PH-87 解析+检查 → v0-PH-88 发射器+三轮自举；随后才发 v1.0。
> 每张卡独立合入/回滚，同一时刻只开一张。泛型 ADT/or/嵌套模式留 v1.1+。
> v0-PH-85–88 期间主线**只收 bugfix**，新特性暂停（D6）；不设 hard deadline（D5）。
> 源码单元切分：M0 粗切并入 v0-PH-85，M1 精细切分落 v1.1 S1；判据两级制与集合基线见
> [D-017](decisions/D-017.md) · [评估](reviews/2026-11-21-unit-split-eval.md)。
> **A 的证据**（全量 FP=0）是 v1.0 硬门禁；**默认强制**由 v1-pre 证据决定，未达标回退“可用不默认”（D2 = B+）。

> **v1.0 发布前清单（2026-11-21 已定项）**：J-6 证据台账、goldens 静态化、SH-73、冻结清单、
> 兼容承诺、能力→节号断言、新特性文档核对、包体系收尾；跟踪见
> [v1 路线 §1.5](planning/v1-release-plan.md#L57-L71) 与 [评估](reviews/2026-11-21-v1-campaign-eval.md)。
> “ADT 时序、函子依赖、deadline/冻结策略、页首版本注入”等仍在讨论，
> 见 [v1 路线 §6](planning/v1-release-plan.md)，未定前不落计划。

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
> 切词按 parser 组合识别（`c?.5 : 1.0` 保持三目），见 [施工卡](phases/v0-PH-53/card.md)。
> 原记录保留为设计依据；其余候选（DF-1/2/3、REQ-JSACCESS-1 等）留需求池或后续相，不占 v0-PH-53。

### ct-pkg 共享库包体系（Phase 54，S0–S7）

契约变更：以 `ct.pkg` 的 `ns-root` 取代「包根 = 单元根」的隐含约定，`ct install` 的 `-I vendor/<name>` 输出契约作废。判据见[需求定稿](planning/ct-pkg-shared-store-requirements.md)，条款见[提案](proposals/ct-pkg-shared-store.md)。

| 切片 | 主题 | 版本位 | 前置 | 退出判据 | 回滚 |
| --- | --- | --- | --- | --- | --- |
| S0 | 观测：lock 格式识别、`ct pkg check` 只读骨架、现状文档与缺陷落库 | v0.54.0 ✅ | 无 | [phase54.md](phases/v0-PH-54/card.md) §4 J1–J8 全绿 | `git revert` 单提交 |
| S1 | 工具最小可用：`publisher`/`ns-root` 解析、store 落盘、lock v2、按 lock 生成 `-I` | v0.55.0 ✅ | S0 收口 | SP-001/002/003/004/005/007/014/017/019/020 全绿 | 关闭 store 写路径，恢复 vendor 写 |
| S2 | 编译读 lock：默认读、`--locked`、dev override 留痕、同名/裸名硬错 | v0.56.0 ✅ | S1 收口 | SP-006/008/009/010/011/013/015 全绿 | 去掉 `--locked` 与自动 `-I`，保留显式 `-I` |
| S3 | 校验与迁移：`ct verify` 校 store、`ct migrate`、`--strict` | v0.57.0 ✅ | S2 收口 | SP-016/029 全绿 | 恢复 vendor 读路径 |
| S5 | 消费端与门禁切换（仓内）：`test/pkg` 共享库用例、双 HOME 复现性、安装脚本提示 | v0.58.0 ✅ | S3 收口 | SP-028 告警落地；本仓无手算 `-I` | 恢复旧构建脚本 |
| S6 | 文档改写与 errata | v0.58.0（公开文档与历史 errata ✅） | S5 | SP-030 现行文档通过（历史 errata 待办） | 回滚文档提交 |
| S7 | 删除 `vendor/` 支持 | v0.62.0 ✅ | **仓内自证（三条可执行）**：① `test/pkg` 的 v1 / 无 lock 工程 `ct build` RC=0，stderr 含 `is read from vendor/ (v1)`；② `ct install` 对每个 v1 包只告警一次；③ `ct migrate` 后移走 `vendor/` 仍可 build | 本仓无 vendor 读写；v1 lock 只报错 | 恢复 S3 读路径一个 minor |

> 包仓对齐（原 S4：std / ct-http / ct-fsguard / ct-json / ct-sse / ct-token / ct-process / ct-llm-sse）归各包仓，不属于本 phase；本仓只提供工具与判据，移交清单按仓分发。
>
> 包仓迁移状态（是否已迁移、`ct migrate` 是否覆盖其全部包、PK-6/12 是否绿）是**外部登记项**，
> 由各包仓自行维护；Ct 不追踪、不判定、不代为登记，也不进入本 phase 的完成判据。

### v0.58.0 之后的排期（2026-11-15 重排）

逐项证据、依赖与放弃/合并理由见 [post-58-plan.md](planning/post-58-plan.md)；
可直接照着走的施工顺序见 [post-58-phase-sequence.md](planning/post-58-phase-sequence.md)。顺序：

1. **静默错误 patch**：PKG-5（缓存键裸名）→ LANG-9（字段可见性）→ LANG-4（下标类型错配）
   → LANG-17（预处理行截断）→ LANG-5 字段形态 / LANG-11。
2. **诊断与工具**：LANG-16 / LANG-8 / LANG-7 / LANG-3（Lexer 与 Expr 族串行）、SH-76；SH-79 只挡 v0-PH-59 M2。
3. **文档收口**：v0-PH-54 S6 历史 errata、issue 状态回填、过时提案退役（不占版本位）。
4. **v0-PH-57 限定名**（SH-18 + LANG-15）→ **v0.59.0**：无前置、无卡，先开卡即可开工。
5. **v0-PH-59 M1 模型导出** → **v0.60.0**：真实前置是 LANG-10 7c（`Field` 补行列），不是不存在的「v0-PH-58」。
6. **v0-PH-60 视图注记** → 条件位 **v0.61.0**：等 v0-PH-59 schema 冻结且确认真实消费者；无消费者则**不立相**，v0-PH-62 顺延到 v0.61.0，不留空号。
7. **v0-PH-62 可写下标**（吸收 v0-PH-61）→ **v0.62.0**：方向已通过研判，先开卡，再按 S0–S3 切片。
8. **v0-PH-54 S7 删除 vendor**：最后做，前置是 S6 errata 完成与 S7 仓内自证三条全绿。

> 版本位按 AGENTS §0.3 的相位表：v0-PH-54 已占 v0.54.0–v0.58.0，后续从 v0.59.0 起按下一个空位连续分配。
> v0-PH-60 为条件相位：无消费者则不立相，v0-PH-62 与 v0-PH-63 依次顺延，不空占版本位。`v0.58.x` 只收 fix。

编号说明：Phase 55 / 56 / 58 不再作为 phase 存在（分别并入 v0-PH-62、放弃、拆成 patch + 前置任务）；
v0-PH-61 已被 v0-PH-62 吸收。**本轮不重排既有编号**；版本位与 phase 号的偏移问题见
[post-58-plan.md](planning/post-58-plan.md) §8，待裁定。

### 未排期（治理项）

- **增量编译基准**：并入 [`v1-PH-2` S9](phases/v1-PH-2/card.md) 的收口证据——冷/热构建各测一次并记录，不单独立项。
- **稳定子集清单**：已由 [stable-subset.md](stable-subset.md) 交付，无待办。

### 外部计划（不在本仓）

- 包仓计划（Agent 内核运行库、ct-pkg Phase 2 等）归各包仓，不属于本仓任何 phase；按仓分发的移交清单见包外册。

### 已定决策与待定项

版本记录见 [流水账 §版本记录](history/phase-log.md#版本记录详表)；已定设计决策见
[流水账 §已定的设计决策](history/phase-log.md#已定的设计决策)；未定项见
[流水账 §决策待定项](history/phase-log.md#决策待定项)。
