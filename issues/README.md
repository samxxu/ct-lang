# 审查发现的问题（issues）

本目录汇总两轮审查的发现：[reports/repo-review](../reports/repo-review/repo-review.md)（首轮）与
[reports/phase7-review](../reports/phase7-review/phase7-review.md)（Phase 7 复审）。
**每条 issue 一个 markdown 文件，按模块分目录存放**。

- 源码锚点：首轮 `8aac450`；Phase 7 复审 `ec97f99`（2026-10-17）——各文件行号以其自身锚点为准。
- 状态：首轮 12 条**已全部修复**；Phase 7 复审新增 8 条**均已处理**（DOC-6–9 修复、TEST-4 修复、TEST-5/6 部分覆盖、SH-3 已决策）。逐条状态见各文件的状态行。
- 严重度：`High`（对外失真/影响正确性认知）· `Medium`（可察觉的缺口）· `Low`（措辞/残留）· `Info`（设计观察）。

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

## 汇总

- High: 4（DOC-1、DOC-2、CI-1、CI-2）——均已修复
- Medium: 11（DOC-3、DOC-4、TEST-1、TEST-2、SH-1 已修复；DOC-6–9 已修复；TEST-5、TEST-6 部分覆盖，剩余项见各自文件）
- Low: 4（DOC-5、TEST-3 已修复；TEST-4 已修复；SH-3 已决策保持 `ctc:`）
- Info: 1（SH-2，已修复）

合计 20 条：已处理 20（其中 TEST-5 / TEST-6 为部分覆盖，未覆盖项已在文件内列明）。

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
