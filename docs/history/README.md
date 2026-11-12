# 历史档案

> 中文 · [English](#english)
>
> 这里保存**已关闭阶段**的设计记录与评审报告，只作历史索引，不描述现状。当前有效文档见
> [../README.md](../README.md)，阶段总览见 [../roadmap.md](../roadmap.md)。

---

## 中文

> **退役阈值（DOC-66 / D26-20）**：`../design/` 保留最近 12 个已完成阶段（当前在研阶段计入）。
> 新阶段立项时，若序号低于 `max−11` 的 `design/phase*.md` 仍存在，必须在同一次改动里
> `git mv` 到本目录的 `design/` 并在下表补一行；`test/docs/check-docs.py`（门禁 11）会拦截
> 越界文件与同名重复归档。

### design/ —— 已关闭阶段的设计记录

| 记录 | 内容 |
| --- | --- |
| [bootstrap.md](design/bootstrap.md) | 自举链的目标目录结构、分层规则与里程碑（M1–M6） |
| [restore.md](design/restore.md) | Phase 2–4 的恢复式重做（D1–D8） |
| [phase5.md](design/phase5.md) | 新增特性：AutoDrop / 路径敏感泄漏分析 / 目录 = namespace（D9–D14） |
| [phase6.md](design/phase6.md) | 生态与扩展：`map`、反向映射表、增量缓存、多目标、方言（D15–D20） |
| [phase8.md](design/phase8.md) | 包管理与分发 `ct-pkg`（D21–D27） |
| [phase9.md](design/phase9.md) | AST 版编译器（D28–D37） |
| [phase10.md](design/phase10.md) | 主线切换到 ct-ast（D38–D45） |
| [phase12.md](design/phase12.md) | 官方 bindings 与方言深化（D46–D52） |
| [phase17.md](design/phase17.md) | 工程质量与新能力：CI 矩阵、官方 `std`、raw 透传、文档分层、包管理补全、`ct build` 一步到位（D17-1–D17-9；2026-11-10 因 design window 归档） |
| [phase18.md](design/phase18.md) | 生态建设：ct-pkg 组织、包规范与首批包、索引 / CI 复用（D18-1–D18-11；2026-11-11 因 design window 归档） |
| [phase19.md](design/phase19.md) | 受限语义检查：调用点 arity、实参类型粗粒度兼容、trait 方法歧义、跨单元签名、`ct check`（D19-1–D19-5；2026-11-11 因 design window 归档） |
| [phase22.md](design/phase22.md) | `loop` 语法糖：`loop(<次数>)` 展开为单行 `for`，上下文相关关键字与嵌套遮蔽告警（D22-1–D22-12；2026-11-13 因 design window 归档） |
| [borrow.md](design/borrow.md) | `borrow` + `Handback` 的设计与实现记录（D-A…D-D） |
| [dialect.md](design/dialect.md) | 方言系统与作者指南 |
| [next-decisions.md](design/next-decisions.md) | 容量上限策略与第三十三批方向（已定案并落地） |
| [global-mangling.md](design/global-mangling.md) | 全局符号的命名与 mangling 约定 |
| [ns-host-map/](design/ns-host-map/spec.md) | 命名空间静态调用与类型宿主映射 |
| `batch2-*` … `batch39-*` | 第二至三十九批的 `spec` / `tasks` / `checklist`（一个目录一批） |

设计记录是**当时的快照**：行号、路径与「待确认」项都按写作时点保留，冲突时以代码与当前文档为准。

### reports/ —— 评审报告

| 报告 | 主题 |
| --- | --- |
| [repo-review/](reports/repo-review/repo-review.md) | 首轮仓库审查（Phase 4 收口时点） |
| [phase7-review/](reports/phase7-review/phase7-review.md) | Phase 7 复审（`v0.7.0`） |
| [phase9-review/](reports/phase9-review/phase9-review.md) | Phase 9 复审（单文件 `selfhost/ast/main.ct` 时代） |
| [review-2026-10-21/](reports/review-2026-10-21/review-2026-10-21.md) | Phase 12 复审 |
| [review-2026-10-21-round2/](reports/review-2026-10-21-round2/review-2026-10-21-round2.md) | 第二轮复审（同一 HEAD 的更深扫描） |
| [release-readiness-2026-10-21/](reports/release-readiness-2026-10-21/release-readiness-2026-10-21.md) | 发布就绪核对 |
| [audit-2026-10-31/](reports/audit-2026-10-31/audit-2026-10-31.md) | 测试覆盖度与文档一致性审计（`v0.13.0`） |
| [review-2026-10-31/](reports/review-2026-10-31/review-2026-10-31.md) | 代码审查 + 文档一致性审查（`v0.15.1`） |
| [review-2026-11-01/](reports/review-2026-11-01/review-2026-11-01.md) | `borrow` / `Handback` 实现审查（`v0.15.1`） |
| [review-2026-11-02/](reports/review-2026-11-02/review-2026-11-02.md) | Phase 18 生态建设与 `v0.18.0` 收口审查 |
| [review-2026-11-03/](reports/review-2026-11-03/review-2026-11-03.md) | Phase 19 受限语义检查与 `v0.19.0` 审查 |
| [evaluation-2026-11-03-v0181/](reports/evaluation-2026-11-03-v0181/evaluation-2026-11-03-v0181.md) | 外部评估（`v0.18.1` + `v0.19.1` 附录）与复核意见 |
| [ct-language-features/](reports/ct-language-features/ct-language-features.html) | 语言特性全景（自包含 HTML） |
| [ctc-ct-analysis/](reports/ctc-ct-analysis/ctc-ct-analysis.html) | `ctc.c` 与 CT 线的对照分析（自包含 HTML） |
| [selfhost-readiness/](reports/selfhost-readiness/selfhost-readiness.html) | 自举就绪总结（自包含 HTML） |

报告正文里的行号与路径是**当时 commit 的快照**；指向已删除的 `selfhost/ast/**`、`selfhost/src/**` 的链接
按历史保留，不再改写（这是文档链接门禁唯一的豁免）。

---

## English

> **Retirement threshold (DOC-66 / D26-20)**: `../design/` keeps the newest 12 completed phases (the
> phase in progress counts). When a new phase starts, any `design/phase*.md` below `max−11` must be
> `git mv`-ed into `design/` here and added to the table below in the same change;
> `test/docs/check-docs.py` (gate 11) rejects out-of-window files and duplicate archives.

> Closed-phase design records and review reports; an index only, not a statement of the present.
> Live documentation starts at [../README.md](../README.md); the phase overview is
> [../roadmap.md](../roadmap.md).

### design/ — records of closed phases

| Record | Content |
| --- | --- |
| [bootstrap.md](design/bootstrap.md) | the bootstrap chain: target layout, layering rules and milestones (M1–M6) |
| [restore.md](design/restore.md) | the Phase 2–4 recovery work (D1–D8) |
| [phase5.md](design/phase5.md) | new features: AutoDrop / path-sensitive leak analysis / directory = namespace (D9–D14) |
| [phase6.md](design/phase6.md) | ecosystem: `map`, the reverse mapping table, the incremental cache, multi-target, dialects (D15–D20) |
| [phase8.md](design/phase8.md) | package management and distribution, `ct-pkg` (D21–D27) |
| [phase9.md](design/phase9.md) | the AST compiler (D28–D37) |
| [phase10.md](design/phase10.md) | the mainline switch to ct-ast (D38–D45) |
| [phase12.md](design/phase12.md) | official bindings and dialect deepening (D46–D52) |
| [phase17.md](design/phase17.md) | engineering quality and new capabilities: CI matrix, official `std`, raw passthrough, documentation layering, package-manager completion and one-step `ct build` (D17-1–D17-9; archived on 2026-11-10 under the design window) |
| [phase18.md](design/phase18.md) | ecosystem build-out: the ct-pkg organisation, package conventions, the first package wave and index / CI reuse (D18-1–D18-11; archived on 2026-11-11 under the design window) |
| [phase19.md](design/phase19.md) | bounded semantic checks: call-site arity, coarse argument-type compatibility, trait-method ambiguity, cross-unit signatures and `ct check` (D19-1–D19-5; archived on 2026-11-11 under the design window) |
| [phase22.md](design/phase22.md) | `loop` sugar: `loop(<count>)` lowers to one `for` line, with a contextual keyword and a nested-shadowing warning (D22-1–D22-12; archived on 2026-11-13 under the design window) |
| [borrow.md](design/borrow.md) | `borrow` + `Handback` design and landing record (D-A…D-D) |
| [dialect.md](design/dialect.md) | the dialect system and the authoring guide |
| [next-decisions.md](design/next-decisions.md) | capacity-limit policy and the batch-33 direction (decided and landed) |
| [global-mangling.md](design/global-mangling.md) | global symbol naming and mangling |
| [ns-host-map/](design/ns-host-map/spec.md) | namespaced static calls and type-hosted mapping |
| `batch2-*` … `batch39-*` | the `spec` / `tasks` / `checklist` of batches 2–39 (one directory each) |

These records are **snapshots**: line numbers, paths and open questions stay as written; the code and today's
documents win on conflict.

### reports/ — review reports

| Report | Topic |
| --- | --- |
| [repo-review/](reports/repo-review/repo-review.md) | first repository review (at the Phase 4 close) |
| [phase7-review/](reports/phase7-review/phase7-review.md) | Phase 7 review (`v0.7.0`) |
| [phase9-review/](reports/phase9-review/phase9-review.md) | Phase 9 review (the single-file `selfhost/ast/main.ct` era) |
| [review-2026-10-21/](reports/review-2026-10-21/review-2026-10-21.md) | Phase 12 review |
| [review-2026-10-21-round2/](reports/review-2026-10-21-round2/review-2026-10-21-round2.md) | second round (a deeper scan of the same HEAD) |
| [release-readiness-2026-10-21/](reports/release-readiness-2026-10-21/release-readiness-2026-10-21.md) | release-readiness check |
| [audit-2026-10-31/](reports/audit-2026-10-31/audit-2026-10-31.md) | test-coverage and documentation audit (`v0.13.0`) |
| [review-2026-10-31/](reports/review-2026-10-31/review-2026-10-31.md) | code and documentation review (`v0.15.1`) |
| [review-2026-11-01/](reports/review-2026-11-01/review-2026-11-01.md) | `borrow` / `Handback` implementation review (`v0.15.1`) |
| [review-2026-11-02/](reports/review-2026-11-02/review-2026-11-02.md) | Phase 18 ecosystem build-out and the `v0.18.0` close review |
| [review-2026-11-03/](reports/review-2026-11-03/review-2026-11-03.md) | Phase 19 restricted semantic check and the `v0.19.0` review |
| [ct-language-features/](reports/ct-language-features/ct-language-features.html) | a language-feature survey (self-contained HTML) |
| [ctc-ct-analysis/](reports/ctc-ct-analysis/ctc-ct-analysis.html) | `ctc.c` versus the CT line (self-contained HTML) |
| [selfhost-readiness/](reports/selfhost-readiness/selfhost-readiness.html) | self-hosting readiness summary (self-contained HTML) |

Line numbers and paths inside the reports are **snapshots of the commit under review**; links into the deleted
`selfhost/ast/**` and `selfhost/src/**` are kept as history (the only exemption of the documentation link gate).
