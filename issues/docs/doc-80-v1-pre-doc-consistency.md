# DOC-80 · v1-pre 前文档一致性审计与优化

| 项 | 值 |
| --- | --- |
| 模块 | docs（全量文档） |
| 定性 | 文档缺口（新语法特性落伍；范围待 battle） |
| 严重度 | High（v1-pre 入口前置） |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [PH-84 S84e](../../docs/design/phase84.md)、[battle doc-consistency-1](../../battle/doc-consistency-1/question.md) |
| 状态 | verified |
| 处置证据 | **复核通过（2026-11-22，REV）**：范围按 battle doc-consistency-1 判决 B（最小集）；E84-9 ✅；`p84_docs_audit` OK；`check-docs` OK（2601 链接 / 401 文件，v0.88.2） |

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

## 复核（2026-11-22，REV）

**结论：`verified`。** DOC-80 的范围已由 [battle doc-consistency-1](../../battle/doc-consistency-1/verdict.md)
判决 B（最小集 + 增量补丁）冻结，PH-84 S84e 按该范围执行；A 的全量审计按判决移交
[DOC-77](doc-77-capability-spec-section-assertions.md) / [DOC-78](doc-78-new-feature-docs-audit.md) /
[DOC-79](doc-79-stable-subset-freeze-list.md)，不在本条验收内。

### 逐条对照

| 判据 | 结果 | 证据 |
| --- | --- | --- |
| E84-9 通过 | ✅ | [phase84.md](../../docs/design/phase84.md) E84-9 行：B 范围 ✅，`p84_docs_audit` `OK` |
| battle 清单内文档对齐 | ✅ | 必需节 spec §4.68–§4.71/§4.73、tutorial §15/§17/§18、patterns §5/§6；入口文档事实/链接修正 |
| 未列入项未扩写 | ✅ | 判决 B §2.4 范围外：全量重写/重排未做；A 归 DOC-77/78/79 |
| `check-docs` 与能力→节号断言 | ✅ | 下方命令；README capability 标记 `cap:params-slices`/`cap:strings`/`cap:box`/`cap:adt` |
| 新增/改写示例进门禁 | ✅ | `p84_docs_audit` 已接入 `check-ast`；ADT 示例见 `test/ast/290/291/292`、`p84_docs`/`p84_layout` |

### 复核命令与原始输出

```console
$ bash test/ast/p84_docs_audit.sh; echo rc=$?
OK p84docs_audit
rc=0

$ python3 test/docs/check-docs.py; echo rc=$?
spec pin: skipped (master spec draft 1.17.0)
check-docs: OK (2601 relative links in 401 files, v0.88.2, 11 hard gates, 12 phase status, 7 适用版本 header(s), 2 superseded link(s), 9 signoff(s), 10 briefing item(s), 34 J-6 row(s), 28 stability row(s), 3 compat marker(s), 20 capability row(s))
design window: ok (12/12)
rc=0

$ grep -nE '^## (15|17|18|22|23)\.' docs/tutorial.md
1896:## 15. `ref` / `out` 参数（Phase 78，v0.78.0 起可用）
1998:## 17. `box<T>` 与 `new`（Phase 81，v0.81.0 起可用）
2035:## 18. 最小 ADT 与 `match`（Phase 84，v0.84.0 起可用）
2274:## 22. `String` / `Str`：拥有还是借用（Phase 80，v0.80.0 起可用）
2309:## 23. 切片 `T[]`：长度跟着指针走（Phase 79，v0.79.0 起可用）

$ grep -n 'cap:params-slices\|cap:strings\|cap:box\|cap:adt' README.md
570:- **参数糖与切片**：`ref` / `out` 形参（Phase 78；`out` 有定值分析，owning 实参须先初始化）、`T[]` 切片（Phase 79；长度随指针走，越界检查由内建 helper 承担），见 spec §4.68 / §4.69 <!-- cap:params-slices -->
571:- **字符串句柄**：`String` 拥有（引用计数，字面量 immortal）、`Str` 借用视图（`{ptr,len}`，零拷贝）；`String` 可作字段，`Str` 不可作字段或 `Map` 键，见 spec §4.70 <!-- cap:strings -->
580:- **单对象句柄**：`box<T>`（16 字节句柄 + 8 字节 `{refs,aux}` 头）、`new T { ... }`（上下文关键字，仅具名 struct）、`b.f` 自动解引用、`retain` / `release` 与 `at()` 借用（Phase 81） <!-- cap:box -->
581:- **ADT 与 `match`**：`enum` 成员带负载即 ADT，`match` 穷尽所有变体或末位 `_`；值是 `{tag, union}`，无 vtable、无隐藏分配（Phase 84），见 spec §4.73 <!-- cap:adt -->
```

逐特性矩阵（String/Str、切片、ref/out、box/new、ADT/match）在
[idioms.md](../../docs/idioms.md) §11 的「首选 / 避免速查」表（§4.70/§4.69/§4.68/§4.71/§4.73 一一对应），
README §3 的能力清单与 §0.5 的可跑示例是入口面。未发现需要再修的矛盾段落。
