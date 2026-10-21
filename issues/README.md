# 审查发现的问题（issues）

> **历史快照（2026-10-21）**：下文早期段落引自 `selfhost/ast/**`（单文件主线）与 `selfhost/src/**` 时代，
> 这些路径**已不存在**；等价路径为 `selfhost/ct-ast/**`（分组多单元主线）与 `selfhost/l2/**`
> （冻结的回归 oracle）。历史段落保持原样，条目状态未逐条回填。

本目录汇总四轮审查的发现：[reports/repo-review](../reports/repo-review/repo-review.md)（首轮）、
[reports/phase7-review](../reports/phase7-review/phase7-review.md)（Phase 7 复审）、
[reports/phase9-review](../reports/phase9-review/phase9-review.md)（Phase 9 复审）与
[reports/review-2026-10-21](../reports/review-2026-10-21/review-2026-10-21.md)（Phase 12 复审）。
**每条 issue 一个 markdown 文件，按模块分目录存放**；Phase 9 复审的发现由下文「Phase 9 复审」一节承载，未另立文件。

- 源码锚点：首轮 `8aac450`；Phase 7 复审 `ec97f99`（2026-10-17）；Phase 9 复审 `8010875`（2026-10-19）；Phase 12 复审 `4ef8b68`（2026-10-21）——各文件行号以其自身锚点为准。
- 状态：首轮 12 条**已全部修复**；Phase 7 复审新增 8 条**均已处理**（DOC-6–9 修复、TEST-4 修复、TEST-5/6 部分覆盖、SH-3 已决策）；Phase 9 复审 14 项发现**全部关闭**（逐项见下文「Phase 9 复审」一节，复核于 v0.10.0 `885d01b`）；Phase 12 复审新增 8 条**已于 2026-10-21 全部修复**（DOC-10–15、SH-5、SH-6）；复核中另订正 25 处「文档说未实现 / 指向旧主线、实际已落地」的陈述漂移（见其后一节）。
- 严重度：`High`（对外失真/影响正确性认知）· `Medium`（可察觉的缺口）· `Low`（措辞/残留）· `Info`（设计观察）。
- 硬关卡计数随阶段演进：6 → 7 → **8**（`check-ast.sh` 于 Phase 9 作为第 8 关接入 `check-all.sh`）。下文各**带日期的验证记录**里出现的「六道 / 七道硬关卡」是该记录当时的口径，非现状；现状一律以 `check-all.sh` 的「8 hard gates green」与 [roadmap](../docs/roadmap.md) 为准。

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

### `testing/` —— 测试覆盖度

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| TEST-1 | Medium | `ctc.c:2837`（cannot create a temporary file）可达但无负例 | [ctc-2837-tmpfile-not-covered.md](testing/ctc-2837-tmpfile-not-covered.md) |
| TEST-2 | Medium | `ctc.c:2708`（cannot read）可达但无负例 | [ctc-2708-cannot-read-not-covered.md](testing/ctc-2708-cannot-read-not-covered.md) |
| TEST-3 | Low | `ctc.c:1491`（nested field path too long）探针未复现，文档却称不可达 | [ctc-1491-nested-path-not-reproduced.md](testing/ctc-1491-nested-path-not-reproduced.md) |
| TEST-4 | Low | Phase 7 的 `ct` 身份只测了一半（`ct build` / `-h` / `ctc compile` 未测） | [phase7-ct-identity-coverage.md](testing/phase7-ct-identity-coverage.md) |
| TEST-5 | Medium | L2 驱动的错误分支仍无负例（10+ 个站点） | [l2-driver-errors-untested.md](testing/l2-driver-errors-untested.md) |
| TEST-6 | Medium | `--emit-map <file>` 成功路径没有用例 | [emit-map-file-path-untested.md](testing/emit-map-file-path-untested.md) |

### `ci/` —— 门禁与入口

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| CI-1 | High | `./test/run.sh` 完全不覆盖 CT 线（L1/L2 ≈8k 行） | [run-sh-misses-ct-line.md](ci/run-sh-misses-ct-line.md) |
| CI-2 | High | 无聚合入口 / 无 CI：不存在一条命令能跑全部门禁 | [no-aggregate-gate-entry.md](ci/no-aggregate-gate-entry.md) |

### `selfhost/` —— 代码结构与容量

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| SH-1 | Medium | `MAX_FUNCS` 余量极小，是 CT 线最紧的扩展瓶颈 | [max-funcs-headroom.md](selfhost/max-funcs-headroom.md) |
| SH-2 | Info | L2 状态无归属：`SymTab *sym` 参数化 63 次 + 52 处文件作用域 static | [unowned-state-sym-param.md](selfhost/unowned-state-sym-param.md) |
| SH-3 | Low | 以 `ct` 运行时驱动错误仍打印 `ctc:` 前缀（37 处硬编码） | [ct-error-prefix.md](selfhost/ct-error-prefix.md) |
| SH-5 | Medium | ct-ast 存在 27 个定义后从未使用的宏 | [ct-ast-dead-macros.md](selfhost/ct-ast-dead-macros.md) |
| SH-6 | Medium | 16 处「上限账本在 main.ct」注释已悬空，且 `main.ct` 自相矛盾 | [ct-ast-stale-cap-comments.md](selfhost/ct-ast-stale-cap-comments.md) |
| SH-7 | Medium | ct-ast 对已赋值的 struct 值字段仍发嵌套 vptr 指定初始化式（`-Winitializer-overrides`） | [ct-ast-duplicate-field-vptr-init.md](selfhost/ct-ast-duplicate-field-vptr-init.md) |

## 汇总

- High: 4（DOC-1、DOC-2、CI-1、CI-2）——均已修复
- Medium: 11（DOC-3、DOC-4、TEST-1、TEST-2、SH-1 已修复；DOC-6–9 已修复；TEST-5、TEST-6 部分覆盖，剩余项见各自文件）
- Low: 4（DOC-5、TEST-3 已修复；TEST-4 已修复；SH-3 已决策保持 `ctc:`）
- Info: 1（SH-2，已修复）

合计 20 条：已处理 20（其中 TEST-5 / TEST-6 为部分覆盖，未覆盖项已在文件内列明）。
另有 Phase 9 复审的 14 项发现，未单独立文件，逐项状态见文末「Phase 9 复审」一节。
**Phase 12 复审（2026-10-21）新增 8 条：DOC-10…15、SH-5、SH-6，已全部修复**（见文末一节）。

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

## 新发现（2026-10-21，未修）

写安装脚本与入门教程时的实测副产物，两条都**未修**，供后续处理：

| ID | 严重度 | 摘要 | 证据 |
| --- | --- | --- | --- |
| [SH-7](selfhost/ct-ast-duplicate-field-vptr-init.md) | Medium | ct-ast 在构造点对**已赋值**的 struct 值字段仍追加 `.字段.__x_vptr` 嵌套指定初始化式，clang `-Wall -Wextra` 报 `-Winitializer-overrides`；L2 对同一输入不追加、零警告 | `/tmp/ctissue1/dup2.ct`，`ct` 与 `/tmp/l2` 对差 |
| [DOC-18](docs/language-spec-struct-array-field-stale.md) | Medium | language-spec §4.8 仍把「struct 类型的数组字段」列为不支持并引 `p18`「按决定延后」，而 §6 已写 ct-ast 逐元素写 vptr；roadmap 743 与 `test/acceptance/run.sh:436-439` 也还停在「p18 为唯一 PENDING」 | `p18` 探针：ct-ast 输出 `3`，L2 编不过；`BASELINE` 已含 p18、整套 20 pass / 0 pending |

两条均**不影响八关**（`check-all: OK (8 hard gates green)`）：SH-7 的写法不在语料里，DOC-18 的
口径矛盾不产生 golden 差异。




