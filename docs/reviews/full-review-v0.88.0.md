# v0.88.0 全面评审报告（v1-pre 收口后）

| 项 | 值 |
| --- | --- |
| 基线 | `5605eb6c`（tag `v0.88.0`，2026-11-21；PH-88 收口 + REV N-1 订正） |
| 范围 | 编译器（L0/L1/L2/ct-ast）、`test/**`、`docs/**`、`examples/**`、`issues/**`、`tools/**`、CI |
| 方法 | 读码 + 离线全量门禁 + 文档/台账脚本 + 抽样探针；不修改源码、测试与既有文档 |
| 结论 | **产品门禁 11/11 绿，v1-pre（PH-78–88）已交付；未发现产品级 P0。v1.0 仍有 5 个 P1 前置未清，尚不可发布。** |
| 证据 | §10；离线日志 `/tmp/ct-review-v088-check-all.log`（11/11） |

> 工作树有未提交的 `docs/guide-for-c-programmers.md`、`battle/ct-guide-1/`、`docs/memory-guide.md`
> 修改与 `issues/selfhost/sh106-*`；这些不是 v0.88.0 基线的一部分，未计入门禁。基线以 tag 为准。

---

## 0. 结论摘要

**强项**

- **产品门禁全绿**：离线 `check-all` 11/11；`check-ast` **1575 passed / 0 failed / 5 skipped**；
  `test/run.sh` 156/0；goldens 25/25；grammar 169/0；package 153/0；`check-docs` 2439 links / 390 files。
- **v1-pre 重写闭环**：PH-85–88 完成词法器 `TokView`、解析器/检查器 kind 切片、发射器 76 个
  `em_*` 切片；66 语料逐字节、345 条诊断逐字、自举不动点 2/3 轮通过。
- **语言面继续扩展并有测试**：`ref`/`out`、切片 `T[]`、`String`/`Str`、`box<T>`/`new`、
  leak guards、`match`/ADT、`ct index verify`、conformance、Linux x64 产物；每相都有 p78–p88 探针。
- **代码卫生保持**：ct-ast 无 `TODO/FIXME`；固定容量越界走硬错；分配有 null 检查；
  ASAN/UBSAN + 确定性 fuzz 在 nightly；C 边界 cwd 后门已由 SH-93 修掉，git 子进程已有超时/禁交互。

**不能发布 1.0 的原因**

1. **v1.0 的两个硬闸门仍是 `待办`**：SH-104（J-6 全量证据台账）、SH-105（goldens 静态化），
   正是 `v1-PH-0` 的 V1-C1/C2 前置；在它们清零前不能开 `v1-PH-0`。
2. **phase-ID 迁移仍未执行**：主规范 1.17.0 的 PN-1…PN-17 已生效，仓库仍用裸 `PH-*`，
   `docs/planning/phase-id-ledger.md` 不存在；迁移 blocker A/B/C 未裁。
3. **治理门禁仍缺 G1/G6**：`tools/check.sh` 只有 `g0`、`g8`、`battle-selftest`；台账里
   184/242 条状态词不在 AGENTS §5.4 闭集内，15 条 open-ish + 14 条 `待办` 仍未清。
4. **自举容量只剩 11 个顶层函数**：`MAX_FUNCS` 实测 **501/512**；v1-PH-0 计划把 76 个切片
   转成穷尽 `match`，再切一批就会撞顶；卡面仍写“余量 37”，与度量冲突。
5. **PH-88 的 E88-1 只“部分通过”**：字面 `match` 因 L2 引导链不支持 ADT 未进源码，承接
   `v1-PH-0` seed cutover；`battle/p88-emit-match` 的 EDITOR 追签仍待补。

---

## 1. 门禁结果

| # | 门禁 | 结果 | 备注 |
| --- | --- | --- | --- |
| 1 | `test/run.sh` | **156 passed / 0 failed** | 8 层 |
| 2 | `check-goldens.sh` | **25 / 25** | L1、L1′、L2 |
| 3 | `check-archive.sh` | **OK** | 归档棘轮 |
| 4 | `check-m2a.sh` | **OK** | L0→L1 字节一致 |
| 5 | `ct-tour.sh` | **OK** | 四代一条龙 |
| 6 | `check-grammar.py` | **169 / 0** | node 缺失时 index skip |
| 7 | `test/pkg/run.sh` | **153 / 0** | 包管理 |
| 8 | `check-ast.sh` | **1575 / 0 / 5 skipped** | skip：Renode / nRF52 / FreeRTOS / GDB / 外部 pin |
| 9 | `check-warnings.sh` | **绿** | 全量生成 C 零告警 |
| 10 | `check-semantics.sh` | **绿** | `ct check` |
| 11 | `check-docs.py` | **OK** | 2439 links / 390 files / 8 signoff |

治理：`g0` OK（1.17.0）、`g8` OK（legacy offset 账本内）。v0.88.0 **干净归档**的 `check-docs`
也通过（2427 links / 388 files），说明 tag 树本身没有死链；`DOC-81` 是 v0.85 历史证据债，不是当前树红。

**前次 P1 的处置**

- 网络挂起：`Pkg.h.ct` 已加 `GIT_TERMINAL_PROMPT=0` / `GIT_ASKPASS=true` /
  `http.lowSpeedLimit` / `http.lowSpeedTime` 与 Linux `timeout 180`（CI-9）。**已修**；
  离线跑 `p77_external` 正常 skip，不再无限挂起。
- C 边界 cwd 后门：`c_boundary_for` 删除 `c_cwd_in_tree`，只按四个仓内目录判定（SH-93）。**已修**。
- 台账闭合：`verified` 从 17 增至 39，open 从 24 降至 8；但状态词规范和 G6 仍未解决。

---

## 2. 测试覆盖度

| 层 | 规模 | 评价 |
| --- | --- | --- |
| L0 `test/run.sh` | 156 项 / 8 层 | 强 |
| L0 unit | 112 checks（`test_helpers.c`） | 仅 L0；ct-ast 仍无白盒单测 |
| L0 cases / errors | 25 golden / 61 负例 | 逐字节 |
| ct-ast 行为 | 312 个目录（含 errors；行为 311） | 编译→零告警→运行→比对 |
| ct-ast 负例 | 295 | 位置 + 文案 |
| 多单元 / 模式 | 102 / 6 | import/pub/map/模式 |
| probes | 61 | p78–p88 均有专项 |
| model / baremetal | 5 / 40（qemu 7 + renode 33） | 模拟器；真机外部 |
| package | 153 | store/lock/index/conformance |

**缺口**

1. **没有行/分支覆盖率**。行为/golden 覆盖很广，但无法回答“45k 行里哪些没跑到”。
   建议 nightly 跑 `llvm-cov`/`gcov`，只报告、不设阈值。
2. **ct-ast 无单元测试**。Lexer/Parser/TypeCheck/Emitter 只经端到端；切片重写后
   `em_*`、`ctype_*`、`tc_expr_*` 的单函数行为没有白盒钉住。
3. **容量上限仍只覆盖 `MAX_CALLS`**。`MAX_FUNCS` 501/512、`io_names[1024]`、
   `MAX_PARAMS`/`MAX_CLOSURES` 没有边界夹具；v1-PH-0 前应至少补 `MAX_FUNCS` 与 `io_names` 的
   “临界 + 越界”两条。
4. **sanitizer / fuzz 只在 nightly**。本地 `check-all` 不含 ASAN/UBSAN 与 fuzz；这是速度取舍，
   但“本地全绿”不等于“无 UB”。
5. **跨平台**：CI 有 Linux GCC / macOS clang；无 Windows；IAR/Keil 未验证。

---

## 3. 文档漂移

| # | 位置 | 现状 | 实际 | 级别 |
| --- | --- | --- | --- | --- |
| D-1 | [test/README.md:19](../../test/README.md#L19) | `ast/` 299 个目录；行为 298 | 312 / 311 | **P2** |
| D-2 | [test/README.md:28](../../test/README.md#L28) | 实测 v0.77.0；1519/0/4 | v0.88.0；1575/0/5 | **P2** |
| D-3 | docs/README 评审索引 | 评审开始时仍写“最新一轮（针对 0.77.0）” | 本报告已更新为 v0.88.0 并保留历史入口 | **P2**（本轮已修） |
| D-4 | [docs/design/phase88.md:160](../design/phase88.md#L160) | `MAX_FUNCS` 余量 37 | p88_metrics 实测 501/512（余 11） | **P2** |
| D-5 | [docs/history/p88_metrics.md:103](../history/p88_metrics.md#L103) | 余量 37 | 同文件 :64 写 501/512（余 11） | **P2** |
| D-6 | [docs/history/phase-log.md:188](../history/phase-log.md#L188) | `MAX_FUNCS` 475/512 | 实测 501/512 | **P2** |
| D-7 | [docs/planning/v1-release-plan.md:7](../planning/v1-release-plan.md#L7) | 基线 v0.65.1 / Phase 66 | v0.88.0 / PH-88 已收口 | **P3** |
| D-8 | `docs/README.md` 评审索引 | 只给 `reviews/` 目录，无 v0.88 报告 | 本报告加入索引 | **P3** |

> 上一轮的 typecheck 计划、session-map、裸机提案、tutorial 示例数、selfhost grammar 数都已修正；
> 本轮的漂移集中在**计数与容量数字**，说明“手工抄数字”仍是复发源。建议把可计数项
> （示例数、ast 目录数、负例数、MAX_FUNCS 余量）改为生成或门禁断言。

---

## 4. 台账与治理

- **242** 个 issue 条目：`verified` 39、`open` 8、`fixed` 6、`已修` 82、`已修复` 38、
  `✅ 已修复` 25、`待办` 14、`受理` 5 等；**184 条不在 §5.4 的 8 词闭集**。
- **15 条 open-ish**：SH-81/82/83/85（受理）、SH-61（blocked）、SH-107（open）、DOC-81/82（open）、
  LANG-8/10/18/20、TEST-21/22、SH-73（保持）。
- **14 条 `待办`**：其中 **SH-104 / SH-105 是 v1.0 硬闸门**；DOC-76/77/78/79/80 是 v1-pre
  文档一致性；PKG-12/13/15/16/17/19/20 是包契约 v1 收尾。
- **历史 High 证据债仍未处置**：SH-107（`e88561af` M0 提交不能独立构建，T-7/T-4 证据不成立）、
  DOC-81（v0.85.0 归档 `check-docs` 死链）、DOC-82（E85-2 “门通过”与卡面“门不通过”冲突）。
  当前树/v0.88 归档不红，但这是**已收口 phase 的证据真实性**问题，不能长期挂 `open`。
- **G1/G6 仍缺位**：`tools/check.sh` 只有 `g0`/`g8`/`battle-selftest`；G1（phase 卡完整性）、
  G6（台账闭合）没有机械实现，也没有 `deviation:`。当前 184 条非闭集状态就是 G6 缺失的直接后果。
- **T-8 签收**：8 个 signoff 被 `check-docs` 校验；`battle/p88-emit-match` 仍写
  “EDITOR 追签待补”，与 PH-88 卡“EDITOR 签收”并存。

---

## 5. 代码与架构

**规模**

| 层 | 行数 | 备注 |
| --- | --- | --- |
| L0 `ctc.c` | ~3.0k | 冻结种子 |
| L1 / L2 | ~3.7k / ~7.2k | 冻结种子 / oracle |
| ct-ast | **45,239（27 个 `.ct`）** | `Emitter` 9371、`Expr` 8819、`Stmt` 5056、`Parser` 4795 |

**优点**

- 0 个 TODO/FIXME；固定容量越界硬错；分配 null 检查；生成 C 零告警；ASAN/UBSAN +
  确定性 fuzz 可覆盖 ct-ast。
- 四代编译器差分 + 66 语料逐字节 + 345 诊断逐字 + 自举不动点，是强正确性防线。
- PH-88 切片把判别式 kind 读数降到每函数 1 次，`emit 0.74→0.76s`（+2.7%，噪声内），
  发射 C +0.88%；重构本身行为保持。

**风险**

1. **自举容量临界**：`MAX_FUNCS` 501/512，只剩 11 个顶层函数。v1-PH-0 要求把 76 个切片
   改成穷尽 `match`，再加 helper 就会撞顶。必须先做容量决策（提高上限 / 用 `impl` 方法 /
   调整切片），并把 501/512 写进 v1-PH-0 的前置。
2. **巨型单元**：`Emitter` 9.4k、`Expr` 8.8k；切片增加了 5.6% 行数，判别式更清晰，但单文件
   可读性已到上限。建议 v1.0 冻结后按“纯函数/子对象”做行为保持拆分。
3. **重复容量常量**：`MAX_FUNCS` 同时在 `Symbols.h.ct` 与 `Expr.h.ct`；`io_names[1024]`
   是字面量（宏不跨单元）。改容量时要同步多处，容易漂移。
4. **默认编译路径不做类型检查**：`ct check --types`/`--check-level` 是 opt-in；这是已定设计，
   但“build 绿”不等于类型正确，README/教程应持续显眼说明。
5. **引导链能力分叉**：ct-ast 不能用自己实现的 `match`/`?`/errdefer（L2 不下降 PH-40/44/84）；
   v1-PH-0 的 seed cutover 是唯一解，且必须同时清 E88-1 承接项。
6. **包链**：官方 pin 有 sha256；第三方索引仍无签名，`ct get` 网络路径虽已加超时/禁交互，
   信任模型仍应写清。

---

## 6. 样例覆盖

- 51 个示例目录（`examples/README.md` 到 `49_socket`）；`49_socket` 是文档型、不进门禁。
- **PH-78 之后没有新增 example**：`ref`/`out`、切片 `T[]`、`String`/`Str`、`box`/`new`、
  `leaks`、`match`/ADT、`ct index verify` 只有 spec/tutorial/测试，没有可运行示例目录。
- 教程已更新到 §21（PH-88），示例计数改为 51（D-4 已修）；但新特性仍缺“最小可跑”的
  `examples/5x_*`。
- 建议补 4 个 example：`ref_out`、`slice`、`box_new`、`match_adt`（每个 20–40 行，带 expected）。

---

## 7. 发布就绪判断

| 维度 | 评分 | 说明 |
| --- | --- | --- |
| 产品正确性 / 测试 | **9/10** | 11 门禁离线绿；1575/0/5；四代差分；ASAN/fuzz |
| 代码质量 | **7.5/10** | 无 TODO、硬错、零告警；45k 行与 9k 单文件、容量临界扣分 |
| 文档准确性 | **6/10** | 上轮大漂移已修；本轮计数/容量数字再次漂移 |
| 治理 / 台账 | **5/10** | G6 缺位；184 条非闭集；14 条待办；历史 High 证据债 |
| 样例覆盖 | **6/10** | 51 个 + tutorial；新语言特性无 example |
| **v1.0 就绪** | **4/10** | SH-104/105、phase-ID、G6、MAX_FUNCS、E88-1 五项未清 |

**判断**：v0.88.0 是 **v1-pre 的合格收口**，产品代码与测试可信；但 **v1.0 不是“再做一点”**，
它需要先清五个硬前置。不能把“PH-78–88 全部收口”等同于“v1.0 可发”。

---

## 8. 建议行动（按优先级）

### P1（v1.0 前必须）

1. **清 SH-104 / SH-105**：J-6 证据台账 + goldens 静态化；把 V1-C1/C2 变成可机判；
   清零前不开 `v1-PH-0`。
2. **解决 `MAX_FUNCS` 501/512**：先复算，再决定提上限（用户签字）/改用 `impl` 方法/
   调整切片；把容量写进 v1-PH-0 前置，并补 501/512 与越界负例。
3. **phase-ID 迁移**：解决 blocker A/B/C，建账本、推进 W0→W1→W2；v1-PH-0 用 `v1-PH-0`
   而不是裸 `PH-*`。
4. **补 G1/G6**（至少 G6）：台账状态词闭集、phase 收口去向、`待办` 与 open 的闭环；
   不实现就登记 `deviation:`。
5. **处置历史 High 证据债**：SH-107（M0 提交不能独立构建）、DOC-81（v0.85 归档死链）、
   DOC-82（E85-2 口径冲突）——修文档/记录，或明确 `wontfix`/`deferred` 并说明不改历史的理由。

### P2（v1.0 前建议）

6. **补 p88 EDITOR 追签**，把 `battle/p88-emit-match` 状态改为 closed。
7. **文档刷新批**：test/README 计数与 v0.88 实测、`docs/README` 评审索引、v1-release-plan
   基线、phase88/p88_metrics/phase-log 的 `MAX_FUNCS` 三个数字统一到 501/512（余 11）。
8. **退役 phase77**：设计窗口 12/12，开 `v1-PH-0` 前归档。
9. **补 4 个新特性 example**（ref/out、slice、box/new、match）。
10. **覆盖率与容量测试**：nightly `llvm-cov` 报告；`MAX_FUNCS` / `io_names` 边界夹具；
    评估 ct-ast 纯函数层单测。
11. **包契约 v1 收尾**：PKG-12/13/15/16/17/19/20；第三方索引 fixture 进 CI。

### P3（卫生项）

12. `docs/README` 的 `reviews/` 行改为具体报告；旧 v0.77 报告保留为历史。
13. 工作树未提交的 guide/battle/memory-guide/sh106 先决定入库或丢弃，避免再次出现
    “工作树绿、归档红”的 DOC-81 类问题。

---

## 9. 复现与证据

```console
$ git rev-parse --short HEAD     # 5605eb6c (v0.88.0)
$ bash tools/check.sh g0         # OK (1.17.0)
$ bash tools/check.sh g8         # OK (legacy offsets)
$ python3 test/docs/check-docs.py
# OK (2439 links / 390 files / v0.88.0 / 12 phase status / 8 signoff)
$ bash selfhost/check-all.sh     # 离线代理：check-all: OK (11 hard gates green)
```

- `check-ast`：1575 passed / 0 failed / 5 skipped；5 skip 为 Renode / nRF52 / FreeRTOS / GDB /
  外部 pin（离线）。
- 干净归档 `v0.88.0` 的 `check-docs`：2427 links / 388 files，OK。
- 工作树只新增本报告与 `docs/README` 索引；未改 `selfhost/**`、`test/**`、`examples/**`、
  `docs/language-spec.md`。
