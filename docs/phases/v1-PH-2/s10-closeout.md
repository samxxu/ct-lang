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
| G-2 | S8b 生成 C 可读性 | REVIEW 签字（E-V3-9b） | REV |
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
| Q-6 | S8B-REM-1 R3/R4（取值 API、lock 字段）与 R5–R7（三大表）、R8（判别式） | 待开 | DEV | **无**（R1/R2 审计已由 REQ 复核；c/d 类由 DEV 自判，REQ 事后验收） | 同上 §3、[审计表](../../design/s8b-rem-audit.tsv) |
| Q-7 | S8「拼写表迁 `LModulePlan`」 | **立项（`planned`，未开工）** | ARCH 出 ADR（拟 `D-033`）→ DEV | 实施排在 S8B-REM-1 R8 之后；排期口径见下注 | [REQ-SPELL-1](../../planning/requirements-pool.md)、差异清单 §3d |
| Q-8 | I2 接口值下标（两阶段） | **四问已裁定；待 ADR `D-034`** | ARCH 起草 `D-034` → DEV | 施工卡 [I2-C1](../../design/i2-interface-subscript-construction.md) 已交 | [REQ-I2-1](../../planning/requirements-pool.md)、[RFC 评估 §3.1](../../reviews/2026-11-27-indexable-rfc-evaluation.md) |
| Q-9 | dist 产物冒烟 | **立项（`planned`）** | DEV（CI/构建） | 无 | 卡 §7.3；口径见本节末注 |
| Q-10 | `v1.2.0` annotated tag + release | 待开（仅所有者） | 所有者 | 收口提交已推送；§7.5 五项校验 | 卡 §7.5 |
| Q-11 | TEST-27 / DESIGN-1 状态 | 待复核 | **REV 出评审结论 → EDITOR 签状态**（T-8：状态词由 REVIEW 写、EDITOR 签） | 证据包 | 本文 §1 |
| Q-12 | LANG-31（常量键折叠，I1） | **待开（2026-11-28 撤回 deferred）** | DEV | ADR `D-031` + spec §4.79（施工卡已有） | [LANG-31](../../../issues/lang/lang-31-const-key-fold.md)、[REQ-INDEXFOLD-1](../../planning/requirements-pool.md) |
| Q-13 | 补 S8b R1/R2 的收官报告节（`dogfooding` §3.8：LOC/`snprintf` 前后、审计表引用） | 待开 | DEV | **无** | [S8B 施工卡](../../design/s8b-remaining-construction.md) §4 第 6 条 |

> **Q-7 排期口径（2026-11-28）**：本条是架构债、无用户可见收益，**不进 1.2 窗口**
> （窗口已由 I1/I2 占满）；建议放在 `v1.2.0` tag 之后的技术债批，不单独立版本。三步：
> ① 阶段 0（可立即并行、不占 DEV）ARCH 起草 `D-033`，定拼写表字段、不变量、作用域与
> "生成 C 逐字节不变"判据；ARCH 长期不在场时参照 `D-030` 由 REQ 起草、REV 签收，
> 并与 `D-034` 同批以减少往返；② 阶段 1 DEV 在 S8B-REM-1 R8 之后开工，切片为
> S1 盘点+拼写表字段 → S2 `write_abi_header` → S3 `emit_adt_life_defs`（差异清单里
> 原名 `emit_drop_defs`）→ S4 map prologue + 删残留 `sym->`，每片沿用 S8B §4 统一验收
> （`CT_C_BOUNDARY=allow` goldens 25/25、`check-ast`、自举 fixpoint 2 轮、`check-seed`
> 两轮、`check-all` 8 门、`check-warnings` 0）；③ 阶段 2 REV 只读复核 → EDITOR 落状态。
> 与 R5/R7（`Symbols` 表转 `Vec`）共用读取点，必须让它们先行。REQ 盘点输入：
> `backend/emit/**` 现约 361 处 `sym->`，本条只涉 ABI header / ADT 生命周期 / map prologue
> 三条路径，逐条清单由 S1 冻结。本条等待 ARCH **不阻塞** S8B R3–R8 与 I1。
>
> **Q-9 立项口径（所有者 2026-11-28 选 C）**：在 CI 增加一步——用 `selfhost/make-dist.sh`
> 产出 `ct-linux-x64.tar.gz`，**解包后用包内的 `ct`** 跑 `ct -v` 与 `examples/50_ref_out`
> （期望 `2 3 4`）、`examples/52_box_new`（期望 `4 4`）；测的是"上传的那份产物"，
> 不是 CI 重新构建的二进制。
>
> 本地尝试记录：macOS + Podman（libkrun，linux/amd64）在 `machine start` 后端口短暂可连、
> 随后 gvproxy 转发消失（`127.0.0.1:53316` connection refused，krunkit 进程仍在），
> **本机冒烟受阻于环境，不作为结论**；以 CI 步骤为准。

**DEV 执行顺序（2026-11-28 排定，无外部阻塞）**

1. D-032 线：M1 ✅（`feb6caa5`）→ M2 ✅（`981f2ee9`）→ M3 ✅（`653dec09`，lib/core 8 → 0、
   seed 5 → 3）；**D032-C1 三片已全部落地**，余 REV 只读复核与 EDITOR 落状态；
2. 可并行：S8B R3–R8（Q-6）、dogfooding §3.8（Q-13），与 D-032 线文件集不重叠；
3. I1（Q-12）：`D-031` 由 **DEV 起草**（先例 [D-030](../../decisions/D-030.md)，DEV 起草、REV 签收），
   **不等 ARCH**；签收后按 `T1–T5` 开工；
4. I2（Q-8）：`D-034` 由 **ARCH 起草**；ARCH 不在场时 **I2 停在这里**，不阻塞第 1–3 项；
5. Q-7（拼写表）：**不进 1.2**，`D-033` 可随时由 ARCH 起草（与 `D-034` 同批更省往返）；
   实施排在 S8B R8 之后、`v1.2.0` tag 后的技术债批，见本节 Q-7 注；
6. REQ 的 spec / c-shim-contract 同步（M3 后）与 REV 的复核都**不进 DEV 前置**。
