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

- 不在 v1.0 内重写 ct-ast（仍归 v1.1 S1，见 §2）；
- 不把 A strict 作为 v1.0 门禁（仍归 v1.1 S2）；
- 不在本线内做 ADT/match；
- 不改语言语义、发射格式、命名契约。

## 2. v1.1：现代语法重写 + A

### 2.1 为什么拆成两段

“全面用最新语法重写 ct-ast”是**大范围行为保持重构**；“A 全量类型/语义进编译路径”是**产品契约变更**。
两者都很大，不能塞进一个普通 task，但按新编号规则它们属于**同一个 phase 的两个 stage**：

- `v1-PH-1 / S1`：ct-ast 语法现代化（行为保持）；
- `v1-PH-1 / S2`：A strict 编译路径（依赖 B + S1）。

S1/S2 不是两个 phase，不分别 bump；v1.1.0 在 S2 收口时只 bump 一次 MINOR。

### 2.2 S1：ct-ast 语法现代化

- 只改 `selfhost/ct-ast/**` 源码，不改用户可见语义/生成 C 行为；
- 用 v1.0 已冻结的语法：`defer`/`?`/`foreach`/模式/`own`/`borrow`/泛型/trait 等，按适用性逐项采用；
- 先做 inventory：哪些旧写法可用新特性替代、预计行数/风险；不“为用而用”；
- 每批任务保持：自举不动点、全量语料生成 C 不变、行为等价；
- 出口：源码可读性/重复度指标改善；无用户可见变化；独立回退。

### 2.3 S2：A（strict 编译路径）

- 以 B1–B4 已完成为前提；A 不是从零重写，而是把 B 的 checker 接到 `ct build --strict`；
- 先 opt-in：`ct build --strict`、新包默认 strict；普通 C 兼容模式保留；
- 进入条件（缺一不可）：
  1. 合法语料 FP=0，且有固定漏报矩阵；
  2. 123 个 import 单元可检，跨单元类型一致；
  3. CFG/定值/return/控制流可用；
  4. 编译时间预算达标（建议 ≤ +10%，H0 冻结）；
  5. 诊断码稳定、迁移说明；
  6. S1 已完成，源码不被旧写法拖累。
- 出口：strict 模式编译路径强制；C 兼容模式不强制；默认全局 strict 留到 v2.0 决策。

### 2.4 A 的“工业级”定位

A 是**终局**，但 v1.1 只承诺“strict profile 可强制”，不承诺：
- Rust 级借用检查；
- 全 C UB/ABI/格式串检查；
- 所有历史 C 代码零迁移；
- 全局默认 strict。

### 2.5 重写前置（2026-11-21 已定项）

> 重写**是否仍在 v1.1**是无争议的（§1.6）；“是否提前到 v1.0”见 §6，未定前不改变本节。

1. **inventory 先行**：按子系统列出“旧写法 → 新特性 → 预计行数 → 风险”，不直接开写；
2. **单切片 spike**：先选一个子系统（建议词法器或发射器）做完整等价重写，产出：
   - 行数前后对比、编译耗时前后对比；
   - 全量 golden 逐字节一致的原始输出；
   - 暴露的 sharp edge 清单（如 `Str` 非 NUL 结尾与 `strcmp`/`%s` 的冲突）；
3. **spike 通过后才排后续切片**；不通过则退化为“按 inventory 逐项替换”，不承诺整体重写；
4. **自举回环复用现有门禁**：`check-ast` 已有“自编译 + 重建逐字节一致”的不动点段，
   扩展它，不另造第三套自举脚本；
5. **依赖边界**：重写不得依赖未落地的语言特性（如 S4 函子）；确需依赖时先立特性卡。

## 3. 版本与 release train

| 里程碑 | phase | 版本 | 说明 |
| --- | --- | --- | --- |
| B 类型核心 | v0-PH-68 | v0.67.0 | opt-in |
| B 跨单元 | v0-PH-69 | v0.68.0 | opt-in |
| B CFG | v0-PH-70 | v0.69.0 | opt-in |
| B own/borrow | v0-PH-71 | v0.70.0 | opt-in |
| v1.0 AST-only | `v1-PH-0` | **v1.0.0** | 新 major 首相；`MINOR=0` |
| v1.1 语法现代化 | `v1-PH-1 / S1` | v1.1 train | 行为保持，不单独 bump |
| v1.1 A strict | `v1-PH-1 / S2` | **v1.1.0** | 同一 phase 的 S2；一次 MINOR |

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
2. 开 `v1-PH-0`（v1.0），先定 seed，再退 L1/L2；
3. 开 `v1-PH-1 / S1`，现代语法重写 ct-ast，行为保持；
4. 开 `v1-PH-1 / S2`，A strict 编译路径；
5. v2.0 再讨论全局默认 strict。

不建议把“去旧代码”“语法重写”“A 全量检查”塞进同一个 phase。

## 6. 争议项（讨论中，未落计划）

> 来源：外部《v1.0 收口战役》提案（2026-11-21）。以下各项**尚未裁定**，不改变
> §1.3/§1.5/§1.6/§2 的现行安排；讨论记录见
> [2026-11-21 评估](../reviews/2026-11-21-v1-campaign-eval.md)。

| # | 争议 | 提案方主张 | 现行计划 | 需要决定 |
| --- | --- | --- | --- | --- |
| D1 | 重写是否提前到 v1.0 | 提前，v1.0 发布“两级自举 + 自证语法” | 重写归 v1.1 S1 | 是否重排 major 里程碑 |
| D2 | A strict 是否作为 v1.0 门禁 | 是（G4） | 归 v1.1 S2 | v1.0 的“产品契约”是否扩大到 A |
| D3 | ADT/match 是否插入战役 | 可选先行，不阻塞 | 无 phase，未排期 | 是否单独立项、何时 |
| D4 | 重写是否可用函子签名 | 检查器用“闭包 + 函子” | S4 函子延后 v1.1+ Wave 2 | 是否先落函子特性卡 |
| D5 | hard deadline ≤6 phase | 建议 6 | 项目不承诺时间 | 是否设 deadline、砍范围顺序 |
| D6 | 重写期主线是否冻结 | 倾向不冻结 + 切片 rebase | 未定义 | 冻结策略与合入门禁 |
| D7 | G7 页首版本注入 | 页首注入版本 | DOC-63：spec 页首不钉版本 | 注入范围（建议仅生成物/README） |
| D8 | 三轮自举是否新建 | 新建三轮回环 | 现有 fixpoint 已覆盖自编译等价 | 扩展现有门禁还是另建 |
| D9 | 收益预估（-20~30%） | 按子系统估算 | 无实测 | 先做 §2.5 单切片 spike 再评估 |

> 争议项收敛方式：先在 `battle` 或 CR 中出结论，再改本文件与 roadmap；
> 未收敛前不得在 phase 卡里提前落实现代码。
