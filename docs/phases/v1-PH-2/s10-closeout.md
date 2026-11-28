# v1-PH-2 · S10 收口清单（已执行，2026-11-27）

> 中文。REQ 起草 2026-11-27，锚点 `3c92e20d`。
> 依据：[卡 §2 S10](card.md)、[E-V3-11](card.md#3-退出判据)、
> 卡内「S10 的版本纪律」注。
> 本文是**施工用清单**，不是新的退出判据；判据以卡为准。**S10 已执行**：结果与原始输出见
> [卡 §6–§7](card.md)；本文件只保留施工口径与待所有者事项。

## 1 当前快照（2026-11-27）

| 项 | 状态 |
| --- | --- |
| S0–S8 尾、S8c、S9 | 已入库；S8r2 单文件默认 LIR、known-gap 清零；S8 尾 D5/D6/外壳落盘（`Emitter.h.ct` 9872→1545）；S8 收尾 D-013 真 lowering（自举 1638/1638、语料 498/498）与外壳行化（882 夹具 0 差异） |
| S8 §5 签字 | **已完成（`0e2edb15`，2026-11-28）**：两份 S8 文档 REV 均「复核通过」，dogfooding §3.7 可读性通过，`D-030` 转 `accepted` |
| S8a（LANG-31，可砍） | **改为必做（2026-11-28 撤回 deferred）**：issue 转回 `open`，施工卡已有；与 I2 共用 D-028 解析表 |
| I2（接口值下标） | **新纳入 1.2**（E-V3-9e）：未开工，先出 ADR（拟 `D-034`）并裁定 I2-Q2–Q4 |
| S8b 剩余 | §3.6 已补 D6/D4/D2 行块/D3a–c；**R1/R2 已完成**（`6ba2a627` Pkg 53→51、`1d93fd77` Symbols 41→24；审计表 `docs/design/s8b-rem-audit.tsv`）；R3/R4/R5–R7/R8 待开 |
| 未关闭 issue | DESIGN-1、TEST-27（`open`） |
| ADR | `D-030`、`D-032` 已 `accepted`；`D-031`（I1）与 `D-034`（I2）待立 |
| 判据 | `E-V3-10` 已由 [CR-V3-1](card.md#8-判据变更记录) 改写为「selfhost/ct-ast 与 lib/core 各一处 manifest allow」；实施卡 [D032-C1](../../design/d032-internal-c-boundary-construction.md) 已交 |

## 2 开工闸（不清零不进 S10）

| # | 前置 | 判据 | 负责人 |
| --- | --- | --- | --- |
| G-1 | S8r2 + S8 尾签字 | [差异清单 §5](../../reviews/2026-11-27-s8-ir2-diff-list.md#5-签字) 有 DEV 证据行（含 S8 尾）与 REV「通过」行，且注明「回退 ≠ 已降级」 | DEV → REV |
| G-2 | S8b 生成 C 可读性 | REVIEW 签字（E-V3-9b）；REQ 2026-11-28 已裁定方案 A（条件通过、保留 SH-123），待 REV 补 `dogfooding §3.8` 最终计数与抽查后签 | REV |
| G-3 | S8b 剩余处置 | D2 符号表 / D3 / D4 / D6 二选一：做完，或由所有者裁定 deferred 并写入本文 §6 | 所有者 |
| G-4 | S8a 去留 | 同上：做（E-V3-9d）或整体 deferred（卡允许） | 所有者 |
| G-5 | `D-030` 签收 | 状态改 `accepted`，签收行非作者席位 | REV |
| G-6 | DESIGN-1 / TEST-27 | 转 `verified` 或明确 deferred，附证据 | REQ / REV |

## 3 版本 bump 清单

**原则**：源码、golden、版本串分提交；先 bump 后重基线，重基线单独提交。

| # | 对象 | 动作 | 数量 |
| --- | --- | --- | --- |
| V-1 | `selfhost/ct-ast/main.ct` | `CTC_VERSION "1.1.0"` → `"1.2.0"` | 1 处 |
| V-2 | seed | `bash selfhost/gen-seed.sh`，整目录 + `bootstrap/MANIFEST.sha256` 提交；两轮逐字节 | `bootstrap/ct-ast/**`（含 `main.c` 版本串） |
| V-3 | `test/goldens/ast/**` | 25 份静态 golden 的 banner 随版本变化，按既有重基线流程重生成（不手改） | 25 |
| V-4 | `test/cases/**` | `.expected.c` / `.expected.h` banner 重生成 | 50 |
| V-5 | 版本断言脚本 | `test/ast/p80_docs.sh`、`p81_box.sh`、`p82_docs.sh`、`p83_verify.sh`、`p83_legacy.sh`、`pkg19_20_rows.sh` 里的 `1.1.0`/`v1.1.0` 字面量 | 6 个脚本 |
| V-6 | 其他带版本串的夹具 | `test/modules/p39_lib`、`test/conformance/pkg/v1/index` | 2 |
| V-7 | 文档 | `README.md`（头行与两处「v1.1.0 的实测」）、`docs/README.md` 头行、`docs/roadmap.md` 的 v1-PH-2 行（收口版本 `v1.2.0`、状态 ✅、单元格只写索引） | 3 |
| V-8 | 卡 | v1-PH-2 卡状态转「完成」，§7 收口表补齐 E-V3-1…11 | 1 |
| V-9 | 流水账 | `docs/history/phase-log.md` 版本记录表加 `v1.2.0` 行 | 1 |
| V-10 | 指标 pin | `p88 live pin`、`test/ir/README.md` 覆盖率若随版本或代码变化，同批校准 | 视实测 |
| V-11 | [stable-subset](../../stable-subset.md) 分档更新 | 为本期新能力补行或改档：自定义下标协议（D-028）、函子签名（D-029）、`Str`/`String` 的 `print`/`println`（D-030）、`c-boundary` 默认 strict（S9）；泛型 ADT 行已标「v1.2.0 起」 | 4 条 |

**V-3 例外**：若 25 份 golden 与版本无关（实测确认），则跳过，并在 S10 记录里写明「实测无 banner」。不要凭印象跳过。

## 4 冷/热构建（不立项）

按 [roadmap 未排期项](../../roadmap.md) 的口径，在 S10 收口提交上各测一次，写入流水账：

| # | 动作 | 记录 |
| --- | --- | --- |
| C-1 | 冷构建：清 build cache 后 `ct build`（或等价入口）计时 | 用时、机器、commit |
| C-2 | 热构建：同树连跑第二次计时 | 同上，并给出冷/热比值 |
| C-3 | 结论 | 只记录不设门禁；异常时进需求池，不在 S10 修 |

## 5 分发产物

| # | 动作 | 判据 |
| --- | --- | --- |
| P-1 | Linux x86-64 上 `bash selfhost/make-dist.sh` | `dist/ct-linux-x64.tar.gz` + `.sha256`；**dist 不入 git** |
| P-2 | 产物自检 | `tar -tzf` 得 `ct` 与 `ctc` 链接；`./ct -v` == `1.2.0`；`sha256sum -c` 通过 |
| P-3 | 冒烟 | 用产物编译并运行 `examples/50_ref_out`、`examples/52_box_new`（与 `release.yml` 同款断言） |
| P-4 | 文档 | `docs/dist.md` 的示例版本串与稳定 URL 不需改（`v<MAJOR>.<MINOR>.<PATCH>`）；如示例写死旧版本，同批更新 |

## 6 收口记录必写内容

S10 提交里的收口记录（卡 §7 或流水账）必须回答，缺一不算收口：

1. **S8a 去留**：做了 → 附 E-V3-9d 证据；没做 → 记 `deferred`、理由与触发条件（卡已授权）。
2. **S8b 剩余**：D2 符号表 / D3 / D4 / D6 各自「已做 / 不做 + 理由」，附最终 LOC 与计数（自由函数 / `realloc` / `snprintf` / 判别式 / `Vec` / `Result`）。
3. **S8 §3d 剩余边界**：[差异清单 §3d](../../reviews/2026-11-27-s8-ir2-diff-list.md#3d-仍未做剩余清单) 四条照抄一遍——外壳未完全 LModule 化、「回退改真修复」技术债、覆盖率数字、"回退 ≠ 已降级"。
4. **issue 收口**：DESIGN-1、TEST-27、LANG-31（或 deferred）、LANG-30（已 `verified`）逐条状态。
5. **ADR**：`D-030`（及 S8a 若做的 `D-031`）状态。
6. **门禁原始输出**：§7 每一项的末行。

## 7 门禁矩阵（S10 提交前全绿）

| 门禁 | 命令 | 期望 |
| --- | --- | --- |
| 全量 | `bash selfhost/check-all.sh` | 全绿（门数按当期实际，卡上写 8/9 时以脚本输出为准） |
| 语料 | `bash selfhost/check-ast.sh <ct>` | fixpoint，0 失败 |
| 静态 golden | `bash selfhost/check-goldens-ast.sh` | 25/25 逐字节 |
| seed | `bash selfhost/check-seed.sh` | 两轮逐字节 |
| 告警 | `bash selfhost/check-warnings.sh` | 0 条 |
| sanitizers | `bash selfhost/check-sanitizers.sh` | 无报告 |
| 文档 | `python3 test/docs/check-docs.py` + `--selftest` | OK |
| 台账 | `bash tools/check.sh g6` | OK，无 `open` 残留（或 deferred 有记录） |
| 治理 | `bash tools/check.sh g0 && bash tools/check.sh g1 && bash tools/check.sh g8` | OK |

## 8 禁止项

- **不自动打 tag、不自动发 release**：annotated tag 与 GitHub Release 由所有者手工验证后创建（卡内版本纪律）。
- 不在同一提交里混「版本串 bump」与「语义/实现改动」。
- 不改已发布 tag，不改 `test/archive/**`。
- 不为凑绿改判据；判据冲突就地停并改卡。

## 9 建议提交切分

1. `chore(seed): v1.2.0 前 seed 重生成`（若与版本无关的代码已定）
2. `chore(release): CTC_VERSION 1.2.0 与 25+50 份 golden 重基线`
3. `docs(release): README / docs/README / roadmap / 卡 / 流水账 v1.2.0`
4. `docs(release): S10 收口记录（S8a、S8b、§3d、issue、门禁输出）`

## 10 待所有者裁定

| # | 问题 | 影响 |
| --- | --- | --- |
| O-1 | S8a（LANG-31）做还是 deferred | **本轮结论：deferred**（卡已授权可砍）；未做 `D-031`，触发条件见卡 §6 |
| O-2 | S8b 剩余 D2 符号表 / D3 / D4 / D6 做多少 | **所有者 2026-11-28 裁定：按方案 A 补完**。施工卡 [s8b-remaining-construction](../../design/s8b-remaining-construction.md)（`S8B-REM-1`）：D2 三大表（`funcs`/`vars`/`structs`）、D3 两域（`Pkg` 53 / `Symbols` 41）、D4 判别式；D6 已完成。E-V3-9b 待收官后转「通过」 |
| O-3 | `v1.2.0` 的 tag 与 release 何时手工执行 | **待所有者**；精确命令与校验项见卡 §7.5 |

## 11 执行结果（2026-11-27）

| 项 | 结果 |
| --- | --- |
| 版本 | `CTC_VERSION 1.2.0`；README / docs/README / AGENTS / roadmap / phase-log / stable-subset 同步 |
| seed | 73 `.c` + 140 `.h` 重生成；`check-seed` 两轮逐字节 + 手改负例红 |
| stable-subset | v1.2 冻结：下标协议、函子、`print`/`println`、默认 strict 入「已冻结」；6 个到期条目转档；保留 1 条「冻结中」 |
| 冷/热构建 | 4.17s / 3.47s（比值 0.83）；只记录，不设门禁 |
| dist | `ct-linux-x64.tar.gz`（static musl，ELF x86-64）；sha256 `98130730155f88934a2c4b4d0ce82e222bc81fc25e34a6fc0fdcf7736a0e28d3`；不入 git；冒烟 UNVERIFIED（无 QEMU 资产） |
| 门禁 | `check-all` 8 门、`check-seed`、sanitizers 662、`check-docs`、`g0/g1/g6/g8`、`test/ir` 15 checks |
| tag/release | **未创建**（按所有者版本纪律）；手工命令见卡 §7.5 |

## 12 收口后队列（2026-11-28）

> 1.2.0 已提交、未打 tag。以下是收口后的排队项，**按前置排序**；写者一栏是唯一可动该文件集的席位。
> 状态词只用：`待签` / `待开` / `进行中` / `已完成` / `登记`。
> **角色边界（所有者 2026-11-28）**：REV 只写评审报告与样例代码，不改其它文档或代码；
> 产物头部的状态落笔由 EDITOR（或该产物的作者席位）执行，REV 只出评审结论。
>
> **设计与签收（所有者 2026-11-28 补充裁定）**：**ARCH 不得缺位**——按工程规范
> [§3.4 架构（ARCH）](../../spec/ai-coding-workflow.md#34-架构arch)，技术选型、技术可行性与
> 架构设计归 ARCH；ADR 由 ARCH 起草，**EDITOR 审核签收**（非作者席位），签收后由
> **REQ 安排具体任务与排期**；REV 只出评审结论与样例代码。ADR 未签收前，DEV 不得按该设计动代码。
>
> **非阻塞原则**：REQ 的文档同步（spec §4.66 / c-shim-contract）与 REV 的评审都**不进入
> DEV 的提交前置**；DEV 可连续 M1 → M2 → M3，也可让 S8B 的 R3–R8 与 D032-C1 并行
> （文件集不重叠）。任何一项若被写成"等 REQ 复核"或"等 REV 签字才能开工"，即视为排程错误。
>
> **REQ 复核记录（2026-11-28）**：R1/R2 审计表 `docs/design/s8b-rem-audit.tsv` 已复核——
> 53 + 17 处逐条归桶齐全（38 带界拷贝 / 2 a / 1 c / 7 d / 5 vsnprintf / 17 b），
> 与提交信息一致；小瑕：`Pkg.h.ct:3270` 的 function 列写成 `install_main`，实为
> `pkg_official_resolve`，不阻塞。
>
> **REQ 验收记录（D-032 M1–M3，2026-11-28）**：M1 `feb6caa5`、M2 `981f2ee9`、
> M3 `653dec09`。实测 shim：selfhost 66 → 3、lib/core 8 → 0、`bootstrap/ct-ast` 68 → 3
> （合计 74 → 3，seed 侧 5 → 3）。`--show-c-boundary`：lib/core 8 个单元与 `utf16/` 子树
> 均 `allow`，`test/cases`、`examples` 仍 `strict`；三个负例（删包根清单 → 全回 strict；
> `lib/core/utf16/ct.pkg: c-boundary = strict` → 该子树 strict、根单元仍 allow；包外 allow
> 不外溢）经 `test/ast/p65_policy.sh` 与临时副本独立复测通过。门禁：`p65_regression`、
> `p65_policy`、`CT_C_BOUNDARY=allow check-goldens-ast` 25/25、`check-seed` 两轮逐字节
> （73 .c + 75 .h）全绿。剩余：REV 只读复核（不改状态），状态由 EDITOR 落。

| # | 事项 | 状态 | 写者 / 批者 | 前置 | 依据 |
| --- | --- | --- | --- | --- | --- |
| Q-1 | D-032 设计签收（内部层 C 边界豁免） | **已完成** | REV | 无（ADR 已 `proposed`） | [D-032](../../decisions/D-032.md)、[签收包](../../reviews/2026-11-28-signoff-package.md) |
| Q-2 | D032-C1 实施 M1（`c_boundary_for`/`leaks_for` 同源解析 + 两处 `ct.pkg`） | **已完成**（`feb6caa5`） | DEV | — | [施工卡](../../design/d032-internal-c-boundary-construction.md) |
| Q-3 | D032-C1 实施 M2（selfhost 63 个 shim 退场） | **已完成**（`981f2ee9`，66 → 3） | DEV | — | 同上 |
| Q-4 | D032-C1 实施 M3（lib/core 8 个 shim 退场，含 utf16 子树） | **已完成**（`653dec09`，8 → 0；seed 5 → 3；REQ 验收见下） | DEV | Q-3 | 同上 |
| Q-5 | S8B-REM-1 R1/R2（Pkg 2 处、Symbols 17 处） | **已完成**（`6ba2a627`、`1d93fd77`） | DEV | 无 | [S8B 施工卡](../../design/s8b-remaining-construction.md)、[审计表](../../design/s8b-rem-audit.tsv) |
| Q-6 | S8B-REM-1 R3/R4（取值 API、lock 字段）与 R5–R7（三大表）、R8（判别式） | **已完成**（R3 `e23338db`、R4 `75fcb698`、R5 `9a0312a0`、R6 `3026f9bb`、R7 `233727d5`、R8 `bd252782`；realloc 96→87） | DEV | **无**（R1/R2 审计已由 REQ 复核；c/d 类由 DEV 自判，REQ 事后验收） | 同上 §3、[审计表](../../design/s8b-rem-audit.tsv) |
| Q-7 | S8「拼写表迁 `LModulePlan`」 | **立项（`planned`，未开工）** | ARCH 出 ADR（拟 `D-033`）→ DEV | 实施排在 S8B-REM-1 R8 之后；排期口径见下注 | [REQ-SPELL-1](../../planning/requirements-pool.md)、差异清单 §3d |
| Q-7 | S8「拼写表迁 `LModulePlan`」 | **立项（`planned`，未开工）** | ARCH 出 ADR（拟 `D-033`）→ EDITOR 签收 → REQ 排期 → DEV（签收口径已对齐，见 Q-12 注） | 实施排在 S8B-REM-1 R8 之后；排期口径见下注 | [REQ-SPELL-1](../../planning/requirements-pool.md)、差异清单 §3d |
| Q-8 | I2 接口值下标（两阶段） | **`D-034` 已签收（accepted）；DEV 可按 I2-1…I2-5 开工** | ARCH 起草 `D-034`（已完成）→ EDITOR 签收（口径已对齐）→ REQ 排期 → DEV | 施工卡 [I2-C1](../../design/i2-interface-subscript-construction.md) §9；起草输入见 [D-034 输入包](../../design/i2-d034-drafting-input.md) | [REQ-I2-1](../../planning/requirements-pool.md)、[RFC 评估 §3.1](../../reviews/2026-11-27-indexable-rfc-evaluation.md) |
| Q-9 | dist 产物冒烟 | **已完成**（`0911029a`；本地方案 B 复跑通过，见下注） | DEV（CI/构建） | 无 | 卡 §7.3；口径见本节末注 |
| Q-10 | `v1.2.0` annotated tag + release | 待开（仅所有者） | 所有者 | 收口提交已推送；§7.5 五项校验 | 卡 §7.5 |
| Q-11 | TEST-27 / DESIGN-1 状态 | 待复核 | **REV 出评审结论 → EDITOR 签状态**（T-8：状态词由 REVIEW 写、EDITOR 签） | 证据包 | 本文 §1 |
| Q-12 | LANG-31（常量键折叠，I1） | **已完成**（D-031 accepted + issue verified；附条件 C1–C4 作为 DEV 后续补测，不阻塞） | DEV 初稿 → ARCH 技术审定（已完成）→ **EDITOR 签收** → REQ 排期 → DEV（T1–T5 已完成） | spec §4.79（已落）；D-031 §8 附条件待补探针；签收口径已对齐（`f0ce1746` + `b4f3a568`） | [D-031](../../decisions/D-031.md)、[LANG-31](../../../issues/lang/lang-31-const-key-fold.md)、[REQ-INDEXFOLD-1](../../planning/requirements-pool.md) |
| Q-13 | 补 S8b R1/R2 的收官报告节（`dogfooding` §3.8：LOC/`snprintf` 前后、审计表引用） | **已完成**（`9eb519c4`） | DEV | **无** | [S8B 施工卡](../../design/s8b-remaining-construction.md) §4 第 6 条 |
| Q-14 | T-8 门禁允许 EDITOR 签收 ADR（B1） | **已完成**（`f0ce1746`；待 EDITOR 审核） | REQ（所有者 2026-11-28 授权直接修复）→ EDITOR | 无 | 本节 Q-12 注；`test/docs/check-docs.py` |
| Q-15 | ADR 规范对齐（B2：`AGENTS §0.7` + 规范矩阵 + sha pin） | **已完成**（`b4f3a568`；待 EDITOR 审核） | REQ（所有者授权直接修复）→ EDITOR | 外部主规范副本需 EDITOR 后续同步（见注） | `AGENTS.md`、`docs/spec/ai-coding-workflow.md` |
| Q-16 | E-V3-9b 条件通过裁定（方案 A） | **已完成**（REQ 2026-11-28 裁定；待 REV 补签） | REQ 裁定 → REV 补 `dogfooding §3.8` 计数与抽查 → REV 签 | 无 | [REV 现状评估](../../reviews/2026-11-28-review-priority-assessment.md) §2；卡 §6 E-V3-9b |

> **Q-7 排期口径（2026-11-28）**：本条是架构债、无用户可见收益，**不进 1.2 窗口**
> （窗口已由 I1/I2 占满）；建议放在 `v1.2.0` tag 之后的技术债批，不单独立版本。三步：
> ① 阶段 0（可立即并行、不占 DEV）ARCH 起草 `D-033`，定拼写表字段、不变量、作用域与
> "生成 C 逐字节不变"判据，**EDITOR 签收**后由 REQ 排期（ARCH 不得缺位，不再由 REQ/DEV 代笔）；
> 与 `D-034` 同批以减少往返；② 阶段 1 DEV 在 S8B-REM-1 R8 之后开工，切片为
> S1 盘点+拼写表字段 → S2 `write_abi_header` → S3 `emit_adt_life_defs`（差异清单里
> 原名 `emit_drop_defs`）→ S4 map prologue + 删残留 `sym->`，每片沿用 S8B §4 统一验收
> （`CT_C_BOUNDARY=allow` goldens 25/25、`check-ast`、自举 fixpoint 2 轮、`check-seed`
> 两轮、`check-all` 8 门、`check-warnings` 0）；③ 阶段 2 REV 只读复核 → EDITOR 落状态。
> 与 R5/R7（`Symbols` 表转 `Vec`）共用读取点，必须让它们先行。REQ 盘点输入：
> `backend/emit/**` 现约 361 处 `sym->`，本条只涉 ABI header / ADT 生命周期 / map prologue
> 三条路径，逐条清单由 S1 冻结。本条等待 ARCH **不阻塞** S8B R3–R8 与 I1。
>
> **Q-8 排期口径（2026-11-28）**：完整排期表见 [I2-C1 §9](../../design/i2-interface-subscript-construction.md)。
> 前置链：`D-034`（ARCH 起草）→ **EDITOR 签收** → REQ 排期 → **I2-1 语法位 → I2-2 只读解析检查
> （E-V3-9e）→ I2-3 发射与跨单元**，然后 **I2-4 写入（E-V3-9f）** → I2-5 文档样例
> （REQ 落 spec/glossary/matrix，DEV 给夹具与实测，REV 复核）。每片独立提交、片末
> `gen-seed.sh` + `check-seed`；`v1.2.0` tag 在 I1 与 I2 两阶段都落地后由所有者执行。
> 串行点：I1 的 `T1`/`T2` 与 I2-2 共用 D-028 解析表，**I1 先落、I2-2 再改同一函数**；
> 与 S8B R3–R8 文件集不重叠可并行。`D-034` 未签期间 DEV 继续 S8B、Q-13，不空转；
> **ARCH 不得缺位**（所有者 2026-11-28 裁定）：不再采用 REQ/DEV 代笔 ADR 的临时口径。
>
> **Q-8 ARCH 起草结果（2026-11-28，子 Agent 执行 ARCH 角色）**：`D-034` 已入库，D1–D10 全部定案——
> ① **D1=(i) 保持分裂**：具体类型只认固有 impl，接口值只认 trait 的 `index`（`JsonStore j` 即使
> 实现带 `index` 的 trait，`j["x"]` 仍按 D-028 拒绝）；② 标记仅在 trait 方法 `)` 后、`;` 前；
> ③ 接口值按键静态类型分派；④ 阶段一写形态一律拒；⑤ 阶段二**只有 trait 声明了
> `void set(K,V) index` 才可写**，否则编译期硬错（不存在运行期“只读实现”分支）；⑥ 所有权按签名；
> ⑦ `set` 仅 `void`；⑧ 同键重复硬错；⑨ 标记随 `pub trait` 进公开头；⑩ 不新增槽、不承诺 ABI。
> **技术更正**：字符串字面量静态类型是 `char *`，`s["name"]` 只命中 `get(char *) index`；
> RFC §3.1.1 已加更正注，I2-C1 §10 的夹具样例与负例已改。**待 EDITOR 签收**；签收前 I2 不动代码。
>
> **Q-9 立项口径（所有者 2026-11-28 选 C）**：在 CI 增加一步——用 `selfhost/make-dist.sh`
> 产出 `ct-linux-x64.tar.gz`，**解包后用包内的 `ct`** 跑 `ct -v` 与 `examples/50_ref_out`
> （期望 `2 3 4`）、`examples/52_box_new`（期望 `4 4`）；测的是"上传的那份产物"，
> 不是 CI 重新构建的二进制。
>
> 本地复跑记录（**方案 B，2026-11-28**）：`zig cc -target x86_64-linux-musl -static` 交叉构建
> `ct-linux-x64.tar.gz`（sha256 `c59acea527260591e11a64f1263c5dca79d44069caff9adc806be0a6542c4509`），
> 在 Podman `ct-ci:24.04` 容器内经 binfmt `qemu-x86_64` 运行包内 `ct`：`ct v1.2.0`、
> `50_ref_out → 2 3 4`、`52_box_new → 4 4` 全部通过。两个环境坑：① Podman VM 必须与
> `podman run` 在同一次终端会话内启动（会话结束 VM 即停，这是先前 `53316` 拒绝连接的原因）；
> ② 容器内从仓库根运行或设 `CT_CORE_DIR=<repo>/lib/core`，否则 `Str` 等内置类型找不到。
> CI 仍是最终判据；本地复跑只作提前验证。
>
> **Q-12 签收口径（所有者 2026-11-28 选定方案 a）**：ADR 走 **ARCH 技术审定 → 主编 EDITOR
> 签收 → REQ 排期**；`D-031` 已有 DEV 初稿（`b6fe515d`），按该路径转交。落地依赖两项前置：
> 1. **门禁扩展（已完成 `f0ce1746`，待 EDITOR 审核）**：`test/docs/check-docs.py` 的 T-8
>    原对 ADR 只接受 `REQ/REVIEW/USER`；现删去拒 `EDITOR` 的分支、报错文案改为
>    `EDITOR/REVIEW/USER`、docstring 同步。所有者 2026-11-28 授权 REQ 直接修复；
>    临时 ADR 探针（`签收：EDITOR`）跑 `check-docs` 通过后已删除；
> 2. **规范对齐（已完成 `b4f3a568`，待 EDITOR 审核）**：① [AGENTS.md §0.7](../../../AGENTS.md#07-主编签收项目加严t-8)
>    拆出 ADR 行（ARCH → EDITOR；battle 判决维持原行）；② [ai-coding-workflow §5.2](../../spec/ai-coding-workflow.md#52-矩阵)
>    的「决策记录」列同步拆分并加口径注；③ `docs/spec` 的 sha256 pin 已随副本更新。
>    **遗留**：外部主规范副本（`~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md`）不在本仓，
>    需 EDITOR 在下次 `sync-agents.sh` 前把同一改动带回主规范，否则刷新块会覆盖本仓口径。
> 门禁与规范已对齐；`D-031` 头部暂按过渡行处理，**待 ARCH 技术审定后由 EDITOR 落签**。
> 同一口径适用于 `D-033`（Q-7）与 `D-034`（Q-8）。
>
> **Q-15 规范改造口径（2026-11-28）**：工程规范正在拆分为 **AI engineering** 与 **engineering**
> 两份外链文件，`AGENTS.md` 将只保留项目自身特殊规定。本次落在本仓 `AGENTS §0.7` 与
> `docs/spec §5.2` 的口径（ADR = ARCH 写、EDITOR 签），在拆分完成后应落到 **engineering**
> 文档的对应节；旧主规范路径（`~/trae-ws/.ai-engineering/methodology/ai-coding-workflow.md`）
> 在拆分落地后作废。`docs/spec` 副本与 sha pin 的同步由 EDITOR 在拆分时一次完成。
>
> **Q-12 审定输入**：`D-031` 的 ARCH 技术审定包已备在
> [2026-11-28-d031-arch-review-packet](../../reviews/2026-11-28-d031-arch-review-packet.md)
> （四问 + 证据 + 边界/风险 + 待填结论）；ARCH 出结论后由 EDITOR 落签。
>
> **Q-12 REQ 验收（2026-11-28）**：`LANG-31` 的实现 T1–T5 已在 DEV 侧落地
> （`93b1bc2c`/`0c10bd2d`/`27becd9a`/`1ede1dce`，探针重钉 `9e4e87e4`），REQ 只读验收通过：
> 8 条探针（折叠 / 链式 / get 回退 / 三条负例 / 写形态 / Box 内部）+ `examples/70` 输出 `7 9`
> 且生成 C 无 `get`/临时；goldens 25/25、seed 两轮、`check-warnings` 622/0、`test/ir` 15 checks。
> **遗留（已闭）**：① `D-031` 已由 **EDITOR 落签**（2026-11-28，转 `accepted`；ARCH 技术审定
> 2026-11-28，接受附条件 C1–C4）；② issue 的 `verified` 已由 EDITOR 落（2026-11-28，依据 issue §7
> + D-031 §8）；③ 实现先于 ADR 签收，已在 [issue §7](../../../issues/lang/lang-31-const-key-fold.md#7-验收记录req2026-11-28) 如实登记。
> 附条件 C1–C4 仍由 DEV 后续补测，不阻塞。
>
> **Q-12 ARCH 审定结果（2026-11-28，子 Agent 执行 ARCH 角色）**：**接受、附条件 C1–C4**
> （临时量负例、`&p["x"]` 正例、前向声明探针、歧义仅“匹配且可见”的 private / 参数类型负例），
> R2 判定可接受（25 条用户语料 + 83 条 IR 语料零命中），要求把该 breaking 写入迁移项与 release note。
> 结论见 [D-031 §8](../../decisions/D-031.md)；附条件探针由 DEV 补、登记在
> [LANG-31 issue §7](../../../issues/lang/lang-31-const-key-fold.md#7-验收记录req2026-11-28)，不影响本次验收结论。
>
> **实施记录（2026-11-28，`0911029a`）**：`ci.yml` 新增 "distribution artefact smoke (Q-9)"
> 一步——`make-dist.sh --out /tmp/ct-dist` 出包、`tar -xzf` 解包、先跑包内 `ct -v`，
> 再用**包内 `ct`** 构建并运行 `examples/50_ref_out`（期望 `2 3 4`）与
> `examples/52_box_new`（期望 `4 4`）；期望不符即硬失败，不设跳过分支。本地已按方案 B
> 复跑通过（见上）；CI 首次运行仍是最终确认，若红先回退该步、不改判据。

**DEV 执行顺序（2026-11-28 排定，无外部阻塞）**

1. D-032 线：M1 ✅（`feb6caa5`）→ M2 ✅（`981f2ee9`）→ M3 ✅（`653dec09`，lib/core 8 → 0、
   seed 5 → 3）；**D032-C1 三片已全部落地**；REV 复核已出（评估 §1），D-032 签收包已更新为已签；
2. S8B R3–R8（Q-6）与 `dogfooding §3.8`（Q-13）：**均已完成**（R3 `e23338db` … R8 `bd252782`、
   §3.8 `9eb519c4`），DEV 侧无剩余动作；余 REVIEW 对 E-V3-9b 签字；
3. I1（Q-12）：**已完成**——DEV 实施 T1–T5、REQ 验收、ARCH 技术审定、**EDITOR 签收 `D-031`
   与 issue `verified`（均 2026-11-28）**；DEV 侧无剩余动作（附条件 C1–C4 的补探针另行补测）；
4. I2（Q-8）：`D-034` 已 **accepted**（ARCH 起草 2026-11-28、EDITOR 签收 2026-11-28），
   **I2-1 可立即开工**，DEV 按 I2-1 → I2-2（只读，`E-V3-9e`）→ I2-3 → I2-4（写入，`E-V3-9f`）
   → I2-5 实施，每片独立提交（见 [I2-C1 §9](../../design/i2-interface-subscript-construction.md)）。
   签收前不动代码的要求已完成；I1 的 `T1`/`T2` 已落，I2-2 直接改同一张解析表；
5. Q-7（拼写表）：**不进 1.2**，`D-033` 由 ARCH 起草、EDITOR 签收（与 `D-034` 同批更省往返）；
   实施排在 S8B R8 之后、`v1.2.0` tag 后的技术债批，见本节 Q-7 注；
6. REQ 的 spec / c-shim-contract 同步（M3 后）与 REV 的复核都**不进 DEV 前置**。

## 13 `v1.2.0` 发版就绪清单（REQ，2026-11-28）

> 用途：tag 前的单一勾选表；只记录状态与证据，**不改判据**（判据仍以卡 §3/§8 为准）。
> 状态词：`✅` 已就绪 / `🟡` 待办（不阻塞 tag） / `⛔` 阻塞 tag。

| # | 项 | 状态 | 负责 | 证据 / 命令 |
| --- | --- | --- | --- | --- |
| A1 | I1 `LANG-31` 实现 T1–T5 | ✅ | DEV | `93b1bc2c`/`0c10bd2d`/`27becd9a`/`1ede1dce`；REQ 验收见 [issue §7](../../../issues/lang/lang-31-const-key-fold.md#7-验收记录req2026-11-28) |
| A2 | `D-031` ARCH 技术审定 + EDITOR 签收 | ✅ | EDITOR | `D-031` 已 `accepted`：ARCH 技术审定 2026-11-28（附条件 C1–C4，[§8](../../decisions/D-031.md)）；EDITOR 2026-11-28 签收（非作者席位） |
| A3 | `LANG-31` issue 转 `verified` | ✅ | EDITOR | issue 状态 `verified`（2026-11-28，依据 [§7](../../../issues/lang/lang-31-const-key-fold.md#7-验收记录req2026-11-28) + D-031 §8）；附条件 C1–C4 由 DEV 后续补测，不阻塞 |
| A4 | `D-034` 起草 + 签收 | ✅ | EDITOR | [D-034](../../decisions/D-034.md) 已 `accepted`：ARCH 起草 2026-11-28（D1=(i) 分裂、D1–D10 定案）；EDITOR 2026-11-28 签收 |
| A5 | I2 阶段一（只读，`E-V3-9e`） | ⛔ | DEV | I2-1 → I2-3；验收清单见 [I2-C1 §10](../../design/i2-interface-subscript-construction.md#10-验收清单e-v3-9e--e-v3-9f) |
| A6 | I2 阶段二（写入，`E-V3-9f`） | ⛔ | DEV | I2-4；同属 1.2 |
| A7 | I2 文档（spec 新节 / 矩阵 / stable-subset） | ⛔ | REQ | I2-5；随 A5/A6 同步 |
| B1 | T-8 门禁允许 EDITOR 签 ADR | ✅（待 EDITOR 审核） | REQ（所有者授权） | `f0ce1746`；临时 ADR 探针验证通过后删除 |
| B2 | `AGENTS.md` §0.7 + 规范矩阵 + `docs/spec` sha pin | ✅（待 EDITOR 审核） | REQ（所有者授权） | `b4f3a568`；`g0` 绿（`sync-agents.sh` 不在本机，块体等价比对被跳过） |
| B3 | D-032 REV 只读复核 + EDITOR 落状态 | 🟡 | REV / EDITOR | M1–M3 已落地、REQ 验收全绿（shim 74 → 3） |
| B4 | S8B R3–R8（Q-6）与 `dogfooding §3.8`（Q-13） | ✅ | DEV / REV | R3 `e23338db` … R8 `bd252782`、§3.8 `9eb519c4`；现测 `realloc` 87、`snprintf` 292（Pkg 43 / Symbols 24）；**E-V3-9b 按方案 A 条件通过（SH-123 保留），待 REV 补 §3.8 计数与抽查后签** |
| B5 | 门禁全绿：8 门 / seed 两轮 / goldens 25/25 / warnings 0 / `test/ir` 15 / `check-docs` | ✅（I1 后） | DEV / REQ | I2 落地后必须重跑一遍再 tag |
| B6 | CI 首绿（含 Q-9 dist 冒烟） | 🟡 | DEV | `0911029a` 已入库；以首次 CI 结果为准 |
| C1 | `CTC_VERSION 1.2.0` | ✅ | — | `selfhost/ct-ast/main.ct` |
| C2 | `roadmap` 的 `v1-PH-2` 行转 ✅ | ⛔ | REQ | tag 前；现为 🟨 |
| C3 | I1 文档：spec §4.79 / 矩阵第 26 行 / stable-subset 冻结行 | ✅ | REQ | `367ba1a8` |
| C4 | I2 文档：spec 新节 / 矩阵行 / stable-subset 行 | ⛔ | REQ | 随 A7 |
| C5 | 流水账 `v1.2.0` 行与收口记录补 I1/I2 | ⛔ | EDITOR / REQ | `docs/history/phase-log.md` |
| C6 | `examples/README` 补 `70_const_key_fold` 索引行 | 🟡 | REV | `examples/` 不在 REQ 写权限内 |
| D1 | 从**最终源码**重出 dist 并更新 sha | ⛔ | DEV | 旧值 `98130730…`（卡 §7.3）已被 I1 改动；本机方案 B 实测为 `c59acea5…`，tag 前须以最终提交重出 |
| D2 | 分支推送（本地领先 `origin/main` 若干提交） | ⛔ | 所有者 / DEV | 卡 §7.5 第 ④ 项要求收口提交在远端 |
| D3 | annotated tag `v1.2.0` + 五项校验 | ⛔ | 所有者 | 卡 §7.5 |
| D4 | GitHub Release 与资产（可选） | 🟡 | 所有者 | 卡 §7.5；资产 sha 与 D1 一致 |

**当前缺口结论（2026-11-28）**：硬阻塞集中在 **A5–A7、C2、C4、C5、D1–D3**。
A2/A4 已完成（`D-031`/`D-034` 均 `accepted`，EDITOR 2026-11-28 签收；issue 已 `verified`）；
A5–A7 是 I2 本体；D1–D3 是发版动作。
I1 侧 DEV 已无剩余动作（ARCH 附条件探针另列）；S8B R3–R8 与 §3.8 已完成（E-V3-9b 待 REV 补签）；
Q-7（`D-033`）按裁定在 1.2 之后，不进本清单。
