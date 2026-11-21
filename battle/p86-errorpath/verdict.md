# battle/p86-errorpath 判决（DEV 建议，待 REVIEW）

- 日期：2026-11-21
- 状态：**proposed（DEV 建议；REVIEW/EDITOR 未签）**
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
