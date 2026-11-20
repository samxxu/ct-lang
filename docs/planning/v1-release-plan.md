# v1.0 / v1.1 发布路线（规划中）

| 项 | 值 |
| --- | --- |
| 性质 | 产品发布路线；**未开卡**，不占 phase、不 bump |
| 日期 | 2026-11-18 |
| 基线 | `ed172075`（`v0.65.1`；Phase 66 已收口） |
| 依据 | [typecheck-semantic-plan](typecheck-semantic-plan.md)、[battle typecheck-1](../../battle/typecheck-1/verdict.md) |
| 结论 | **B 在 v1.0 前完成并 opt-in；v1.0 只保留 AST 主线；v1.1 先做 ct-ast 语法现代化，再做 A（strict 编译路径）** |

## 0. 一句话

v1.0 = AST-only + 去掉旧管线 + B 检查器可用（opt-in）；v1.1 = 先用新语法重写 ct-ast 自身，
再把 A（全量类型/语义 strict）接到编译路径。**A 不在 v1.0，也不做“一次大爆炸”。**

## 1. v1.0：AST-only 收口

### 1.1 目标

- 开发主线只有 `selfhost/ct-ast/**`；
- `selfhost/l1/**`、`selfhost/l2/**` 不再参与构建、CI、golden、oracle；
- `ct build/compile` 仍不做全量类型检查；B 的 `ct check` 可用但 opt-in；
- 语言在 v1.0 冻结，后续只做兼容性修复/明确版本化变更。

### 1.2 必须先决定：bootstrap seed

“只有 AST 自举”不等于“零 seed”。从源码构建仍需要一个可信起点：

| 方案 | 内容 | 评价 |
| --- | --- | --- |
| A. 保留 L0 C seed | `selfhost/l0/ctc.c` 只做 bootstrap，不参与功能开发 | **推荐**；最小、可审计、可复现 |
| B. 生成 C seed | 从 ct-ast 生成一份 `bootstrap/ct-ast.c`，L0/L1/L2 全退 | 可行；体积大、生成物需冻结与审计 |
| C. 只发二进制 | 不提供源码自举 | 不推荐；破坏可复现/开源构建 |

**建议 v1.0 选 A 或 B；不要在没有 seed 的情况下删 L0。** L1/L2 可以移除/归档，L0 或生成 seed
必须保留。若“旧代码”指 L1/L2 旧管线，v1.0 可以做到；若连 L0 也删，必须选 B 并接受生成物入库。

### 1.3 v1.0 范围

| 项 | 内容 |
| --- | --- |
| 构建 | `install.sh` 改为 seed → ct-ast，不再 L1→L2；`ctc` 兼容别名保留 |
| 门禁 | `check-goldens.sh`/`check-archive.sh` 的 L1/L2 段退役；换成 AST-only 回归、seed 重建、行为等价 |
| 代码 | L1/L2 移到 `history/` 或删除；归档 tag 保留；`docs/agents` 同步 |
| 语言 | 冻结；B 的检查器 opt-in，不强制 |
| 迁移 | 旧工程仍用 v0.x 编译器；v1.0 不承诺接受所有旧内部语法 |
| 版本 | `v1.0.0` 是 MAJOR；按 [phase-numbering-major-reset](../proposals/phase-numbering-major-reset.md) 用 `v1-PH-0`，`MINOR=0`；提案未生效前仍按旧规则登记 deviation |

### 1.4 退出条件

- 干净环境只靠 seed 能构建 ct-ast 并自举；
- 全量语料/示例通过 AST-only 门禁；
- L1/L2 不再被任何构建/CI/文档引用（历史说明除外）；
- B1–B4 的检查器已可用，但默认不阻断 `ct build`；
- 版本/安装/文档/迁移说明齐全。

### 1.5 v1.0 发布前清单（2026-11-21 已定项）

> 来源：外部《v1.0 收口战役》提案评估（[2026-11-21 评估](../reviews/2026-11-21-v1-campaign-eval.md)）。
> 只收录**无争议**项；重写时序、A-strict 门禁、ADT 等见 §6，未定前不落计划。

| # | 事项 | 验收 | 跟踪 |
| --- | --- | --- | --- |
| V1-C1 | J-6 全量证据台账（P-1…P-6）+ J-3/J-4/J-5 逐张核对 | 台账零未决；“已实施未验证”清零 | [SH-104](../../issues/selfhost/sh104-j6-evidence-ledger.md) |
| V1-C2 | goldens 静态化（去 L1/L2 的前置） | 静态期望文件覆盖全部语料；`ct-ast vs 静态 golden` 可独立跑 | [SH-105](../../issues/selfhost/sh105-goldens-static-freeze.md) |
| V1-C3 | SH-73 解除 + README §0.1 三断点闭环 | 完整路径可原样书写并钉入 `test/ast` | [SH-73](../../issues/selfhost/sh73-temp-receiver-dynamic-dispatch.md) |
| V1-C4 | 稳定子集冻结清单成文（三档 + 改动授权级别） | 成文且进 check-docs 断言 | [DOC-79](../../issues/docs/doc-79-stable-subset-freeze-list.md) |
| V1-C5 | 兼容承诺重述“不再是 C 超集” | README / spec / roadmap 三处同步 | [DOC-76](../../issues/docs/doc-76-no-longer-c-superset.md) |
| V1-C6 | 能力标签→spec 节号一致性断言 | check-docs 可机器判；版本只注入生成物/README，**不钉 spec 页首**（DOC-63） | [DOC-77](../../issues/docs/doc-77-capability-spec-section-assertions.md) |
| V1-C7 | 新特性文档核对（String/Str/切片/ref-out/box/new） | spec §4.68–§4.70 已存在；补 box/new/patterns 与一致性断言 | [DOC-78](../../issues/docs/doc-78-new-feature-docs-audit.md) |
| V1-C8 | 包体系收尾：第三方真实包 fixture + `ct index verify` 进 CI | 固定 fixture 可重放；CI 常规跑 | [PKG-17](../../issues/packages/pkg-17-third-party-fixture-ci.md) |

### 1.6 v1.0 不包含（已定）

- 不在 v1.0 内重写 ct-ast（归 v1-pre：PH-85…88，见 §2.3）；
- A 的**默认强制**不作为 v1.0 门禁（归 v1.1 S2）；但 **A 的机制**在 PH-85 接线，
  **A 的证据**（全量 FP=0）是 v1.0 硬门禁（D2 = B+）；
- 不在本线内做 ADT/match；
- 不改语言语义、发射格式、命名契约。

## 2. v1-pre：编译器现代语法重写 + v1.1：A strict

> D1 已定（2026-11-21）：重写**不进 v1.0、也不推到 v1.1**，而是在 v0.x 序列里插入
> **v1-pre 阶段（PH-85…PH-88）**；D3 已定：**ADT/match（PH-84）先行**，
> 重写用穷尽 match 替换 `node->kind` 判别。v1.0 在 PH-88 之后发布，v1.1 只保留 A 默认强制。

### 2.1 为什么分四段

- **ADT 前置（PH-84）**：最小 ADT/match，语言新增；为重写提供穷尽判别；
- **v1-pre（PH-85…88）**：ct-ast 用最新语法重写，行为保持；大范围重构，必须独立隔离；
- **v1.0（v1-PH-0）**：AST-only 收口、去 L1/L2、证据台账；在重写之后做快照发布；
- **v1.1（v1-PH-1 / S2）**：A 默认强制，产品契约变更。

四者不塞进同一个 phase；各 phase 独立 bump MINOR（v0.84–v0.88）。

### 2.2 S1：ct-ast 语法现代化（v1-pre，PH-85…88）

- 只改 `selfhost/ct-ast/**` 源码，不改用户可见语义/生成 C 行为；
- 用 v1.0 前已冻结的语法：`defer`/`?`/`foreach`/`own`/`borrow`/泛型/trait，以及 PH-84 的最小 ADT/match；按适用性逐项采用；
- 先做 inventory（PH-85）：哪些旧写法可用新特性替代、预计行数/风险；不“为用而用”；
- 每批任务保持：自举不动点、全量语料生成 C 不变、行为等价；
- **不依赖函子签名**（D4 已定）：检查器用既有闭包 / trait / 函数指针表达；
  S4 函子仍留 v1.1+ Wave 2；
- 出口：源码可读性/重复度指标改善；无用户可见变化；独立回退。

### 2.3 v1-pre 重写 train（PH-84…88，D1/D3 已定）

| phase | 版本 | 内容 | 入口 | 出口 |
| --- | --- | --- | --- | --- |
| PH-84 | v0.84.0 | **最小 ADT/match**：名义和类型 + 构造器负载 + 穷尽 match + 变量绑定 | PH-83 收口 | tag 判别可机械替换为穷尽 match；漏分支进 golden 负例；合法语料零误报 |
| PH-85 | v0.85.0 | inventory + 单切片 spike（门）+ **M0 粗切**（5–6 单元，零精细分类）+ **A 机制接线** | PH-84 收口（含 S84e 文档一致性） | spike 报告 + M0 集合基线/映射 + 状态清单；A 机制可用且默认不变 |
| PH-86 | v0.86.0 | 词法器重写（零拷贝 `Str` 切片；NUL/长度契约） | PH-85 | 测试语料发射逐字节不变；自身发射允许差异（自举+ASan+行为测试） |
| PH-87 | v0.87.0 | 解析器 + 检查器重写 | PH-86 | 测试语料发射逐字节不变；诊断文本不变 |
| PH-88 | v0.88.0 | 发射器重写 + 扩展自举不动点（轮数参数化） | PH-87 | 每切片 2 轮、tag 前 3 轮逐字节一致；行数报告落 history |

> PH-84 的 ADT 范围按 D3-A：**只做**名义和类型、负载、穷尽检查、变量绑定；
> 泛型 ADT、or 模式、嵌套模式登记为 v1.1+ 增量提案。若 spike 证明某类节点形态
> （如变长负载）无法覆盖，允许在 A 内增补该单一形态，不升级为泛型/全功能。
> **PH-84 还包含 S84e 文档一致性**：范围由 [battle doc-consistency-1](../../battle/doc-consistency-1/question.md)
> 决定；PH-85 入口要求它一起收口（详见 [PH-84 §1.4/§2](../design/phase84.md)）。

- 每张卡独立合入、独立回滚；同一时刻只允许一张施工卡；
- 任一阶段不通过，停在原地，不进入下一阶段；
- **不设 hard deadline**（D5 已定）：沿用项目“不承诺时间”口径，不用日历或 phase 数倒逼范围；
- **重写期冻结策略**（D6 已定 A）：从 PH-85 开始到 PH-88 收口，主线**只收 bugfix**，
  新特性暂停；每张重写卡独占合入，不做“特性 + rebase”并行。PH-84 的 ADT 不在冻结窗口内。

### 2.4 A：机制 / 证据 / 默认值（D2 已定：B+）

> D2 已定（2026-11-21）：三件事解耦——**机制立即在 v0.x 落地，证据作为 v1.0 门禁，
> 默认值由 v1-pre 窗口证据决定**。C（把发布闸门绑在存量 FP 未知数上）不采纳。

| 层 | 内容 | 落点 |
| --- | --- | --- |
| **机制** | 把 B 的 checker 接进 build 路径，提供 `off / warn / error` 严重级别阶梯；默认值先保持 off | **PH-85（v0.85.0）**，与 inventory+spike 同卡 |
| **证据** | 全量语料 FP=0、固定漏报矩阵、123 个 import 单元、CFG/定值、编译时间 ≤+10%、诊断码稳定 | **v1.0 硬门禁**（v1-PH-0） |
| **默认值** | v1-pre 窗口内：证据推进时默认 warn；证据达标升 error；pre 不足则维持 warn/可用，默认强制顺延到 v1.1 | v1.1 S2；不达标即 D 回退 |

- 机制必须在重写前就位：42.8k 行新代码要在“有检查”的环境里写，这是 A 的最大规模 dogfood；
- v1.0 承诺的是“**检查器可信**”（证据达标），不是“默认强制”；
- 若 v1-pre 窗口证据不足，落到“可用但不默认”（D 回退），因机制已就位，顺延零成本；
- 普通 C 兼容模式始终保留；全局默认 strict 仍留 v2.0 讨论。

### 2.5 A 的“工业级”定位

A 是**终局**，但 v1.1 只承诺“strict profile 可强制”，不承诺：
- Rust 级借用检查；
- 全 C UB/ABI/格式串检查；
- 所有历史 C 代码零迁移；
- 全局默认 strict。

### 2.6 重写前置细则（PH-85 门）

> D1/D3 已定（§2.3）：PH-84 先做 ADT/match，重写在 PH-85…88；v1.0 之后只保留快照发布。
> 本节是 PH-85 的执行细则，不改变 phase 划分。

1. **inventory 先行**：按子系统列出“旧写法 → 新特性 → 预计行数 → 风险”，不直接开写；
2. **单切片 spike**：先选一个子系统（建议词法器或发射器）做完整等价重写，产出：
   - 行数前后对比、编译耗时前后对比；
   - 全量 golden 逐字节一致的原始输出；
   - 暴露的 sharp edge 清单（如 `Str` 非 NUL 结尾与 `strcmp`/`%s` 的冲突）；
3. **spike 通过后才排后续切片**；不通过则退化为“按 inventory 逐项替换”，不承诺整体重写；
4. **自举回环复用现有门禁**（D8 已定 A）：`check-ast` 已有“自编译 + 重建逐字节一致”的
   不动点段；扩展它，不另造脚本。**轮数参数化**：日常/每切片 2 轮，v1.0 tag 前 3 轮，
   同一套比对逻辑，零代码分叉；
5. **依赖边界**：重写不得依赖未落地的语言特性（如 S4 函子）；确需依赖时先立特性卡。

### 2.7 单元切分 M0/M1（D-017 已定）

> 提案 v3 的落点：**M0 粗切并入 PH-85，R 不变，M1 落 v1.1**。
> 完整裁定见 [D-017](../decisions/D-017.md)、[评估](../reviews/2026-11-21-unit-split-eval.md)。

- **时序**：PH-84 ADT → PH-85 inventory+spike + **M0 粗切** + A 机制 → PH-86–88 R → v1.0 → v1.1 S1 **M1 精细切分** → S2 A；
- **M0**：按子系统粗切 5–6 个单元，不做精细分类；目的是降低 R 期间 diff 噪声；
- **M1**：纯搬移落位，v1.1 第一个 stage；不影响 v1.0；
- **两级判据**：测试语料发射逐字节不变；编译器自身发射允许差异，靠自举不动点 + ASan + 行为测试；
- **集合基线**：每个命令有期望文件集合 + 旧→新映射；M0/M1 可有意变更，但同一 commit 更新基线；
- **J1**：函数体哈希集合不变 + 机械行白名单（import/include/声明重排）；
- **J4**：M 不新增 import 环；现状环清单先交，破环单独成案；
- **状态/命名**：先交文件级状态清单与归属规则；单元名 `<Subsystem><Role>.h.ct`（PascalCase、全局唯一）；
- **单写者**：M0/M1 期间同一时刻只有一个会话持有搬移分支；合入窗口要求 `check-all` 全绿；
- **事实修正**：函数/全局可先用后定义；类型/trait 必须先声明。token 的 `Str` 生命周期覆盖解析阶段。

## 3. 版本与 release train

| 里程碑 | phase | 版本 | 说明 |
| --- | --- | --- | --- |
| B 类型核心 | v0-PH-68 | v0.67.0 | opt-in |
| B 跨单元 | v0-PH-69 | v0.68.0 | opt-in |
| B CFG | v0-PH-70 | v0.69.0 | opt-in |
| B own/borrow | v0-PH-71 | v0.70.0 | opt-in |
| ADT/match（最小） | PH-84 | v0.84.0 | 语言新增；只为重写提供穷尽判别 |
| v1-pre inventory+spike+M0 | PH-85 | v0.85.0 | 门：通过才排后续；含 M0 粗切 + A 机制接线 |
| v1-pre 词法器 | PH-86 | v0.86.0 | 行为保持 |
| v1-pre 解析+检查 | PH-87 | v0.87.0 | 行为保持 |
| v1-pre 发射器+回环 | PH-88 | v0.88.0 | 三轮逐字节一致 |
| v1.0 AST-only | `v1-PH-0` | **v1.0.0** | 新 major 首相；`MINOR=0`；在 PH-88 之后 |
| v1.1 M1 精细切分 | `v1-PH-1 / S1` | v1.1 train | 纯搬移；不单独 bump |
| v1.1 A 默认强制 | `v1-PH-1 / S2` | **v1.1.0** | 机制已在 PH-85；证据达标则翻转默认，未达标回退“可用不默认” |

> 该编号依赖 [phase-numbering-major-reset](../proposals/phase-numbering-major-reset.md)
> 被主规范受理。未受理前，v1.0/v1.1 仍按旧规则登记 `major-release`/`release-train` deviation；
> 不手改 AGENTS 生成块。

## 4. 风险

| 风险 | 处置 |
| --- | --- |
| 删 L0 后无法自举 | 先定 seed 方案；A 或 B，不能空 |
| 删 L1/L2 丢 oracle | 用 seed 重建 + AST-only 行为等价；历史 tag 保留 |
| 语法现代化改变生成 C | 每批任务固定“用户可见输出不变”；自举不动点 |
| A 在 v1.1 被误当 sound | strict profile 文档写清边界；C 兼容模式保留 |
| v1.1 同时做重构和 A 太大 | 同一 `v1-PH-1` 的 S1/S2，独立任务/回退 |
| 版本规则冲突 | 先走 major-reset CR；未受理前登记 deviation，不绕过 `g1-version`/`g8-version` |

## 5. 建议顺序

1. 完成 B（v0-PH-68–71），保持 opt-in；
2. 开 `PH-84`（v0.84.0）：最小 ADT/match；
3. 开 `PH-85`（v0.85.0）：inventory + 单切片 spike（门）+ M0 粗切 + A 机制接线；
4. 依次开 `PH-86` 词法器、`PH-87` 解析+检查、`PH-88` 发射器+回环（v1-pre）；
5. 开 `v1-PH-0`（v1.0），先定 seed，再退 L1/L2；
6. 开 `v1-PH-1 / S1`（M1 精细切分）→ `S2`（A 默认强制）；
7. v2.0 再讨论全局默认 strict。

不建议把“去旧代码”“语法重写”“A 全量检查”塞进同一个 phase。

## 6. 争议项裁定记录（D1–D9 全部已定）

> 来源：外部《v1.0 收口战役》提案（2026-11-21）。**D1–D9 全部已定**，裁定已并入
> §1.3/§1.5/§1.6/§2；讨论记录见 [2026-11-21 评估](../reviews/2026-11-21-v1-campaign-eval.md)。
> 后续若需改判，按 D-014 式 ADR 或 battle 显式覆盖，不改本表历史。

| # | 争议 | 提案方主张 | 现行计划 | 需要决定 |
| --- | --- | --- | --- | --- |
| D1 | 重写是否提前到 v1.0 | 提前，v1.0 发布“两级自举 + 自证语法” | **已定**：ADT 先行（PH-84），重写为 v1-pre（PH-85…88），不进 v1.0、不推 v1.1 | — |
| D2 | A strict 与 v1.0 | 是（G4） | **已定 B+**：机制 PH-85 接线；证据 FP=0 为 v1.0 硬门禁；默认值由 v1-pre 证据决定，不足则回退“可用不默认” | — |
| D3 | ADT/match 是否插入战役 | 可选先行，不阻塞 | **已定 B（A 范围）**：PH-84 先做最小 ADT/match；泛型/or/嵌套留 v1.1+ | — |
| D4 | 重写是否可用函子签名 | 检查器用“闭包 + 函子” | **已定 A**：不依赖函子；用既有闭包/trait/函数指针；S4 仍留 v1.1+ Wave 2 | — |
| D5 | hard deadline ≤6 phase | 建议 6 | **已定 A**：不设 deadline；失败就地停，不用时间/phase 数倒逼范围 | — |
| D6 | 重写期主线是否冻结 | 倾向不冻结 + 切片 rebase | **已定 A**：PH-85–88 主线只收 bugfix，新特性暂停；切片独占合入 | — |
| D7 | G7 页首版本注入 | 页首注入版本 | **已定 A**：版本只注入 README/生成物，spec 页首保持 DOC-63；能力→节号断言进 check-docs（V1-C6） | — |
| D8 | 三轮自举是否新建 | 新建三轮回环 | **已定 A**：扩展现有 fixpoint，轮数参数化（日常 2 轮、tag 前 3 轮），不新建脚本 | — |
| D9 | 收益预估（-20~30%） | 按子系统估算 | **已定 A**：以 PH-85 spike 实测为准，不承诺区间；行数/耗时报告落 history |

> 收敛方式：裁定先入本表与 roadmap，再开 phase 卡；未入库前不得在卡里提前落实现代码。
> 改判需显式 ADR/battle 覆盖，不改本表历史。
