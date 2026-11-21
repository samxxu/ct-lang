# DOC-80 · v1-pre 前文档一致性审计与优化

| 项 | 值 |
| --- | --- |
| 模块 | docs（全量文档） |
| 定性 | 文档缺口（新语法特性落伍；范围待 battle） |
| 严重度 | High（v1-pre 入口前置） |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [PH-84 S84e](../../docs/design/phase84.md)、[battle doc-consistency-1](../../battle/doc-consistency-1/question.md) |
| 状态 | open |
| 处置证据 | **待办（范围由 battle 判定；PH-84 内执行）** |

## 现象

新语法特性已落地（String/Str、切片、ref/out、box/new，ADT/match 随 PH-84），但文档仍落伍：
- spec 有 §4.68–§4.71，但 README、llm-guide、glossary、architecture 等未系统覆盖；
- tutorial/patterns 只有零散片段；
- 同一特性的类型/语义/限制在多处可能矛盾；
- ADT/match 尚无文档。

## 期望

1. 按 [battle doc-consistency-1](../../battle/doc-consistency-1/question.md) 的判决冻结：
   - 审计文档清单；
   - 允许重写的文档/章节；
   - 验收方式（check-docs、能力→节号、示例门禁）。
2. 逐特性矩阵：String/Str、切片、ref/out、box/new、ADT/match；
3. 过期段落允许重写，但不得写未实现能力；
4. 示例可编译运行，或明确标注负例与期望输出；
5. 文档改动不改代码/ABI/语言语义，可单卡回滚。

## 验收

- E84-9 通过；
- battle 清单内文档全部对齐，未列入项未顺手扩写；
- `check-docs` 与能力→节号断言通过；
- 新增/改写示例进门禁。

## 关联

- [PH-84](../../docs/design/phase84.md) S84e、[DOC-77](doc-77-capability-spec-section-assertions.md)、[DOC-78](doc-78-new-feature-docs-audit.md)
