# v0.77.0 全面评审报告

| 项 | 值 |
| --- | --- |
| 基线 | `5b13fef4`（v0.77.0 + PH-77 收口复核，2026-11-19） |
| 范围 | 编译器（L0 / L1 / L2 / ct-ast）、`test/**`、`docs/**`、`examples/**`、`issues/**`、`tools/**` |
| 方法 | 读码 + 全量门禁 + 文档/台账脚本核对 + 抽样探针；不修改源码、测试与既有文档 |
| 结论 | **产品门禁 11/11 绿；未发现产品级 P0。主要风险集中在治理门禁、问题台账、phase-ID 迁移与文档漂移，尚不到 v1.0 发布门槛。** |
| 证据 | 本报告 §10；离线日志 `/tmp/ct-full-review-check-all-offline.log`（11/11） |

---

## 0. 结论摘要

**做得好的部分**

- **正确性防线强**：L0 / L1 / L2 / ct-ast 四代编译器 + 逐字节 golden + 不动点 + 归档棘轮 + 全量语料等价；
  `check-all` 离线 11/11 绿，`check-ast` **1517 passed / 0 failed / 5 skipped**。
- **测试面广**：`test/ast` 299 个目录、`test/ast/errors` 295 个负例、`test/modules` 102、`test/cases`
  25 个 L0 golden、`test/pkg` 147、VS Code 语法 169 项断言；另有 sanitizer 与确定性 fuzz 的 nightly。
- **代码卫生好**：ct-ast 无 `TODO/FIXME/XXX`；固定容量越界走硬错；分配有 null 检查；
  生成 C 在 `-Wall -Wextra` 下零告警；PH-64/65/66 的裸机、C 边界、libc I/O 契约都有门禁。
- **文档链接健康**：`check-docs` 1938 条相对链接、323 个文件全绿（含本报告）。

**不能直接发布 1.0 的原因**

1. **治理门禁只实现了一部分**：`tools/check.sh` 只有 `g0`、`g8`、`battle-selftest`；
   G1/G2/G4/G5/G6/G7/G9 没有同名子命令，也没有 `deviation:` 登记。G6 缺位直接导致问题台账不闭合。
2. **台账没有闭合**：221 个 issue 文件中 31 个仍是 open/受理/保持类状态，其中至少 13 个已被后续 phase
   实际修复（LANG-3/4/9/11/16/17、SH-65/67、PKG-9/10/11、TEST-21 等），phase 卡的“✅”与 issue 的
   `open` 并存；状态词有 168 个不符合 AGENTS §5.4 的闭集。
3. **phase-ID 迁移未执行**：主规范已到 1.17.0，PN-1…PN-17 要求 `v<M>-PH-<n>` 与迁移账本；
   仓库仍用裸 `PH-*`，`docs/planning/phase-id-ledger.md` 不存在，迁移被 A/B/C 三个 blocker 明确挂起。
   这不阻塞 v0.77，但阻塞 `v1-PH-0` 的干净开卡。
4. **文档漂移成簇**：类型检查规划仍写“未开卡”（PH-68–71 已收口）；`test/README` 写 119 个目录 /
   141 个负例（实际 299 / 295）；教程写 16 个示例（实际 52）；AGENTS 实例化节仍写 `phase=PH-66`。
5. **硬门禁依赖网络且可无限挂起**：首次 `check-all` 卡在 `p77_external`（`ct get` → `system("git clone")`
   无超时），>15 分钟未返回，人工 kill 后 gate 8 报 exit 143；离线重跑才 11/11 绿。

---

## 1. 评审方法

- 全量门禁：`bash selfhost/check-all.sh`（首次联网、第二次用不可达代理模拟离线）。
- 治理门禁：`bash tools/check.sh g0`、`bash tools/check.sh g8`。
- 文档门禁：`python3 test/docs/check-docs.py`。
- 结构统计：按目录/文件/状态词脚本汇总（`issues/**`、`test/**`、`docs/**`、`examples/**`）。
- 代码抽样：`selfhost/ct-ast/**` 的模块大小、容量上限、分配检查、错误路径、网络/子进程边界。
- 行为抽样：`--show-c-boundary` 的仓内/仓外差异、`ct get` 的网络路径、近相 phase 探针。

**不覆盖**：真机/电气验证（HW-1/HW-2）、IAR/Keil 非 GCC 工具链、Windows、长期运行/性能基准。
---

## 2. 门禁结果

| # | 门禁 | 结果 | 备注 |
| --- | --- | --- | --- |
| 1 | `test/run.sh`（L0 八层） | **156 passed / 0 failed** | 含 examples / dialect / errors / cli |
| 2 | `check-goldens.sh` | **25 / 25**（L1、L1′、L2） | 不动点成立 |
| 3 | `check-archive.sh` | **OK** | 归档棘轮无回归 |
| 4 | `check-m2a.sh` | **OK** | L0→L1 字节一致 |
| 5 | `ct-tour.sh` | **OK** | 四代编译器一条龙 |
| 6 | `check-grammar.py` | **169 checks / 0 failed** | node 缺失时 index 检查 skip |
| 7 | `test/pkg/run.sh` | **147 passed / 0 failed** | 包管理 |
| 8 | `check-ast.sh` | **1517 passed / 0 failed / 5 skipped** | 5 skip：Renode / nRF52 / FreeRTOS / GDB / 外部 pin（离线） |
| 9 | `check-warnings.sh` | **绿** | 全量生成 C `-Wall -Wextra` |
| 10 | `check-semantics.sh` | **绿** | `ct check` 语义入口 |
| 11 | `check-docs.py` | **OK** | 1918 links / 322 files / 12 phase status |

治理门禁：`g0` OK（1.17.0）；`g8` OK（9 条 legacy offset warning，全部在账本内）。

**关键异常（P1）**：首次 `check-all` 在 `PH-77-S4 install` 之后的下一个探针 `p77_external` 卡死。
该探针的 `curl` 有 `--max-time 10`，但随后的 `ct get` 走 `Pkg.h.ct` 的
`system("git clone --quiet …")`（[Pkg.h.ct:944](../../selfhost/ct-ast/tool/pkg/Pkg.h.ct#L944)），没有超时；
网络黑洞/凭据提示都会让硬门禁无限等待。离线重跑时 `p77_external` 以 77 skip，11/11 才绿。
建议：给 `ct get` 的子进程加超时/`GIT_TERMINAL_PROMPT=0`，或在探针外层加 `timeout`，并补一条
“网络挂起 N 秒内返回 77”的负例。

---

## 3. 测试覆盖度

| 层 | 规模 | 评价 |
| --- | --- | --- |
| L0 `test/run.sh` | 156 项、8 层 | 强；含 CLI / limits / dialect |
| L0 unit | 1 个 `test_helpers.c` | 白盒仅覆盖 `ctc.c` static 函数；够 L0，不覆盖 ct-ast |
| L0 golden | 25 个 `.ct`（`test/cases`） | 与 L1/L2 逐字节对差 |
| L0 negative | 61（`test/errors`） | 逐字节 expected-err |
| ct-ast 行为 | 299 个目录 | 编译→零告警构建→运行→输出比对 |
| ct-ast 负例 | 295（`test/ast/errors`） | 非零退出 + 位置 + 文案 |
| 多单元 | 102（`test/modules`） | import / pub / map / 缓存 |
| 模式 | 6（`test/patterns`） | OO 组合 |
| 探针 | 49（`test/probes`） | 专项 |
| 模型 | 5（`test/model`） | `--emit-model` |
| 裸机 | 40（qemu 7 + renode 33） | 模拟器；真机硬件外部依赖 |
| 包 | 147（`test/pkg`） | store / lock / v1 迁移 |
| 文档 | 1938 links | 链接与版本 |

**覆盖缺口**

1. **没有行/分支覆盖率数据**。全部是行为/golden 覆盖，无法回答“ct-ast 的 37k 行里哪些没跑到”。
   建议加一个 nightly `llvm-cov`/`gcov` 任务（只报告，不设阈值），至少给出热点与盲区。
2. **ct-ast 没有单元测试**。Lexer / Parser / TypeCheck / Emitter 只经端到端夹具；回归定位依赖
   golden diff。建议为纯函数层（编码、转义、类型名、map 记录）补少量白盒单测。
3. **容量上限只测了 `MAX_CALLS`**。`MAX_GENERIC_INSTS=64`、`MAX_CLOSURES=64`、`MAX_PARAMS=16`、
   `MAX_STRUCT_TPARAMS=2` 等只靠代码硬错，没有边界夹具；大项目可能先撞上限。
4. **sanitizer / fuzz 只在 nightly**。本地 `check-all` 不含 ASAN/UBSAN 与 fuzz；这是合理的速度取舍，
   但意味着“本地全绿”不等于“无 UB”。
5. **跨平台只到 Linux GCC / macOS clang**。无 Windows；IAR/Keil 未验证（生成 C 依赖
   `__attribute__`，armclang/arm-none-eabi-gcc 可用，ICCARM 另说）。

---

## 4. 文档漂移

| # | 位置 | 现状 | 实际 | 级别 |
| --- | --- | --- | --- | --- |
| D-1 | [docs/planning/typecheck-semantic-plan.md:1](../planning/typecheck-semantic-plan.md#L1) | “规划中 / 未开卡”，基线 v0.65.1，版本位 v0-PH-68…71 | PH-68–71 均已收口（v0.67.0–v0.70.0） | **P1** |
| D-2 | [docs/README.md:41](../README.md#L41) | 类型检查规划（**未开卡**） | 同上 | **P1** |
| D-3 | [test/README.md:6](../../test/README.md#L6)、[:18](../../test/README.md#L18) | `ast/errors` 141 个；`ast/` 119 个目录 | 295 个负例；299 个目录 | **P1** |
| D-4 | [docs/tutorial.md:1903](../tutorial.md#L1903) | “16 个可运行示例” | 52 个示例目录 | **P2** |
| D-5 | [AGENTS.md:452](../../AGENTS.md#L452) | `phase=PH-66` | 当前 PH-77 | **P1** |
| D-6 | [docs/session-map.md:21](../session-map.md#L21) | 表格中间插入 blockquote，后续 PH-66…77 行被截断 | 表格渲染断裂；且首行 phase 仍是旧值 | **P2** |
| D-7 | [docs/roadmap.md:89](../roadmap.md#L89) | Phase 76 收口 v0.76.1 | PH-76 收口 v0.76.0；v0.76.1 是 SH-92 fix | **P3** |
| D-8 | [README.md:25](../../README.md#L25)、[:32](../../README.md#L32)、[:55](../../README.md#L55) | 以 0.44.1 为完整路径的阻塞基线 | 当前 v0.77.0；结论可能仍成立，但应写“最近实测”并注明历史 | **P2** |
| D-9 | `README.md` 常用命令表 | 缺 `--emit-model`（PH-74）与 `ct check --types`（PH-68–71） | 已发布能力未进用户入口 | **P2** |
| D-10 | [docs/architecture.md:5](../architecture.md#L5) | “面向要修改 ctc.c 的人”；全篇 L0 | 主线是 ct-ast；ct-ast 无对应架构文档 | **P2** |
| D-11 | [selfhost/README.md:33](../../selfhost/README.md#L33) | grammar “40 项断言” | 实际 169 项 | **P3** |
| D-12 | [docs/proposals/ct-bare-metal-proposal.md:6](../proposals/ct-bare-metal-proposal.md#L6) | “草案；未立项” | PH-64 已按该提案收口（v0.63.0）；docs/README 仍写“待评估” | **P2** |
| D-13 | [docs/language-spec.md:2423](../language-spec.md#L2423) | 自定义 `[]` 的 `v[0]` 参数类型匹配“尚未实现” | `test/ast/p72_subscript.sh` 已钉住该错误；至少一处需更新 | **P2**（待复核） |

**共性原因**：文档里的计数、phase 状态、提案状态是手工维护的；没有脚本从
`test/**`、`issues/**`、`roadmap` 回填。建议把可计数项（示例数、ast 目录数、负例数、断言数）
改成生成或至少在 `check-docs` 里做“数字 ↔ 实际”断言。

---

## 5. 台账与治理

### 5.1 问题台账未闭合

- 221 个 issue 文件；`open` 24、`受理` 5、`保持` 1、`blocked` 1、`?` 1，其余为
  `已修` / `已修复` / `✅ 已修复` / `verified` / `fixed` 等 20 余种写法。
- 至少 **13 个已被 phase 修复但 issue 仍 open**：
  - LANG-3 / LANG-4 / LANG-11 / LANG-16 / LANG-17 / SH-76（PH-72，v0.71.0）
  - LANG-9（PH-73，v0.72.0）
  - SH-65 / SH-67（PH-75，v0.74.0）
  - PKG-9 / PKG-10 / PKG-11（v0.58.2 / v0.63.3 / v0.63.4）
  - TEST-21（PH-67 已在 CI 绿，issue 仍是 `open`）
- 反例：`issues/lang/lang-4…md:8` 写 `open`，而 `docs/design/phase72.md:61` 写 `✅`；
  `issues/lang/lang-9…md:8` 写 `open`，`docs/design/phase73.md:57-59` 写 `✅`；
  `docs/design/phase75.md:56` 写 SH-65“⬜ 未做”，同文件 `:66` 又写“✅”。
- 按 AGENTS §5.4，状态词只允许 8 个；当前至少 **168 条**不在闭集内。G6 若实现，这一片会红。

### 5.2 治理门禁缺位

`tools/check.sh` 只有 `g0`、`g8`、`battle-selftest`；AGENTS §6.4 列出的 G1/G2/G4/G5/G6/G7/G9
没有同名子命令。项目用 `selfhost/check-all.sh`（11 道产品硬门禁）+ `check-docs.py` 替代，
但这不等于 G1/G2/G5/G6/G7 的判据：

- **G1**（phase 卡完整性 / 草案 / 编号）：没有机械校验；PH-75 卡自相矛盾就是漏网。
- **G2**（ACC 映射）：没有。
- **G4**（snippet / 300 行 / `applies-to`）：`docs/snippets/` 不存在；`language-spec` 2824 行、
  `tutorial` 1931 行，按 300 行规则本应失败或分拆；`check-docs` 只做了链接/版本部分。
- **G5**（每条判据有测试、每个门禁断言有负例）：靠人工；部分 phase 卡的 T-7 证据不完整。
- **G6**（台账闭合）：没有，直接导致 §5.1。
- **G7**（密钥/依赖/sanitizer）：sanitizer 只在 nightly，密钥扫描没有。
- **G9**：`check-docs` 覆盖了 pin/版本部分，但没有独立 `g9` 入口。

这属于“规范要求 vs 项目实现”的放宽，按 AGENTS 应登记 `deviation:`；目前没有。

### 5.3 phase-ID 迁移被 blocker 挂起

- 主规范 1.17.0 已生效（PN-1…PN-17）；仓库仍用裸 `PH-*`，`docs/planning/phase-id-ledger.md`
  不存在；[phase-migration-blockers.md](../planning/phase-migration-blockers.md#L5) 明确写
  “**迁移未开始**；先解决 blocker”。
- Blocker A（旧 major 的 `version-minor` 偏移）、B（卡路径 `docs/design/` vs `docs/phases/`）、
  C（旧卡缺 `phase-id`/`version-minor`）都需要主规范或用户裁定。
- 影响：`v1-PH-0` 不能在旧命名/无账本状态下干净开卡；迁移面约 66 个 roadmap 行、142 个文件引用、
  51 个 ID。**这是 v1.0 的硬前置，不是普通文档债。**

### 5.4 设计窗口已满

`docs/design/` 有 12 个已完成 phase 卡（phase66–77），`check-docs` 报 `design window: 12/12`。
下一次开 phase 前必须把 phase66 退役到 `docs/history/design/`；否则新卡会触发窗口门禁。

---

## 6. 代码与架构

**规模**

| 层 | 行数 | 备注 |
| --- | --- | --- |
| L0 `ctc.c` | 2966 | 单文件、冻结种子；只修 bug |
| L1 `ctc.ct` | 3685 | 冻结种子 |
| L2 `core+driver.ct` | 7179 | 回归 oracle |
| ct-ast | 37163（21 个 `.ct`） | 最大 `Expr.h.ct` 7575、`Emitter.h.ct` 6694、`Stmt.h.ct` 4458 |

**优点**

- 0 个 `TODO/FIXME/XXX`；固定容量越界走 `fail`/`die`；`calloc` 有 null 检查；
  `-Wall -Wextra` 零告警；ASAN/UBSAN 与 fuzz 能覆盖 ct-ast。
- 四代编译器互为差分 oracle，是比单一 golden 更强的正确性防线。

**风险**

1. **巨型单元**：`Expr.h.ct` 与 `Emitter.h.ct` 都在 6–7k 行；改一处要跨多个子对象。当前有
   unit-name lint 和分派层，短期可维护，但已接近单文件可读性的上限。建议在 1.0 冻结后按
   “纯函数/子对象”做行为保持拆分，不改变生成物。
2. **重复常量**：`MAX_GENERIC_INSTS=64` 同时在 `Symbols.h.ct` 与 `Expr.h.ct`；`MAX_TEXT=160`
   在多个单元重复。改上限时容易漂移。建议集中到单一头。
3. **默认编译路径不做类型检查**：`ct check --types` 是 opt-in；这是已定设计（v1.1 A），但意味着
   “ct build 绿”不等于“类型正确”。用户入口需要更醒目的说明（README 目前只写“受限语义检查”）。
4. **C 边界有 cwd 后门**：`c_boundary_for` 在 `c_cwd_in_tree()` 为真时对所有输入返回 allow
   （[Module.h.ct:392](../../selfhost/ct-ast/frontend/module/Module.h.ct#L392)、[:2427](../../selfhost/ct-ast/frontend/module/Module.h.ct#L2427)）。
   实测同一 `/tmp/p65x.ct`：从 `/tmp` 看是 `strict`，从 CT 仓根看是 `allow`。spec §4.66 只说四个
   仓内路径豁免；这是未文档化的放宽。建议收紧到 `c_path_is_core` 或写明 cwd 规则并补负例。
5. **包链信任**：官方 `ct/std` 有内置 pin + sha256（好）；第三方索引仍无签名，`ct get` 走系统
   `git`，网络挂起无超时（§2）。建议把“官方 pin 强校验、第三方索引仅便利”的信任模型写进
   package-guide，并给 git 子进程加超时/禁交互。
6. **可移植性**：生成 C 依赖 `__attribute__`（`unused`/`constructor` 已收敛，但仍有 `attribute` 直通）；
   GCC/clang 之外（ICCARM 等）未验证。嵌入式采用前需要一张“工具链 × 特性”矩阵。

---

## 7. 样例覆盖

- 52 个示例目录，编号到 `49_socket`；`examples/README.md` 是完整索引。
- **没有 PH-64 之后的示例**：`--freestanding` / `--alloc`、`--c-boundary` / shim、`--emit-model`、
  `ct check --types`、`ct get ct/std` 都只有测试/文档，没有可运行 example。
- `49_socket` 是**文档型样例**（只有 README，不进门禁），其依赖的 `FileDesc`/`Socket` 在仓内不存在；
  这是有说明的缺口，但用户点进去会发现不能跑。
- `examples/tour/` 与 `examples/c-superset/` 是特殊子套件，前者有 nested expected，后者用
  `run.sh`/`cases.tsv`；不属于“缺 expected”。
- 教程仍写“16 个可运行示例”（D-4），与 52 个目录不符。

建议补 4 个最小 example（每个 20–40 行）：`freestanding_blink`（`--freestanding` + `--alloc`）、
`c_boundary_shim`（`.ct` + `.shim.h`）、`typecheck_bad`（`ct check --types` 负例）、
`emit_model`（`--emit-model` JSON）。

---

## 8. 发布就绪判断

| 维度 | 评分 | 说明 |
| --- | --- | --- |
| 产品正确性 / 测试 | **9/10** | 11 门禁离线绿；四代差分；负例 356；sanitizer/fuzz |
| 代码质量 | **8/10** | 无 TODO、分配检查、硬错；巨型单元与重复常量扣分 |
| 文档准确性 | **5/10** | 链接健康，但计数/phase/提案状态成簇漂移 |
| 治理 / 台账 | **4/10** | G1/G2/G4/G5/G6/G7 缺位；台账 13+ 条不闭合；phase-ID 迁移挂起 |
| 样例覆盖 | **7/10** | 52 个 + tour + c-superset；近相能力无 example |
| **v1.0 就绪** | **5/10** | 产品可用，治理/迁移/台账未达标 |

**判断**：v0.77.0 是一个**可信的开发里程碑**，可以继续做 v1.0 规划，但**不建议直接宣布 1.0 发布**。 1.0 的阻塞不在编译器正确性，而在“发布契约”：phase-ID / 台账 / 文档 / 门禁。

---

## 9. 建议行动（按优先级）

### P1（发布前必须）

1. **修 `check-all` 网络挂起**：给 `ct get` 的 `git` 子进程加超时与 `GIT_TERMINAL_PROMPT=0`；
   `p77_external` 外层加 `timeout`；补“网络黑洞 N 秒返回 skip”的负例。
2. **补治理门禁或登记 deviation**：至少实现 `g6`（台账闭合）与 `g5`（判据↔用例）的最小子集；
   `g4` 要么补 `docs/snippets/` + 300 行门禁，要么在 AGENTS 登记明确放宽。
3. **做一次台账闭合批**：把 LANG-3/4/9/11/16/17、SH-65/67/76、PKG-9/10/11、TEST-21 等
   已修条目改成 `fixed`/`verified`，统一状态词；修 PH-75 卡的“未做 vs ✅”矛盾。
4. **解决 phase-ID blocker A/B/C**，在开 `v1-PH-0` 前建立账本与迁移脚本；迁移前不要再新增裸 `PH-*` 引用。
5. **文档刷新批**：D-1…D-6（类型检查计划、test/README、tutorial、AGENTS 0.1、session-map、
   docs/README 索引）；把可计数项改为脚本断言。

### P2（1.0 前建议）

6. **退役 phase66**，给 `v1-PH-0` 留出设计窗口。
7. **补 README 的 `--emit-model` / `ct check --types`**；给 ct-ast 补一份架构概览（或明确
   `docs/architecture.md` 只讲 L0）。
8. **补 4 个 near-phase example**（freestanding / c-boundary / type-check / emit-model）。
9. **补覆盖率报告**（nightly，仅报告）与 3–5 个容量上限夹具；评估 ct-ast 纯函数层单测。
10. **收紧 C 边界 cwd 后门**或写清规则；补一条 `--show-c-boundary` 的“仓根 + 外部路径”负例。
11. **文档/提案生命周期**：把 `ct-bare-metal-proposal` 标为已采纳（PH-64）；`docs/README`
    的提案索引与 `roadmap` 的 Phase 76 版本位一起修正。

---


## 10. 复现与证据

```console
$ git rev-parse --short HEAD      # 5b13fef4
$ bash tools/check.sh g0          # OK (block 1.17.0)
$ bash tools/check.sh g8          # OK (9 legacy offsets)
$ python3 test/docs/check-docs.py # OK (1938 links / 323 files / 12 phase status)
$ bash selfhost/check-all.sh      # 首次卡 p77_external；离线 11/11 green
```

- 全量离线日志：`/tmp/ct-full-review-check-all-offline.log`（本机；不随仓库提交）。
- `check-ast` 终局：`1517 passed, 0 failed, 5 skipped`；5 skip 为 Renode / nRF52 / FreeRTOS / GDB /
  外部 pin（离线）。
- 工作树新增本报告与 `docs/README` 的索引行；未修改 `selfhost/**`、`test/**`、`examples/**`、`docs/language-spec.md`。
