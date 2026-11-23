# v0.58.0 之后的重排评估（2026-11-15）

| 项 | 值 |
| --- | --- |
| 状态 | **评估完成，按本文件执行；不改实现代码** |
| 基线 | `aa7aece3`（v0.58.0 + 文档分离 6 笔），与 `origin/main` 一致 |
| 核对面 | `docs/roadmap.md`、`docs/phases/v0-PH-54/card.md`、`docs/phases/v0-PH-59/card.md`、`docs/planning/open-items-routing.md`、`docs/planning/requirements-pool.md`、`issues/**`、`docs/proposals/**` |
| 方法 | 逐份读仓库实际内容；条目状态以 issue 文件 + 代码现状交叉核对。**本轮未运行任何夹具或门禁**，凡标「读码」的结论只表示代码路径成立，不表示已复现 |
| 说明 | 本仓没有 `docs/phases/` 目录；phase 卡在 `docs/design/`，归档在 `docs/history/design/` |

## 1. 结论

1. **58 之后真正待做的只有两类**：静默错误（包缓存串用、字段可见性、下标类型错配、预处理器行截断）与包机制收尾（S6 历史 errata、S7 删 vendor）。
2. **v0-PH-59 模型导出可以开工，但不是「等 v0-PH-58」**：`v0-PH-58` 在 roadmap 里不存在，是 `open-items-routing.md` 的草案号；它的实际前置是「`Field` 补行列」与（可选的）LANG-9 可见性。
3. **v0-PH-62 可写下标方向已通过研判，但没有卡**；它比模型导出更贴下游（JSON 写回），却还差一张卡才能施工。
4. **v0-PH-55 / v0-PH-56 / v0-PH-58 不建议作为 phase 存在**：一个已被 v0-PH-62 吸收，一个是冗余语法糖，一个应拆成 patch + 一条前置任务。v0-PH-60 保留但排在模型导出之后。
5. **v0-PH-54 的 S7 判据已定（2026-11-15）：本仓自证**。包仓迁移状态降级为外部登记项，由各包仓自行维护，Ct 不追踪、不判定。

## 2. 编号与断裂（只记录，不重排）

| # | 现象 | 证据 | 处理建议 |
| --- | --- | --- | --- |
| N-1 | Phase 55–58 在 roadmap 中**没有卡**，却被 `open-items-routing.md` 当作已分配编号使用 | roadmap 原只有 Phase 54、59 两行；routing `:105-142` | 55/56/58 按 §6 放弃或拆解；57 保留为「未开工、无卡」的候选，本轮已补其版本位行 |
| N-2 | `v0-PH-58` 被 phase59 卡与两份提案当作**硬前置**引用，但仓库里没有这张卡 | `docs/phases/v0-PH-59/card.md:9`、`:115`；`docs/proposals/ct-model-export-proposal.md:8`；`docs/proposals/ct-view-annotation-proposal.md:8` | 把引用改成真实缺陷号（LANG-10 7c），见 §7 |
| N-3 | v0-PH-54 的切片序列缺 S4 | `phase54.md:3`、`:129`；S4 已移出本相 | 这是**定义性删除**，不是漏项；不得当作待办补回 |
| N-4 | v0-PH-61 已被 v0-PH-62 吸收 | `docs/proposals/ct-append-subscript-proposal.md:5` | 61 成为永久空号；不重排、不回收 |
| N-5 | 版本位与 phase 号已脱钩：v0-PH-54 吃掉 v0.54.0–v0.58.0 五个 MINOR，而 AGENTS `deviation: version-minor-offset` 只登记到 v0-PH-44 | `AGENTS.md:320-341`；roadmap Phase 54 行 | **已裁定（2026-11-15）**：认偏移、不重打 tag，后续按相位表连续分配；见 AGENTS §0.3 |
| N-6 | Phase 59 的版本位原写「不提前钉号」，与 V-1「MINOR == n」名义冲突 | `phase59.md:113` | **已裁定**：钉 v0.60.0，随 N-5 的相位表 |

> 历史空号（Phase 13–16 未使用、27–30 与 31–33 合并发布）见 roadmap 备注，不在本轮处理范围。

## 3. 在册项矩阵

判定列说明：**需要** = 仍应做；**覆盖** = 已被既有工作覆盖；**待裁** = 需要用户决定；**放弃** = 建议关闭。

### 3.1 Phase 卡

| 项 | 证据 | 现状 | 是否仍需要 | 依赖 | 可独立开工 | 需等待 |
| --- | --- | --- | --- | --- | --- | --- |
| v0-PH-54 · S6 历史 errata | roadmap `:99`「历史 errata 待办」；提案 `:175` 要求历史 phase 文档加「已被共享库取代」；全仓 grep 该短语 **0 命中** | 半完成 | **需要**（纯文档） | 无 | **可** | 无 |
| v0-PH-54 · S7 删除 vendor | `phase54.md:139`；代码仍有完整 vendor 读写（`Pkg.h.ct:2794`、`:2884`） | 未开工 | **需要**，但判据先改 | 兼容期 + 前置口径裁定 | 否 | 判据统一（§8） |
| v0-PH-59 · 模型导出 M1 | `phase59.md` 全文；代码无 `--emit-model`（grep 0）；`test/model/` 不存在 | 规划中 | **需要** | `Field` 行列（J11）、LANG-9（可见性，可降级为 `unknown`） | 卡面已就绪，可先落夹具/CLI | `Field` 行列 |
| v0-PH-60 · 视图注记 | 提案 `:5`「待研判、不排卡」 | 仅提案 | **跳过**（D-006：无消费者） | — | — | — |
| v0-PH-62 · 可写下标 | 提案 `:5`；研判 `ct-writable-subscript-proposal-review.md:7` 已通过方向；代码仍拒绝写（`Expr.h.ct:4056`、`:4065`） | 仅提案 | **需要** | 无语言依赖；与 Expr/TypeCheck 族串行 | 否（缺卡） | 先开卡 |

### 3.2 包机制（`Pkg.h.ct` 单车道）

| 项 | 证据 | 现状 | 是否仍需要 | 依赖 | 可独立开工 | 需等待 |
| --- | --- | --- | --- | --- | --- | --- |
| PKG-5 缓存键裸名 | 状态 fixed（v0.58.1）；缓存键 `<publisher>/<name>`，origin 不一致硬错 | **已交付** | 已完成 | 无 | — | — |
| PKG-6 `ct install` 不校验 import | 状态 fixed（v0.58.2）；install 按 lock 的 `-I` 试解析项目 import | **已交付** | 已完成 | 无 | — | — |
| PKG-3 未知键静默 | 状态 fixed（v0.58.3）；`read_manifest` 对未知键发 warning | **已交付** | 已完成 | 无 | — | — |
| PKG-4 同名包静默 | 状态仍写 open，但代码已硬错（`Pkg.h.ct:2284-2291`、`:2872-2877`） | **覆盖**（SP-006/013） | 不需实现，只需回填状态 | 无 | 可（文档） | 无 |
| PKG-7 build 不读 lock | 状态仍写 open，但 S2 已落地（`Pkg.h.ct:2872+` 自动 `-I`） | **覆盖**（SP-008） | 不需实现，只需回填 | 无 | 可（文档） | 无 |
| PKG-8 dev override 无痕 | 状态仍写 open，但 `Pkg.h.ct:2896` 已发 `note:` | **覆盖**（SP-015） | 不需实现，只需回填 | 无 | 可（文档） | 无 |

### 3.3 语言与编译器

| 项 | 证据 | 现状 | 是否仍需要 | 依赖 | 可独立开工 | 需等待 |
| --- | --- | --- | --- | --- | --- | --- |
| LANG-9 字段可见性 / ABI | 状态 open（`lang-9…md:8`）；头文件发射不看 `pub`（`Emitter.h.ct:1574-1585`） | open（High，ABI 锁死） | **需要** | 无 | **可**（单独发，冻结其它 header 改动） | 无 |
| LANG-4 下标类型错配静默空值 | 状态 open（`lang-4…md:8`）；匹配只看方法名 + 参数个数 | open（High 静默） | **需要** | 无 | 可 | 无 |
| LANG-5 结果作接收者（字段形态） | 状态：方法形态已修，字段形态 open（`lang-5…md:8`） | 半完成（High） | 需要 | 与 LANG-13 同族 | 可 | 无 |
| LANG-11 同名 `.h.ct`/`.ct` 产物冲突 | 状态 open（`lang-11…md:8`）；输出按 `base` 命名 | open（High） | 需要 | 无 | 可 | 无 |
| LANG-16 诊断位置负列 | 状态 open（`lang-16…md:9`）；v0.53.1 实测有 `1:-3788`（见可写下标提案 `:34`） | open | 需要（Medium） | Lexer 族 | 可 | 无 |
| LANG-3 MAX_CALLS 1024 | 状态 open（`lang-3…md:8`）；`Expr.h.ct:55` 仍是 1024 | open（Medium） | 需要（诊断/容量） | 无 | 可 | 无 |
| LANG-7 / LANG-8 | 均 open（`lang-7…md:8`、`lang-8…md:8`） | open（Low） | 需要 | Lexer/Parser 族 | 可 | 无 |
| LANG-10 机器可读诊断 | 警告 JSON 已实现（`Diag.h.ct:275-330`）；解析错误仍纯文本；字段级位置缺失 | 半完成 | 拆三块：7a 补夹具、7b patch、7c 前置任务 | 7c 是 v0-PH-59 的 J11 | 可 | 无 |
| LANG-12 自定义类型属性访问 | 状态 open（`lang-12…md:8`） | 冗余需求 | **放弃**（与 v0-PH-56 同判，见 §6） | — | — | — |
| LANG-15 枚举限定值 | 状态 open（`lang-15…md:9`） | open | 需要，并入 v0-PH-57 | SH-18 | 可 | v0-PH-57 开卡 |
| SH-18 类型限定名 | 部分修复（`ct-ast-qualified-type-name-rejected.md:9`） | 半完成 | 需要，并入 v0-PH-57 | LANG-15 | 可 | v0-PH-57 开卡 |
| SH-76 内置层缺失误诊 | 状态 open（`sh76…md:8`）；`Driver.h.ct:104` 只有 `CT_STD_DIR` | open（High） | 需要（影响仓外消费） | Driver 族 | 可 | 无 |
| SH-79 `--emit-map` 两 facet | 状态 open（`sh79…md:8`）；`Module.h.ct:1573` 的 lib 分支提前收口，`:1819` 固定 `units[0].prog` | open（High） | 需要，但**只挡 v0-PH-59 M2** | 无 | 可 | v0-PH-59 M1 不等它 |
| SH-65 / SH-67 闭包作方法实参 | 均 open（`sh65…md:9`、`sh67…md:9`） | open | 需要，同一入口族 | TypeCheck | 可 | 二者串行 |
| SH-60 1a/1b、SH-61、SH-73 | `sh60…md:9`、`sh61…md:9`、`sh73…md:9` | 待裁 / blocked / 有意限制 | 见 §6 | D-60-1 等 | 否 | 决定 |
| DF-1 预处理行 160 字节截断 | 代码注释自认（`Expr.h.ct:806`、`Stmt.h.ct:402`）；提案 `ct-build-frontend-defects.md:31-58` 有 510→159 实测 | **真 open，但没进台账** | **需要**（High 静默） | 无 | 可 | 先立 LANG-17 |

### 3.4 提案与需求池

| 项 | 证据 | 判定 |
| --- | --- | --- |
| `ct-json-capability-blockers.md` | J-1 已由 v0-PH-46、J-2 由 v0-PH-47、J-3 由 v0-PH-48、J-4 由 v0-PH-49 覆盖（roadmap `:62-65`） | **退役** |
| `language-capability-gaps.md` | 基线 v0.44.1、26 条能力域归并（文件头），此后 v0-PH-46–53 已改掉多批前提 | **退役或重新基线**；不得直接当需求单执行 |
| `custom-index-protocol.md` | REQ-L1 已 `done`（requirements-pool `:17`） | **归档** |
| `user-index-operator.md` | `:3` 自述「未立项、未过分析，不作数」 | **并入 v0-PH-62 作设计附件** |
| `ct-append-subscript-proposal.md` | `:5` 已被 v0-PH-62 吸收 | 已归档 |
| REQ-JSACCESS-1 / REQ-INDEX-1 | 均 `open`（requirements-pool `:79`、`:113`） | 作为 v0-PH-62 的 S1/S2 判据 |
| REQ-ABI-2/3/4、REQ-TYPE-1、REQ-MEM-2、REQ-CI-1/2 | 均 `open`，多为触发式（`:170`、`:183`、`:196`、`:212`、`:246`、`:262`、`:278`） | 不排期；保持需求池 |

### 3.5 治理与台账

| 项 | 证据 | 判定 |
| --- | --- | --- |
| 增量编译基准 | roadmap「未排期（治理项）」 | 低优先，不阻塞 58 后主线 |
| 稳定子集清单 | 同上 | 低优先，文档治理 |
| DOC-69 Phase 26 判据缺口 | `doc69…md:9` open | 建议关闭（冻结判据不追溯） |
| DOC-71 range `$` 叙述 | `doc71…md:9` open | 随手改，不单独立项 |
| CI-7 v0.19.0 无 tag | `ci-7…md:9` blocked | **待裁**：补 tag 或关闭；不擅自动 tag |
| issues 汇总计数 | `issues/README.md:380-388` 仍写 20 条 | 台账卫生，随回填一起修，不单独立项 |

## 4. 从 58 起的建议顺序

### 第 0 批 · 静默错误（逐条 patch，不攒批）

| 序 | 条目 | 为什么排这里 |
| --- | --- | --- |
| 0.1 | **PKG-5** ✅ / **PKG-6** ✅ / **PKG-3** ✅ | 三条包机制缺陷已按 v0.58.1–v0.58.3 交付；下一项 v0-PH-57 开卡 |
| 0.2 | **LANG-9** | 静默 + ABI 锁死；越晚修，越多外部包头文件固化私有字段。单独发，期间冻结其它 header 改动 |
| 0.3 | **LANG-4** | 编译通过、运行给错值；同时是 v0-PH-62/REQ-INDEX-1 的语义前置 |
| 0.4 | **DF-1（先立 LANG-17）** | 510 字节宏被截成 159 仍 rc=0，属会静默改行为的编译器缺陷 |
| 0.5 | **LANG-5 字段形态 / LANG-11** | 前者静默坏 C，后者 `duplicate symbol`；两者根因不同，各发一条 |

### 第 1 批 · 诊断与工具（可与第 0 批并行开发，串行发版）

`LANG-16 → LANG-8 → LANG-7 → LANG-3`（Lexer/Expr 族串行）；`SH-76`（Driver 族，单独）；`SH-79` 只在 v0-PH-59 M2 前处理。

### 第 2 批 · 文档收口（随时可做，不占版本位）

1. **v0-PH-54 S6 历史 errata**：给 `docs/history/design/phase20*.md` 等仍把 `-I vendor/<pkg>` 当契约的历史卡加一节「已被共享库取代」，不改正文。
2. **issue 状态回填**：PKG-4/7/8 已修；PKG-3 部分；PKG-2 已解决；顺手修汇总计数。
3. **退役册标注**：`ct-json-capability-blockers`、`language-capability-gaps`、`custom-index-protocol`、`user-index-operator` 按 §6 标注去向。

### 第 3 批 · v0-PH-57（限定名，含 SH-18 + LANG-15）→ v0.59.0

纯语言特性，无前置。版本位必须随收口单调递增，因此 v0-PH-57 排在 v0-PH-59 之前，先开卡。
与 v0-PH-62 同为 Parse/TypeCheck 族，**串行**；它不阻塞包机制（包仓的 `PK-*` 判据已归包外）。

### 第 4 批 · v0-PH-59 M1（模型导出）→ v0.60.0

前置只有两件：`Field` 补 `line`/`col`（LANG-10 7c），以及决定 `visibility` 是否等 LANG-9（不等则写 `unknown`，这是已定降级）。
J11 依赖字段级 `loc`；若暂不做 7c，按 `phase59.md:115` 降级为「`file` + `line`」，但要接受日后补 `col` 需 +1 schema 版本。
`SH-79` 两项 facet 只进 M2，不挡 M1。

### 第 5 批 · v0-PH-60（视图注记）→ 条件位 v0.61.0

只在 v0-PH-59 schema 冻结且**确认真实消费者**后开卡；无消费者则不立相，v0-PH-62 顺延到 v0.61.0、v0-PH-63 到 v0.62.0，不空占版本位。

### 第 6 批 · v0-PH-62（可写下标与嵌套链）→ v0.62.0

顺序：先开卡（把 v0-PH-55 / REQ-JSACCESS-1 / REQ-INDEX-1 并进来），再按研判建议切片：
S0 读物化与诊断位置 → S1 `v[] = x` → S2 `set` 补齐 / `len` / 洞释放 → S3 嵌套写。
它与 v0-PH-59 **可以并行开发**（v0-PH-59 在 Driver/Emitter，v0-PH-62 在 Expr/TypeCheck），但改 `Emitter` / `Symbols` 时要串行。

### 第 7 批 · v0-PH-54 S7（删 vendor）

最后做，因为它**删除回退路径**。前置：S6 errata 完成；S7 仓内自证三条全绿（v1 工程可 build、`ct install` 每包告警一次、`ct migrate` 后移走 vendor 仍可 build）；`ct migrate` 保留。
包仓迁移状态是外部登记项，不入本相判据。按兼容期节奏，v0.58.0 之后再发两个 MINOR 才谈收口，最早 **v0.61.0**。

## 5. 并行 / 串行

| 车道 | 文件族 | 队列 |
| --- | --- | --- |
| A 包机制 | `tool/pkg/Pkg.h.ct` | PKG-5 → PKG-6 → PKG-3 |
| B 头文件 / ABI | `backend/emit/Emitter.h.ct` | LANG-9（独占窗口） |
| C 表达式 | `frontend/parse/Expr.h.ct`、`TypeCheck.h.ct` | LANG-4 → LANG-5 → v0-PH-62 |
| D 词法 | `frontend/parse/Lexer.h.ct` | DF-1 → LANG-16 → LANG-8 |
| E 驱动 / 模块 | `tool/driver/Driver.h.ct`、`frontend/module/Module.h.ct` | LANG-11 → SH-76 → SH-79 |
| F 文档 | `docs/**`、`issues/**` | S6 errata、状态回填、退役标注（可与任何车道并行） |

发版仍串行：静默错误优先，一条 patch 一个主题；文档批次不占版本位。

## 6. 放弃 / 合并清单

| 对象 | 处置 | 理由 |
| --- | --- | --- |
| v0-PH-56 · Map 点访问 | **放弃** | `m.server.host` 在缺键时是空指针解引用，无法安全定义；安全形态 `m["server"]?.host` 已由 v0-PH-53 覆盖（`open-items-routing.md:62-82`） |
| LANG-12 · 自定义类型属性访问 | **放弃** | 与 v0-PH-56 同判；自定义容器的点访问没有安全语义，`[]` / `?.` 已够用 |
| v0-PH-55 · 自定义容器 `get` 协议 | **并入 v0-PH-62** | 与 REQ-JSACCESS-1 / REQ-INDEX-1 是同一套匹配与展开机制，分两个 phase 只会重复改 `Expr.h.ct` |
| v0-PH-61 · 追加下标 | **保持已并入 v0-PH-62** | 提案自身已写「S1 切片」 |
| v0-PH-58 · 诊断与调试（作为 phase） | **拆解** | 7a 已实现、7b 是 patch、7c 是 v0-PH-59 前置；`--keep-c` / `-g` 无消费者，不单独立相 |
| `ct-json-capability-blockers` | **退役** | J-1–J-4 已被 v0-PH-46–49 覆盖 |
| `language-capability-gaps` | **退役 / 重新基线** | 基线 v0.44.1，26 条能力域已漂移，不能直接当需求单 |
| `custom-index-protocol` | **归档** | REQ-L1 已 `done` |
| `user-index-operator` | **并入 v0-PH-62 设计附件** | 文件自述「未立项、不作数」 |
| SH-61 | **关闭或长期 blocked** | 前置「变参 trait」不在任何在册项里，无法排期 |
| SH-73 | **关闭（有意限制）** | 用限制换求值顺序，已有绕法 |
| SH-77 / SH-78 | **关闭（设计口径）** | 已由 D42-10 / REQ-ABI-2 承接 |
| SH-60 1a/1b | **待裁后关闭或排期** | 卡在 D-60-1，不是工作量 |
| DOC-69 | **关闭** | 冻结判据不事后扩写 |
| CI-7 | **已解决（2026-11-15）** | 补 annotated `v0.19.0`（→ `4b9946b`）；归档补 tag 后 200 |

## 7. 引用修正（随本次落地）

- `phase59.md` 与本文件相关提案里的「前置 v0-PH-58」改为「LANG-10 7c（`Field` 补行列）」；`v0-PH-58` 注明是 `open-items-routing.md` 的草案号，未在 roadmap 立项。
- `open-items-routing.md` 顶部加作废口径横幅：0.53.x patch 位与 v0-PH-55–62 草案号在 v0.58.0 后不再执行，正文保留作研判依据。
- 新增 LANG-17（预处理行截断），把 `ct-build-frontend-defects.md` 的 DF-1 从提案搬进台账。
- 版本位按 AGENTS §0.3 的相位表钉号：v0-PH-54 记 v0.54.0–v0.58.0，v0-PH-57 / 59 / 60 / 62 依次记 v0.59.0 / v0.60.0 / v0.61.0 / v0.62.0。
- S7 判据改为仓内自证三条；包仓迁移状态明确为外部登记项，Ct 不追踪。

## 8. 待裁定（不自行决定）

> 2026-11-15 已裁定两条（保留记录）；仅 CI-7 仍待决定。

1. ~~V-1 版本偏移~~ **已裁定：认偏移、不重打已发布 tag、功能不降 PATCH**。v0-PH-54 覆盖 v0.54.0–v0.58.0；
   后续按「下一个空位」连续分配：**v0-PH-57 → v0.59.0、v0-PH-59 → v0.60.0、v0-PH-60 → v0.61.0、v0-PH-62 → v0.62.0**。
   换算表与 d 值见 AGENTS §0.3。
2. ~~S7 前置口径~~ **已裁定：本仓自证**。三条可执行判据见 roadmap S7 行；包仓迁移状态降级为外部登记项，Ct 不追踪、不判定。
3. ~~CI-7~~ **已解决（2026-11-15）**：补 annotated `v0.19.0` → `4b9946b`，归档恢复 200；见 [CI-7](../../issues/ci/ci-7-v0190-untagged.md)。

## 9. 验收建议

- 每个 patch：对应 issue 的状态行从 `open` 改为 `已修`，并写回归夹具名；静默错误必须先有红证。
- v0-PH-59：`Field` 行列落地后，`--emit-model` 的 J11 才能按字段级 golden 比对；否则按 `phase59.md:115` 降级并标注。
- v0-PH-62：开卡时把 REQ-JSACCESS-1 / REQ-INDEX-1 的 A1–A7 转成卡内判据，不得另立两套。
- 文档批次：`python3 test/docs/check-docs.py` 必须绿；不动 `lib/` 与 `selfhost/`。
