# battle/doc-consistency-1 反对席（REVIEW）——反证与替代方案

> 席位：REVIEW（反对席）。主张：**B（最小集 + 增量补丁）**。
> 只证伪 A（全量审计重写）在本 phase 的可行性，并给出可验收的最小集；
> 不提出新的语言/代码改动。

## E1 文档规模与改动面（命令 + 原始输出）

```console
$ wc -l docs/language-spec.md docs/tutorial.md docs/patterns.md docs/llm-guide.md docs/glossary.md docs/architecture.md README.md
    3117 docs/language-spec.md
    2111 docs/tutorial.md
     161 docs/patterns.md
      83 docs/llm-guide.md
     276 docs/glossary.md
     186 docs/architecture.md
     526 README.md
    6460 total
```

结论：A 的“全量审计重写”要在一个 M 任务（S84e）里动 6460 行入口/参考文档，
与 PH-84 的单卡范围（S84a–S84d）和 D6“重写期只收 bugfix”冲突；B 只动
“新特性可定位 + 事实/链接”这一最小面，可单卡回滚。

## E2 事实锚点（含不利于己方的一条）

- `docs/llm-guide.md:24` 内置层仍写 `Vec` / `Map` / `Option` / `Result` / `Str`，
  **缺 `String` / `U16String`**，且 `Str` 语义仍是 PH-80 之前的 owning——
  **这条不利于 B**：它证明“只改 spec/tutorial/patterns”不够，入口文档确实在带错用户，
  B 因此必须把 llm-guide 的事实修正纳入最小集。
- `docs/glossary.md:89` 把 `Str` 记成 `lib/std/Str.h.ct` 的 owning 句柄，
  与 PH-80 S5b（删除 `StrLegacy`、`Str` 改为借用视图）冲突。
- `docs/architecture.md` 的 AST 结构表没有 ADT/`match` 行：新语法在架构入口不可见。
- 支持 B 的一面：`docs/patterns.md` 只有 95→161 行、`docs/tutorial.md` 已有 ref/out 与
  String 片段；把新增特性补成“可定位小节”成本远低于重写。

## E3 可证伪预测

若 B 成立，则最小集内每项都可在 1 次 grep 内定位：`String`/`Str`（spec §4.70 /
tutorial / llm-guide H1）、切片（§4.69）、`ref`/`out`（§4.68）、`box`/`new`（§4.71）、
ADT/match（§4.73 / tutorial §18 / patterns §6）；任一特性找不到可定位小节，B 不通过。

## E4 代价量化

- 最小集改动预计 ≤ 300 行（含 4 份入口文档的事实句与链接、glossary 3 行、architecture 1 行）；
- A 的全量重写 ≥ 2000 行，且需要逐段评审，无法在本卡一个 M 任务内完成；
- 失败隔离：B 的改动可单卡回滚；A 重写若中途停下，入口文档会处于半新半旧状态。

## E5 对 A 最强论点的 steelman 回应

A 最强处：入口/索引文档落后会让用户按旧模型写代码（llm-guide 的内置层清单就是实例）。
回应：这不构成“重写”的理由，而是“事实修正”的理由——把 stale 清单改对、给
glossary/architecture 补一行、把 ADT/match 链到 spec/tutorial，已经消除带错用户的主路径；
剩余的系统性审计（DOC-77/DOC-78/DOC-79）继续按 issue 闭环，不塞进 S84e。
