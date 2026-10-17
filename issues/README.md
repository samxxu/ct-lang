# 审查发现的问题（issues）

本目录汇总 [reports/repo-review](../reports/repo-review/repo-review.md) 的审查发现，**每条 issue 一个 markdown 文件，按模块分目录存放**。

- 源码锚点：commit `8aac450`（2026-10-17）——文中行号是该 commit 的快照。
- 状态：**11 条已修复、1 条部分修复**（2026-10-17；逐条状态与修复提交见各文件的状态行，汇总见下方「修复进展」）。
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

### `testing/` —— 测试覆盖度

| ID | 严重度 | 标题 | 文件 |
| --- | --- | --- | --- |
| TEST-1 | Medium | `ctc.c:2837`（cannot create a temporary file）可达但无负例 | [ctc-2837-tmpfile-not-covered.md](testing/ctc-2837-tmpfile-not-covered.md) |
| TEST-2 | Medium | `ctc.c:2708`（cannot read）可达但无负例 | [ctc-2708-cannot-read-not-covered.md](testing/ctc-2708-cannot-read-not-covered.md) |
| TEST-3 | Low | `ctc.c:1491`（nested field path too long）探针未复现，文档却称不可达 | [ctc-1491-nested-path-not-reproduced.md](testing/ctc-1491-nested-path-not-reproduced.md) |

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

## 汇总

- High: 4（DOC-1、DOC-2、CI-1、CI-2）
- Medium: 5（DOC-3、DOC-4、TEST-1、TEST-2、SH-1）
- Low: 2（DOC-5、TEST-3）
- Info: 1（SH-2）

合计 12 条。

## 修复进展（2026-10-17）

11 条已修复、1 条部分修复：

| 提交 | 覆盖 |
| --- | --- |
| `5bde821` docs: correct stage and CT-line gates | DOC-1、DOC-2、DOC-3 |
| `b6b3dc4` docs: fix reachability and stale to-dos | DOC-4、DOC-5、TEST-3、SH-1 |
| `1a1ae91` test(cli): cover two driver failure sites | TEST-1、TEST-2 |
| `8765c83` chore(ci): add the aggregate gate entry point | CI-1、CI-2（`selfhost/check-all.sh`） |
| `54c3713` refactor(selfhost): give the symtab to Pipe | SH-2（第一步：`sym` 收进 `Pipe`） |

部分修复（保留的设计取舍）：

| ID | 说明 |
| --- | --- |
| SH-2 | `struct SymTab *sym` 已从 32 个方法收进 `Pipe`；剩下的文件作用域 static（扫描状态 / 诊断表 / 缓冲）被顶层自由函数直接读取，移进对象需要给设施层全部加参数，成本高于收益。若 Phase 5 引入 AST，上下文对象应随之整体设计 |

验证：`bash selfhost/check-all.sh` 六道硬关卡全绿（acceptance 18 pass / 1 pending，预期）；`./test/run.sh` **117 passed, 0 failed**（原 115，新增 `cli/cannot-read` 与 `cli/tmpfile-cannot-create`）。

> 审查期间未修改任何文件；本目录与报告最初为只读产物，后续修复见上「修复进展」。
