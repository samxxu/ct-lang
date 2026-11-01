# 审查发现的问题（issues）

> **历史快照（2026-10-21）**：下文早期段落引自 `selfhost/ast/**`（单文件主线）与 `selfhost/src/**` 时代，
> 这些路径**已不存在**；等价路径为 `selfhost/ct-ast/**`（分组多单元主线）与 `selfhost/l2/**`
> （冻结的回归 oracle）。历史段落保持原样，条目状态未逐条回填。

本目录汇总八轮审查的发现：[reports/repo-review](../reports/repo-review/repo-review.md)（首轮）、
[reports/phase7-review](../reports/phase7-review/phase7-review.md)（Phase 7 复审）、
[reports/phase9-review](../reports/phase9-review/phase9-review.md)（Phase 9 复审）、
[reports/review-2026-10-21](../reports/review-2026-10-21/review-2026-10-21.md)（Phase 12 复审）、
[reports/review-2026-10-21-round2](../reports/review-2026-10-21-round2/review-2026-10-21-round2.md)（第二轮复审）、
[reports/audit-2026-10-31](../reports/audit-2026-10-31/audit-2026-10-31.md)（测试覆盖度与文档一致性审计）与
[reports/review-2026-10-31](../reports/review-2026-10-31/review-2026-10-31.md)（代码审查 + 文档一致性审查）、
[reports/review-2026-11-01](../reports/review-2026-11-01/review-2026-11-01.md)（`borrow` / `Handback` 实现审查）。
**每条 issue 一个 markdown 文件，按模块分目录存放**；Phase 9 复审的发现由下文「Phase 9 复审」一节承载，未另立文件。

- 源码锚点：首轮 `8aac450`；Phase 7 复审 `ec97f99`（2026-10-17）；Phase 9 复审 `8010875`（2026-10-19）；Phase 12 复审 `4ef8b68`（2026-10-21）；第二轮复审 `dde0dda`（2026-10-21）；审计 `f4c77b1`（2026-10-31，`v0.13.0`）；代码审查 `524ba99`（2026-10-31，`v0.15.1`）；`borrow` 实现审查 `8b047f5`（2026-11-01，工作树含在途改动）——各文件行号以其自身锚点为准。
- 状态：首轮 12 条**已全部修复**；Phase 7 复审新增 8 条**均已处理**（DOC-6–9 修复、TEST-4 修复、TEST-5/6 部分覆盖、SH-3 已决策）；Phase 9 复审 14 项发现**全部关闭**（逐项见下文「Phase 9 复审」一节，复核于 v0.10.0 `885d01b`）；Phase 12 复审新增 8 条**已于 2026-10-21 全部修复**（DOC-10–15、SH-5、SH-6）；第二轮复审新增 8 条（SH-8…SH-12、DOC-19…DOC-21）**已于 2026-10-21 全部关闭**（见文末「处置」节），SH-7 / DOC-18 复核后仍复现；复核中另订正 25 处「文档说未实现 / 指向旧主线、实际已落地」的陈述漂移（见其后一节）。
- 2026-10-31 审计新增 **18 条**，已于同日处置：**13 条修复**、2 条部分处置（TEST-9 / CI-4）、
  2 条不采纳（TEST-7 / SH-24，理由见文末「处置」节）；DOC-28 复核确认已修复。
- 2026-10-31 代码审查新增 **21 条**（DOC-31…DOC-43、SH-25…SH-32），**已于同日全部修复**
  （无「不采纳」条目），见文末「代码审查与文档一致性审查（2026-10-31）」与其后的「处置」节。
- 2026-10-31 `borrow` / `Handback` 提案评审追加 **1 条**（**SH-33**，High：AutoDrop 在
  `return` 前不注入、不置空），**已于 2026-11-01 修复**（探针 `test/ast/61_autodrop_return`，
  `check-ast.sh` 的 `sh33` 断言），见同节「提案评审追加」。
- 2026-11-01 `borrow` / `Handback` 实现审查新增 **15 条**（**SH-34**…**SH-41**、**DOC-44**…**DOC-50**），
  **已于同日全部修复/文档化**；其中 3 条 High 均为新特性的语义漏洞（文件作用域静默接受、同层赋值取消归还、
  `return` 表达式提到借用对象即跳过归还），见文末「代码审查（2026-11-01）」与其后的「处置」节。
- 2026-11-01 第三方评估复核（`v0.16.1`，锚点 `61e35e4`）新增 **5 条**（**DOC-51**、**DOC-52**、**SH-42**、
  **SH-43**、**SH-44**）：2 条文档漂移（教程 §7 的 import 后缀、§11 与 spec §6.2 的行管线限制）、
  1 条分发体积（arena 静态数组 → 88MB 二进制）、1 条工具缺口（`ct build` 不代为编译，Info / 待决）、
  1 条包摘要加固（FNV-1a → SHA-256）；**已于同日处置**：4 条修复 + SH-43 维持待决。报告其余条目复验后
  不立案，逐条理由见文末「第三方评估复核（2026-11-01）」一节。
- 严重度：`High`（对外失真/影响正确性认知）· `Medium`（可察觉的缺口）· `Low`（措辞/残留）· `Info`（设计观察）。
- 硬关卡计数随阶段演进：6 → 7 → 8 → **9**（`check-warnings.sh` 接入后为九关；构成见 [check-all.sh:72-80](../selfhost/check-all.sh#L72-L80)）。下文各**带日期的验证记录**里出现的「六道 / 七道 / 八道硬关卡」是该记录当时的口径，非现状；现状一律以 `check-all.sh` 的「9 hard gates green」与 [roadmap](../docs/roadmap.md) 为准。

## 模块索引

### `docs/` —— 文档一致性

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| DOC-1 | High | README 顶部阶段声明滞后（写 Phase 3，实为 Phase 5） | [readme-phase-drift.md](docs/readme-phase-drift.md) |
| DOC-2 | High | AGENTS §1 阶段与 `ctc.c` 行数滞后，且与 §2 自相矛盾 | [agents-stage-linecount-drift.md](docs/agents-stage-linecount-drift.md) |
| DOC-3 | Medium | AGENTS §6 称「五层覆盖」不实（实为 7 层），且未列 CT 线关卡 | [agents-dod-layer-count.md](docs/agents-dod-layer-count.md) |
| DOC-4 | Medium | architecture.md 断言多个 `die` 点「不可达」，其中 2 处实测可达 | [architecture-unreachable-claim.md](docs/architecture-unreachable-claim.md) |
| DOC-5 | Low | roadmap.md 残留「待做 / PENDING」条目，已被后续进展取代 | [roadmap-stale-todo.md](docs/roadmap-stale-todo.md) |
| DOC-6 | Medium | 冻结期改动登记只记 2 次，实际 `ctc.c` 有 5 次（含 4 次 bump） | [freeze-register-incomplete.md](docs/freeze-register-incomplete.md) |
| DOC-7 | Medium | README / AGENTS 仍写「当前命令 `ctc`」，与 Phase 7 矛盾 | [naming-command-stale.md](docs/naming-command-stale.md) |
| DOC-8 | Medium | README CLI 表缺 `-I` / `--line` / `--ns-root` / `--diagnostics` | [readme-cli-flags-missing.md](docs/readme-cli-flags-missing.md) |
| DOC-9 | Medium | language-spec 范围与时态过期（仍称 L2 语法「正在重做」） | [language-spec-scope-stale.md](docs/language-spec-scope-stale.md) |
| DOC-10 | High | glossary 仍把 namespace 写成块式，编译器已拒绝 | [glossary-block-namespace.md](docs/glossary-block-namespace.md) |
| DOC-11 | High | language-spec 仍称 ct-ast 与 L2「行为等价」，实际已有两处分叉 | [language-spec-equivalence-false.md](docs/language-spec-equivalence-false.md) |
| DOC-12 | Medium | README「其它任意 C 代码原样透传」对出厂 ct-ast 不成立 | [readme-passthrough-scope.md](docs/readme-passthrough-scope.md) |
| DOC-13 | Medium | phase10 的 D44 写两态（实为三态）、PkgOps 写 28（实为 29） | [phase10-identity-and-counts.md](docs/phase10-identity-and-counts.md) |
| DOC-14 | Low | 关卡脚本头注释过期：20 vs 21 断言、缺 11.x / 12.x | [gate-comment-drift.md](docs/gate-comment-drift.md) |
| DOC-15 | Medium | issues / reports 指向已消失的 `selfhost/ast/**`、`selfhost/src/**` | [stale-selfhost-ast-paths.md](docs/stale-selfhost-ast-paths.md) |
| DOC-16 | Medium | 「零警告」只在 Apple clang 下成立，GCC 会在冻结层报 `-Wformat-truncation` | 见文末「容器复验」（2026-10-21） |
| DOC-17 | Medium | 两个探针依赖 BSD libc（`cli/short-read`、`cli/tmpfile-cannot-create`） | 见文末「容器复验」（2026-10-21） |
| DOC-18 | Medium | language-spec §4.8 仍把「struct 类型的数组字段」列为不支持，与 §6 及实际行为相反 | [language-spec-struct-array-field-stale.md](docs/language-spec-struct-array-field-stale.md) |
| DOC-19 | Medium | 教程四处与实现不符：`delete` 的 `p = 0`、`ctc` 建议、数组字段、示例行号 | [tutorial-claims-vs-impl.md](docs/tutorial-claims-vs-impl.md) |
| DOC-20 | Low | README 快速开始 1b 只构建 `ctc`，后续步骤却调用 `ct` | [readme-quickstart-branch.md](docs/readme-quickstart-branch.md) |
| DOC-21 | Low | construction.md 自称「描述现状」却未标适用编译器，两处描述在 ct-ast 上不成立 | [construction-scope-unspecified.md](docs/construction-scope-unspecified.md) |
| DOC-22 | Low | Batch 2 落地后仍残留 `unit-private` / `not mangled` 陈述，设计文档状态仍写「待实现」 | [doc22-batch2-stale-statements.md](docs/doc22-batch2-stale-statements.md) |
| DOC-23 | **High** | README 把 `build --emit-map -` 写成不可用，实测可用 | [doc23-emit-map-build-stdout.md](docs/doc23-emit-map-build-stdout.md) |
| DOC-24 | **High** | 教程称普通 `.ct` 会生成 `.h`，与 batch 30 规则和 README 相反 | [doc24-tutorial-h-output.md](docs/doc24-tutorial-h-output.md) |
| DOC-25 | Medium | README 称 `-I` 两模式均限 16，compile 实际无上限（且忽略该开关） | [doc25-include-roots-asymmetry.md](docs/doc25-include-roots-asymmetry.md) |
| DOC-26 | Medium | 多处断言计数与 tag 布局过期（grammar 21→27、check-ast 105→317、v0.13.0 仍写旧布局） | [doc26-stale-counts-and-tag-layout.md](docs/doc26-stale-counts-and-tag-layout.md) |
| DOC-27 | Medium | `test/README.md` 的层图与负例约定过期（01..18、缺 patterns、include 路径错误） | [doc27-test-readme-stale.md](docs/doc27-test-readme-stale.md) |
| DOC-28 | Medium | `issues/README.md` 仍写 8 关、把已关闭的第二轮 8 条列为待修 | [doc28-issues-readme-gate-count.md](docs/doc28-issues-readme-gate-count.md) |
| DOC-29 | Low | batch 4 的 checklist 27 项全未勾，与其他 32 份不一致 | [doc29-batch4-checklist-unchecked.md](docs/doc29-batch4-checklist-unchecked.md) |
| DOC-30 | Low | 版本登记漂移：glossary 暗示 Phase 13，AGENTS 中文版 bump 登记缺 v0.13.0 | [doc30-version-register-drift.md](docs/doc30-version-register-drift.md) |
| DOC-31 | **High** | 教程称 `switch` / `do-while` / `goto` 不受 ct-ast 支持，实际早已支持 | [doc31-tutorial-c-forms-unsupported.md](docs/doc31-tutorial-c-forms-unsupported.md) |
| DOC-32 | Medium | 教程命令表称普通 `.ct` 同时产出 `.h`，与同文 §1 和 README 相反 | [doc32-tutorial-cli-h-output.md](docs/doc32-tutorial-cli-h-output.md) |
| DOC-33 | Low | 教程称 `examples/` 有 7 个可运行示例，实际 8 个 | [doc33-tutorial-example-count.md](docs/doc33-tutorial-example-count.md) |
| DOC-34 | Low | 编辑器语法断言数仍写 27（实为 31），`check-all.sh` 第 8 关标签停在 12.1 | [doc34-grammar-assertion-count.md](docs/doc34-grammar-assertion-count.md) |
| DOC-35 | Medium | `test/README.md` 的探针区间与负例计数过期（01..56 / 56-of-68） | [doc35-test-readme-probe-counts.md](docs/doc35-test-readme-probe-counts.md) |
| DOC-36 | **High** | `bindings/README.md` 中文 §5 仍称接口值不能跨单元，与英文 §5 和实现相反 | [doc36-bindings-cross-unit-interface.md](docs/doc36-bindings-cross-unit-interface.md) |
| DOC-37 | Medium | `selfhost/README.md` 中文表仍是 ct-ast 三文件旧布局，且门禁清单漏 `check-warnings.sh` | [doc37-selfhost-readme-ct-ast-layout.md](docs/doc37-selfhost-readme-ct-ast-layout.md) |
| DOC-38 | Medium | README 干净 clone 段对 `.gitignore` 的描述不成立 | [doc38-readme-gitignore-claim.md](docs/doc38-readme-gitignore-claim.md) |
| DOC-39 | Medium | glossary 把节点池模块指成 `backend::mem::Memory` | [doc39-glossary-arena-module.md](docs/doc39-glossary-arena-module.md) |
| DOC-40 | Low | roadmap 对 `check-ast.sh` 断言数给出两个互斥且均已过期的数字（317 / 359） | [doc40-roadmap-check-ast-count.md](docs/doc40-roadmap-check-ast-count.md) |
| DOC-41 | Low | glossary 的「能力补丁」例外清单漏 `v0.15.1` | [doc41-glossary-capability-patch-list.md](docs/doc41-glossary-capability-patch-list.md) |
| DOC-42 | Low | README 英文版称 `test/ast/errors/` 只按退出码断言 | [doc42-readme-ast-errors-assertion.md](docs/doc42-readme-ast-errors-assertion.md) |
| DOC-43 | Low | `MAX_NODES` 只存在于文档与注释里，代码中没有这个宏 | [doc43-max-nodes-not-a-macro.md](docs/doc43-max-nodes-not-a-macro.md) |
| DOC-44 | Medium | `SH-25`…`SH-32` 已修复，8 个 issue 文件的「状态」仍写「待修」 | [doc44-ledger-statuses-stale.md](docs/doc44-ledger-statuses-stale.md) |
| DOC-45 | **High** | 教程 §8 自相矛盾：代码块已写 `p = 0`，正文仍称 `delete` 不置空；`return` 行首要求也已不成立 | [doc45-tutorial-memory-delete-null.md](docs/doc45-tutorial-memory-delete-null.md) |
| DOC-46 | Medium | README 变换表三行过期：`delete` 未置空、`own`/`borrow` 仍写「行首 `return`」 | [doc46-readme-transform-table-stale.md](docs/doc46-readme-transform-table-stale.md) |
| DOC-47 | Medium | `memory-guide.md` 整篇以「SH-33 未修 + `delete` 不置空」为前提，六处过期 | [doc47-memory-guide-stale.md](docs/doc47-memory-guide-stale.md) |
| DOC-48 | Medium | `design/borrow.md` 头部写「已实现」，§2 仍以 SH-33 未修为据；D1/D6 未归档 | [doc48-borrow-design-stale-status.md](docs/doc48-borrow-design-stale-status.md) |
| DOC-49 | Medium | 新语法 `borrow` / `Handback` 未同步编辑器语法，`check-grammar.py` 无断言 | [doc49-editor-grammar-borrow.md](docs/doc49-editor-grammar-borrow.md) |
| DOC-50 | Low | roadmap 没有 `borrow` / `Handback` 的阶段与版本归属 | [doc50-roadmap-borrow-missing.md](docs/doc50-roadmap-borrow-missing.md) |
| DOC-51 | **High** | 教程 §7 的跨单元示例把普通 `.ct` 当可 import 单元，照抄必失败 | [doc51-tutorial-impl-unit-import.md](docs/doc51-tutorial-impl-unit-import.md) |
| DOC-52 | Medium | 教程 §11 与 spec §6.2 的「跨行 / 单行函数体 / 注释续行不重写」在 ct-ast 上均不成立 | [doc52-line-pipeline-scope-stale.md](docs/doc52-line-pipeline-scope-stale.md) |

### `testing/` —— 测试覆盖度

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| TEST-1 | Medium | `ctc.c:2837`（cannot create a temporary file）可达但无负例 | [ctc-2837-tmpfile-not-covered.md](testing/ctc-2837-tmpfile-not-covered.md) |
| TEST-2 | Medium | `ctc.c:2708`（cannot read）可达但无负例 | [ctc-2708-cannot-read-not-covered.md](testing/ctc-2708-cannot-read-not-covered.md) |
| TEST-3 | Low | `ctc.c:1491`（nested field path too long）探针未复现，文档却称不可达 | [ctc-1491-nested-path-not-reproduced.md](testing/ctc-1491-nested-path-not-reproduced.md) |
| TEST-4 | Low | Phase 7 的 `ct` 身份只测了一半（`ct build` / `-h` / `ctc compile` 未测） | [phase7-ct-identity-coverage.md](testing/phase7-ct-identity-coverage.md) |
| TEST-5 | Medium | L2 驱动的错误分支仍无负例（10+ 个站点） | [l2-driver-errors-untested.md](testing/l2-driver-errors-untested.md) |
| TEST-6 | Medium | `--emit-map <file>` 成功路径没有用例 | [emit-map-file-path-untested.md](testing/emit-map-file-path-untested.md) |
| TEST-7 | **High** | ct-ast 的生成 C 无逐字节 oracle；§4.12–4.38 共 27 节只有行为探针 | [test7-ct-ast-no-byte-golden.md](testing/test7-ct-ast-no-byte-golden.md) |
| TEST-8 | Medium | 12 个负例只断言「有位置」，消息文本可静默漂移 | [test8-negative-messages-not-pinned.md](testing/test8-negative-messages-not-pinned.md) |
| TEST-9 | Medium | 绝大多数容量上限可达但无用例（仅 MAX_MAPS / MAX_ERRORS 有夹具） | [test9-cap-limits-untested.md](testing/test9-cap-limits-untested.md) |
| TEST-10 | Medium | build 模式的 CLI 错误分支几乎未测 | [test10-build-cli-errors-untested.md](testing/test10-build-cli-errors-untested.md) |
| TEST-11 | Medium | compile 与 build 两模式没有同一特性的镜像用例 | [test11-mode-mirror-missing.md](testing/test11-mode-mirror-missing.md) |
| TEST-12 | Low | `check-warnings.sh` 未扫描 `test/patterns`（及 archive / acceptance） | [test12-check-warnings-patterns.md](testing/test12-check-warnings-patterns.md) |
| TEST-13 | Low | `missing_method.ct` 在两个负例目录各一份，清点时易重复计数 | [test13-missing-method-duplicate.md](testing/test13-missing-method-duplicate.md) |

### `ci/` —— 门禁与入口

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| CI-1 | High | `./test/run.sh` 完全不覆盖 CT 线（L1/L2 ≈8k 行） | [run-sh-misses-ct-line.md](ci/run-sh-misses-ct-line.md) |
| CI-2 | High | 无聚合入口 / 无 CI：不存在一条命令能跑全部门禁 | [no-aggregate-gate-entry.md](ci/no-aggregate-gate-entry.md) |
| CI-3 | Low | 门禁依赖 `diff` / `python3` / `git`，缺一个就产生成百条假 FAIL | [gates-assume-host-tools.md](ci/gates-assume-host-tools.md) |
| CI-4 | Medium | 仓库无 CI 配置，九道门禁只靠手工执行 | [ci-4-no-ci-config.md](ci/ci-4-no-ci-config.md) |

### `selfhost/` —— 代码结构与容量

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| SH-1 | Medium | `MAX_FUNCS` 余量极小，是 CT 线最紧的扩展瓶颈 | [max-funcs-headroom.md](selfhost/max-funcs-headroom.md) |
| SH-2 | Info | L2 状态无归属：`SymTab *sym` 参数化 63 次 + 52 处文件作用域 static | [unowned-state-sym-param.md](selfhost/unowned-state-sym-param.md) |
| SH-3 | Low | 以 `ct` 运行时驱动错误仍打印 `ctc:` 前缀（37 处硬编码） | [ct-error-prefix.md](selfhost/ct-error-prefix.md) |
| SH-5 | Medium | ct-ast 存在 27 个定义后从未使用的宏 | [ct-ast-dead-macros.md](selfhost/ct-ast-dead-macros.md) |
| SH-6 | Medium | 16 处「上限账本在 main.ct」注释已悬空，且 `main.ct` 自相矛盾 | [ct-ast-stale-cap-comments.md](selfhost/ct-ast-stale-cap-comments.md) |
| SH-7 | Medium | ct-ast 对已赋值的 struct 值字段仍发嵌套 vptr 指定初始化式（`-Winitializer-overrides`） | [ct-ast-duplicate-field-vptr-init.md](selfhost/ct-ast-duplicate-field-vptr-init.md) |
| SH-8 | High | ct-ast 不校验 impl 完整性，缺方法时生成 NULL vtable 槽并在运行期段错误 | [ct-ast-missing-impl-check.md](selfhost/ct-ast-missing-impl-check.md) |
| SH-9 | Medium | ct-ast 解析期诊断缺文件名与列号，与四份文档的 `file:line:col: error:` 不符 | [ct-ast-parse-diag-format.md](selfhost/ct-ast-parse-diag-format.md) |
| SH-10 | Medium | 生成物触发 `-Wall -Wextra` 告警家族：`_self` 未使用、未被引用的 vtable、未被引用的 Drop 函数 | [ct-ast-unused-self-warning.md](selfhost/ct-ast-unused-self-warning.md) |
| SH-11 | Medium | ct-ast 在表达式中间静默提升右值接收者，改变求值顺序 | [ct-ast-rvalue-hoist-order.md](selfhost/ct-ast-rvalue-hoist-order.md) |
| SH-12 | Medium | `map` 语法（`map trait T for instance x`）在 test/cases 与 examples 中无正例，新用户入口缺失 | [ct-ast-map-no-positive-example.md](selfhost/ct-ast-map-no-positive-example.md) |
| SH-13 | **High** | `pub` 全局变量在 build 模式下被整个丢弃，连定义单元自身都无法编译 | [ct-ast-pub-global-dropped.md](selfhost/ct-ast-pub-global-dropped.md) |
| SH-14 | **High** | vtable 为 `static`，接口值无法在消费单元装箱（跨单元 OO 的唯一阻塞） | [ct-ast-cross-unit-vtable-static.md](selfhost/ct-ast-cross-unit-vtable-static.md) |
| SH-15 | Medium | `map` 每条绑定无条件生成 wrapper，缺少直绑零生成路径 | [ct-ast-map-wrapper-per-binding.md](selfhost/ct-ast-map-wrapper-per-binding.md) |
| SH-16 | Medium | impl 未用参数触发 `-Wunused-parameter`；`(void)_self;` 落在 `return` 之后 | [ct-ast-impl-unused-param-warning.md](selfhost/ct-ast-impl-unused-param-warning.md) |
| SH-17 | Low | 同一单元被多次 import 时生成物重复 `#include` 其头文件 | [ct-ast-import-dep-duplicate.md](selfhost/ct-ast-import-dep-duplicate.md) |
| SH-18 | Medium | 类型位置不接受命名空间限定名，诊断指向函数查找；trait 类型连裸名也不可用 | [ct-ast-qualified-type-name-rejected.md](selfhost/ct-ast-qualified-type-name-rejected.md) |
| SH-19 | **High** | trait 方法的裸 `void *` 参数被当成空参数列表，直接报 `unexpected token` | [ct-ast-trait-void-pointer-param.md](selfhost/ct-ast-trait-void-pointer-param.md) |
| SH-20 | Medium | `map` 曾强制要求已声明实例（命名空间级绑定曾不可用；2026-10-22 已修） | [ct-ast-map-requires-instance.md](selfhost/ct-ast-map-requires-instance.md) |
| SH-21 | Medium | 函数指针不能指向 C 库函数，只能指向 CT 声明的函数或 ALL_CAPS 宏 | [ct-ast-fnptr-cannot-name-libfn.md](selfhost/ct-ast-fnptr-cannot-name-libfn.md) |
| SH-22 | Medium | `extern` 只接受变量：函数原型被拒，且诊断位置漂移到后续行 | [ct-ast-extern-function-prototype.md](selfhost/ct-ast-extern-function-prototype.md) |
| SH-23 | **High** | ct-ast 静默截断超长标识符（159 字符），与 spec「>127 报错」相反且可致重定义 | [ct-ast-identifier-truncation.md](selfhost/ct-ast-identifier-truncation.md) |
| SH-24 | Info | compile 与 build 两套 CLI 解析器并存，导致 `-I` 上限与文案分叉 | [cli-parser-duplication.md](selfhost/cli-parser-duplication.md) |
| SH-25 | **High** | 带 tag 的 `typedef` 别名漏拷 `dims`，数组字段生成编译不过的 C | [sh25-typedef-alias-drops-dims.md](selfhost/sh25-typedef-alias-drops-dims.md) |
| SH-26 | Medium | `*p = v;` 的赋值路径读取未初始化的 `tt` | [sh26-assign-deref-uninit-type.md](selfhost/sh26-assign-deref-uninit-type.md) |
| SH-27 | Medium | `struct_def_ahead` 不回滚行号状态，跨行前瞻后诊断行号永久偏移 | [sh27-struct-ahead-line-drift.md](selfhost/sh27-struct-ahead-line-drift.md) |
| SH-28 | Medium | 无花括号分支里的 `own` 既不 AutoDrop 也不告警，静默泄漏 | [sh28-own-in-braceless-branch.md](selfhost/sh28-own-in-braceless-branch.md) |
| SH-29 | Medium | 第 65 个字段被静默丢弃（`MAX_FIELDS` 越界不报错） | [sh29-max-fields-silent-drop.md](selfhost/sh29-max-fields-silent-drop.md) |
| SH-30 | Low | `emit_unit` / `write_unit_header` 的失败路径漏 `fclose`，`build` 还留下半截 `.h` | [sh30-emit-error-cleanup.md](selfhost/sh30-emit-error-cleanup.md) |
| SH-31 | Info | `emit_cond` 的 `B_AND` / `B_OR` / `B_XOR` 分支永远不可达 | [sh31-emit-cond-dead-branches.md](selfhost/sh31-emit-cond-dead-branches.md) |
| SH-32 | Low | compile 模式接受多个位置参数，静默只编译最后一个 | [sh32-multi-input-silently-ignored.md](selfhost/sh32-multi-input-silently-ignored.md) |
| SH-33 | **High** | AutoDrop 只在 `}` 注入：含 `return` 的函数静默泄漏，生成死代码且不置空 | [sh33-autodrop-return-no-inject.md](selfhost/sh33-autodrop-return-no-inject.md) |
| SH-34 | **High** | 文件作用域的 `borrow` 被静默接受，`borrow` 原样写进生成的 C | [sh34-file-scope-borrow.md](selfhost/sh34-file-scope-borrow.md) |
| SH-35 | **High** | 同作用域 `q = c;` 取消 `borrow` 的出口归还，池槽位静默泄漏 | [sh35-borrow-store-cancels-handback.md](selfhost/sh35-borrow-store-cancels-handback.md) |
| SH-36 | **High** | `return` 表达式「提到」变量就取消出口释放：`return b->n;` / `return c->fd;` 不释放 | [sh36-return-mention-cancels-autodrop.md](selfhost/sh36-return-mention-cancels-autodrop.md) |
| SH-37 | Medium | `static` 局部变量可以接收借用指针，逃逸检查漏判 | [sh37-static-local-holds-borrow.md](selfhost/sh37-static-local-holds-borrow.md) |
| SH-38 | Medium | `borrow` 无法跨单元使用：`impl Handback` 必须与借用点同单元 | [sh38-borrow-cross-unit.md](selfhost/sh38-borrow-cross-unit.md) |
| SH-39 | Low | `impl Handback` 写在 `borrow` 之后被误报「has no impl」 | [sh39-impl-order-false-no-impl.md](selfhost/sh39-impl-order-false-no-impl.md) |
| SH-40 | Medium | 新增的置空让 `delete <非左值>` 生成非法 C（`get() = 0`） | [sh40-delete-non-lvalue-null.md](selfhost/sh40-delete-non-lvalue-null.md) |
| SH-41 | Medium | 归还所有权的 `return p;` 被误报为泄漏（L2 不报） | [sh41-return-transfer-false-leak.md](selfhost/sh41-return-transfer-false-leak.md) |
| SH-42 | Medium | arena 的 `nodes[131072]` / `strpool` 是静态数组，装出的 `ct` 有 88MB（`__DATA` 105MB） | [sh42-arena-static-footprint.md](selfhost/sh42-arena-static-footprint.md) |
| SH-43 | Info | `ct build` 只发 `.c/.h` 并打印 `cc` 行，不代为编译（工具缺口，待决） | [sh43-build-no-cc.md](selfhost/sh43-build-no-cc.md) |
| SH-44 | Medium | `ct.lock` 的内容摘要用 FNV-1a + 加法折叠，非抗碰撞 | [sh44-pkg-digest-fnv.md](selfhost/sh44-pkg-digest-fnv.md) |

## 汇总

- High: 4（DOC-1、DOC-2、CI-1、CI-2）——均已修复
- Medium: 11（DOC-3、DOC-4、TEST-1、TEST-2、SH-1 已修复；DOC-6–9 已修复；TEST-5、TEST-6 部分覆盖，剩余项见各自文件）
- Low: 4（DOC-5、TEST-3 已修复；TEST-4 已修复；SH-3 已决策保持 `ctc:`）
- Info: 1（SH-2，已修复）

合计 20 条：已处理 20（其中 TEST-5 / TEST-6 为部分覆盖，未覆盖项已在文件内列明）。
另有 Phase 9 复审的 14 项发现，未单独立文件，逐项状态见文末「Phase 9 复审」一节。
**Phase 12 复审（2026-10-21）新增 8 条：DOC-10…15、SH-5、SH-6，已全部修复**（见文末一节）。

**第二轮复审（2026-10-21，锚点 `dde0dda`）新增 8 条，已于 2026-10-21 全部关闭**：SH-8（High）、SH-9 / SH-10 / SH-11 / SH-12 / DOC-19（Medium）、DOC-20 / DOC-21（Low）；SH-7 与 DOC-18 复核后仍复现（见文末一节）。

**Batch 2（2026-10-22）新增 6 条：SH-13…SH-18；其中 5 条已修（SH-13…SH-17），SH-18 按需求规格仅文档化**（见文末一节）。
**同日复核（锚点 `224c08f`）再新增 5 条：SH-19（High）、SH-20 / SH-21 / SH-22（Medium）、DOC-22（Low）；SH-18 由 Low 升 Medium**（见文末「Batch 2 落地复核」一节）。

**测试覆盖度与文档一致性审计（2026-10-31，锚点 `f4c77b1`）新增 18 条**：DOC-23 / DOC-24 / TEST-7 / SH-23 为 High，
DOC-25…28 / TEST-8…11 / CI-4 为 Medium，DOC-29 / DOC-30 / TEST-12 / TEST-13 为 Low，SH-24 为 Info；
DOC-28 已随本轮同步修正（见文末「测试覆盖度与文档一致性审计（2026-10-31）」一节）。

状态附注：第二轮复审覆盖了上一轮评审的同一 HEAD `dde0dda`，工作树当时包含第二轮产生的 7 个 issue 文件 + 报告目录 + 本文件编辑（均为新增/只读产物，不触碰源码）。**全量生成物 `-Wall -Wextra` 扫描（2026-10-21）**发现 ct-ast 对 test/cases、test/ast、test/modules 生成的 C 文件有 3 类告警家族（`_self` 未使用、未被引用的 vtable、未被引用的 Drop 函数）——check-all.sh 当前只对 ct-ast 自身构建跑告警检查，不对生成物跑；详见 SH-10（扩展为 Medium）。

## 修复进展（2026-10-17）

12 条已全部修复：

| 提交 | 覆盖 |
| --- | --- |
| `5bde821` docs: correct stage and CT-line gates | DOC-1、DOC-2、DOC-3 |
| `b6b3dc4` docs: fix reachability and stale to-dos | DOC-4、DOC-5、TEST-3、SH-1 |
| `1a1ae91` test(cli): cover two driver failure sites | TEST-1、TEST-2 |
| `8765c83` chore(ci): add the aggregate gate entry point | CI-1、CI-2（`selfhost/check-all.sh`） |
| `54c3713` … `fe6c29f`（6 个 refactor 提交） | SH-2：`sym` 进 `Pipe`；Drop 表/`Warn` 表进 `SymTab`；输出缓冲与扫描状态进 `Pipe`；driver 全局进 `struct Build`。static 52 → 11（剩余为扫描上下文、`die` 恢复协议与三个单例） |

验证：`bash selfhost/check-all.sh` 六道硬关卡全绿（acceptance 18 pass / 1 pending，预期）；`./test/run.sh` **117 passed, 0 failed**（原 115，新增 `cli/cannot-read` 与 `cli/tmpfile-cannot-create`）。后续 Phase 5 新增 `ast_parse_spike`，acceptance 现为 **19 pass / 1 pending**；`check-grammar.py` 现为 **20 项断言**。

> 审查期间未修改任何文件；本目录与报告最初为只读产物，后续修复见上「修复进展」。

## 复核（2026-10-17，Phase 6.6 之后）

12 条修复均仍成立（`ctc.c` 2930 行、`cli/cannot-read` 与 `cli/tmpfile-cannot-create` 在册、`check-all.sh` 为聚合入口、`architecture.md` 的可达性表述已改、roadmap 无残留待做）。但 Phase 6 的 6.1–6.4 / 6.6 落地后，**DOC-1 / DOC-2 的「当前阶段」表述再次滞后**，并出现两处新的清单漂移：

- README 顶部与 AGENTS §1 仍把阶段停在 Phase 5 → 已补「Phase 6 的 6.1–6.4 与 6.6 已落地，6.5 仅设计冻结」。
- roadmap 总览表（中英）仍写「6.1–6.4 已落地」→ 已改为「6.1–6.4 + 6.6 已落地」。
- glossary 的 `layer` 清单漏 `dialect`；`map` / 反向映射表仍按「排期 Phase 6（D8）」描述 → 已按 6.1 / 6.5 / 6.6 的实际状态订正，设计决策范围补到 D1–D20。

以上均为文档订正，未触碰 `ctc.c` / `selfhost/**` / `test/**`。

## Phase 7 复审（2026-10-17，锚点 `ec97f99`）

完整报告见 [reports/phase7-review](../reports/phase7-review/phase7-review.md)。所有硬关卡实测绿色：

- `./test/run.sh` → `118 passed, 0 failed`（八层：1/1/25/6/1/60/6/18）
- `bash selfhost/check-all.sh` → `OK (6 hard gates green)`，`SCRIPT_EXIT=0`
- `check-goldens` 25/25 + L1′ 25 + L2 25 + 不动点 2；`check-archive` 3/10/4/32；
  `check-m2a` PASS；`ct-tour` OK；grammar 20/20；acceptance 19 pass / 1 pending（p18 已知）

本轮新增 8 条，**已于 2026-10-18 全部处理**：

| ID | 严重度 | 摘要 | 处理 |
| --- | --- | --- | --- |
| [DOC-6](docs/freeze-register-incomplete.md) | Medium | 冻结登记只写 2 次，实际 `ctc.c` 有 5 次改动（4 次 bump 未登记） | ✅ AGENTS §2 增加「版本 bump 另行登记」段，指向 roadmap 与 tag |
| [DOC-7](docs/naming-command-stale.md) | Medium | README L8 / AGENTS L17、L146 仍写「当前命令 `ctc`」 | ✅ 统一为「入口命令 `ct`，`ctc` 为兼容别名」 |
| [DOC-8](docs/readme-cli-flags-missing.md) | Medium | README CLI 表缺 `-I` / `--line` / `--ns-root` / `--diagnostics` | ✅ 中英表各补 4 行 |
| [DOC-9](docs/language-spec-scope-stale.md) | Medium | spec 仍称 L2 语法「正在重做」 | ✅ 改契约：spec 覆盖 L0/L2 共有语法，L2 独有给链接；AGENTS §5 分层 |
| [TEST-4](testing/phase7-ct-identity-coverage.md) | Low | `ct build` / `ct -h` / `ctc compile` 无断言 | ✅ ct-tour 第 7 步补 5 类断言 |
| [TEST-5](testing/l2-driver-errors-untested.md) | Medium | L2 驱动 10+ 个错误分支无负例 | ✅ 两轮共补 9 条（`-o`/`-I`/diagnostics/std/cannot open/short read，加 `too many inputs` / `too many -I roots` / map `cannot write`）；仅 build 模式缺参与 `--ns-root` 缺参受 runner 限制未覆盖（已在文件中说明） |
| [TEST-6](testing/emit-map-file-path-untested.md) | Medium | `--emit-map <file>` 成功路径无用例 | ✅ compile 写盘 `map_file` + build 写盘 `map_file_build`（runner 归位后比对 `expected.map`），另补 `map_unwritable` 钉住 `cannot write` |
| [SH-3](selfhost/ct-error-prefix.md) | Low | 以 `ct` 运行时错误仍打印 `ctc:` | ✅ 决策保持 `ctc:`，README + roadmap 记录 |

验证（2026-10-18）：`check-archive` 39 pass / 0 regression（新增 7 个 designed 用例）；`ct-tour` OK（含新增身份断言）；手工三件套通过。

验证（2026-10-18，TEST-5/TEST-6 收尾）：`check-archive` designed **43 pass / 0 regression**（新增 `map_file_build` / `map_unwritable` / `too_many_inputs` / `too_many_inc`）；`bash selfhost/check-all.sh` 七道硬关卡全绿。

## Phase 9 复审（2026-10-19，锚点 `8010875`）

完整报告见 [reports/phase9-review](../reports/phase9-review/phase9-review.md)。评审基线为八关全绿；本轮在
**v0.10.0（`885d01b`）** 上复核，仍为八关全绿（`test/run.sh` 118、`check-ast.sh` 105、`test/pkg` 35、
`check-grammar.py` 20）。报告列出的 14 项发现**全部关闭**：

| ID | 严重度 | 摘要 | 状态与证据 |
| --- | --- | --- | --- |
| SH-4 | Low（前向风险） | `ParseOps` = 32 = `MAX_METHOD`，解析层已无余量 | ✅ 已记录：roadmap「容量预算」表写明 32/32，并注明 10.2 / 10.3 / 10.5 / 10.6 的新能力全部落在新 trait（`DiagOps` / `MemoryOps` / `CacheOps` / `PkgOps`），未触碰 `ParseOps`。**后续为解析层加方法必须先拆 trait** |
| §3.2-1 | Medium | AST 驱动的 CLI / 错误分支无用例 | ✅ 已修：10.1 先覆盖身份（`ct-ast` / `ct` / `ctc`）、`--diagnostics`、`-I`、`--std`；本轮补齐剩余 10 个驱动分支——`-h`、无输入、`-o` / `-I` / `--ns-root` 缺参、未知选项、cannot open / write、compile 模式 `import`、build 缺 `-o`（`check-ast.sh` 95 → **105**） |
| §3.2-2 | Medium | 自包含契约未被钉死 | ✅ 已修：`check-ast.sh` 增「output contract」节，断言 compile 模式 `.c` **不含**自身 `#include` |
| §3.2-3 | Low | `test/ast/errors/` 仅 1 例 | ✅ 已修：现为 4 例（`missing_semi` / `assign_target` / `undeclared_var` / `unknown_trait`） |
| F1 | Medium | `ct get` 不回写 `ct.pkg` | ✅ 已修：`fccfac7` |
| F3 | Low | `get` / `install` 包名口径不一致 | ✅ 已修：`fccfac7`（抽出 `dep_name`） |
| F4/F5 | Low | `ct install` 无参数处理、usage 未列 `install` | ✅ 已修：`fccfac7` + `48e2d8b`（`test/pkg` 27 → 35） |
| D-a | Medium | glossary 滞后且缺 Phase 9 词条 | ✅ 已修：`db47f7c`；本轮又补 Phase 10 与 D38–D45 |
| D-b | Medium | roadmap 仍写「待授权 / 未 bump」 | ✅ 已修：Phase 9 行改为「已 bump 到 v0.9.0 收口」，Phase 10 行同步收口到 v0.10.0 |
| D-c | Low | `check-all.sh` 头注释层数 / 断言数 / 阶段号过期 | ✅ 已修：`db47f7c`（八层 / 20 assertions / 9.1–9.7）；本轮补掉漏网的 gate 横幅（原「9.1–9.5b」） |
| D-d | Low | `check-ast.sh` 头注释停在 9.5b | ✅ 已修：现写 `Phase 9.1-9.7, Phase 10.x` |
| D-e | Low | README 表格把 `check-ast` 标为 9.1–9.5b | ✅ 已修：现写「Phase 9.1–9.7 + Phase 10.x」 |
| §6 | Medium | `pre-ast-mainline` tag 定位偏早（落在 Phase 4/5 边界） | ✅ 已决策：`297e39c` 保留 tag，把文档口径改为「2026-10-17 的 frozen 边界」，Phase 9 起点由 `v0.8.0` 标出 |

> 唯一保留的长期约束是 SH-4：`ParseOps` 已顶格，这不是缺陷而是容量事实，修复方式是「下次先拆 trait」。

## 复核中顺手订正（2026-10-19）

除报告列出的项外，本轮对 HEAD 的文档做了一遍交叉核对，订正了下列「文档说未实现 / 指向旧主线，实际已落地」的陈述漂移：

| 文档 | 原表述 | 订正 |
| --- | --- | --- |
| [design/phase9.md](../docs/design/phase9.md) 头部 | 「设计已冻结，未实现；不要照此创建 `selfhost/ast/**`」 | 改为 9.1–9.7 已全部落地（v0.9.0 收口），Phase 10 起该实现是安装入口主线 |
| [construction.md](../docs/construction.md) 状态行 / §1 表 / §2 推论 2 / §3.5 / §6（中英） | 堆对象创建「推迟到 Phase 1」，需手写 vptr | 堆对象已落地（[restore](../docs/design/restore.md) D1=A：`T *p = malloc\|calloc(...)` 声明后自动补 vptr），D5 记为「源文件自带 `<stdlib.h>`」 |
| [polymorphism.md](../docs/polymorphism.md) 头部 | 「尚未实现：接口数组、接口字段的装箱」 | 已于 2026-10-17 补齐，由 `test/cases/28_iface_field.ct` 与 acceptance 的 p01–p08 钉住 |
| [design/bootstrap.md](../docs/design/bootstrap.md) 状态行（中英） | 「目录结构与构建流程都还不存在」 | 自举链已在 `selfhost/**` 运行；仅目标 `ctrait/` 布局未落地 |
| [roadmap.md](../docs/roadmap.md) Phase 7 三处（中英） | `ct get` / `ct install`「待做 / remain unimplemented」 | 标注 Phase 8 已落地（`ct-pkg`） |
| [architecture.md](../docs/architecture.md) 英文表 | 仍称 2837 / 2708 / 1491「已逐个探针确认不可达」；`cannot open` / `short read` 行号也偏一行 | 与中文表同步为四态分桶：2837 / 2708 已由 `cli/tmpfile-cannot-create` / `cli/cannot-read` 钉住，1491 仅记为「未复现」；行号改为实测的 L2703 / L2711 |
| [language-spec.md](../docs/language-spec.md) 状态行 / §4.8 注 / §4.9（中英） | 称 L2 是「当前编译器」 | 改为「CT 线（L2；v0.10.0 起安装入口由行为等价的 ct-ast 提供）」 |
| [AGENTS.md](../AGENTS.md) §6（中英） | `test/pkg` 仍写「Phase 8.1 本地源用例」、`check-ast` 未列 CLI 错误分支 | 改为 8.1–8.3（本地源 / git 源 / install）与 9.1–9.7 + 10.x（含 CLI 错误分支） |
| [roadmap.md](../docs/roadmap.md) Phase 5 段 | acceptance 基线仍写「12 项 / 12 pass」 | 改为 **19 项 / 19 pass**，并注明 `p18` 刻意留在 PENDING |
| [README.md](../README.md) 自举 gate 段（中英） | 只描述 L0→L1→L2，未列 `selfhost/ast/main.ct` | 补上 ct-ast 作为第三级的安装入口，并标注 L2 自 10.7 起是回归 oracle |
| [README.md](../README.md) 机制段（中英） | 「CT 线（L2）」「当前编译器 L2」「当前不被接受」 | 统一为「CT 线（L2 / ct-ast）」，并把模块语法的拒绝方明确为 **L0** |
| [issues/selfhost/unowned-state-sym-param.md](selfhost/unowned-state-sym-param.md) 与 [roadmap](../docs/roadmap.md) 重构记录 | 剩余文件作用域 static 仍写 11 个 | 实测 **13 个**（Phase 7 的 `g_ct_prog` 与 Phase 8 的 `g_pkg` 各加一个单例），issue 列表与 roadmap 记录均已补 |
| [roadmap.md](../docs/roadmap.md) Phase 0.2 / 0.3 行（中英） | 0.2 仍写「接口数组尚未实现」；0.3 写 `ctc.c` 2897 行 | 0.2 注明这是 **L0** 边界、CT 线已由 Phase 5 补齐；0.3 补「现为 2930 行」 |
| [vision.md](../docs/vision.md) §2.4（中英） | 泄漏警告「尚属展望，计划 Phase 4 用 CT 重做」 | 改为「已在 Phase 4 落地（text / JSON，`--diagnostics`）」 |
| [design/dialect.md](../docs/design/dialect.md) 状态行（中英） | 「设计定型，暂缓实现；方言展开器尚不存在」 | 改为「设计草案存档；能力已在 Phase 6.6 以仓库外展开器落地」，实现形态指向 phase6.md §7（D20） |
| [editors/vscode](../editors/vscode) README / package.json / snippets | 仍称编译器为 `ctc`；语法自检写「13 assertions」 | 统一为「`ct`（`ctc` 为兼容别名）」；断言数改为实测 **20**（CHANGELOG 标注「发布时 13、现 20」） |
| [issues/testing/l2-driver-errors-untested.md](testing/l2-driver-errors-untested.md) 状态行 | 未覆盖清单漏了 `too many units` | 状态行补齐「build 缺参 / `--ns-root` 缺参 / `too many units`」 |
| [glossary.md](../docs/glossary.md) 自举链与单入口条目（中英） | 自举链写「L0 → L1 → L2」；单入口写「L2 二进制名为 ct」 | 补为「L0 → L1 → L2 → ct-ast」，并注明 10.7 起 `ct` 二进制由 ct-ast 构建 |
| [selfhost/ast/main.ct](../selfhost/ast/main.ct#L821-L827) 顶层 usage | 只列 compile / build，未列 `get` / `install`（F5 在 L2 修过，但 10.7 切主线后未同步到 ct-ast） | 补上 `get <spec>[@<range>]` 与 `install` 两行；`check-ast.sh` 的 `-h` 断言同时钉住三条子命令 |
| [selfhost/ct-ast/main.ct](../selfhost/ct-ast/main.ct) 驱动诊断前缀 | CLI / I/O 错误仍打印 `ct-ast:`，违反 README 与 phase10 非目标「驱动错误前缀固定 `ctc:`」（SH-3） | ✅ 已修：35 处诊断消息统一改回 `ctc:`；`check-ast.sh` 的负例断言同步，自编不动点与 105 项全绿 |
| [polymorphism.md](../docs/polymorphism.md) 英文头部 | 中文头部已改「已于 2026-10-17 补齐」，英文仍写「Not implemented yet: interface arrays / automatic boxing」 | 英文同步为「landed on 2026-10-17，由 `test/cases/28_iface_field.ct` 与 p01–p08 钉住」，与中文一致 |
| [design/dialect.md](../docs/design/dialect.md) §0.1 表（中英） | 「包管理未落地、命名未定」/「the package manager is unimplemented (named `ct-pkg`)」 | 改为「包管理（`ct-pkg`）已在 Phase 8 落地（`ct get` / `ct install`）；方言的全局分发仍属远期」 |
| [design/dialect.md](../docs/design/dialect.md) §15 表第 7 项（中英） | 「远期（依赖未落地的包管理）」/「depends on the unimplemented package manager」 | 改为「包管理已在 Phase 8 落地；方言的全局分发目录尚未落地」 |

## Phase 12 复审（2026-10-21，锚点 `4ef8b68`）

完整报告见 [reports/review-2026-10-21](../reports/review-2026-10-21/review-2026-10-21.md)。本轮为只读评审，
加权「垃圾代码 / 垃圾注释」与「文档-代码-注释一致性」。评审时工作树**不干净**：
`selfhost/ct-ast/main.ct` 有一处未提交改动（删除主文件里的上限宏与节点/词法/算符宏）。

验证基线：`bash selfhost/check-all.sh` → **`check-all: OK (8 hard gates green)`**（315 个 `ok`、0 `FAIL`），
`check-grammar.py` `21 checks, 0 failed`；另建 `/tmp` 全链（L0→L1→L2→ct-ast）四层零警告，
并用同一输入对 L2 与 ct-ast 做差分（块式 namespace、跨命名空间裸调用、`switch` / `do-while`）。

本轮新增 8 条，**已于 2026-10-21 全部修复**：

| ID | 严重度 | 摘要 | 修复 |
| --- | --- | --- | --- |
| [DOC-10](docs/glossary-block-namespace.md) | High | 术语表仍把 namespace 写成块式 `{ … }`，ct-ast 实测直接拒绝 | ✅ 中英两条均改为分号式 `namespace A::B;`，并注明块式被拒（`a namespace is file-scoped`） |
| [DOC-11](docs/language-spec-equivalence-false.md) | High | language-spec 仍称 ct-ast 与 L2「行为等价」，实际已有块式 namespace 与跨命名空间裸调用两处分叉 | ✅ 删除「行为等价」，改为 L0 / L2（冻结 oracle）/ ct-ast（安装入口）并列，并新增中英分叉表（块式 namespace、裸调用、C 透传） |
| [DOC-12](docs/readme-passthrough-scope.md) | Medium | README「其它任意 C 代码｜原样透传」对出厂 ct-ast 不成立（`switch` / `do-while` 实测报错） | ✅ 中英转换表末行按编译器分述，表下注补「透传只对 L0 / L2 成立」 |
| [DOC-13](docs/phase10-identity-and-counts.md) | Medium | phase10 的 D44 写两态（实为 `ct` / `ctc` / `ct-ast` 三态）、`PkgOps` 写 28 个方法（实为 29） | ✅ D44 改为三态并注明 `ct-ast` 是 `prog` 初值；10.6 的方法数改为 29 |
| [DOC-14](docs/gate-comment-drift.md) | Low | `check-all.sh` 头注释写「20 assertions」（实为 21），第 8 关标签缺 Phase 11.x / 12.1 | ✅ 20 → 21；第 8 关标签与 `check-ast.sh` 头注释统一为「Phase 9.1–9.7 + 10.x + 11.x + 12.1」 |
| [DOC-15](docs/stale-selfhost-ast-paths.md) | Medium | issues / reports 仍指向已消失的 `selfhost/ast/**`、`selfhost/src/**`，且部分已修条目未回填 | ✅ `issues/README.md` 与 `reports/phase9-review/**` 顶部加历史快照横幅（给出等价路径）；SH-3 前缀条目回填为已修并指向 `selfhost/ct-ast/main.ct` |
| [SH-5](selfhost/ct-ast-dead-macros.md) | Medium | ct-ast 有 27 个定义后从未使用的宏（`Parser.h.ct` 占 18 个 `N_*` 加 `MAX_MAPS`） | ✅ 27 个死宏全部删除（Parser 19、Emit 7、Memory 2、pkg 1），复核扫描无残留 |
| [SH-6](selfhost/ct-ast-stale-cap-comments.md) | Medium | 16 处「caps must stay equal to … in main.ct」注释已悬空；`main.ct` 内两段注释自相矛盾 | ✅ `frontend/sym/Symbols.h.ct` 定为上限权威清单，其余单元注释改为指向真实持有者；`main.ct` 只留版本与一条宏作用域说明，删去 8 段重构流水账 |

验证（2026-10-21）：`bash selfhost/check-all.sh` → **`check-all: OK (8 hard gates green)`**——
`test/run.sh` 118、`check-goldens` L1′ 25 + L2 25（含不动点）、`check-archive` 0 pending / 0 regression、
`check-m2a: PASS`、`ct-tour` OK、`check-grammar.py` **21 checks, 0 failed**、`test/pkg` 35、
`check-ast` **136 passed, 0 failed**（含自编不动点）；`test/acceptance` 20 pass / 0 pending。
手工三件套：L0 零警告、生成静默、`greeter` 输出两行。

另有三条**非缺陷澄清**（见报告 §5）：跨命名空间裸调用被拒符合提交意图；驱动诊断形态 `ctc: line N:`
与 AGENTS §4 的 `file:line:col: error:` 不一致属独立议题；`pre-ast-mainline` tag 位置偏早属仓库元数据问题。

## 容器复验（2026-10-21，提交后）

在 podman 里用 Debian 12 + gcc 12 从干净 clone 重跑八关，暴露两个平台相关的问题：

| 发现 | 证据 | 处理 |
| --- | --- | --- |
| **BUG-1**：`snprintf` 源与目标同缓冲（未定义行为），gcc 下生成出残缺 C | `backend/emit/Init.h.ct` 的 `emit_array_field_vptrs` 里 `snprintf(sub, sizeof sub, "%s[__ct_j%d]", sub, depth)`；glibc 会先清空目标，基址丢失，产出 `[__ct_j0].__expr_vptr = …`（缺 `d.ab`），`p18_struct_array_field` 由 PASS 变 REGRESSION | ✅ 改为先写中间缓冲 `next` 再拷回；容器内重跑输出 `3`，host `check-ast` 136/136，golden 与不动点未变 |
| **DOC-16**：`零警告` 只在 Apple clang 下成立 | gcc 12 在 `-Wall -Wextra` 下对 L0 / L1 / L2 报一大批 `-Wformat-truncation`（误报），第 2/3/4/5 关在 Linux 上必然红 | ✅ AGENTS §6（中英）与 README 声明基准编译器是 Apple clang 并给出 `-Wno-format-truncation`；`check-all.sh` 检测到 GCC 时自动加一层只追加该开关的 wrapper，冻结层代码不动 |
| **DOC-17**：两个探针依赖 BSD libc | `cli/short-read`（把目录当输入）与 `cli/tmpfile-cannot-create`（`$TMPDIR` 不可用）在 glibc 下分别读成 0 字节与退回 `P_tmpdir`，Linux 上必然红；`check-archive` 的 `cli_short_read` 同源 | ✅ 三处在非 Darwin 上以 `skip` 呈现（不计数、不隐藏回归），AGENTS §6 与 README 记录 |
| **BUG-2**：`-Wrestrict` 疑似重叠 | gcc 对 `snprintf(b->wrapper, MAX_TEXT, "%s_%s_%s", inst, rtrait, b->method)` 报「argument 6 overlaps destination」，因两数组是同一 struct 的兄弟字段 | ✅ 先拼进局部 `wname` 再拷入；不改用 `-Wno-restrict`，以免掩盖 BUG-1 那一类真问题 |

结论：仓库本身**可发布**（macOS 干净 clone 与 Linux 容器各跑一遍八关，均绿）；BUG-1 是本次复验的主要收获，其余三条是平台差异的收口。

验证（2026-10-21，容器）：`podman` + Debian 12 / gcc 12 / arm64 上 `check-all: OK (8 hard gates green)`——
`test/run.sh` 116 passed / 0 failed（2 项 BSD libc 探针 skip）、`check-archive` 46 designed / 0 regression
（`cli_short_read` skip）、`check-ast` 136、`test/pkg` 35、`check-grammar.py` 21。
macOS（Apple clang）侧同期复跑：`./test/run.sh` 118 passed / 0 failed。

## 新发现（2026-10-21，同日已修复）

写安装脚本与入门教程时的实测副产物，两条当时**未修**，已于同日修复（状态见各自 issue 文件）：
SH-7 在 `015946a` 修掉（`emit_field_vptrs` 跳过已被初始化式赋值的字段），DOC-18 在 `776bfc3`
按编译器分述。

| ID | 严重度 | 摘要 | 证据 |
| --- | --- | --- | --- |
| [SH-7](selfhost/ct-ast-duplicate-field-vptr-init.md) | Medium | ct-ast 在构造点对**已赋值**的 struct 值字段仍追加 `.字段.__x_vptr` 嵌套指定初始化式，clang `-Wall -Wextra` 报 `-Winitializer-overrides`；L2 对同一输入不追加、零警告 | `/tmp/ctissue1/dup2.ct`，`ct` 与 `/tmp/l2` 对差 |
| [DOC-18](docs/language-spec-struct-array-field-stale.md) | Medium | language-spec §4.8 仍把「struct 类型的数组字段」列为不支持并引 `p18`「按决定延后」，而 §6 已写 ct-ast 逐元素写 vptr；roadmap 743 与 `test/acceptance/run.sh:436-439` 也还停在「p18 为唯一 PENDING」 | `p18` 探针：ct-ast 输出 `3`，L2 编不过；`BASELINE` 已含 p18、整套 20 pass / 0 pending |

两条均**不影响八关**（`check-all: OK (8 hard gates green)`）：SH-7 的写法不在语料里，DOC-18 的
口径矛盾不产生 golden 差异。

## 第二轮复审（2026-10-21，锚点 `dde0dda`）

完整报告见 [reports/review-2026-10-21-round2](../reports/review-2026-10-21-round2/review-2026-10-21-round2.md)。
本轮仍为**只读评审**，工作树干净，覆盖上一轮（`4ef8b68`）之后的全部 9 个提交。

验证基线：`bash selfhost/check-all.sh` → **`check-all: OK (8 hard gates green)`**（310 个 `ok`、0 `FAIL`，
`SCRIPT_EXIT=0`）；另在 `/tmp` 重建 L0 → L1 → L2 → ct-ast 四层，**零警告**，`ct v0.12.0`；
新增的 `install.sh` 用本地源（`CT_SOURCE_DIR=.`）端到端安装成功（`install_exit=0`，产出 `ct` 与 `ctc -> ct`）。
差分实验：`impl` 缺方法（L0/L2 报错、ct-ast 放行）、`int x = ;`（L0/L2 透传、ct-ast 报错）、
表达式中间右值接收者（仅 ct-ast 静默提升并改变求值顺序）。

本轮新增 **8 条待修**（覆盖上一轮评审同一 HEAD 的更深层 `gcc -Wall -Wextra` 生成物告警扫描）：

| ID | 严重度 | 摘要 | 文件 |
| --- | --- | --- | --- |
| SH-8 | **High** | ct-ast 不校验 impl 完整性，缺方法时生成 `NULL` vtable 槽，运行期 SIGSEGV；L0 / L2 均正确报错 | [ct-ast-missing-impl-check.md](selfhost/ct-ast-missing-impl-check.md) |
| SH-9 | Medium | ct-ast 解析期诊断只有 `ctc: line N:`，缺文件名与列号，与 README / tutorial / glossary 的 `file:line:col: error:` 不符 | [ct-ast-parse-diag-format.md](selfhost/ct-ast-parse-diag-format.md) |
| SH-10 | **Medium**（从 Low 升级） | **生成物 `-Wall -Wextra` 告警家族**：`_self` 未使用（L2/ct-ast 同）、未被引用的 vtable（`Dict_Hashable_vtable`、`uart1_Controller_vtable`）、未被引用的 Drop 函数（`Person_Drop_drop`）；全量扫描 3 类告警、10+ 个语料 | [ct-ast-unused-self-warning.md](selfhost/ct-ast-unused-self-warning.md) |
| SH-11 | Medium | ct-ast 在表达式中间静默提升右值接收者，改变求值顺序，与 language-spec §4.9 的「必须报错」冲突 | [ct-ast-rvalue-hoist-order.md](selfhost/ct-ast-rvalue-hoist-order.md) |
| SH-12 | **Medium（新增）** | `map` 语法（`map trait T for instance x`）在 test/cases（25 正例）与 examples（7 正例）中无端到端正例，新用户入口缺失 | [ct-ast-map-no-positive-example.md](selfhost/ct-ast-map-no-positive-example.md) |
| DOC-19 | Medium | 教程四处与实现不符：`delete` 的 `p = 0`、`ctc` 建议、数组字段、示例行号 | [tutorial-claims-vs-impl.md](docs/tutorial-claims-vs-impl.md) |
| DOC-20 | Low | README 快速开始 1b 只构建 `ctc`，步骤 2/3 却统一调用 `ct`（中英同） | [readme-quickstart-branch.md](docs/readme-quickstart-branch.md) |
| DOC-21 | Low | `construction.md` 自称「描述现状」却未标适用编译器，两处描述在 ct-ast 上不成立 | [construction-scope-unspecified.md](docs/construction-scope-unspecified.md) |

**关键数据补充**（第二轮追加扫描）：

- 全量生成物 `gcc -Wall -Wextra` 扫描：test/cases 2/25 有告警、test/ast 1/18 有告警、test/modules 至少 6 个文件有告警；examples 7/7 零告警；ct-ast 自举产物 20 个 `.c` 零告警。
- **check-archive.sh 的被测编译器是 L2**（冻结回归 oracle），而非 ct-ast——L2 接受 block-style namespace，ct-ast 拒绝（已知分叉，DOC-11 已记录）。archive cases 的 expected 由 L2 生成，ct-ast 根本没法编这些文件。
- `test/ast/11_map/prog.ct` **不含** `map` 语法——它测的是 `-emit-map` 元数据输出（trait + impl + 函数调用映射），不是 `map trait T for instance x { ... }` 构造。真正的 map 语法正例只存在于 test/ast/13-15 与 test/modules/map*。

复核上一轮：**DOC-10…15、SH-5、SH-6 已确认修复**（死宏机器复扫 0 命中、20 个头注释文件名全部匹配）；
**SH-7 与 DOC-18 仍复现**（SH-7 实测 2 条 `-Winitializer-overrides`；DOC-18 另新增同源站点
`docs/tutorial.md:403`，已并入 DOC-19）。

非缺陷观察（详见报告 §5）：L0 对普通 C 语法零校验是设计使然；BSD 探针在 Linux `skip` 是 `6395f5d`
的有意设计；`install.sh` 的 `ctc` 别名在目标已存在普通文件时用 `cp`，与 README 措辞略有出入但行为正确；
leak 系列 test/modules 里的 `p` unused 是**源文件层面**的告警（`malloc` 后没再引用也没调 `delete`），不是 ct-ast 发射问题。

### 处置（2026-10-21，同日）

本轮 8 条已全部关闭：SH-8 / SH-11 / SH-9 见 `84c6677` 与 `9050ed2`；SH-10 的 `_self` 与 vtable /
`Drop_drop` 两族见 `015946a` 与「未被引用符号带 `__attribute__((unused))`」的后续修复；SH-12 见
`e383798`（`examples/08_map_binding/`）；DOC-19 / DOC-20 / DOC-21 见 `776bfc3`。

复扫结果（ct-ast 生成物，`gcc -Wall -Wextra -std=c99 -fsyntax-only`，69 个 `.c`）：只剩 5 条**源文件层面**
的告警——3 个 leak fixture 的 `p` unused、2 个 sig_mismatch fixture 的 `-Wreturn-type`，均非发射器产出。

## Batch 2 需求来源（2026-10-22，锚点 `2ead601`）

本轮不是评审产出，而是**第三方使用反馈 + 定向 spike**。完整需求规格（含设计决策、实现顺序、
验收标准与出口条件）见 [docs/design/batch2-cross-unit-oo.md](../docs/design/batch2-cross-unit-oo.md)，
该文件经用户批准，是本批次的**实现依据**。

第三方在写网络库时提出四条阻塞：(1) 跨单元接口值传不出去；(2) `map` 需要命名空间级绑定与表达式实参；
(3) 生成 `.h` 需要复制源文件顶部的 `#include`；(4) 需要 `extern` 与函数指针。
用自建四层链（L0 → L1 → L2 → ct-ast）逐条实测后，状态拆分为：

| 第三方诉求 | 实测结论 | 本批处理 |
| --- | --- | --- |
| (3) `.h` 复制 `#include` | **已修**（Batch 1 / #8） | 无需处理 |
| (2) 宏常量作 `map` 实参 | **已修**（Batch 1 / #11） | 无需处理 |
| (2) 不造空 struct 实例 | **已可用**：`void *h;` 直接作实例 | 仅补文档 |
| (1) 跨单元接口值 | 传递与派发都已通；**只有"在消费单元装箱"失败**，原因是 vtable 为 `static` | [SH-14](selfhost/ct-ast-cross-unit-vtable-static.md) |
| (4) `extern` / `pub` 全局 | `pub` 全局符号被整个丢弃 | [SH-13](selfhost/ct-ast-pub-global-dropped.md) |
| (2) 表达式实参 / (4) 零 wrapper | 两者冲突，需要两级设计 | [SH-15](selfhost/ct-ast-map-wrapper-per-binding.md) |
| 附带发现 | 未用参数告警、`(void)_self` 位置、重复 `#include`、限定类型名被拒 | SH-16 / SH-17 / SH-18 |

本轮新增 6 条（SH-13…SH-18），全部**待修**，实现由其他 agent 按需求规格执行。
其中 SH-13 / SH-14 为 High，是"OO 只能停在单文件演示级别"这一判断的实际来源。

### 处置（2026-10-22，同日）

六条按需求规格第 5 节顺序落码，改动仅在 ct-ast；L0 / L1 / L2 未动，未 bump `CTC_VERSION`，
`test/cases/**` 与 `examples/**` 的 golden 未改。

| ID | 处置 | 验收点 |
| --- | --- | --- |
| SH-13 | 已修（2a.2） | `test/modules/pub_global`：`count.h` 出 `extern int g_counter;`，`count.c` 出定义 |
| SH-14 | 已修（2a.1） | `test/modules/xunit_box`：`net.h` 出 `extern struct Stream_vtbl Conn_Stream_vtable;`，消费单元装箱通过 |
| SH-15 | 已修（2b.1 / 2b.5） | `test/ast/22_map_direct`：直绑零 wrapper，`--emit-map` 标 `"wrapper": false`；`15_map_args` 仍标 `true` |
| SH-16 | 已修（2c.1） | `test/ast/23_impl_unused`：未用参数发 `(void)x;`，所有 `(void)` 语句前移到函数体开头，生成物零告警 |
| SH-17 | 已修（2c.2） | `xunit_box` 生成物中 `#include "net.h"` 只出现一次 |
| SH-18 | 仅文档化（规格 3.4 非目标） | `language-spec.md` §4.11 / §4.12 记录类型位置不支持限定名，绕法为 `import net::conn::Conn as Conn;` |

口径说明（2b.3）：规格写的是 `map … for instance A::B::h` → C 名 `A_B_h`。最初实现为"接受限定写法、
按最后一段取已声明的 C 名"，随后按用户决定补齐**全局 mangling**（批次见
[docs/design/global-mangling.md](../docs/design/global-mangling.md)）：命名空间内的全局发射为 `A_B_h`，
`extern` 豁免（C 库符号保持原名），表达式支持限定引用 `a::h`，两个被导入的命名空间导出同名全局时
裸名报错并要求限定。`test/modules/map_ns`、`test/modules/ns_globals` 与 §4.10/§4.11 均按该行为描述。

门禁：`bash selfhost/check-all.sh` 九关全绿、零 `FAIL`；`bash selfhost/check-warnings.sh` 对全部
正例、示例与测试用例的生成 C 执行 `-Wall -Wextra -std=c99` 零告警。

## Batch 2 落地复核（2026-10-22，锚点 `224c08f`）

复核方式：自建 L0 → L1 → L2 → ct-ast 四层链（`/tmp/b2r`），九关全绿的基础上，按第三方的
四条诉求逐条搭最小工程实测，不以读码代替运行。**结论：诉求 (1)(3) 已真正可用，(4) 兑现一半，
(2) 当时仍缺「无实例绑定」（当日由 [SH-20](selfhost/ct-ast-map-requires-instance.md) 补齐）。**

| 第三方诉求 | 复核结果 | 证据 |
| --- | --- | --- |
| (1) 跨单元接口值 | **已解决**：`pub trait` + `pub struct` 的 vtable 导出，消费单元可直接装箱，也能接住 `pub` 函数返回的接口值 | 两单元工程（`pub trait Stream` / `pub struct Conn` / `pub Stream stream_open(void)`）编译、运行、零告警；`net.h` 出 `extern struct Stream_vtbl Conn_Stream_vtable;`；map 实例跨单元装箱同样通过 |
| (3) `.h` 复制 `#include` | **已解决**：`#include <sys/socket.h>` 进头文件，`struct sockaddr *` 参数不再退化成 `void *` | `net.h` 前部含 `#include <stdio.h>` / `#include <sys/socket.h>`，`int (*send)(void *, struct sockaddr *, int);` |
| (2) `map` 两级绑定 | **部分（当日补齐）**：直绑零生成、表达式实参、宏常量、限定实例都已可用；**当时仍要求实例是已声明变量**，同日由 SH-20 的命名空间宿主补上 | `-> real_put;` 生成 `.put = real_put` 且 `--emit-map` 为 `"wrapper": false`；`map trait Writer for instance hal::netlib` 当时报 `is not a declared variable` → [SH-20](selfhost/ct-ast-map-requires-instance.md) |
| (4) `extern` + 函数指针 | **部分**：`extern` 变量、函数指针的声明/赋值/调用/字段/跨单元导出都可用；函数原型被拒，库函数名不能作右值 | `p = exit;` 报 `use of an undeclared variable` → [SH-21](selfhost/ct-ast-fnptr-cannot-name-libfn.md)；`extern int lib_fn(int);` 报 `extern declares a variable, not a function` 且位置漂移 → [SH-22](selfhost/ct-ast-extern-function-prototype.md) |

复核中新发现的硬阻塞：

| ID | 严重度 | 结论 |
| --- | --- | --- |
| SH-19 | **High** | `trait T { int f(void *p); }` 直接报 `unexpected token`；`const void *` 可绕过。C 的 buffer/ownership API 几乎都用裸 `void *`，跨单元链接通了但接口签名写不出来 |
| SH-18 | Medium（升级） | 命名空间内的 trait 类型在消费单元**裸名也不可用**（`Writer w;` → undeclared variable），只有 alias import 可行；struct 裸名却可用，两者不一致 |
| SH-20 | Medium | 命名空间级绑定当时仍需一行 dummy 实例（`void *h;` 可充当，但不是「无需实例」）；当日已修 |
| SH-21 | Medium | 函数指针右值必须是 CT 函数或 ALL_CAPS 宏，库函数要 `#define` 绕过——诉求里明确不要宏 |
| SH-22 | Medium | `extern` 函数原型被拒，且诊断位置落在后续行（违反 `file:line:col:` 约定） |
| DOC-22 | Low | `bindings/mock-hal/uart.ct`、`bindings/README.md`、`test/modules/map_ns/hal/uart.ct` 的 `unit-private` / `not mangled` 注释过期；设计文档状态仍写「待实现」 |

新用例覆盖：`test/modules/{xunit_box,extern_decl,dup_impl,map_ns,pub_global,ns_globals,ambig_global}`、
`test/ast/{15_map_args,20_map_expr,21_fnptr,22_map_direct,23_impl_unused,19_bitops}` 与
`test/ast/errors/{extern_function,map_unknown_arg,bitops_assign_target}`，均由 `check-ast.sh` 钉住。

### 处置（2026-10-22，同日）

本轮 6 条全部落地：4 条修复、1 条部分修复、1 条文档化 + 诊断改进。

| ID | 处置 | 验收点 |
| --- | --- | --- |
| SH-19 | 已修：`parse_trait` 在 `void` 后前瞻一个 token，`(void)` 仍表示空参数，`void *p` 按普通参数解析 | `test/ast/24_trait_voidptr`（trait 方法与 impl 都用 `void *`，装箱调用） |
| SH-22 | 已修：`extern` 接受函数原型（只声明，`pub extern` 进 `.h`、`.c` 不定义）；`extern` 名不 mangling；诊断位置改用 `extern` 行的快照 | `test/modules/extern_decl` 增 `pub extern int lib_fn(int x);` + `lib_impl.c` 提供符号；负例 `extern_function.ct` 报在 `extern` 行 |
| SH-21 | 已修：裸名右值在 CT 符号表里查不到时原样发射，由 C 编译器按原型校验（与普通调用、map wrapper 的既有策略一致） | `test/ast/25_fnptr_libfn`：`p = strcmp;` 后调用 |
| SH-18 | 部分修复：导出的 `pub struct` / `pub trait` / `pub typedef` 可按**裸名**引用（`Writer w;` / `struct Uart u;` 解析到 `hal_Writer` / `hal_Uart`）；两个命名空间同名时裸名报错并提示 alias import；限定类型写法仍不支持，但诊断已明确 | `test/modules/ns_types`（正例）、`test/modules/ambig_type`（负例） |
| SH-20 | **已修（同日追加）**：新增命名空间宿主 `map trait T for namespace A::B { … }` 与 `T::A::B` 装箱，`self` 为 `NULL`，不再需要占位实例；命名空间宿主禁用直绑（无 `self` 可交）；`pub` trait 时 vtable 跨单元导出；`--emit-map` 每条 map 带 `"host"` | `test/ast/26_ns_host`（输出 68）、`test/modules/ns_host`（`writer.h` 出 `extern`、消费单元 NULL 装箱）、负例 `ns_host_no_map.ct` / `ns_host_direct.ct`；language-spec §4.10 中英对称 |
| DOC-22 | 已修：mock-hal 注释、`bindings/README.md` §5、`map_ns` 注释、Batch 2 设计文档状态与 `phase12.md` 状态注记 | `grep -rn "unit-private\|not mangled" bindings test/modules docs` 只剩已标注为历史的冻结正文 |

门禁：`bash selfhost/check-all.sh` 九关全绿、零 `FAIL`；`bash selfhost/check-warnings.sh` 零告警。

## 测试覆盖度与文档一致性审计（2026-10-31）

完整报告：[reports/audit-2026-10-31](../reports/audit-2026-10-31/audit-2026-10-31.md)。锚点 `f4c77b1`、
`v0.13.0`；基线 `bash selfhost/check-all.sh` → `check-all: OK (9 hard gates green)`。

### 结论

- 九关全绿，但**ct-ast 的生成 C 没有任何逐字节 oracle**：判据是 D34（退出码 + 零警告构建 + 程序输出），
  `test/cases` 的 25 个 golden 仍是 L0 时代构造，`docs/language-spec.md` §4.12–4.38 的 27 个特性只有行为探针。
- 负例强度被高估：68 个 ct-ast 负例中 56 个钉死消息文本，12 个只断言「有位置」，约 140 条诊断消息无夹具。
- 文档有 8 处事实性漂移，其中 **DOC-23 / DOC-24** 会让用户按文档操作得到错误结果。

### 新增 18 条

| ID | 严重度 | 标题 |
| --- | --- | --- |
| DOC-23 | High | README 把 `build --emit-map -` 写成不可用，实测可用 |
| DOC-24 | High | 教程称普通 `.ct` 会生成 `.h`，与 batch 30 规则和 README 相反 |
| DOC-25 | Medium | README 称 `-I` 两模式均限 16，compile 实际无上限（且忽略该开关） |
| DOC-26 | Medium | 多处断言计数与 tag 布局过期（grammar 21→27、check-ast 105→317、v0.13.0 仍写旧布局） |
| DOC-27 | Medium | `test/README.md` 的层图与负例约定过期（01..18、缺 patterns、include 路径错误） |
| DOC-28 | Medium | `issues/README.md` 仍写 8 关、把已关闭的第二轮 8 条列为待修（本轮已同步修正） |
| DOC-29 | Low | batch 4 的 checklist 27 项全未勾，与其他 32 份不一致 |
| DOC-30 | Low | 版本登记漂移：glossary 暗示 Phase 13，AGENTS 中文版 bump 登记缺 v0.13.0 |
| TEST-7 | **High** | ct-ast 的生成 C 无逐字节 oracle；§4.12–4.38 共 27 节只有行为探针 |
| TEST-8 | Medium | 12 个负例只断言「有位置」，消息文本可静默漂移 |
| TEST-9 | Medium | 绝大多数容量上限可达但无用例（仅 MAX_MAPS / MAX_ERRORS 有夹具） |
| TEST-10 | Medium | build 模式的 CLI 错误分支几乎未测 |
| TEST-11 | Medium | compile 与 build 两模式没有同一特性的镜像用例 |
| TEST-12 | Low | `check-warnings.sh` 未扫描 `test/patterns`（及 archive / acceptance） |
| TEST-13 | Low | `missing_method.ct` 在两个负例目录各一份，清点时易重复计数 |
| CI-4 | Medium | 仓库无 CI 配置，九道门禁只靠手工执行 |
| SH-23 | **High** | ct-ast 静默截断超长标识符（159 字符），与 spec「>127 报错」相反且可致重定义 |
| SH-24 | Info | compile 与 build 两套 CLI 解析器并存，导致 `-I` 上限与文案分叉 |

### 关键探针（原始结果）

```text
# build --emit-map -（DOC-23）
$ mkdir -p out && ct-ast build h.ct -o out --emit-map -
{…JSON…}                                   # exit 0

# 普通 .ct 不产 .h（DOC-24）
$ ct-ast hello.ct -o hello.c
$ ls hello.h
ls: hello.h: No such file or directory

# -I 两模式不对称（DOC-25 / SH-24）
$ ct-ast -I d1 … -I d30 in.ct -o out.c     # exit 0（compile 忽略该开关）
$ ct-ast build -I d1 … -I d17 in.ct -o out # ctc: too many -I roots / exit 1

# 超长标识符静默截断（SH-23）
$ ct-ast /tmp/idc.ct -o /tmp/idc.c         # exit 0
$ gcc -Wall /tmp/idc.c
/tmp/idc.c:7:9: error: redefinition of 'aaa…（159 个 a）'
```

### 建议的处理顺序（按风险）

1. TEST-7：为 ct-ast 的开关 / enum / union / goto / 位域 / 匿名成员各建一条逐字节 golden；
2. SH-23：超长标识符改为报错，并补负例；
3. TEST-8 / TEST-9：补齐 12 条消息文本与各 `MAX_*` 夹具；
4. TEST-10 / DOC-25：先定 `-I` 口径，再补 build 的 CLI 错误分支；
5. DOC-23 / DOC-24：两处面向用户的高危漂移；
6. CI-4：加 `check` 别名与最小 CI，让九关不再依赖个人记忆。

### 审计未覆盖

- 未在 Linux / glibc 上复跑；两条 BSD 探针仍 `skip`（macOS 专属）。
- 未逐条审计 `docs/design/batch5..35/**` 正文，只做了状态行与计数抽样。
- 审计期间观察到一次并发 `check-all.sh` 的 `FAIL`，串行重跑九关全绿且未复现；门禁的并发安全性未设计、未验证。








## 处置（2026-10-31，审计 18 条的结论）

设计记录与验证数据见 [docs/design/batch37-audit-fixes](../docs/design/batch37-audit-fixes/spec.md)。

| 结论 | 条目 |
| --- | --- |
| 已修复（13） | DOC-23 / 24 / 25 / 26 / 27 / 29 / 30；TEST-8 / 10 / 11 / 12 / 13；SH-23 |
| 复核确认已修复（1） | DOC-28 |
| 部分处置（2） | TEST-9：新增 5 个生成式上限用例（params / methods / funcs / scopes / vars），其余按需再补；CI-4：新增 `Makefile` 的 `make check`，不加云端 workflow（宿主与凭据未定，BSD 探针需跳过策略） |
| 不采纳（2） | TEST-7：不建 27 节逐字节 golden——D34 的判据是行为，且 L0 golden、自编不动点、L0 种子关已提供字节级覆盖；SH-24：不合并两套 CLI 解析器——Info 级、两种行为都可工作，合并属结构改动，差异已在 README 写清 |

修复后的门禁：`check-ast.sh` 351 passed、`check-warnings.sh` 152 ok、`check-all.sh` 九关全绿；
生成物、golden 与 `CTC_VERSION` 未变，L0 / L1 / L2 未动（SH-23 只落 ct-ast）。

## 代码审查与文档一致性审查（2026-10-31，锚点 `524ba99`、`v0.15.1`）

完整报告：[reports/review-2026-10-31](../reports/review-2026-10-31/review-2026-10-31.md)。

### 结论

- 九关全绿（`test/run.sh` 118、`check-ast.sh` **403**、`check-warnings.sh` 161、acceptance 20）。
- 文档 **13 处**事实漂移：2 条 High（教程把已支持的 `switch`/`do-while`/`goto` 说成不支持；
  `bindings/README.md` 中文 §5 与英文 §5、实现相反），5 条 Medium，6 条 Low。
- 代码 **8 处**缺陷候选：1 条 High（带 tag 的 `typedef` 别名丢 `dims` → 生成 C 编译失败），
  4 条 Medium（未初始化读、诊断行号永久偏移、无花括号分支的 `own` 静默泄漏、第 65 个字段静默丢弃），
  2 条 Low，1 条 Info。
- `borrow` / `Handback` 提案评审追加 **1 条 High**（SH-33：AutoDrop 在 `return` 前不注入、
  不置空 → 含 `return` 的函数静默泄漏并留下死代码）。

### 新增 21 条

| ID | 严重度 | 标题 |
| --- | --- | --- |
| DOC-31 | **High** | 教程称 `switch` / `do-while` / `goto` 不受 ct-ast 支持，实际早已支持 |
| DOC-32 | Medium | 教程命令表称普通 `.ct` 同时产出 `.h`，与同文 §1 和 README 相反 |
| DOC-33 | Low | 教程称 `examples/` 有 7 个可运行示例，实际 8 个 |
| DOC-34 | Low | 编辑器语法断言数仍写 27（实为 31），`check-all.sh` 第 8 关标签停在 12.1 |
| DOC-35 | Medium | `test/README.md` 的探针区间与负例计数过期（01..56 / 56-of-68） |
| DOC-36 | **High** | `bindings/README.md` 中文 §5 仍称接口值不能跨单元，与英文 §5 和实现相反 |
| DOC-37 | Medium | `selfhost/README.md` 中文表仍是 ct-ast 三文件旧布局，且门禁清单漏 `check-warnings.sh` |
| DOC-38 | Medium | README 干净 clone 段对 `.gitignore` 的描述不成立 |
| DOC-39 | Medium | glossary 把节点池模块指成 `backend::mem::Memory` |
| DOC-40 | Low | roadmap 对 `check-ast.sh` 断言数给出两个互斥且均已过期的数字（317 / 359） |
| DOC-41 | Low | glossary 的「能力补丁」例外清单漏 `v0.15.1` |
| DOC-42 | Low | README 英文版称 `test/ast/errors/` 只按退出码断言 |
| DOC-43 | Low | `MAX_NODES` 只存在于文档与注释里，代码中没有这个宏 |
| SH-25 | **High** | 带 tag 的 `typedef` 别名漏拷 `dims`，数组字段生成编译不过的 C |
| SH-26 | Medium | `*p = v;` 的赋值路径读取未初始化的 `tt` |
| SH-27 | Medium | `struct_def_ahead` 不回滚行号状态，跨行前瞻后诊断行号永久偏移 |
| SH-28 | Medium | 无花括号分支里的 `own` 既不 AutoDrop 也不告警，静默泄漏 |
| SH-29 | Medium | 第 65 个字段被静默丢弃（`MAX_FIELDS` 越界不报错） |
| SH-30 | Low | `emit_unit` / `write_unit_header` 的失败路径漏 `fclose`，`build` 还留下半截 `.h` |
| SH-31 | Info | `emit_cond` 的 `B_AND` / `B_OR` / `B_XOR` 分支永远不可达 |
| SH-32 | Low | compile 模式接受多个位置参数，静默只编译最后一个 |

### 提案评审追加（2026-10-31）

评审 `borrow` / `Handback` 提案时实测追加 1 条；设计规格见
[docs/design/borrow.md](../docs/design/borrow.md)。

| ID | 严重度 | 标题 |
| --- | --- | --- |
| SH-33 | **High** | AutoDrop 只在 `}` 注入：含 `return` 的函数静默泄漏，生成死代码且不置空 |

```text
# SH-33：函数体内 own + return，对象既不 drop 也不 free，释放语句落在 return 之后
$ ct-ast body.ct -o body.c ; echo $?
0
$ cc -Wall -Wextra -std=c99 body.c -o body && ./body
using 7                 # 没有 "dropped 7"，stderr 也没有告警
$ awk '/^int f\(void\)/,/^}/' body.c
    return 1;
    if (p) { Box_Drop_drop(p); free(p); }    # 死代码，且没有 p = 0
# L2（oracle）同一输入：`if (p) { Box_Drop_drop(p); free(p); p = 0; }` 在 return 之前
```

### 关键探针（原始结果）

```text
# SH-25：typedef 别名丢 dims（DOC 之外的唯一 High 代码缺陷）
$ ct-ast td.ct -o td.c ; echo $?
0
$ grep 'WrapT w' td.c
    WrapT w = { .items.__t_vptr = &Inner_T_vtable };
$ cc -Wall -Wextra -std=c99 -c td.c
td.c:34:23: error: field designator cannot initialize a non-struct, non-union type 'struct Inner[2]'

# SH-27：struct 头跨行后诊断行号 +1
$ ct-ast ln.ct -o ln.c          # 重复定义实际在第 3 行
ln.ct:4:10: error: duplicate struct 'S'

# SH-29：第 65 个字段被丢弃（63 个 int + Inner 正常，64 个 int + Inner 丢 init）
n=63 → struct Big b = { .in.__t_vptr = &Inner_T_vtable };
n=64 → struct Big b;

# SH-28：无花括号分支的 own 不生成 drop/free，且无告警
$ ct-ast own2.ct -o own2.c ; echo $?
0

# SH-32：多个位置参数只编最后一个
$ ct-ast a.ct b.ct -o out.c ; echo $?
0
```

### 本轮未覆盖

- 未在 Linux / glibc 上复跑；两条 BSD 探针仍按设计 `skip`。
- 未逐条审计 `docs/design/**` 的 59 份批次档案正文（只核对 batch 38/39 的状态与计数）。
- SH-30 / SH-31 为读码确认，未构造触发（前者需要「发射中途失败」的输入，后者只影响死代码可读性）。
- batch 39 的伴生 C shim 收尾改动为在途状态（10 个已修改文件），本报告不评判。

### 处置（2026-10-31，代码审查 21 条）

21 条全部确认为真实问题并于同日修复，**无「不采纳」条目**。逐条状态已回填到各 issue 文件；
验收点如下：

| ID | 处置 | 验收点 |
| --- | --- | --- |
| DOC-31 / DOC-32 / DOC-33 | 已修 | `docs/tutorial.md` 中英：§11.5 改「均已支持」；§10 命令表改「普通 `.ct` 只写 `.c`，`.h.ct` 才额外写 `.h`」；§12 examples 7 → 8 |
| DOC-34 | 已修 | `README.md` / `AGENTS.md`（中英）/ `check-all.sh` 第 6 关 27 → 31；第 8 关标签补到 batches 3–39 |
| DOC-35 | 已修 | `test/README.md` 中英：探针 `01..60`；负例 72/72 全部钉死（63 进表 + 9 个独立 `grep -q`） |
| DOC-36 | 已修 | `bindings/README.md` 中文 §5 与英文对齐（Batch 2 起接口值可跨单元）；检查清单同步 |
| DOC-37 | 已修 | `selfhost/README.md` 中文表改分组多单元；中英门禁清单补 `check-warnings.sh` |
| DOC-38 / DOC-42 | 已修 | `README.md` 中英 `.gitignore` 段按实际改写；英文 negatives 描述补「源位置 + 钉死文本」 |
| DOC-39 / DOC-41 | 已修 | glossary 中英：arena → `runtime::arena::Arena`；能力补丁清单补 `v0.15.1` |
| DOC-40 | 已修 | roadmap 中英 317 / 359 → 2026-10-31 实测 408，去掉「当前」字样 |
| DOC-43 | 已修（含代码） | `Arena.h.ct` 新增 `#define MAX_NODES 131072`；数组字段仍写字面量（宏不跨翻译单元）；language-spec 中英补实现说明 |
| SH-25 | 已修 | `Parser.h.ct` tag→别名字段复制补 `dims`；新增行为探针 `test/ast/59_typedef_alias_array` |
| SH-26 | 已修 | `Stmt.h.ct` 的 `=` 分支初始化 `tt`；`iface_ref_type` 增空串短路 |
| SH-27 | 已修 | `struct_def_ahead` 回滚 `line` / `tokline` / `tokstart` / `lstart`；新增 `struct lookahead line` 断言 |
| SH-28 | 已修 | `parse_branch` 无花括号也建 `N_BLOCK` 并追加 AutoDrop；新增行为探针 `test/ast/60_branch_autodrop` |
| SH-29 | 已修 | `register_field` 两处越界改硬报错 `too many fields in a record`；新增 `cap fields` 断言 |
| SH-30 | 已修 | 两个发射函数的正文拆到文件作用域静态 helper（不新增 trait 方法），失败路径对称 `fclose`；`.h` 失败时删除半截产物 |
| SH-31 | 已修 | 删除 `emit_cond` 的三个不可达分支 |
| SH-32 | 已修 | compile 模式拒绝第二个位置参数；显式消费 `compile` 关键字；新增 `compile mode refuses a second input` 断言 |

取舍说明（用户可据此复核，均非「不采纳」）：

1. **DOC-43 不能只加一个宏**：节点数组会进生成的 `Arena.h`，而宏不跨翻译单元，字段长度必须是
   字面量 `131072`；实现保留宏供 `alloc` 判界，并在注释与 language-spec 里写明两者必须相等。
2. **SH-32 保留 `compile` 关键字**：`ct compile <file>` 是 README 记载的合法写法，加多输入校验前
   必须先显式消费该关键字，否则会把关键字本身当成第一个输入。
3. **SH-30 用静态 helper 而非 trait 方法**：L2 oracle 的 `MAX_MAP_IMPLS` 已到顶
   （`selfhost/l2/core.ct:50`），新增 impl 方法会让 L2 编 ct-ast 直接失败；按既有约定
   （`docs/design/batch33-header-compat/spec.md`）不抬上限。

修复后门禁：`check-ast.sh` **408 passed**、`check-warnings.sh` 163 ok、
`check-all.sh` 九关全绿（`test/run.sh` 118、editor grammar 31、pkg 与 acceptance 全绿）；
`CTC_VERSION` 未动（v0.15.1），`*.expected.*` 未重生成，`selfhost/l2/**` 未改。


## 代码审查（2026-11-01，锚点 `8b047f5`，`borrow` / `Handback` 实现）

完整报告：[reports/review-2026-11-01](../reports/review-2026-11-01/review-2026-11-01.md)。

### 结论

工作树里的 `borrow` / `Handback` 已实现到「声明 + 出口归还 + 逃逸警告」的完整形态，
`test/ast/61_autodrop_return` 与 `62_borrow_handback` 两条探针钉住了 SH-33 的修复与出口生成，
九道硬关卡全绿（`check-ast.sh` **425 passed**、`check-warnings.sh` **165 ok**）。

但新特性有 3 条 High 级语义漏洞，都指向同一个模式：**「归还」被挂在 `own` 的逃逸分析上，
任何一处把 `autodrop` 清掉，出口就静默不归还**：

```
`q = c;`        → leak_assign 清 autodrop          → 无 handback，无告警   （SH-35）
`return c->f;`  → leak_return 清 autodrop          → 无 handback，无告警   （SH-36）
文件作用域声明  → 根本不进 parse_stmt              → `borrow` 原样进 C     （SH-34）
```

其余 5 条是判定覆盖不到的位置（`static` 局部、跨单元、impl 顺序）与置空带出的回归（SH-40 / SH-41）。

### 新增 15 条

| 类别 | 条目 |
| --- | --- |
| 代码（8） | SH-34、SH-35、SH-36（High）；SH-37、SH-38、SH-40、SH-41（Medium）；SH-39（Low） |
| 文档（7） | DOC-45（High）；DOC-44、DOC-46、DOC-47、DOC-48、DOC-49（Medium）；DOC-50（Low） |

### 复核确认已修的 8 条

SH-25…SH-32 的修复都在工作树里，本轮逐条实测通过（详见
[DOC-44](docs/doc44-ledger-statuses-stale.md) 的表）；这 8 个 issue 文件的 `状态` 曾一律写「待修」，
台账与代码不同步——这就是 DOC-44 本身，其状态行已在本轮回填。

### 建议的处理顺序

1. SH-36 → SH-35 → SH-34：三条 High 互相咬合，一起修（`leak_*` 只对 `!borrowed` 清标志 +
   `expr_mentions` 换 `expr_returns` + 顶层拒绝文件作用域 `borrow`）。
2. SH-40：置空只对可赋值实参，属 SH-33 修复带出的回归，改动最小。
3. SH-37 / SH-38 / SH-39：借用判定的同一模块，建议一次改完；SH-38 若不修，必须先写进 §4.40「已知限制」。
4. 文档：DOC-45 → DOC-47 → DOC-46 → DOC-48 → DOC-49 → DOC-44 → DOC-50 一次改完（前三者是同一行为变更的下游残留）。

### 未覆盖与不采纳

`goto` 跨声明静默失效、池对象与栈对象不区分、`store(c)` / `s->p = c` 不检查，均为设计已声明的已知限制，
本轮不重复立案；batch 39 的在途改动同样不在范围内。

### 处置（2026-11-01，代码审查 15 条）

15 条全部处理完毕：**14 条修复 + 1 条按建议文档化（SH-38 的跨单元 `Handback` 不实现）**。
逐条状态已回填到各 issue 文件；验收点如下：

| ID | 处置 | 验收点 |
| --- | --- | --- |
| SH-34 | 已修 | `Parser.h.ct` 顶层声明入口拒绝 `borrow`（`'borrow' is only allowed inside a function body`）；门禁 `bw_neg borrow_file_scope` |
| SH-35 | 已修 | `Memory.h.ct` 的 `leak_assign` / `leak_decl` 跳过 `borrowed`（逃逸交给 `check_borrow_store`）；`Stmt.h.ct` 拒绝重赋值（`a borrowed pointer cannot be reassigned`）；门禁 `bw_neg borrow_reassign` + 正例 `bw_copy.ct` |
| SH-36 | 已修 | `Memory.h.ct` 的 `leak_return` 在 `autodrop` 分支改用 `expr_returns`（`p` / `p[0]` 才算移交，`p->n` 不算）并同时清 `owned`；门禁正例 `bw_ret.ct` |
| SH-37 | 已修 | `Symbols.h.ct` 的 `Var` 新增 `is_static`、`parse_var` 置位；`check_borrow_store` 拒 `static` 局部与文件作用域目标；门禁 `bw_neg store_static` |
| SH-38 | 已修（文档化不实现） | 跨单元 `impl Handback` 需跨单元 impl 表（`Drop` 同样没有），记入 `docs/design/borrow.md` §7 与 `language-spec` §4.40 的已知限制；门禁 `bw_neg no_impl` 钉死 `but this unit has no impl` |
| SH-39 | 已修 | `mark_borrow` 失败消息改为 `struct '<S>' uses trait 'Handback' but this unit has no impl`（impl 写在 `borrow` 之后也不再误报）；门禁 `bw_neg no_impl` |
| SH-40 | 已修 | `Emitter.h.ct` 的 `N_DELETE` 只在实参可赋值（`N_VAR` / `N_MEMBER` / `N_ARROW` / `N_INDEX` / `N_DEREF`）时追加 ` = 0; `，否则生成 `if (e) { …; }`；门禁正例 `bw_delete.ct` |
| SH-41 | 已修 | 与 SH-36 同一处 `expr_returns` 判定，`return b;` 不再误报 `potential leak`；门禁正例 `bw_handoff.ct` |
| DOC-44 | 已修 | SH-25…SH-32（8 个）与 DOC-31…DOC-43（13 个）的状态行全部回填，本文顶部与本节同步 |
| DOC-45 | 已修 | `docs/tutorial.md` §8 中英：`delete` 会置空（非左值只释放）；`own` 在 `}` 与每个 `return` 之前释放，「行首」只属 L2 |
| DOC-46 | 已修 | `README.md` 中英变换表：`delete` / `own` / `borrow` 三行与生成物一致，英文侧补回 borrow 行 |
| DOC-47 | 已修 | `docs/memory-guide.md` 中英 10 处旧 AutoDrop 表述改为 v0.16.0 现状（含出口示例与决策树） |
| DOC-48 | 已修 | `docs/design/borrow.md` 头部锚点与状态、§2 前提订正、§8 同批落地、§11 决策表加「状态」列、§7 已知限制第 7/8 条 |
| DOC-49 | 已修 | `ct.tmLanguage.json` 新增 `ct-borrow` / `ct-borrow-param` / `ct-trait-builtin` 并入 `patterns`；`check-grammar.py` 31 → **33** 断言全绿，README / AGENTS / `check-all.sh` / 插件 README 同步（插件版本 0.3.0） |
| DOC-50 | 已修 | `docs/roadmap.md` 的 v0.16.0 记录四处（版本表 / 批次记录 / 英文表 / 英文记录）与 `docs/glossary.md` 的 borrow / AutoDrop 措辞改为「每个 `return`、无位置要求」 |

门禁结果见本轮提交正文；`CTC_VERSION` 未动（仍 v0.16.0），`*.expected.*` 未重生成。

## 第三方评估复核（2026-11-01，`v0.16.1`，锚点 `61e35e4`）

被复核对象是仓库外的一份独立评估报告（`v0.16.1` 快照，10 条缺点 + 10 条优点）。本轮把它能在本仓
复现的部分逐条实测，凡确认为真的按既有格式立项，不可复现或属定位取舍的记入「不立案」。
报告的环境数据与现状吻合：`ct v0.16.1`、`88M`、文档行数 `3290 / 971 / 2550` 全部一致。

### 复验结果

| 报告条目 | 复验 | 处置 |
| --- | --- | --- |
| D1 impl ↔ trait 签名不一致不报错 | 成立：`ct` exit 0，`cc` 在生成物上报 `incompatible function pointer types`；**L0 同样 exit 0**，故不是主线退化 | 不立案：`language-spec.md:1460` 与 `AGENTS.md:23` 已明写「不做签名检查 / 不做类型检查」，属定位取舍；只建议给 `vision.md` §2.4 加「由 C 编译器在生成物上报」的限定语 |
| D2 四层逐字节一致是结构性成本 | 事实成立；「日常降级为发行前快照」的建议不采纳 | 不立案：`check-archive` / `check-m2a` 是四层不漂移的唯一自动防线；容量问题按 SH-1 / SH-42 处理 |
| D3 88MB 二进制，根因静态 arena | 成立：`__DATA 105267200`，`Node ≈ 528 B × 131072` | **SH-42** |
| D4 文档漂移两处 | 两处均复现，且**漏项**：§11 另有第 3、4 条与 spec §6.2 三行同样过期 | **DOC-51**、**DOC-52** |
| D5 无标准库 | 描述成立 | 不立案（窄定位取舍，报告自身 A1 亦如此论证） |
| D6 限定名与消歧弱 | `Rep::OK` 被拒成立；但限定**调用**（`a::one()` / `Point::size(p)`）是支持的，标题与结论不符；「多 trait 同名静默取首个」无可复现脚本 | 不立案：限定调用部分失实，其余待最小复现再开 |
| D7 全是 `int` 返回码 | 描述成立 | 不立案（C 直通定位） |
| D8 无 CI / `build` 不编译 / 无 LSP | CI 部分 = 在册 CI-4（已有 `make check`，仍无 workflow）；其余成立 | 不立案 CI（CI-4 已覆盖）；`ct build` 记 **SH-43** |
| D9 FNV-1a 摘要 | 成立（`Pkg.h.ct:249-318`，逐文件 `file_digest ^ name_digest` 相加） | **SH-44** |
| D10 `borrow` 语义陡 | 条数引自本轮 SH-34…SH-41，未做独立审计 | 不立案；3 条 High 的根因已在本文「代码审查（2026-11-01）」记录 |

### 新增 5 条

| 类别 | 条目 |
| --- | --- |
| 文档（2） | DOC-51（High）、DOC-52（Medium） |
| 代码 / 工程（3） | SH-42（Medium）、SH-44（Medium）、SH-43（Info / 待决） |

### 处置（2026-11-01，第三方复核 5 条）

4 条修复 + 1 条维持待决（SH-43）。逐条状态已回填到各 issue 文件；验收点如下：

| ID | 处置 | 验收点 |
| --- | --- | --- |
| DOC-51 | 已修 | `docs/tutorial.md` §7 中英把 `impl_dog.ct` 改为 `impl_dog.h.ct`，并补「承载 `impl` 的单元要写成 `.h.ct` 才能被 import」；未照抄评估报告关于 `ct build` 拒绝 `.h.ct` 的错误提示 |
| DOC-52 | 已修 | `docs/tutorial.md` §11 第 2–4 条与 `docs/language-spec.md` §6.2 三处标注「仅 L2」，删除「一行一句是硬要求」，补「ct-ast 不保留源码注释」；中英同改 |
| SH-42 | 已修 | `Arena` 的 `nodes` / `strpool`、`Symbols` 四张大表、`Parser.g_maps`、`Module.g_units` 改为 `calloc`；`ls -lh ct` **637K**（验收 < 5MB）、`size -m ct` 的 `__DATA` **589824 B**（验收 < 1MB）；`test/ast/**` 生成物零字节变化 |
| SH-43 | 待决（不实现） | 维持「`ct build` 只发 `.c/.h`、打印 `cc` 行」的现状；不新增 `--emit-build-plan` / `--cc`，能力变更留待维护者决定 |
| SH-44 | 已修 | `Pkg.h.ct` 改 SHA-256（FIPS 180-4，单流：按路径排序后逐个喂 `相对路径\n` + 内容），lock 写 `sha256:<64 hex>`；旧 16 位 FNV 摘要显式报 `unsupported digest`；`test/pkg/run.sh` 夹具同步并新增「同尺寸篡改」与「旧格式」两个负例（37 断言全绿）。摘要与 Python `hashlib` 参考实现逐字节一致 |

迁移影响：SH-44 使既有 `ct.lock` 失效（需重新 `ct get` 生成）；本轮未 bump `CTC_VERSION`，也未打新 tag。

### 建议处理顺序

1. DOC-51 → DOC-52：同一页 §7 / §11，中英同改，改完用报告附录的探针自查；
2. SH-42（arena 堆化）：唯一动运行时的一步，先量后改，验收以 `ls -lh ct` 与九关为准；
3. SH-44（摘要换 SHA-256）：涉及 `ct.lock` 兼容（旧 lock 失效需授权），并重生成 `test/pkg` 夹具；
4. SH-43（`ct build` 能力）：先定「加不加」，再加则同步 README / spec / usage 与门禁。

### 不立案与偏差订正

- D1 / D5 / D7 / D10 属定位取舍或已在册，未新开条目；D2 的降级建议明确不采纳；
- D6 的「限定调用不支持」不成立，修复本条时不要照抄该报告；
- 报告称「`ct build` 会拒绝 `.h.ct` 单元」，实测不成立（`ct build -I <dir> <unit>.h.ct -o <out>` 返回 0）；
  真正被拒的是 **compile 单文件模式**里的 `import`（`error: 'import' is not supported in compile mode`）；
- 仓库根残留 `demo.o` / `impl_dog.o`（已被 `.gitignore` 挡住，未入库）属信息级整洁问题，不单独立项。
