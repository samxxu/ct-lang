---
id: doc-consistency-1
head: 408e33bc
trigger: B-5
proposer: REQ
opposition: REVIEW
judge: EDITOR
forbidden: selfhost/**, test/**, docs/**
---

# battle/doc-consistency-1 — v1-pre 前文档一致性：全量审计重写，还是最小集增量补丁

## 争点

v1-pre（PH-85）开工前，必须把文档与新语法特性对齐。两案分歧：

- **A（REQ）全量审计 + 重点重写**：审计 README、language-spec、tutorial、patterns、llm-guide、
  glossary、architecture、package-guide；对 String/Str、切片、ref/out、box/new、ADT/match
  逐特性核对；过期段落直接重写，示例挂门禁。
- **B（REVIEW）最小集 + 增量补丁**：只改 language-spec / tutorial / patterns 的必需节；
  README、llm-guide、glossary、architecture 只做链接与事实修正，不重写；其余交给
  DOC-77/DOC-78 的后续 issue。

争点边界：不讨论是否做文档一致性（已由用户指令确定），只讨论**范围、重写深度、验收方式**。

## 背景与触发

- 触发：用户 2026-11-21 指令“v1-pre 前文档一致性也要考虑，新语法特性文档落伍；在 PH-84
  增加文档优化，可能要重写，具体 battle 决定”。
- 当前 HEAD：`408e33bc`。
- 相关：[PH-84 §2 S84e](../../docs/design/phase84.md)、[DOC-77](../../issues/docs/doc-77-capability-spec-section-assertions.md)、
  [DOC-78](../../issues/docs/doc-78-new-feature-docs-audit.md)、[v1 路线 §1.5](../../docs/planning/v1-release-plan.md)。
- 现状抽样：spec 已有 §4.68 ref/out、§4.69 切片、§4.70 String/Str、§4.71 box/new；
  tutorial 有 ref/out 与 String 片段；patterns 有 box 树模式；但 README/llm-guide/glossary/
  architecture 未系统覆盖新特性，且 ADT/match（PH-84）尚无文档。

## 逐条判据（J-1…J-6）

| ID | 判据 | 通过方式 |
| --- | --- | --- |
| J-1 | 覆盖度：A 案列出全部待审文档与逐特性矩阵；B 案列出最小集与被跳过文档的理由 | 文档清单 + 矩阵提交到 claim；缺项即不通过 |
| J-2 | 新特性覆盖：String/Str、切片、ref/out、box/new、ADT/match 在 spec/tutorial/patterns 各有可定位章节或示例（ADT 随 PH-84 实现补齐） | grep/链接检查 + 评审目检；每特性至少一处 |
| J-3 | 一致性：同一特性的类型/语义/限制在三处不矛盾；能力→spec 节号断言可机器判 | check-docs 断言 + 人工抽查 |
| J-4 | 示例可信：新增/改写的示例可编译运行，或有明确负例与期望输出；挂到既有门禁 | `test/ast` 或文档示例门禁；失败即不通过 |
| J-5 | 不越界：不改代码/ABI/语言语义；文档改动可单卡回滚 | diff 仅 `docs/**`（battle 席位本身只写 `battle/**`） |
| J-6 | 范围冻结：最终采纳的文档清单与重写深度写入 PH-84 S84e，未列入项不得顺手扩写 | 卡面 S84e 与 verdict 一致；越界打回 |

## 席位与边界

| 字段 | 值 |
| --- | --- |
| proposer | REQ（A：全量审计 + 重点重写） |
| opposition | REVIEW（B：最小集 + 增量补丁） |
| judge | EDITOR |
| 禁止触碰 | `selfhost/**`、`test/**`、`docs/**` |

- 证据按 §7.7 E1–E5 提交；每轮至少新增 1 条 E1/E2（§7.11）。
- 最多 3 轮；三轮无结论按 §7.10 出 C 或 open-question。
