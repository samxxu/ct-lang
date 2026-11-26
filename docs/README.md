# 文档导航

> 中文
>
> **当前版本 v1.1.0。** 全部 phase 卡集中在 [phases/](phases/)，一卡一目录（`docs/phases/v<M>-PH-<n>/card.md`，PN-1）；`design/` 只保留计划、评审与映射等辅助记录，`history/design/` 为历史快照；评审报告
> 与其余历史记录在 [history/](history/README.md)。仓库入口见 [../README.md](../README.md)，改动
> 规约见 [../AGENTS.md](../AGENTS.md)。
>
> **语言约定：** 默认中文；英文仅根 [README.en.md](../README.en.md)，供人类阅读，AI 代理不读。

---

## 中文

### 从哪读起

| 文档 | 内容 | 何时读 |
| --- | --- | --- |
| [tutorial.md](tutorial.md) | 逐章入门：核心范式（字符串 → factory → trait 对象 → 接口链）→ 安装 → 派发 → 模块 → 内存 → `map` → 可选链 / `ref`·`out` / `Box` / ADT·`match` / `String`·`Str` / 切片，附命令行速查与常见坑 | 第一次使用 |
| [guide-for-c-programmers.md](guide-for-c-programmers.md) | 给 C 程序员的内存心智模型：`String`/`Str`、切片、`ref`/`out`、`Box`、ADT/`match`、残余风险 | 从 C 迁移到 Ct |
| [c-shim-contract.md](c-shim-contract.md) | 手写 C shim 的正式契约：文件/命名、头文件边界、所有权、错误码、ISR/任务上下文、ABI、DMA 五条硬条款、host mock + Renode 冒烟 | 写或评审 shim、接裸机 |
| [c-interop-semantics-matrix.md](c-interop-semantics-matrix.md) | guide 附录：C 互操作语义矩阵，14 项逐项给 Ct 行为、边界（透传 · strict 禁区 · shim）与权威节 + 证据 | 查一条 C 写法走哪条边界 |
| [language-spec.md §4.10.1](language-spec.md#4101-链式构建器范式权威定义与两档路径) | **链式构建器范式的唯一权威定义**：三段顺序、轻量 / 完整两档的判断依据、逐段边界与报错原文（含 SH-75 后的当前状态） | 要写或判断一条链式调用时 |
| [language-spec.md](language-spec.md) | `.ct` 的语法与展开规则、命名契约、容量上限、明确不支持 | 想知道「这条写法展开成什么 C」 |
| [glossary.md](glossary.md) | 术语表：项目名、语言构造、内部符号 | 读文档遇到生词 |
| [vision.md](vision.md) | 定位、设计原则与生态策略 | 想知道「为什么这样设计」 |
| [architecture.md](architecture.md) | 编译器内部结构与关键算法 | 改编译器 |
| [design/lowering-invariants.md](design/lowering-invariants.md) | 发射前 lowering 不变量：清理边、errdefer、临时物化、可机械检查子集与剩余项（SH-111） | 改发射器 / 排查临时值与清理边 |
| [diagnostics/codes.md](diagnostics/codes.md) | 稳定诊断码 registry：`E-`/`W-<域>-<编号>`、文本/JSON 共用、查重规则与扩展流程（LANG-25） | 接 IDE/CI、加诊断或改文案 |
| [polymorphism.md](polymorphism.md) | 接口多态与派发 | 设计对象协作 |
| [construction.md](construction.md) | 对象构造语义（vptr 由谁、何时写入） | 排查构造期问题 |
| [patterns.md](patterns.md) | 设计模式在现有特性下的写法 | 判断「要不要新增语言特性」 |
| [memory-guide.md](memory-guide.md) | 指针层内存实践：`own` / `borrow` / 工厂 / 池 / arena | 写逃生层或维护旧代码 |
| [package-guide.md](package-guide.md) | 包作者指南：`ct.pkg` 键、`ns-root`、`ct install` / `ct build` 行为、常见失败 | 编写或消费一个包 |
| [stable-subset.md](stable-subset.md) | 稳定子集三档与改动授权矩阵：哪些已冻结、谁能批、截止版本 | 判断一项改动能不能做、要谁批 |
| [modern-oo-gap.md](modern-oo-gap.md) | 需求侧评估：以现代化 OO 为参照的差距清单、battle 记录与三档结论 | 判断「还缺哪些语言特性」 |

### 生态：先复用，别重写

| 文档 | 内容 | 何时读 |
| --- | --- | --- |
| [idioms.md](idioms.md) | Ct 惯用优先级：所有权分层、String/Str、切片、ref/out、ADT、遍历、泄漏；附录 briefing 带 spec 节号 | 写代码前定选型；给编码助手喂压缩事实 |
| [llm-guide.md](llm-guide.md) | 面向 LLM / 代理的固定决策顺序与硬规则 | 写任何 Ct 代码前 |
| [std-catalog.md](std-catalog.md) | `std` 16 个模块的用途、入口 `import`、完整 API 在哪 | 要用容器 / 字符串 / 文件 / UTF-8 / arena / test |
| [ct-pkg.md](ct-pkg.md) | ct-pkg 四个角色：编译器 / std / 平台包 / 索引 | 判断一个能力该由谁提供 |
| [ct-pkg-index.md](ct-pkg-index.md) | 索引的六字段现行形态、旧五字段兼容、信任边界与发布入口 | 加包、查索引、判断可信度 |
| [package-guide.md](package-guide.md) | 包作者指南：清单键、`ns-root`、`ct install` | 发布或消费一个包 |
| [package-coding-conventions.md](package-coding-conventions.md) | 包编码通用条款 CG-1…CG-7：命名、对象式调用、能力寄生、三层模型、资源与错误处理、映射唯一实现 | 设计或评审一个包的公开 API |

> `proposals/` 下的文档是**提案**，不是现状；现状以本表与 language-spec / package-guide /
> ct-pkg-index 为准。索引没有签名，pin / 签名未落地前不要声称可信。

### 计划与台账

| 文档 | 内容 |
| --- | --- |
| [roadmap.md](roadmap.md) | 简要阶段表：阶段 / 主题 / 状态 / 收口版本 / 详情入口 |
| [proposals/phase-numbering-major-reset.md](proposals/phase-numbering-major-reset.md) | 主规范 CR 提案：每个 MAJOR 从 `v0-PH-0` 重编号，`MINOR == 本 major 内 n`；`v1-PH-0`/`v1-PH-1`，历史 `PH-*` 不复用 | 查看大版本 phase 编号提案 |
| [planning/phase-migration-blockers.md](planning/phase-migration-blockers.md) | phase ID 迁移 blocker：旧 major 的 `version-minor` 偏移、卡片布局、旧卡字段；裁定前不动文件 | 查看迁移阻塞项 |
| [planning/v1-release-plan.md](planning/v1-release-plan.md) | v1.0/v1.1 发布路线（**规划中**）：v1.0 AST-only 去旧管线（保留 seed）、B 检查器 opt-in；v1.1 语法现代化 → A strict 编译路径 | 查看 v1 发布路线 |
| [proposals/typed-lowered-ir.md](proposals/typed-lowered-ir.md) | v1.2 Typed/Lowered IR 设计提案（**设计验收完成、未实施**）：TIR/LIR、统一清理 CFG、emitter 契约、不变量验证器、迁移/回滚与语义依赖图；实施 deferred 到 `v1-PH-2`（[D-026](decisions/D-026.md)） | 查看 v1.2 IR 设计 |
| [planning/typecheck-semantic-plan.md](planning/typecheck-semantic-plan.md) | 类型/语义检查（**已交付、历史计划**）：v0-PH-68–71 已收口（版本 0.67.0–0.70.0）——类型核心 → 跨单元/泛型 → CFG → own/borrow；全部 opt-in，不进编译路径 | 查看类型检查方案与收口追溯 |
| [planning/post-58-plan.md](planning/post-58-plan.md) | 58 之后的重排评估：在册项矩阵、依赖、顺序与并行、放弃/合并清单、编号断裂与待裁定 | 决定 58 之后先做什么、哪些不做 |
| [planning/hardware-readiness-requirements.md](planning/hardware-readiness-requirements.md) | 硬件可用性需求（评估会产出，**未立项**）：P0 数组/const vptr、v0-PH-64 freestanding/alloc/const vtable、硬件 pilot；含采纳/延后/不采纳与顺序 | 查看硬件需求与验收 |
| [planning/post-58-phase-sequence.md](planning/post-58-phase-sequence.md) | 58 之后的正式 phase 序列：包管理器线先收口、语言线按依赖排序、版本位与并行车道 | 照着走的施工顺序 |
| [history/phase-log.md](history/phase-log.md) | 逐相流水账：Phase 0–42 的详细记录、版本记录、已定决策与待定项 |
| [history/p88_metrics.md](history/p88_metrics.md) | v0-PH-88 度量与 sharp edge：发射器 76 个 kind 切片、行数/耗时/发射 C 行数、fixpoint 2/3 轮、与 v0-PH-85 spike 对照 | 复核 v0-PH-88 或下一批切片 |
| [history/v1-pre-evidence.md](history/v1-pre-evidence.md) | v1-pre 证据摘要：v0-PH-84…v0-PH-88 逐相结论、字面 `match` 的承接目标（`v1-PH-0`）与遗留清单 | 进入 v1.0 前 |
| [phases/v0-PH-20/card.md](phases/v0-PH-20/card.md) · [phases/v0-PH-21/card.md](phases/v0-PH-21/card.md) · [phases/v0-PH-24/card.md](phases/v0-PH-24/card.md) · [phases/v0-PH-25/card.md](phases/v0-PH-25/card.md) · [phases/v0-PH-26/card.md](phases/v0-PH-26/card.md) | 已完成的阶段计划（Phase 20–26）：包支持 / 非逃逸栈闭包 / `loop` 语法糖 / `loop(a..b)` 范围 / 数组 range 初值 / 静态映射调用的闭包实参 / 泛型函数；phase17、phase18、phase19、phase22、phase23 与 phase25–phase31 已按 DOC-66 归档到 [history/design/](history/design/) |
| [phases/v0-PH-27/card.md](phases/v0-PH-27/card.md) | 已完成的阶段记录（Phase 27）：`foreach` 语句形态（数组形态已实现，容器协议由 Phase 29 解冻；语法、展开规则与决策见正文） |
| [phases/v0-PH-28/card.md](phases/v0-PH-28/card.md) | 已完成的阶段记录（Phase 28，泛型两阶段第一相）：trait 约束的泛型函数与静态派发（语法、落码、E28-1–E28-9 收口核对与 D28-1–D28-11 见正文；未 bump） |
| [phases/v0-PH-29/card.md](phases/v0-PH-29/card.md) | 已完成的阶段计划（Phase 29，泛型两阶段第二相）：泛型 struct + 内置 `Vec`/`Map`，解冻 `foreach` 容器协议（`Map` 遍历为硬判据）、`Vec`/`Map` 从 `ct-pkg/std` 迁入 `lib/std/`（当时目录；现 `lib/core`，DOC-87 迁移。std 其余模块不动）（D29-1–D29-16 见正文） |
| [phases/v0-PH-30/card.md](phases/v0-PH-30/card.md) | 已完成的阶段计划（Phase 30）：接收者语境块 `<receiver> into { … }`——块内 `.name` 访问接收者成员/方法、`$` 指代自身；`into` 为后置上下文关键字，块结束后仍返回接收者、可继续接后缀链或连续多段 `into`；语句形态与值形态（初始化器 / 赋值 / `return`，结果为接收者本身）；接收者只求值一次并按 value category 提升；`.m.ct` 类型宿主（含 shim）可作接收者、`$ =` 可接链（D30-1–D30-19 见正文） |
| [phases/v0-PH-31/card.md](phases/v0-PH-31/card.md) | 已完成的阶段计划（Phase 31）：接口值进容器（`Vec<Show>` / `Map<char *, Show>`）与嵌套容器的元素寿命与所有权、`v[i]` / `m[k]` 仅展开为 `get`、`Vec` / `Map` 花括号初值（E31-1–E31-23、L31-1–L31-21、D31-1–D31-17 见正文） |
| [phases/v0-PH-32/card.md](phases/v0-PH-32/card.md) – [phases/v0-PH-42/card.md](phases/v0-PH-42/card.md) | 阶段草案（Phase 32–42，均已完成）：类型安全网 / 有界泛型 struct / 生态可用性 / 泛型 trait / 泛型 Drop 与 `Str` / trait 签名硬错与运行期契约 / `defer` / C ABI 与库制品 / `errdefer` 错误出口 / 原子并发（`atomic T`）/ `impl` 方法可见性；状态以 [roadmap.md](roadmap.md) 为准 |
| [phases/v0-PH-43/card.md](phases/v0-PH-43/card.md) · [phases/v0-PH-44/card.md](phases/v0-PH-44/card.md) · [phases/v0-PH-45/card.md](phases/v0-PH-45/card.md) | 已完成（Phase 43–45）：43 错误出口类型契约 / 44 `?` 传播 / 45 闭包 `return` 与指针基类型判据；收口版本见 [roadmap.md](roadmap.md)；未立项评估结论与门禁欠账见 [planning/requirements-pool.md](planning/requirements-pool.md) |
| [design/phase46-52-plan.md](design/phase46-52-plan.md) | 分期方案（Phase 46–52；46–52 已收口）：排序依据、相间依赖、硬阻塞前置、裁定状态、本波不覆盖清单；**§10 交接说明、§11 缺陷与绕法、§12 实战限制、§13 裁决落地与 errata、§14 远端文档债** |
| [design/phase46-52-handoff.md](design/phase46-52-handoff.md) | 施工手册（给外部实现方；45–52 已收口，保留为历史施工入口）：施工顺序、每卡入口条件与出口证据、门禁命令、禁止事项、收口五样证据 |
| [reviews/phase46-52-freeze-verdict.md](reviews/phase46-52-freeze-verdict.md) | 定稿裁决：四组实测、73 条输入逐条结论（采纳 67 / 部分 6 / 不采纳 1）、5 条已于 2026-11-15 按建议值签字 |
| [phases/v0-PH-46/card.md](phases/v0-PH-46/card.md) · [phases/v0-PH-47/card.md](phases/v0-PH-47/card.md) | 已完成（Phase 46–47）：46 `Map` 元素完整性 / 47 容器键协议（`Str` 键深拷贝）；收口版本见 [roadmap.md](roadmap.md) |
| [phases/v0-PH-48/card.md](phases/v0-PH-48/card.md) · [phases/v0-PH-49/card.md](phases/v0-PH-49/card.md) | 已完成（Phase 48–49）：48 Drop 语义闭环 / 49 `own` 所有权转移；收口版本见 [roadmap.md](roadmap.md) |
| [phases/v0-PH-50/card.md](phases/v0-PH-50/card.md) · [phases/v0-PH-51/card.md](phases/v0-PH-51/card.md) · [phases/v0-PH-52/card.md](phases/v0-PH-52/card.md) | 已完成（Phase 50–52，0.50.0 至 0.53.0）：容器 `has`·`at` / 指针接收者 `.` 发射缺陷 / 自定义下标 `[]`（方案 A，只主张单层字符串键；`v[0]` 的参数类型匹配见 [REQ-JSACCESS-1](planning/requirements-pool.md)）；状态以 [roadmap.md](roadmap.md) 为准 |
| [phases/v0-PH-53/card.md](phases/v0-PH-53/card.md) | 已完成（Phase 53，0.53.0）：可选链 `?.` 只收指针 / map 与值上取到的指针/map 跳；struct 值接收者拒绝；切词按 parser 组合识别（`c?.5 : 1.0` 保持三目）；E53-1–E53-16 全绿 |
| [proposals/ct-bare-metal-proposal.md](proposals/ct-bare-metal-proposal.md) | 裸机生成契约提案（**已采纳并交付**）：v0-PH-64 按本提案收口（`--freestanding` / 按需单元 / `--alloc` / const vtable，见 roadmap） | 查看裸机生成契约提案与落地 |
| [proposals/ct-pkg-index-proposal.md](proposals/ct-pkg-index-proposal.md) | 索引仓提案（**待目标组评估**）：release dispatch + 定时扫描生成、签名/pin、digest 复用、allowlist；不在客户端扫描组织 | 查看包索引维护提案 |
| [proposals/ct-pkg-package-maintainer-rules.md](proposals/ct-pkg-package-maintainer-rules.md) | 包仓维护者规则：`ct.pkg`、semver tag、release dispatch、digest、撤回与安全；配套索引提案 | 查看包仓发布规则 |
| [proposals/ct-max-funcs-growth.md](proposals/ct-max-funcs-growth.md) | 容量切片提案（**已定动态增长，提前到当前 pre 窗口**）：初始 512、按需翻倍、安全阀 65536；固定 512 不再是功能上限；L2 冻结层例外 | 查看容量提案 |
| [proposals/ct-hardware-pilot-proposal.md](proposals/ct-hardware-pilot-proposal.md) | 工程试点提案（**待 Ct 组评估**）：不新增语法，用真实 MCU 验证 Ct 生成 C 的上层业务/驱动封装、交叉编译、volatile/ISR/DMA/ABI/实时性/调试；底层保留 C/汇编 | 查看硬件参考工程提案 |
| [proposals/ct-model-export-proposal.md](proposals/ct-model-export-proposal.md) | 模型导出 `--emit-model` 提案（Phase 59 依据） | 查看编译器模型导出设计 |
| [proposals/ct-str-char-conversion-proposal.md](proposals/ct-str-char-conversion-proposal.md) | 语言侧使用反馈提案（**待项目组评估**）：`Str` → `char *` 借用视图、`char *` → `Str` 三处隐式深拷贝、目标类型决定产出与归属；实现口径与排期由项目组裁定 | 查看字符串接口互操作提案 |
| [reviews/ct-str-char-conversion-battle.md](reviews/ct-str-char-conversion-battle.md) | 上述提案的一轮对抗评审：主张席 C1–C8 判据、反证席 R1–R10 反例与代价、裁判席**部分受理**（借用可存变量、深拷贝限三处、失败改为显式失败返回） | 查看裁定与待决事项 |
| [proposals/ct-str-builtin-type-proposal.md](proposals/ct-str-builtin-type-proposal.md) | 语言侧提案（**待项目组评估**）：`Str` 内置身份、P1/P2/P3、方法映射、借用可存变量与只读布局、不表示空状态、显式失败返回；语言侧可用后 std 保留一个 MINOR 兼容 shim 再移除 | 查看 `Str` 内置化提案 |
| [reviews/ct-str-builtin-type-battle.md](reviews/ct-str-builtin-type-battle.md) | 上述提案的一轮对抗评审与后续裁定：主张席 C1–C8、反证席 R1–R16、裁判席**部分受理**；负责人裁定走语言层、方法层为 C 函数映射 | 查看裁定与待决事项 |
| [reviews/ct-str-null-state-battle.md](reviews/ct-str-null-state-battle.md) | `Str` 空状态问题的一轮对抗评审：不表示无值 / 表示无值 / 可失败构造三条路线；裁判**不受理空状态与静默转空串**，`NULL` 只在构造点显式处理 | 查看空状态裁定 |
| [proposals/ct-pure-type-alias-proposal.md](proposals/ct-pure-type-alias-proposal.md) | 语言侧提案（**待项目组评估**）：现有 `type` 别名的现状评估（部分够用）与放开普通 `.ct` 单元声明；纯同义词、不改判等与赋值、方法随宿主可见、`own` 一致 | 查看纯类型别名提案 |
| [proposals/phase53-optional-chain-draft.md](proposals/phase53-optional-chain-draft.md) | Phase 53 设计记录（已定稿为施工卡）：`?.` 的语义、切词策略、值接收者裁定与 battle 结论；施工以 [phases/v0-PH-53/card.md](phases/v0-PH-53/card.md) 为准 |
| [proposals/user-index-operator.md](proposals/user-index-operator.md) | `REQ-INDEX-1` 设计草案（**已并入 v0-PH-62**）：用户类型下标运算符补完——参数类型匹配、借用视图、缺失语义、复合赋值拒绝清单；含四组两席打与施工切片 |
| [proposals/defect-namespaced-static-method.md](proposals/defect-namespaced-static-method.md) | 缺陷请求（待修）：带 `namespace` 的单元里静态固有方法报 `use of an undeclared variable`；含两种最小复现、边界表、名字解析定位、下游绕法与 N1–N5 判据 |
| [reviews/max-calls-limit.md](reviews/max-calls-limit.md) | 只读核对：`MAX_CALLS` 1024 的计数口径（按已解析自由函数调用表达式）、固定表成因（无「禁止动态分配」证据）、按需增长的改动面与外部包余量实测 |
| [reviews/full-review-latest.md](reviews/full-review-latest.md) | 最新全面评审（v1-pre 收口后）：11 门禁离线 11/11、check-ast 1575/0/5；P1 五项（SH-104/105、phase-ID、G1/G6、MAX_FUNCS 余量、E88-1 承接）与 v1.0 就绪 4/10 | 发布前总检 |
| [reviews/doc-freshness-2026-11-23.md](reviews/doc-freshness-2026-11-23.md) | README/文档样例新鲜度审计：首屏仍以旧特性为主线，新特性被压到速查表；`examples/52_box_new` 的 `ct build` 失败而 compile 门禁未拦住；P0 1 / P1 4 / P2 5，附每周自动审计任务 | 文档发布前检查 |
| [reviews/2026-11-27-str-print-api-review.md](reviews/2026-11-27-str-print-api-review.md) | `Str`/`String` 打印入口提案 REVIEW：方案 A 接受，但 `fwrite`/`stdout` C 边界与“零分配”判据未定，暂不进 DEV | 查看 LANG-30 复核 |
| [reviews/naming-consistency-2026-11-24.md](reviews/naming-consistency-2026-11-24.md) | 语言名书写一致性评审：`Ct` 为散文名、`ct` 为命令/标识符；28 处裸 `ct`（20 处语言名、8 处命令/基线）；AGENTS §1 与 DOC-94 冲突；生成块/`docs/spec` 仍有 `CT`，需上游 CR | 命名规范检查 |
| [reviews/full-review-latest-disposition.md](reviews/full-review-latest-disposition.md) | 该评审处置：接受项落库、争议项 [battle/v1-readiness-1](../battle/v1-readiness-1/verdict.md) 判决、Tier 1/Tier 2 门禁 | 查看处置 |
| [reviews/2026-11-21-v088-external-review-eval.md](reviews/2026-11-21-v088-external-review-eval.md) | 外部 v0.88 评审与惯用卡评估：MAX_FUNCS/SH-104-105 勘误、lib/core 已定 bugfix、SH-73 已裁定 bug、惯用卡逐条修正 | 查看外部评估 |
| [reviews/2026-11-22-grokbot-architecture-assessment-eval.md](reviews/2026-11-22-grokbot-architecture-assessment-eval.md) | GrokBot 外部架构评估核对：规模/测试/容量/许可逐项一致；3 处事实错误（内置层预算、issues 计数、`atomic` 分类）；无新架构项 | 查看外部评估 |
| [reviews/2026-11-22-kimi-v088-review-eval.md](reviews/2026-11-22-kimi-v088-review-eval.md) | Kimi v0.88 评审核对：非 GrokBot 评阅；D4/D5/D6 已闭环、D2 待 SH-110；`MAX_FUNCS` 475/512 为旧数；CLI `warn` 已裁决提前到下一 v0.x（SH-115） | 查看外部评估 |
| [reviews/2026-11-22-four-external-guides-eval.md](reviews/2026-11-22-four-external-guides-eval.md) | 外部四份文档核对：速览有 4 个示例跑不通（ADT 语法/递归/Box API/`#include`）与 3 处布局语义错；内存/性能指南各 4 处需修；惯用卡已归档且过期 | 查看外部文档评估 |
| [reviews/2026-11-22-arena-rename-proposal-eval.md](reviews/2026-11-22-arena-rename-proposal-eval.md) | `std::arena` 改名提议核对：模块/类型命名前提不成立；selfhost 零 `import std::`，路径 B 不触发；真正待办是 std-catalog 与 guide/battle 的 arena 矛盾 | 查看提议评估 |
| [reviews/2026-11-22-kimi-opinion-on-grok-eval.md](reviews/2026-11-22-kimi-opinion-on-grok-eval.md) | Kimi 对 GrokBot 的元评审核对：test/README 已开 TEST-26；DOC-87 已覆盖 `lib/core` + `core::*`；SH-110“修复进行中”不成立；定位/GPL 两项待裁决 | 查看元评审 |
| [reviews/2026-11-22-lib-core-proposal-eval.md](reviews/2026-11-22-lib-core-proposal-eval.md) | lib/core 提案核对：主体与 DOC-87 一致并已提前到 pre 窗口；AutoDrop 不是 trait、LANG-23 时点冲突、`CT → Ct` 需独立 ADR | 查看提案评估 |
| [reviews/2026-11-23-json-v11-proposal-eval.md](reviews/2026-11-23-json-v11-proposal-eval.md) | JSON v1.1 提案核对：递归 ADT 布局、ADT 方法/glue、`map binding`、`match` 表达式 6 项不成立；建议先走 arena/struct 包装或 LANG-27 前置 | 查看提案评估 |
| [reviews/](reviews/) | 历史全面评审（v0.77）：网络挂起、治理门禁缺位、台账未闭合、phase-ID 迁移、文档漂移；其中网络挂起与 C 边界 cwd 已在 v0.88 前修复 | 追溯 |
| [../issues/README.md](../issues/README.md) | 审查发现台账（每条一文件，含状态与处置） |
| [history/README.md](history/README.md) | 历史档案索引：已关闭阶段的设计记录与评审报告 |

目录级说明：[../selfhost/README.md](../selfhost/README.md)（四代编译器与门禁脚本）、
[../test/README.md](../test/README.md)（测试分层）、[../test/bindings/README.md](../test/bindings/README.md)（binding 规约）。

### 文档约定（由 `test/docs/check-docs.py` 校验）

1. **语言**：默认中文；英文仅根 [README.en.md](../README.en.md)（人类阅读，AI 不读）；其他文档不写英文段。
2. **相对链接必须可解析，`#fragment` 必须命中**。节锚点按 GitHub slug 比对（中文保留、
   标点去掉、重复标题依次加 `-1`；目标标题里的行内代码参与 slug）；行号锚点
   `#L10` / `#L10-L20` 只校验 `1 <= a <= b <= 行数`。`docs/history/**` 是冻结快照，
   整棵豁免；历史 issue / battle 里按当时行号写的锚点逐条登记在
   [check-docs.py](../test/docs/check-docs.py) 的 `FRAGMENT_EXEMPT`，新增死锚点仍会红。
   路径豁免：`docs/history/reports/**` 里指向当时存在、现已删除的
   `selfhost/ast/**` 与 `selfhost/src/**` 的链接（历史快照，正文不改写）。
3. **版本标记**：`README.md` 与本文出现的 `vX.Y.Z` 必须是当前版本（取自 `selfhost/l0/ctc.c` 的 `CTC_VERSION`）。
   历史版本只出现在 [history/phase-log.md](history/phase-log.md) 的版本记录与 [history/](history/README.md)。
4. **门禁条数**：`README.md`、本文与 [glossary.md](glossary.md) 写出的硬门禁条数必须等于
   `selfhost/check-all.sh` 实际运行的条数（当前共 8 道硬门禁）。
5. **阶段状态**：`docs/design/phase*.md` 的状态行（完成 / 实施中 / 规划中）必须与 [roadmap.md](roadmap.md)
   的简要阶段表一致（✅ / 🟨 / ⬜）；详细证据见 [history/phase-log.md](history/phase-log.md)。
6. **路线图与流水账**：[roadmap.md](roadmap.md) 只做简要索引，不写逐相叙述；逐相细节、版本记录与决策全文在
   [history/phase-log.md](history/phase-log.md)。
7. **ADR 与 battle 的取代关系**：battle 卡头的 `superseded-by` 与 ADR 的 `superseded-battles`
   必须双向一致；缺一边即红（结构化校验，不做自由文本比对）。
8. **briefing 与 spec 同步**：`docs/idioms.md` 附录里的 briefing 是压缩过的二手事实，
   每条编号断言必须标注 `language-spec.md` 的 `§N`，且该节号必须存在于规范正文；
   节号过时或缺失即红。`idioms.md` 尚未入库时本条由校验脚本跳过，文件落地即自动生效。

校验脚本是 [../test/docs/check-docs.py](../test/docs/check-docs.py)，已接入 `check-all.sh`。
