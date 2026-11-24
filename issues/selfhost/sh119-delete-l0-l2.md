# SH-119 · 删除 L0/L1/L2：archive 改 sha256 清单，门禁链改为 seed + 静态 goldens

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（构建链 / 门禁 / 测试驱动） |
| 定性 | 架构清理（所有者 2026-11-24 裁定方案 C） |
| 严重度 | **High**（改动 gate 1–5、`test/run.sh`、`install.sh`、`check-ast` 探针） |
| 锚点 | `db4e6500`（`v1.0.0` 后；2026-11-24） |
| 依据 | 所有者裁定（A/B/C 中选 C）；[v1-PH-1](../../docs/phases/v1-PH-1/card.md)；[DOC-99](../docs/doc-99-v11-prework-tracker.md) |
| 状态 | verified |
| 负责人 | DEV |
| 处置证据 | **accepted（2026-11-24 所有者：全删 L0/L1/L2，`test/archive` 用 sha256 manifest 守）** |

## 1. 决策

1. 删除 `selfhost/l0/`、`selfhost/l1/`、`selfhost/l2/`；
2. `test/archive/` 的 46 个文件由 **`test/archive/MANIFEST.sha256`** 守（**已生成本轮**）；
3. gate 2 / 3 / 4 / 5 退役；gate 1 的被测编译器改为 seed 构建的 `ct`；
4. gate 8 里“ct-ast 编译 `selfhost/l0/ctc.c`”的探针删除，自举证据由 gate 13（seed 两轮）与 fixpoint 承担；
5. 历史可追溯：`git show v1.0.0:selfhost/l0/ctc.c` 等仍可取回；不重写 tag。

## 2. 影响面（实测）

| 对象 | 现状 |
| --- | --- |
| 脚本 | 12 个引用 `l0/l1/l2/ctc.c`：`check-all`、`check-archive`、`check-ast`、`check-goldens`、`check-goldens-ast`、`check-install`、`check-m2a`、`check-seed`、`ct-tour`、`gen-seed`、`test/run.sh`、`test/ast/p80_docs.sh` |
| 门禁 1 | [`test/run.sh:74`](../../test/run.sh) 用 `cc selfhost/l0/ctc.c` 构建被测编译器；删 L0 后必须换 |
| 门禁 8 | [`check-ast.sh:473`](../../selfhost/check-ast.sh#L473) 构建 L0 链；[`:7372`](../../selfhost/check-ast.sh#L7372) 用 `ctc.c` 作输入做 seed 探针 |
| `install.sh` | 仍有 L1/L2 的 legacy 分支（`l1_src` / `l2_src`） |
| 文档 | 119 个 `.md` 提到 `selfhost/l0/l1/l2`（含 AGENTS、README、architecture、history） |

## 3. 必须先解决的三件事

1. **gate 1 的替代**：`test/run.sh` 现以 L0 编译 `test/cases`。改为 seed 构建的 `ct`（或 `ct check/build`）后，
   要逐个确认 cases 仍能编译并产出相同 stdout；编不了的 case 标 `retired`，**不许静默删**。
2. **`ctc.c` 探针**：它是“ct-ast 能编 2966 行 C”的能力证据。删除前确认 gate 13 的 seed 两轮 + `p88_fixpoint`
   覆盖等价；若不等价，保留一份 `ctc.c` 副本作为**纯输入夹具**（放 `test/`，不再当编译器）。
3. **archive manifest 门禁**：新增一条“目录哈希与 manifest 一致”的校验，挂在 gate 12 内（**不新增门禁编号**）；
   负例：改一个字节必须红。

## 4 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S1 红 | manifest 校验负例（改字节变红）；`test/run.sh` 改被测编译器后的失败清单 | 两条红证入库（含 `baseline: <sha>`） | M |
| S2 删 L1/L2 | 删目录；`check-goldens` / `check-archive` / `check-m2a` / `ct-tour` 退役或改写；`check-all` 去掉对应 `run_gate` | `check-all` 绿；门禁数变化同步 README/docs | M |
| S3 删 L0 | 删目录；`install.sh` 去 legacy 分支；`check-ast` 去 ctc 构建与探针（或改为 `test/` 输入夹具） | 干净目录 `./install.sh` 仍能装；`ct -v` = 当前版本 | M |
| S4 文档 | 119 处引用改为历史说明或删除；`architecture.md` 的“只覆盖 L0”章节退役 | `check-docs` 绿；无死链 | M |
| S5 收口 | 全量 `check-all`；记录门禁新数量 | 全绿；`g8-version` 绿（**零版本移动**） | S |

## 5 验收

- `selfhost/l0`、`l1`、`l2` 三个目录不存在；`grep -rn 'selfhost/l0\|selfhost/l1\|selfhost/l2'` 只剩历史文档；
- `test/archive/MANIFEST.sha256` 46 行，校验门禁有正负例；
- gate 1 用 seed-built `ct` 跑完 `test/cases`，输出与旧口径一致或逐条登记 `retired` 理由；
- `check-all` 全绿，门禁数量与实际一致（README / docs/README / glossary / issues/README）；
- 不改语言语义、不改生成物、不 bump `CTC_VERSION`。

## 6 非目标

- 不重写 `test/archive` 的期望文件（只加 manifest）；
- 不动 seed（`bootstrap/ct-ast`）与 gate 13；
- 不在本卡改 v1.1 的语言面（LANG-26/28）；
- 不删除 `docs/history` 与历史 tag 里的引用。

## 7 关联

- [v1-PH-1](../../docs/phases/v1-PH-1/card.md)（v1.1 范围）
- [DOC-99](../docs/doc-99-v11-prework-tracker.md)（前置准备，本卡不属准备项）
- [D-022](../../docs/decisions/D-022.md)（seed 策略）
- [SH-105](sh105-goldens-static-freeze.md)（静态 goldens，gate 12 的来源）


## S1 切片（2026-11-24，DEV）

已完成 **manifest 校验 + 负例**，未删任何目录：

- 新增 `selfhost/check-archive-manifest.sh`：46 行 manifest 逐文件 sha256；缺文件/摘要不符/未列文件均红；
- `--selftest`：干净副本绿、追加一字节红、删除一文件红；
- 挂进 gate 12 `selfhost/check-goldens-ast.sh`（不新增门禁号），gate 12 仍 `25/25` 且输出 `archive-manifest: OK (46 files)`；
- 本切片只加校验与负例，未改 `test/run.sh`、未改构建链、未动版本。


## S2 收口（2026-11-24，DEV）

- 删除 `selfhost/l1`、`selfhost/l2` 与 gate 2–5 脚本（`check-goldens`/`check-archive`/`check-m2a`/`ct-tour`）；
- `check-all` 保留原编号、移除 4 个 `run_gate`，硬门禁 **13 → 9**；
- `check-ast` 删除 L0→L1→L2 oracle 构建与 L2 对差分支；`gen-seed` 去掉无 seed 的旧链 fallback；
- 门禁计数同步 README/docs/AGENTS/glossary/selfhost README/issues README；历史引用走 check-docs 的 SH-119 豁免，S4 再清；
- `check-all: OK (9 hard gates green)`；`check-docs` OK；`check-install` 在 S2 提交后复跑。


## S3 收口（2026-11-24，DEV）

- 删除 `selfhost/l0`；`install.sh` 已无 L0/L1/L2 legacy 分支（S1/S2 完成）；
- `test/run.sh` 改为 seed-built `ct`：seed 构建、版本、25 个 `test/cases` 编译 + `cc -c`、`examples/01` 端到端；
  L0 专属 unit/dialect/CLI 夹具随 L0 退役，语料覆盖由 gate 12 静态 goldens + gate 8 check-ast 承担（未静默删 fixture）；
- `check-ast` 删除 L0 seed 探针；`examples/c-superset` 的 L0 构建改 seed；版本落点收敛到 `selfhost/ct-ast/main.ct`；
- `check-install` 版本源改 ct-ast、检查 L1/L2 已退役；`gen-seed` 无 seed 时只报错；
- 门禁数仍 9（gate 1 保留，gate 2–5 退役）。


## S4/S5 收口（2026-11-24，DEV）

- S4：`docs/architecture.md` 重写为 ct-ast 架构（L0 章节退役）；test/selfhost/glossary/design 的 L0/L1/L2 活跃引用改为历史说明；历史链接改指 v1.0.0 历史或代码跨度；删除 check-docs 的 SH-119 临时豁免。
- S5：`check-all: OK (9 hard gates green)`；`check-docs` OK（9 gates）；`check-install`、`check-seed` 绿；`g8-version` 绿（零版本移动）。
