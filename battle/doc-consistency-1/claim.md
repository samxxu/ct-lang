# battle/doc-consistency-1 主张席（REQ）

- 主张：**A — 全量审计 + 分级处理（重写 / 补节 / 仅修事实）**。
- 理由：新语法特性已落地，但文档不是“缺一节”，而是**入口文档仍按旧模型描述**；
  只补 spec/tutorial 会让 README、llm-guide、glossary 继续把用户带错。
- 范围：只动文档，不改代码/ABI/语言语义；历史文档（history/decisions/battle）不回改。

## E1 — 文档规模与覆盖度

```console
$ wc -l README.md docs/README.md docs/language-spec.md docs/tutorial.md docs/patterns.md \
        docs/llm-guide.md docs/glossary.md docs/architecture.md docs/package-guide.md docs/memory-guide.md
  526 README.md
  112 docs/README.md
 3005 docs/language-spec.md
 2020 docs/tutorial.md
   95 docs/patterns.md
   83 docs/llm-guide.md
  276 docs/glossary.md
  186 docs/architecture.md
  324 docs/package-guide.md
  586 docs/memory-guide.md
```

新特性词频（`String|Str|切片|T[]|ref|out|box<|new T`）：

```text
82 docs/language-spec.md
29 docs/tutorial.md
 7 docs/glossary.md
 5 docs/patterns.md
 3 docs/llm-guide.md
 2 README.md
 2 docs/architecture.md
 2 docs/memory-guide.md
```

结论：spec 覆盖最好，**入口/索引/术语/架构文档明显落后**；这正是“全量审计”的对象。

### E1.1 逐特性 × 文档矩阵（审计起点）

| 特性 | language-spec | tutorial | patterns | llm-guide | glossary | README |
| --- | --- | --- | --- | --- | --- | --- |
| `String` / `Str`（UTF-8） | 有 §4.70 | 片段 | 缺 | **旧**（H1 未列 String） | 缺 | 缺 |
| 切片 `T[]` | 有 §4.69 | 片段 | 缺 | 缺 | 缺 | 缺 |
| `ref` / `out` | 有 §4.68 | 有 | 缺 | 缺 | 缺 | 缺 |
| `box<T>` / `new` | 有 §4.71 | 缺 | 有（树模式） | 缺 | 缺 | 缺 |
| ADT / `match`（PH-84） | 缺（随 PH-84） | 缺 | 缺 | 缺 | 缺 | 缺 |

> “片段”= 有零散示例但无系统小节；“旧”= 有内容但与当前实现冲突；“缺”= 无。
> 审计完成后，每个格子必须变成“有”或明确写“不适用”，否则 J-2 不通过。

## E2 — 锚点（含不利于己方）

**支持 A 的事实**

- [llm-guide.md:24](../../docs/llm-guide.md#L24) 内置层仍写
  “`Vec` / `Map` / `Option` / `Result` / `Str`”，**没有 `String` / `U16String`**；
  `Str` 的语义也已从 owning 变成借用视图（PH-80）。
- [llm-guide.md:28](../../docs/llm-guide.md#L28) 与 `:68` 仍写五字段旧行“只读兼容”；
  契约 v1（[D-014](../../docs/decisions/D-014.md)）已改为**按行硬错**。
- [glossary.md](../../docs/glossary.md) 没有 `String` / `Str`（借用）/ `T[]` / `ref` / `out` /
  `box<T>` / `new` / ADT/match 的条目；“切片”只作为阶段术语存在。
- [patterns.md](../../docs/patterns.md) 只有 `box` 树模式；没有切片视图、String/Str、ref/out、ADT/match 的写法。
- [README.md:33](../../README.md#L33) 的 §0.1 仍以 0.44.1 历史基线描述“三断点”，未同步当前能力。
- [architecture.md:12](../../docs/architecture.md#L12) 的“四代编译器”表在 v1.0 去 L1/L2 后会过期，
  需要标注“v1-pre/1.0 后的终态”。

**不利于 A 的事实（必须承认）**

- 审计面约 8k 行，重写容易把“文档事实”与“实现事实”再次拉偏；
  [language-spec](../../docs/language-spec.md) 已有 §4.68–§4.71，说明“缺节”不是主要问题，
  主要问题是**入口文档与术语表没跟上**。
- 新增示例若没有门禁，会变成第三套“不可执行的真相”。

## E3 — 可证伪预测

若 A 成立，完成审计后应能通过：

1. 每个新特性在 `language-spec` / `tutorial` / `patterns` 至少一处可定位；
2. `llm-guide` 的 H1/H5 与契约 v1、`lib/std` 实际内置层一致；
3. `glossary` 能查到全部新术语；
4. `check-docs` 的能力→节号断言可机器判；
5. 新增/改写的示例可编译运行，或明确为负例。

若做不到 1–3，说明“全量审计”没有产生可验证收益，应退回 B。

## E4 — 代价与分级

A 不是“全部重写”，而是三级：

| 级别 | 文档 | 动作 |
| --- | --- | --- |
| 重写 | `README.md` §0.1、`llm-guide`、`glossary`、`patterns`、`tutorial` 新特性章节 | 按当前实现重写/补节 |
| 补节/修事实 | `language-spec`（ADT/match 新节、§4.68–4.71 交叉引用）、`package-guide`（五字段硬错）、`memory-guide`（String/box 所有权） | 局部改，不动结构 |
| 仅标注 | `architecture`（四代→终态）、`docs/README`（索引） | 加时效说明与链接 |

不为历史文档（`docs/history/**`、`docs/decisions/**`、`battle/**`）回改事实；它们记录当时状态。

## E5 — 对 B 最强论点的 steelman

B 最强：**“只改 spec/tutorial/patterns 的必需节，成本最低；入口文档只修链接，不重写。”**

回应：这正是当前落伍的成因——读者从 README/llm-guide 进入，看到的仍是旧模型；
只修 spec 会让“唯一权威”与“入口”继续分裂。A 用三级处理把重写限制在入口文档与新特性章节，
并保留 B 的“不动历史文档”约束；若评审认为 `glossary`/`architecture` 不必重写，
可把它们降到“仅标注”级，不影响 A 的核心（入口与新特性一致）。

## 待评审席挑战的点

1. `README` §0.1 是“目标形态”，重写是否会掩盖 SH-73 尚未解除的事实？——A 要求同时标注
   “当前可跑/目标形态”，不删断点。
2. `glossary` 是“唯一对照表”，新增术语的命名权是否应先由 EDITOR 裁决？——A 接受
   “先提术语草案，EDITOR 签收后入表”。
3. 示例门禁放 `test/ast` 还是文档探针？——A 倾向 `test/ast`，避免新工具。
