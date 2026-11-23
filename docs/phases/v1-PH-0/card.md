---
phase-id: v1-PH-0
version-minor: 0
---

# v1-PH-0 — v1.0 AST-only 收口（seed cutover）

> **状态：规划中**（seed 策略已于 2026-11-23 裁定，见 [D-022](../../decisions/D-022.md)；施工未开工）。
> **签收：** 待 EDITOR/REVIEW 复核 seed 裁定与卡片冻结字段（T-8 对 `实施中` 卡生效，本卡未开工不触发门禁）。
> **前置**：v0-PH-88 收口（`v0.88.3`）；[D-022](../../decisions/D-022.md)（seed = 冻结 ct-ast 生成的 C）。
> **编号**：`v1-PH-0`，`version-minor = 0`；phase-ID 迁移已执行（DOC-74 / DOC-83，D-019），本卡位于 `docs/phases/v1-PH-0/card.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | `v1-PH-0`（`MINOR = 0` ↔ `v1.0.0`） |
| 目标 | v1.0：ct-ast 的构建与安装改走“冻结 seed → ct-ast”，L1/L2 降为回归 oracle；v1.0 硬门禁证据齐全后发 MAJOR |
| 范围 | seed 冻结与重建门禁、`install.sh`/`check-ast` 改由 seed 构建 ct-ast、L1/L2 降为回归 oracle、FP=0 证据、文档与版本收口 |
| 非目标 | 删 L1/L2 源码（另立卡，不进 v1.0）；改语言语义/发射格式/命名契约；A 的默认强制（v1.1 S2）；Typed IR（v1.2）；M1 精细切分（v1.1 S1） |
| 交付物 | `bootstrap/ct-ast/` + manifest、gate 13 `check-seed.sh`、切换后的 `install.sh` 与 `check-ast` 构建段、FP=0 证据、v1.0.0 tag |
| 任务清单 | §2（S0–S5，四列齐全） |
| 退出判据 | E-V1-1…E-V1-9（§3） |
| version-minor | 0 |
| 已知风险 | R-V1-1…R-V1-5（§4） |

## 1 seed 裁定（已定，不再讨论）

按 [D-022](../../decisions/D-022.md)：

1. seed = `bootstrap/ct-ast/`（27 个 `.c` + 26 个头，约 50,945 行 / 2.3 MB），由收口版 ct-ast 生成，
   每个 release tag 重新生成一次；只读，手改由 gate 13 判红。
2. `install.sh`：`cc bootstrap/ct-ast/*.c -o ct`；`ctc` 兼容别名保留。
3. L1/L2 **保留为独立回归 oracle**（gate 2/3/4/5 自建自测），但不再参与 ct-ast 的构建与安装；
   删源码另立卡，不进 v1.0。原因：`match` 进 ct-ast 后 L2 编不了（D-022 §2.2），
   降为 oracle 后两者可共存。
4. L0 `selfhost/l0/ctc.c` 保留，继续支撑旧链 gate，并作为不同源的对照。
5. 新增 gate 13；gate 2/3/4/5 保留，只改 `check-ast` / `ct-tour` 里“L2 构建 ct-ast”那一步（D-022 §4）。

实测依据（A 案 L0 无 `import`；B′ 案的 L2 对 ADT/`match` 透传；B 案两轮生成逐字节一致）
见 D-022 §2，不再复述。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S0 seed 冻结 | `bootstrap/ct-ast/*.c`、`bootstrap/MANIFEST.sha256`、生成脚本或命令记录 | `sh selfhost/check-seed.sh` 红→绿；两轮重建逐字节 | M |
| S1 `install.sh` 切换 | 删 L0→L1→L2 段，改 `cc bootstrap → ct`；`ctc` 别名 | 干净目录 `./install.sh --prefix /tmp/ctv1` 后 `/tmp/ctv1/ct -v` = `v1.0.0` | S |
| S2 构建路径切换 | `install.sh` 与 `check-ast` 的 ct-ast 段改由 seed 构建；`ct-tour` 第 7 步同步；L1/L2 保留为 oracle | `check-all` 绿；`grep -n 'l2' install.sh` 无构建 ct-ast 的引用 | M |
| S3 门禁 | 新 gate 13 `check-seed.sh`；gate 2/3/4/5 保留且绿；gate 12 独立可跑 | 门禁计数 13 同步四处文档；负例（改一个字节）判红 | M |
| S0.5a `match` 发射器 | 76 个 `em_*` 切片改为「一 kind 一臂、共用体调同一 helper」的穷尽 `match`；`p88_emit` 清单改臂 | `p88_emit` 红→绿；66 语料逐字节；`match does not cover variant` 负例 | M |
| S0.5b `match` 判别助手 | `expr_ctype`/`maybe_box`/`chk_type` 的 kind 判别改为穷尽 `match`；负例覆盖缺臂 | 红→绿；345 诊断逐字；自举 2 轮逐字节 | M |
| S4 v1.0 硬门禁证据 | 全量语料 FP=0 的命令与原始输出（[SH-118](../../../issues/selfhost/sh118-full-corpus-fp-zero.md)）；J-6 剩余夹具与 J-4b 条款（[SH-117](../../../issues/selfhost/sh117-j6-local-closeout.md)）；P-3.5 处置 | 证据入库；J-6 台账无 `缺失` | L |
| S5 文档/版本/收口 | README/spec/安装与迁移说明；`v1.0.0` bump；新 MAJOR 签字 decision；tag | `check-all` 13/13 绿；README 版本断言通过；tag 指向收口提交 | M |

每项先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`）；S5 的纯文档部分可写
`no-test: 文档与版本`,由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E-V1-1 | `bootstrap/ct-ast/` 由 ct-ast 生成且两轮重建逐字节一致；纯 `cc` 可构建可运行的 `ct` |
| E-V1-2 | `install.sh` 不引用 L0/L1/L2；无网络、无 git、干净环境可安装 |
| E-V1-3 | ct-ast 的构建/安装路径不依赖 L2：`install.sh` 与 `check-ast` 的 ct-ast 段均吃 seed；L1/L2 只作 oracle |
| E-V1-4 | `check-all` 13 道全绿：gate 2/3/4/5 照旧、gate 12 独立、gate 13 有正负例 |
| E-V1-5 | 全量语料 `--check-level=warn` FP=0 的命令、清单与原始输出入库（[SH-118](../../../issues/selfhost/sh118-full-corpus-fp-zero.md)） |
| E-V1-6 | J-6 **本仓段**无 `缺失` / `部分`（[SH-117](../../../issues/selfhost/sh117-j6-local-closeout.md)）；`外部` 段（P-3.6 / P-6.1–P-6.4）不计入；`阻塞` 仅 P-1.3（迁移 lint，归 v1.x；所有者 2026-11-23 已裁定可带此阻塞发布） |
| E-V1-7 | DOC-76/77/79 的兼容承诺、能力节号、冻结清单断言全绿；README 版本 = `v1.0.0` |
| E-V1-8 | 单卡回滚：`bootstrap/` + `install.sh` + 门禁改动同一提交回滚后，`v0.88.3` 链路仍可用 |
| E-V1-9 | tag 前 3 轮自举逐字节一致（复用 `check-ast` fixpoint，轮数参数化） |
| E-V1-10 | 76 个发射器切片与 `expr_ctype`/`maybe_box`/`chk_type` 已改为穷尽 `match`；`p88_emit` 以臂计数；缺臂负例红；66 语料逐字节 |

## 4 风险与回滚

| # | 风险 | 处置 |
| --- | --- | --- |
| R-V1-1 | 2.3 MB 生成物进仓 | 只在 release 提交更新；gate 13 判手改 |
| R-V1-2 | seed 出问题时没有第二条路 | L1/L2 保留为 oracle；回退时 `install.sh` 单提交回到旧链 |
| R-V1-3 | 门禁计数 12→13 漂移 | 四处计数断言同批改；`check-docs` 会红 |
| R-V1-4 | J-6 本仓段夹具未清零（`P-3.5` / `P-5.x` / `J-4b`） | DEV 补夹具与条款；外部段已转 std 包，不再影响 v1.0 |
| R-V1-5 | 新语法让旧 seed 解析不了 | 一步自举；必要时两阶段 bootstrap，单独记录 |

回滚：S0–S3 可分阶段回滚；S5 的版本提交与 tag 单独回滚，不回退 seed 目录。

## 5 关联

- [D-022](../../decisions/D-022.md)（seed 策略）
- [v1 路线](../../planning/v1-release-plan.md) §1.2–§1.5
- [SH-105](../../../issues/selfhost/sh105-goldens-static-freeze.md)（静态 goldens）
- [SH-104](../../../issues/selfhost/sh104-j6-evidence-ledger.md)（J-6 台账）
- [SH-117](../../../issues/selfhost/sh117-j6-local-closeout.md)（J-6 本仓段收尾）
- [SH-118](../../../issues/selfhost/sh118-full-corpus-fp-zero.md)（全量 FP=0 证据）
- [battle/p88-emit-match](../../../battle/p88-emit-match/verdict.md)（字面 `match` 引入 ct-ast）
- [编号提案](../../proposals/phase-numbering-major-reset.md)、[迁移 blocker](../../planning/phase-migration-blockers.md)
