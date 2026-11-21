# v1-pre 证据摘要（PH-84…PH-88，v0.84.0–v0.88.0）

> **S88d 交付物**。v1-pre = 编译器现代语法重写（D-017 §1）：PH-84 提供 ADT/`match`
> 前置，PH-85–88 按子系统重写（词法器 → 解析器/检查器 → 发射器），PH-88 同时
> 把自举不动点扩成轮数参数化。**v1.0 紧随其后**（`v1-PH-0`，AST-only + seed
> cutover）。本页只做逐相结论与遗留索引，细节在各卡与评审报告。

## 1 逐相结论

| 相 | 版本 | 结论 | 关键证据 | 遗留 |
| --- | --- | --- | --- | --- |
| PH-84 | v0.84.0 / v0.84.1 | **通过**（首轮打回 F1/F2，v0.84.1 修 typedef 别名） | `p84_layout` 26/0、`p84_match` 13/0、`p84_syntax` 14/0；[REV 复核](../reviews/2026-11-21-phase84-rev-verdict.md) §9 | S84e 全量文档审计归 DOC-77/78/79 |
| PH-85 | v0.85.0 | **通过（E85-2 有条件，D-018）** | inventory 27 单元/842 函数/0 环；词法器 spike 391→425 行、语料逐字节、零告警；M0 六个粗切单元 body-hash 827 全保留；A 机制 `off`/`warn`/`error` | 单切片 spike 未证明“整子系统新语法重写门”，PH-86 改 per-function；[D-018](../decisions/D-018.md) |
| PH-86 | v0.86.0 | **通过** | token 改源缓冲 `TokView`（`toktext` 728→0）；345 条诊断逐字；66 语料逐字节；[REV 复核](../reviews/2026-11-21-phase86-rev-verdict.md) | `?`/errdefer 在 ct-ast 源码不可用（L2 不下降）→ [battle/p86-errorpath](../../battle/p86-errorpath/verdict.md) 采 A：错误出口清单 |
| PH-87 | v0.87.0 | **通过；E87-2 部分通过**（字面 `match` 未落地，REV 追签 battle A） | 解析器 13 切片/14 kind、检查器 15/20，单判别；66 语料逐字节；345 诊断逐字；dogfood 10 条同一类 FP | 字面 `match` 移交 PH-88（再由 PH-88 写死承接目标）；FP 待立案；切片互换变异探针未红（N-1） |
| PH-88 | v0.88.0 | **通过；E88-1 部分通过**（字面 `match` 按 battle 承接，见 §2） | 发射器 76 切片、判别式各读 1 次；66 语料逐字节；345 诊断逐字；fixpoint 2/3 轮逐字节；[p88_metrics](p88_metrics.md) | 见 §2 |

## 2 字面 `match`：承接目标（写死）

PH-87 §3.3 的两项条件由 PH-88 承接为
[battle/p88-emit-match](../../battle/p88-emit-match/verdict.md) 的判决：

1. **承接目标 = v1.0 seed cutover（`v1-PH-0`）**，不是 PH-88 内换 seed。PH-88 的
   引导链仍是 `L0→L1→L2→ct-ast`，L2 不实现 PH-84；在 PH-88 内换 seed 会把
   v1.0 的 §1.2 决策提前，且超出本卡非目标。`v1-PH-0` 的出口判据必须包含：
   用新 seed 构建第一代 ct-ast 后，把下列判别全部改成「一 kind 一臂，共用体调
   同一 helper」的穷尽 `match`（PH-84 无 or 模式）；
2. **承接范围**：PH-88 的 76 个发射器切片（`em_node_*`/`em_expr_*`/`em_decl_*`/
   `em_inline_*`/`em_field_*`），加上 PH-87 §3.3 点名的剩余 kind 判别
   `expr_ctype`、`maybe_box`、`chk_type`（`--types` 通路）。漏一项即 v1.0 的
   E88-1 欠账未清。

在 `v1-PH-0` 之前，ct-ast 源码**不得**出现 ADT/`match` 语法：L2 会原样发射成
非法 C（证据 [p87_l2_adt_evidence.txt](../../test/probes/p87_l2_adt_evidence.txt)、
[p88-emit-match](../../battle/p88-emit-match/verdict.md)）。

## 3 v1-pre 遗留清单

| # | 项 | 去向 | 触发条件 |
| --- | --- | --- | --- |
| 1 | 字面 `match` 替换（发射器 76 + `expr_ctype`/`maybe_box`/`chk_type`） | `v1-PH-0` | seed cutover 后 |
| 2 | `String`/可增长 buffer 在发射器不适用（流式 `FILE *` + `MAX_TEXT` 契约） | M1/v1.1 复核 | 若引入 std `String` 到引导编译器 |
| 3 | `MAX_FUNCS` 余量 37 个顶层函数（475/512） | 下一批切片前复算 | 再加 >37 个 free function |
| 4 | `MAX_IO_CALLS` 512→1024（PH-88 容量调整） | 已交付；若继续切片需再评估 | 再增 ~80 个不同 callee 名 |
| 5 | 检查器/解析器切片互换变异探针不红（PH-87 N-1） | VERIFY 后续 | 有探针预算时 |
| 6 | dogfood 10 条同一类 FP（`T a[]`） | SH-106 立案（工作树，待提交） | 由 REQ 处理 |
| 7 | M1 精细切分（纯移动） | v1.1 S1 | v1.0 发布后 |
| 8 | A 默认强制（strict 编译路径） | v1.1 S2 | v1.0 发布后 |
| 9 | 阶段 ID 迁移（legacy `PH-*` → `v0-PH-*`） | 迁移 blocker 解除后 | 见 [phase-migration-blockers](../planning/phase-migration-blockers.md) |

## 4 总门禁

PH-88 收口时 `bash selfhost/check-all.sh` 11/11、`check-warnings` 0 失败、
`sanitizer` 全绿、`check-docs` OK、`tools/check.sh g0` / `g8` OK；版本五处
`CTC_VERSION` 与 golden/ABI banner 均为 `0.88.0`。原始输出见
[p88_evidence.txt](../../test/probes/p88_evidence.txt) 与 phase-log 的 v0.88.0 行。
