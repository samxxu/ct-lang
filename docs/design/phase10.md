# Phase 10 — 主线切换：让 `ct` 由 AST 版编译器提供

> 中文 · [English](#english)
>
> 状态：**10.1–10.5 已落地（2026-10-19）**；10.6–10.7 待推进。D38–D45 已按建议值确认。
> Phase 9 已把 `selfhost/ast/main.ct`（下称 **ct-ast**）做成开发主线，但**用户实际运行的 `ct` 仍由旧管线 L2（`selfhost/src/**`）提供**。
> Phase 10 的目标是补齐 ct-ast 相对 L2 的能力缺口，并把安装入口切过去；旧线保留为回归 oracle。

---

## 中文

### 1. 目标与出口

| 项 | 内容 |
| --- | --- |
| 目标 | 让 **ct-ast** 提供完整的 `ct` 命令行：`compile` / `build` / `get` / `install` 与全部既有选项，行为与 L2 等价 |
| 出口 | 以 ct-ast 构建的 `ct` 跑完整套关卡（`test/run.sh`、`test/modules`、`test/pkg`、`ct-tour`、`acceptance`）全绿；`check-ast.sh` 覆盖全部语料 |
| 版本 | `v0.10.0`（Phase 10 ↔ `v0.10.x`），收口时 bump（冻结期例外，需用户授权） |
| 回退 | 旧线 `selfhost/src/**` 冻结保留，tag `v0.9.0` 即为可回退点；切换本身再打一个非版本 tag |

### 2. 非目标

- 不新增语言特性（`map` 仍只设计冻结）。
- 不改变已发布的产物命名、banner 与 `ctc:` 驱动错误前缀（SH-3 决策）。
- 不改 `ctc.c` / L1。
- 不要求 ct-ast 与 L2 生成的 C **逐字节相同**（D34：行为等价）。

### 3. 能力对差（2026-10-19 按代码实测）

| 能力 | L2（`selfhost/src/**`） | ct-ast（`selfhost/ast/main.ct`） | 缺口 |
| --- | --- | --- | --- |
| compile：`-o` / 默认输出名 / `#line` / `--emit-map` | ✅ | ✅ | — |
| build：多文件 / `import` / `pub` / `namespace` / `--ns-root` / `-I` | ✅ | ✅ | — |
| 身份：二进制名为 `ct` 时 `-v`/usage 打印 `ct` | ✅ | ✅（`argv[0]` basename：`ct` / `ctc` / 开发名 `ct-ast`） | — |
| `--diagnostics=text\|json`（接受、校验、切换格式） | ✅ | ✅ 接受、校验与告警输出（text / JSON） | — |
| `--std=c99\|gnu99` | ✅ | ✅（build 的建议 `cc` 命令带上目标标准） | — |
| compile 模式接受 `-I` | ✅（静默接受） | ✅ | — |
| build 打印建议 `cc` 命令 | ✅ | ✅（10.1 补齐，含 `-std`） | — |
| 语义诊断：重复 trait / struct 报错 | ✅ | ✅（`file:line:col: error:` + `ctc: N error(s) generated`，位置指向 `{`） | — |
| 语义诊断：impl 签名不一致告警（text/json） | ✅ | ✅（措辞与 JSON 与 L2 逐字节一致；发射时取 trait 的返回类型） | — |
| 多错误恢复（`MAX_ERRORS=20` + 产物清理 + `N error(s) generated`） | ✅ | ✅（逐行重同步；超上限输出 `ctc: too many errors, stopping`） | — |
| Drop trait（`use Drop` / 递归释放） | ✅ | ✅ | — |
| AutoDrop（`own`） | ✅ | ✅ | — |
| 泄漏分析（作用域 / 条件 return / `ret_owned`） | ✅ | ✅（保守规则与 L2 一致） | — |
| 增量缓存 `.ctcache/<unit>.key` | ✅ | ✅（键与 L2 逐字节一致） | — |
| 包管理 `get` / `install` | ✅ | ❌ | 10.6 |
| 语料覆盖：`test/modules` 的 autodrop / leak / line / map 用例 | ✅ | 全部覆盖（line / map 见元数据层） | — |

### 4. 切片与出口

| 切片 | 内容 | 出口 |
| --- | --- | --- |
| 10.1 | CLI 与身份对齐：`--diagnostics`、`--std`、compile `-I`、`argv[0]` 身份、usage 文本 | ✅ **已落地（2026-10-19）**：`g_prog` 按 `argv[0]` 取 `ct` / `ctc` / `ct-ast`；两模式接受并校验 `--diagnostics=text\|json`（`g_diag_json` 留给 10.3）与 `--std=c99\|gnu99`；compile 模式接受 `-I`；build 补发建议 `cc -std=… <unit>.c… -o a.out`。`check-ast.sh` 新增 8 项 CLI/身份断言（64 → **72**） |
| 10.2 | 语义诊断：重复定义报错、签名不一致告警（text/json） | ✅ **已落地（2026-10-19）**：新增 `DiagOps`（`sem_error` / `record_sig_warn` / `emit_warnings`）；重复 trait/struct 报 `file:line:col: error:` 并以 `ctc: N error(s) generated` 收尾、失败不留产物（前置声明合法）；impl 签名不一致按 L2 措辞告警（text stderr / `{"warnings":[…]} ` stdout），发射函数取 **trait 的返回类型**使产物仍可编译。`check-ast.sh` 逐字节比对 `dup_struct` / `dup_trait` / `sig_mismatch` / `sig_mismatch_json`（72 → **76**） |
| 10.3 | 内存：Drop / AutoDrop / 泄漏分析 | ✅ **已落地（2026-10-19）**：`Drop` 内置 trait（`use Drop` / `impl Drop` / 递归释放 / `delete` 调用）与 AutoDrop（`own`，作用域末逆序释放，布局/Drop/作用域三种负例按 L2 措辞报错）落地；泄漏分析按 D40 复刻 L2 的保守规则（声明即跟踪 `malloc`/`calloc`/`ret_owned` 调用、赋值逃逸、`delete` 释放、条件 return 的路径告警、作用域末确定泄漏），text / JSON 均逐字节一致。新增 trait `MemoryOps`（11 个方法，未触碰 `ParseOps`）。`check-ast.sh` 新增 10.3 段：autodrop 4 例 + leak 7 例（76 → **87**） |
| 10.4 | 多错误恢复 | ✅ **已落地（2026-10-19）**：`parse_program` 在报错后重同步（到下一条行首或 `}` 之后，同 L2 的 `recover_pos`），继续解析后续声明；`impl` 指向未定义 struct 时按 L2 在 `{` 处报 `impl for undefined struct 'X'` 并跳过整个 body；`use` 引用未定义 trait 时在 struct 的 `{` 处报错；超过 `MAX_ERRORS=20` 输出 `ctc: too many errors, stopping` 并以 1 退出。报错单元一律返回失败，产物不落盘。`check-ast.sh` 新增 `multi_err` / `multi_err_build` / `max_errors` 三项（逐字节比对 L2，87 → **90**） |
| 10.5 | 增量缓存 | ✅ **已落地（2026-10-19）**：`build` 为每个单元写 `<outdir>/.ctcache/<base>.c.key`，键覆盖编译器版本、`--line` 强制度、诊断格式、`--ns-root`、单元路径、`mtime.size`、import 摘要与依赖 digest，拼写与 L2 **逐字节一致**（D41）。依赖按后序 DFS 保证 digest 先算；依赖变脏则下游变脏；`--emit-map` 不复用；键只在成功发射后落盘，`-c/-h` 缺失或键不符时重编。`check-ast.sh` 新增 10.5 段：冷编盖章、键对 L2、暖编复用、依赖失效、产物缺失重建（90 → **95**） |
| 10.6 | 包管理迁移 | `test/pkg/run.sh` 改为驱动新入口；`get`/`install` 仍不触碰编译核 |
| 10.7 | 切主线 | 安装形态改由 ct-ast 构建；`check-all.sh` 的默认编译器切到新线，L2 降级为回归 oracle；bump v0.10.0 |

每片要求：`check-all.sh` 零回退；`check-ast.sh` 全绿；新增/修改语料必须由真实二进制输出生成期望值。

### 5. 待确认决策（建议值）

| 编号 | 议题 | 建议 |
| --- | --- | --- |
| D38 | 代码落点 | 继续单文件 `selfhost/ast/main.ct`；`ParseOps` 已 32/32，新增能力放**新 trait**（如 `DiagOps` / `MemoryOps` / `CacheOps`），不拆多单元 |
| D39 | 诊断等价口径 | 告警文本与 JSON **逐字节一致**（`test/modules/*/expected.stderr` / `expected.stdout` 是逐字节比对的），这是 10.2/10.3 的硬约束 |
| D40 | 泄漏分析范围 | 只复刻 L2 的**保守规则**（作用域结束 / 条件 return / `ret_owned`），不引入新算法 |
| D41 | 缓存键 | 与 L2 同格式同算法（FNV-1a），命中的行为也一致：**不重放 `#line` 与告警**，`--emit-map` 不命中 |
| D42 | 包管理归属 | `get`/`install` 留在**驱动层**，不进编译核；入口由新编译器提供，编译核仍零网络零子进程 |
| D43 | 切换与回退 | 双轨期 ct-ast 为主、L2 为 oracle；切换前打 tag `pre-ct-ast-switch`；`v0.9.0` 永远是回退点 |
| D44 | 身份识别 | ct-ast 也按 `argv[0]` basename 识别：`ct` → `ct`，其余 → `ctc`（与 L2 相同） |
| D45 | 版本与收口 | Phase 10 ↔ `v0.10.x`；只有 10.7 全绿后才 bump `v0.10.0` |

### 6. 风险

| 风险 | 说明 |
| --- | --- |
| 诊断文本逐字节 | 告警措辞、顺序、行列号都进入 golden；任何措辞调整都会触发语料重生成，需先对差 |
| 错误恢复与 AST | 行重写版靠「重同步到下一行 / `}`」；AST 版要在解析器里定义可恢复边界，工作量最大 |
| 泄漏分析 | ct-ast 目前没有 `owned` 概念，需先把所有权信息挂到声明节点上 |
| 容量 | `ParseOps` 已满；新 trait 与 `MAX_METHOD 32` 的预算要像 9.x 一样预先算好 |
| 包管理入口 | 切主线后 `ct get` 的 argv[0] 与 `CT_REGISTRY` 行为必须保持，否则 `test/pkg` 与用户脚本都会断 |

---

## English

### 1. Goal and exit

Phase 9 made `selfhost/ast/main.ct` (**ct-ast**) the development mainline, but the installed `ct`
still comes from the old pipeline L2 (`selfhost/src/**`). Phase 10 closes the capability gap and
switches the shipped entry to ct-ast, keeping the old line as a regression oracle.

| Item | Content |
| --- | --- |
| Goal | ct-ast offers the full `ct` CLI: `compile` / `build` / `get` / `install` and every existing option, behaving like L2 |
| Exit | a `ct` built from ct-ast passes the whole suite (`test/run.sh`, `test/modules`, `test/pkg`, `ct-tour`, `acceptance`); `check-ast.sh` covers the entire corpus |
| Version | `v0.10.0` (Phase 10 ↔ `v0.10.x`), bumped when 10.7 closes (a freeze-period exception needing user authorisation) |
| Rollback | `selfhost/src/**` stays frozen; `v0.9.0` is the rollback point, and the switch itself gets a non-version tag |

### 2. Non-goals

No new language features (`map` stays design-frozen), no change to published output naming, the
banner or the `ctc:` driver prefix (SH-3), no edits to `ctc.c` / L1, and no byte-identical output
requirement between ct-ast and L2 (D34 is behavioural equivalence).

### 3. Capability diff (measured against the code, 2026-10-19)

| Capability | L2 | ct-ast | Gap |
| --- | --- | --- | --- |
| compile: `-o`, default name, `#line`, `--emit-map` | ✅ | ✅ | — |
| build: multi-file, `import`, `pub`, `namespace`, `--ns-root`, `-I` | ✅ | ✅ | — |
| identity: a binary named `ct` prints `ct` in `-v`/usage | ✅ | ✅ (`argv[0]` basename: `ct` / `ctc` / the dev name `ct-ast`) | — |
| `--diagnostics=text\|json` (accept, validate, switch format) | ✅ | ✅ accepted, validated and emitted (text / JSON) | — |
| `--std=c99\|gnu99` | ✅ | ✅ (the suggested `cc` command carries the target standard) | — |
| compile mode accepts `-I` | ✅ (ignored) | ✅ | — |
| build prints the suggested `cc` command | ✅ | ✅ (added in 10.1, `-std` included) | — |
| semantic check: duplicate trait / struct is an error | ✅ | ✅ (`file:line:col: error:` + `ctc: N error(s) generated`, positioned at the `{`) | — |
| semantic check: impl signature mismatch warning (text/json) | ✅ | ✅ (wording and JSON byte-identical to L2; the emitted function takes the trait's return type) | — |
| multi-error recovery (`MAX_ERRORS=20`, artifact cleanup, `N error(s) generated`) | ✅ | ✅ (line-start resynchronisation; past the cap `ctc: too many errors, stopping`) | — |
| Drop trait (`use Drop`, recursive release) | ✅ | ✅ | — |
| AutoDrop (`own`) | ✅ | ✅ | — |
| leak analysis (scope / conditional return / `ret_owned`) | ✅ | ✅ (the same conservative rules as L2) | — |
| incremental cache `.ctcache/<unit>.key` | ✅ | ✅ (keys byte-identical to L2) | — |
| package manager `get` / `install` | ✅ | ❌ | 10.6 |
| corpus coverage of `test/modules` autodrop / leak / line / map cases | ✅ | all covered (line / map live in the metadata layer) | — |

### 4. Slices and exit criteria

| Slice | Content | Exit |
| --- | --- | --- |
| 10.1 | CLI and identity: `--diagnostics`, `--std`, compile `-I`, `argv[0]` identity, usage text | ✅ **landed (2026-10-19)**: `g_prog` comes from `argv[0]` (`ct` / `ctc` / `ct-ast`); both modes accept and validate `--diagnostics=text\|json` (`g_diag_json` is reserved for 10.3) and `--std=c99\|gnu99`; compile mode accepts `-I`; build prints `cc -std=… <unit>.c… -o a.out`. `check-ast.sh` gained 8 CLI/identity assertions (64 → **72**) |
| 10.2 | semantic diagnostics: duplicate definitions error, signature-mismatch warning (text/json) | ✅ **landed (2026-10-19)**: new `DiagOps` (`sem_error` / `record_sig_warn` / `emit_warnings`); a duplicate trait/struct reports `file:line:col: error:` and closes with `ctc: N error(s) generated`, leaving no artifacts (forward declarations stay legal); a signature mismatch warns in L2's wording (text stderr / `{"warnings":[…]}` stdout) and the emitted function takes the **trait's** return type so the output still compiles. `check-ast.sh` compares `dup_struct` / `dup_trait` / `sig_mismatch` / `sig_mismatch_json` byte for byte (72 → **76**) |
| 10.3 | memory: Drop / AutoDrop / leak analysis | ✅ **landed (2026-10-19)**: the built-in `Drop` trait (`use Drop`, `impl Drop`, recursive release, `delete` calling it) and AutoDrop (`own` — reverse-order release at scope exit, with the layout / Drop / scope negatives reporting L2's wording); the leak analysis replicates L2's conservative rules per D40 (tracking `malloc` / `calloc` / `ret_owned` calls at the declaration, escape on assignment, release on `delete`, one path warning per conditional return, definite leak at scope exit) with text and JSON byte-identical. The new `MemoryOps` trait (11 methods) leaves `ParseOps` untouched. `check-ast.sh` gained the 10.3 section: 4 autodrop + 7 leak assertions (76 → **87**) |
| 10.4 | multi-error recovery | ✅ **landed (2026-10-19)**: `parse_program` resynchronises after a reported error (past the next `}` or to the start of the next line, L2's `recover_pos`) and keeps parsing; an `impl` of an undefined struct reports `impl for undefined struct 'X'` at its `{` and skips the body; a `use` of an undefined trait reports at the struct's `{`; past `MAX_ERRORS=20` both print `ctc: too many errors, stopping` and exit 1. A unit with errors always fails, so no artifacts are written. `check-ast.sh` gained `multi_err` / `multi_err_build` / `max_errors` (byte-diffed against L2, 87 → **90**) |
| 10.5 | incremental cache | ✅ **landed (2026-10-19)**: `build` stamps `<outdir>/.ctcache/<base>.c.key` per unit; the key covers the compiler version, the `--line` force, the diagnostics format, `--ns-root`, the unit path, its `mtime.size`, an import digest and the folded dependency digests, spelled exactly as L2 writes them (D41). A postorder DFS computes digests before they are folded; a dirty dependency makes its importers dirty; `--emit-map` never reuses; the key is stored only after a successful emit, and a missing `.c`/`.h` or a stale key rebuilds. `check-ast.sh` gained the 10.5 section: cold stamps, key parity with L2, warm reuse, dependency invalidation and a missing artefact (90 → **95**) |
| 10.6 | package manager migration | `test/pkg/run.sh` drives the new entry; `get`/`install` still stay out of the compile core |
| 10.7 | mainline switch | the install shape builds from ct-ast; `check-all.sh` defaults to the new line with L2 as the regression oracle; bump v0.10.0 |

Every slice keeps `check-all.sh` regression-free and `check-ast.sh` green; any new or changed
fixture expectation must be produced by the real binary, never hand-written.

### 5. Decisions to confirm (proposed)

| Id | Topic | Proposal |
| --- | --- | --- |
| D38 | Code location | keep the single file `selfhost/ast/main.ct`; `ParseOps` is full (32/32), so new capabilities go into **new traits** (`DiagOps` / `MemoryOps` / `CacheOps`) rather than splitting the tree |
| D39 | Diagnostic equivalence | warning text and JSON must match **byte for byte** (`test/modules/*/expected.stderr` / `expected.stdout` are compared literally) — the hard constraint on 10.2/10.3 |
| D40 | Leak-analysis scope | reproduce only L2's **conservative rules**; no new algorithm |
| D41 | Cache key | identical format and algorithm (FNV-1a) and identical hit behaviour: **no `#line` or warning replay**, `--emit-map` never hits |
| D42 | Package-manager ownership | `get`/`install` stay in the driver layer, never in the compile core; the new compiler provides the entry, and the core stays network- and process-free |
| D43 | Switch and rollback | dual-track with ct-ast primary and L2 as the oracle; tag `pre-ct-ast-switch` before switching; `v0.9.0` is always the rollback point |
| D44 | Identity | ct-ast also derives identity from `argv[0]`: `ct` → `ct`, otherwise `ctc` (same as L2) |
| D45 | Version and close | Phase 10 ↔ `v0.10.x`; bump `v0.10.0` only after 10.7 is green |

### 6. Risks

Byte-exact diagnostics (wording, order and line/column all enter goldens); error recovery inside an
AST parser (the line-based version resynchronises at the next line or `}`); ownership tracking must
land on declaration nodes before leak analysis can exist; `ParseOps` has no method budget left;
and the `ct get` entry must keep `argv[0]` / `CT_REGISTRY` behaviour or `test/pkg` and user scripts
break.
