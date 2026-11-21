# battle/p87-kind-match 判决（DEV 自决，REVIEW 2026-11-21 已追签）

- 日期：2026-11-21
- 状态：**accepted（DEV 2026-11-21 建议；REVIEW 2026-11-21 追签，条件见文末「REVIEW 追签」）**
- 判据来源：[question.md](question.md)

## 判决

采用 **A**：

1. **本卡不做** ct-ast 源码里的字面 `match`：L2 引导链不认 ADT/`match`，
   写进去必破链（证据：`test/probes/p87_l2_adt_evidence.txt`）。
2. S87b 的交付改为**按 kind 切片的单一判别**：`expr_type` 的 20 个分支拆成
   15 个 `tc_expr_*` 切片，判别式只读一次 `nodes[n].kind`；S87a 同样处理
   `static_ctype`（14 个 kind / 13 个 `ctype_*` 切片）。行为等价由语料逐字节、
   345 条诊断逐字、自举不动点与 ASan 验收。
3. 漏分支的保证改挂探针：`p87_checker` / `p87_parser` 对源码做切片清单核对，
   并**自测**“删掉一条切片 → 探针必须变红”。语言级负例
   `test/ast/p87_checker/missing_arm.ct` 钉住 `match does not cover variant`
   的逐字诊断，作为 PH-88 落地时的现成判据。
4. **E87-2 的字面 `match` 部分移交 PH-88**：PH-88 的任务包含“自举不动点扩展/
   轮数参数化”，它决定引导链是否改为自举或种子；一旦 ct-ast 源码可由支持
   ADT 的编译器编译，把 `tc_expr_*`/`ctype_*` 切片改成 `match` 是机械动作
   （切片与变体 1:1，见卡 §7 的映射表）。
5. 本卡的 E87-2 记为 **“可验证切片通过 + 语言级负例通过；字面替换未做，
   移交 PH-88”**，不得记成“全部通过”。

## 反对意见的落点

若 REVIEW 要求本卡字面完成 E87-2，B 是唯一真做的路径；它要改 L0/L1/L2 之外的
引导层与 L2 发射器，应另立 phase/decision，不能借 PH-87 夹带（同 battle/p86-errorpath
对 `?`/errdefer 的处置）。

## 与 PH-86 battle 的关系

PH-86 battle 已裁定 `?`/errdefer 不在 ct-ast 源码使用（错误路径按“出口清单 +
诊断对照”交付）。本判决对 `match` 采用同一口径：**语法新特性在引导链支持前
不得写进 ct-ast 源码**；差别是 `match` 的阻塞点是 L2 未实现 PH-84，而
`?`/errdefer 是 ct 语言本身未实现。

## REVIEW 追签（2026-11-21）

**A 成立，本复核追签。** 已在归档自举上独立复现 L2 前置（`enum NodeKind` 被 L2
原样发射成非法 C，20 errors；同一源码 ct-ast 可编），L1/L2 中 ADT/match 下降
命中 0。E87-2 记**部分通过**，不得记全部通过。

追签附两项条件，REQ/EDITOR 须在 PH-88 开卡前落实（详见
[PH-87 复核 §3.3](../../docs/reviews/2026-11-21-phase87-rev-verdict.md)）：

1. **承接目标写死**：PH-88 卡现只写发射器 + 轮数参数化，引导链仍由 L2 起步，
   编不了含 `match` 的源码；字面项只能由 v1.0 的 seed cutover（`v1-PH-0`）或
   PH-88 内显式新增的「换 seed」任务承接。二选一写进退出判据，否则欠账会丢。
2. **承接范围含全部剩余 kind 判别**：`expr_ctype`、`maybe_box`，以及本卡 §7.6
   漏列的 `chk_type`（`--types` 通路的 `switch (kind)`）。

另：本判决「切片与变体 1:1」的措辞需修正为「一 kind 一臂，共用体调同一 helper」
（13 函数/14 kind、15/20；PH-84 无 or 模式）。本复核不推翻 A，也不改实现。
