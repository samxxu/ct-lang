# Phase 88 — v1-pre：发射器重写 + 自举回环

> **状态：完成**（2026-11-21 收口；`v0.88.0`；E88-1 部分通过，承接见 §3.1）。
> **签收：EDITOR 2026-11-21**（主编统一签收；卡作者 REQ）；收口复核待 REVIEW（§7）。
> **施工闸门**：PH-87 已收口（`47a8f786`，REV PASS）；S88a–S88d 已施工。
> **前置**：PH-87；[D-017](../decisions/D-017.md)（两级判据、自举轮数参数化）。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase88.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-88（legacy 文件 `phase88.md`） |
| 目标 | 发射器按最终惯用法重写；扩展自举不动点（轮数参数化）；给出 v1-pre 收口证据 |
| 范围 | 发射器函数集重写、tag 判别→`match`、String 拼接、fixpoint 2/3 轮、度量报告 |
| 非目标 | 改发射格式/命名契约/ABI；改语言语义；M1 精细切分；v1.0 收口本身 |
| 交付物 | 发射器重写、`test/ast/p88_*`、扩展 fixpoint、度量报告、v1-pre 证据摘要 |
| 任务清单 | §2（S88a–S88d） |
| 退出判据 | E88-1…E88-8（§3） |
| version-minor | 88（PH-88，`d=0`） |
| 已知风险 | R88-1…R88-5（§4） |

## 1 需求与边界

### 1.1 重写内容

- 发射器函数集切片重写：`switch`/`if` 链中的 tag 判别换穷尽 `match`；
- 手写可增长 buffer / 格式化拼接按适用性改用 `String`；
- 错误路径 `?`/errdefer；不改发射格式与命名契约。

### 1.2 自举回环（D-017/D8）

- 复用 `check-ast` 的 §9.6 不动点段，**轮数参数化**：
  - 日常/每切片 2 轮；
  - v1.0 tag 前 3 轮；
- 同一套比对逻辑，零代码分叉；不新建脚本。

### 1.3 等价判据（D-017 A1）

- 测试语料发射产物逐字节不变；
- 编译器自身实现的发射 C 允许差异；验收 = 自举不动点 + ASan + 行为测试；
- 期望文件集合基线 + 旧→新映射保持有效（M0 后若变化需更新）。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S88a 发射器重写 | 函数集切片；tag→`match`；String 拼接 | `p88_emit` | M |
| S88b 自举回环 | fixpoint 轮数参数化（2/3） | `p88_fixpoint` | M |
| S88c 度量/证据 | 行数、编译耗时、sharp edge 汇总 | `p88_metrics` | S |
| S88d 文档/收口 | spec/tutorial 发射片段；v1-pre 证据摘要 | `p88_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S88c/S88d 可写 `no-test:`，由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E88-1 | 发射器函数集重写完成；tag 判别换穷尽 `match` |
| E88-2 | 测试语料发射逐字节不变；编译器自身发射差异按两级制处理 |
| E88-3 | fixpoint 轮数参数化：日常 2 轮、v1.0 tag 前 3 轮；同一比对逻辑 |
| E88-4 | 行数/编译耗时/sharp edge 报告落 `history/`，对照 PH-85 spike |
| E88-5 | `check-all` 全绿；ASan 通过；无新增警告 |
| E88-6 | 集合基线/映射仍有效，或已按 D-017 A2 更新 |
| E88-7 | spec/tutorial 发射相关段落同步；v1-pre 证据摘要入库 |
| E88-8 | 单卡回滚：发射器可退回旧实现，输出与 v0.87 一致 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R88-1 | 发射器重写改变 C 形态 | 两级判据；测试语料逐字节；行为测试 |
| R88-2 | fixpoint 轮数增加拖慢 CI | 参数化：日常 2 轮，tag 前 3 轮 |
| R88-3 | String 拼接引入分配/性能回退 | 度量报告；必要时局部保留 buffer |
| R88-4 | 集合基线随重写漂移 | A2 映射；同一 commit 更新 |
| R88-5 | 顺手改发射格式/ABI | 非目标写死；diff 审阅 |

回滚：单卡回滚；PH-85–88 的 R 切片可独立退回。

### 3.1 E88-1 承接裁定（PH-87 复核 §3.3 的落实）

E88-1 的“tag 判别换穷尽 `match`”在 v0.88.0 的引导链下**不能字面完成**：ct-ast
源码由 L2 编译，L2 不实现 PH-84，ADT/`match` 会被原样发射成非法 C（原始输出见
[battle/p88-emit-match](../../battle/p88-emit-match/question.md)）。按 PH-87 先例
（battle/p87-kind-match）开 [battle/p88-emit-match](../../battle/p88-emit-match/verdict.md)，
把承接写死为：

| 项 | 裁定 |
| --- | --- |
| 承接目标 | **v1.0 seed cutover（`v1-PH-0`）**，不在 PH-88 内换 seed |
| 承接范围 | 本卡 76 个发射器切片 + PH-87 §3.3 点名的 `expr_ctype`、`maybe_box`、`chk_type` |
| 本卡交付 | 按 kind 切片（单一判别）+ `p88_emit` 清单/变异自测 + 66 语料逐字节 + 345 诊断 + fixpoint 2/3 轮 |
| E88-1 记录 | **部分通过**（切片/等价完成；字面 `match` 未做，承接见上） |
| 非作者追签 | battle 判决待 REVIEW/EDITOR 追签；DEV 不自签（0.7/T-8） |

## 7 收口记录（v0.88.0，2026-11-21）

### 7.1 任务、红证与实现

| 任务 | 交付 | 红证（baseline `47a8f786`） | 实现提交 | 验收 |
| --- | --- | --- | --- | --- |
| S88a 发射器重写 | 五个判别函数 76 个 `em_*` 切片 + 判别式单读 + `MAX_IO_CALLS` 容量 | `test(ct-ast): PH-88-S88a 红` = `a516db47`；`p88_emit` exit 1（`emit_expr: ... exactly once, found 34`） | `feat(ct-ast): PH-88-S88a 发射器按 kind 切片` = `26986463` | `p88/emit` ok；66 语料逐字节；345 诊断逐字；`p84`/`p87` 探针全绿 |
| S88b 自举回环 | `CT_FIXPOINT_ROUNDS`（日常 2 / tag 前 3）、唯一 `fixpoint_stage`、`--fixpoint-only` | `96006f57`；`p88_fixpoint` exit 1（`the daily default is not 2`…） | `50703784` | `p88/fixpoint` ok；2/3 轮逐字节 |
| S88c 度量/证据 | `docs/history/p88_metrics.md`（行数/耗时/sharp edge/PH-85 对照） | `1729dec8`；`p88_metrics` exit 1（文档缺失） | `6d457365` | `p88/metrics` ok（9/0） |
| S88d 文档/收口 | spec §4.75、tutorial §21、`v1-pre-evidence.md`、原始输出 | `733be810`；`p88_docs` exit 1（`2 passed, 24 failed`） | `9cfabef0` | `p88/docs` ok（26/0） |

四条探针由 `e08b4b2b`（`test(check-ast): 接入 p88_* 探针`）接入门禁；每个
`test 红` 都是对应实现提交的父提交。`p87_docs` 的快照核对由 `4879f7f9`
改为读 `11961895`（v0.87.0）的 Expr 行数，历史报告不因 PH-88 容量注释漂移。

### 7.2 E88 逐条结论

| ID | 结论 | 依据 |
| --- | --- | --- |
| E88-1 | **部分通过**（切片完成；字面 `match` 承接，见 §3.1） | `p88_emit` 76 切片/单读/变异自测；[battle/p88-emit-match](../../battle/p88-emit-match/verdict.md) |
| E88-2 | **通过** | 66 语料逐字节（[p88_evidence](../../test/probes/p88_evidence.txt)）；自身产物按 D-017 A1 第 2 层 = fixpoint + ASan + 行为测试 |
| E88-3 | **通过** | 2/3 轮同一 `fixpoint_stage`/一次 `diff -r`；`p88_fixpoint` 6/0；越界轮数 exit 2 |
| E88-4 | **通过** | [p88_metrics](../history/p88_metrics.md) 行数/耗时/sharp edge/PH-85 spike 对照；`p88_metrics` 复算 9/0 |
| E88-5 | **通过** | `check-all: OK (11 hard gates green)`；`check-sanitizers: OK (588 checks)`；`check-warnings: 502 ok, 0 failed` |
| E88-6 | **通过** | 集合基线/映射未变：`p85_m0`、66 语料清单 `diff` 空；无产物集合变更 |
| E88-7 | **通过** | spec §4.75、tutorial §21（片段编译运行 7/5/8）、[v1-pre 证据](../history/v1-pre-evidence.md) |
| E88-8 | **通过** | 回滚：`git archive HEAD` 后把 `26986463` 的两个文件换回 `26986463^`，重走 L0→L1→L2→ct-ast；`test/cases` 与 `examples` 产物与 HEAD 逐字节相同，66 语料清单 `diff` 空 |

### 7.3 总门禁原始输出

```console
$ TMPDIR=... bash selfhost/check-all.sh
== summary: 1575 passed, 0 failed, 5 skipped ==        # check-ast（含 p88/emit/fixpoint/metrics/docs）
check-warnings: 502 ok, 0 failed
check-docs: OK (2417 relative links in 388 files, v0.88.0, 11 hard gates, ...)
check-all: OK (11 hard gates green)
$ bash selfhost/check-sanitizers.sh
check-sanitizers: OK (588 checks, no sanitizer report)
$ bash tools/check.sh g0
g0: OK (block 1.17.0, session-map present)
$ bash tools/check.sh g8
g8: OK (PN-2 version coherence; 9 legacy offsets)
```

5 个 skip：`p83/dist`（本地 `dist/` 的 v0.87.0 产物无法在无 zig 的 mac 上
重建，见 §7.5）、QEMU/门禁既有的 4 个环境 skip。上述全部原始输出见
[p88_evidence](../../test/probes/p88_evidence.txt)。

### 7.4 版本与回滚

- 五处 `CTC_VERSION` = `0.88.0`；51 个 `test/cases/*.expected.*` 与
  `test/modules/p39_lib/lib.expected.abi.h` banner = `v0.88.0`；
  `README.md` / `docs/README.md` / `AGENTS.md` 当前版本 = `v0.88.0`；
  `test/ast/p80_docs.sh` / `p81_box.sh` / `p82_docs.sh` 的版本断言同步；
- `g8: OK`；`version-minor` = 88（`d=0`）；
- 单卡回滚见 E88-8：发射器可退回旧实现，输出与 v0.87 一致；实现提交
  `26986463` 只含 `Emitter.h.ct` 与 `Expr.h.ct`，可单独 `git revert`。

### 7.5 未覆盖

1. 字面 `match`：L2 引导链前置，承接 `v1-PH-0`（§3.1 / battle）；
2. `?`/errdefer：L2 不下降 PH-40/PH-44（§3.2，PH-86 battle A），错误路径保留显式 `return -1`/`fail_from`；
3. `String`/可增长 buffer：发射器流式写 `FILE *`，不适用（度量 §4-6）；
4. `MAX_FUNCS` 余量 11 个顶层函数（501/512）：下一批切片前必须复算；
5. 本地 `dist/ct-linux-x64.tar.gz` 是 v0.87.0 的未纳管产物；本机无 zig，
   无法重建 0.88.0 Linux 产物，`p83/dist` 按设计 skip（77）。发布前需在
   有交叉工具链的环境重跑 `selfhost/make-dist.sh --cross <zig>`。

### 3.2 错误路径 `?`/errdefer（沿用 PH-86 battle A）

S88a 的“错误路径尽量 `?`/errdefer”在 v0.88.0 **不适用**：L2 引导链不下降
PH-40 / PH-44 的 `errdefer` 与后缀 `?`，写进 ct-ast 源码会被原样发射成非法 C
（独立复现见 [battle/p86-errorpath](../../battle/p86-errorpath/verdict.md) REVIEW
判决；L2 中 `errdefer` 命中 0、无后缀 `?` 下降）。PH-87 卡 §1 已按同一口径
“不改”，PH-88 沿用：

- 切片保留原有的显式 `return -1` / `fail_from` 错误值，不新增也不改写错误通道；
- 错误出口的行为由 345 条诊断逐字 + `p86_errors` 23/0 验收；
- 与字面 `match` 同一个解锁点：`v1-PH-0` seed cutover 之后，才谈在 ct-ast 源码
  使用 `?`/errdefer；本卡不代决。
