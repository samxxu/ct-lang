# battle/p86-errorpath 判决（REVIEW 2026-11-21 已签）

- 日期：2026-11-21
- 状态：**accepted（REVIEW 2026-11-21 签；DEV 建议稿）**
- 判据来源：[question.md](question.md)

## 建议

采用 **A**：

1. PH-86 S86c 交付“错误出口清单 + 诊断逐字不变”的证据，不把 `?`/errdefer 写进
   ct-ast 源码；理由与原始输出见 [p86_errors.md](../../docs/design/p86_errors.md) §3。
2. `p86_errors` 探针以 `test/probes/p86_error_diags.tsv`（基线 345 条）与
   `test/ast/p86_errors/*.expected.err` 为准，覆盖词法边界与内嵌 token 的文案。
3. PH-87/88 的 `?`/errdefer 判据不在本卡代决；建议 REQ 在开卡前二选一
   （先补引导层，或把判据降级为 `no-test` 文档项）。

## 反对意见的落点

若 REVIEW 要求字面执行卡 §2，B 是唯一真做 `?`/errdefer 的路径；它的代价是改
L0/L1/L2 冻结层与产物 golden，应另立 phase/decision，不能借 PH-86 夹带。

## REVIEW 判决（2026-11-21）

**A 成立。** 独立复现（不用 `Result` 类型，排除原证据里 `cc` 先因未知类型失败的
干扰）：`selfhost/l2` 对 `int v = get(&x)?;` 与 `errdefer { … }` 原样发射，
`cc` 在 `get(&x)?` 处 `expected expression`；`selfhost/l2` 中 `errdefer` 命中 0，
也没有后缀 `?` 的下降分支。ct-ast 源码由 L2 引导编译，写入这两个构造必破链。

- 本判决**只覆盖 PH-86 S86c 的范围**：S86c 的交付改为“错误出口清单 + 诊断逐字
  对照”，属**范围缩减**，不是 S86c 字面任务通过；不改卡 §2 任务清单与 E86-4 文本。
- E86-4 的字面判据（诊断文本与既有负例一致；行为测试/ASan 通过）已由 345 条
  exit+stderr sha256、8 条词法边界 fixture 与 sanitizer/ASan 证据满足。
- 条件：PH-87/88 开卡前由 REQ 二选一——先给 L1/L2 补 PH-40/PH-44 的下降，或把
  同名判据降为 `no-test` 文档项；不得在 PH-87/88 静默沿用本卡口径。
