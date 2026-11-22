# DOC-94 · 语言名书写规范 `CT → Ct`（立项）

| 项 | 值 |
| --- | --- |
| 模块 | docs（全仓散文书写规范 + check-docs 门禁） |
| 定性 | 命名/品牌规范变更（不改语言语义） |
| 严重度 | Low（纯书写；但影响面是全仓活跃散文） |
| 锚点 | v0.88.3（2026-11-22） |
| 依据 | 所有者 2026-11-22 立项；外部《lib/core 提案》§2；[lib/core 提案评估](../../docs/reviews/2026-11-22-lib-core-proposal-eval.md) §4 |
| 状态 | open |
| 处置证据 | **accepted（2026-11-22 所有者立项；先全量替换，后开 ratchet）** |

## 目标

活跃散文统一写 **Ct**（「Ct 语言」「给 C 程序员的 Ct 指引」）；标识符、命令、路径、
组织名保持现状。全大写 **CT** 只保留在历史记录与豁免上下文。

## 范围

**要改（活跃散文，`.md` 为主）**：

- `README.md`、`README.en.md`；
- `docs/*.md` 中仍维护的文档（spec / tutorial / guide / patterns / idioms / stable-subset /
  roadmap / vision / glossary / memory-guide / std-catalog / planning 的活跃页）；
- `AGENTS.md` 的散文段（不含生成块与固定格式串）。

**不改（历史/记录快照）**：

- `docs/history/**`、`docs/reviews/**`、`docs/review/**`、`docs/proposals/**`、
  `docs/decisions/**`、`docs/design/**`、`battle/**`、`issues/**`；
- 代码块、行内代码、标识符、命令、路径、环境变量、组织名、C 宏与 C 符号。

## 豁免清单（不触发 ratchet）

- `ct` / `ctc` / `ct-ast` / `ct-pkg` / `ct-lang` / `.ct` / `ct.lock` 等命令与路径；
- `CT_CORE_DIR` / `CT_STD_DIR` / `CT_HOME` / `CT_STD_DIR` 等环境变量与宏；
- 代码块与反引号内文本；
- 历史目录（见上）；
- 第三方专名（如 computed tomography 的 CT 语境）。

## 执行顺序

1. **清点**：`grep -rn '\bCT\b'` 只统计活跃散文，产出按目录分组清单；
2. **替换**：按目录分批（README → docs 活跃页 → AGENTS 散文），每批单独提交、可单独回滚；
   历史目录加一行“2026-11-22 起书写为 Ct”的指路，不批量改旧文；
3. **门禁**：`check-docs` 新增断言——活跃散文中出现全大写 `CT`（豁免清单除外）即红；
   负例自测：故意写回 `CT` 必须红；
4. **收尾**：glossary 的 `ct（CT = C with Traits）` 改为 `ct（Ct = C with Traits）`，
   并保留一句“旧写 CT”说明。

## 验收

- 活跃散文中 `CT` 仅出现在豁免清单与历史目录；
- `check-docs` 新增负例可红、正例绿；
- 不改任何编译器代码、测试行为、生成物；
- 外部四份文档的 Ct 写法与本规范一致，但仓库在替换完成前仍以现行为准。

## 非目标

- 不改 CLI/命令/包名/仓库名（仍是 `ct` / `ct-pkg` / `ct-lang`）；
- 不改语言关键字、诊断文本、C 符号；
- 不与 DOC-87 的目录/命名空间改动混在同一提交。

## 关联

- 外部《提案：内置层目录更名 lib/std → lib/core》§2；
- [lib/core 提案评估](../../docs/reviews/2026-11-22-lib-core-proposal-eval.md) §4；
- [glossary](../../docs/glossary.md)；
- [DOC-87](doc-87-lib-core-rename.md)（lib/core / core::*，独立批次）。
