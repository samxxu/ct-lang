# DOC-95 · 接收规范组移交的 Ct 包编码通用条款（PROP-004）

| 项 | 值 |
| --- | --- |
| 模块 | docs（包规范） / 跨仓移交受理 |
| 定性 | 文档归属移交（语言专用条款，非缺陷） |
| 严重度 | Info |
| 锚点 | v0.88.3（2026-11-23） |
| 依据 | 规范组 PROP-004《语言专用编码条款的移交》（2026-11-23）；[AGENTS.md §9.10](../../AGENTS.md) CF-1…CF-5 |
| 状态 | verified |
| 处置证据 | **accepted（2026-11-23，REQ 按所有者授权受理）：接收，B 档（仓内独立文档）；已落地 [package-coding-conventions](../../docs/package-coding-conventions.md)** |

## 1. 提案要点

规范仓把方法论拆成「工程」与「AI 工程」两份语言无关正文；`methodology/ct-package-coding-general.md`
（170 行，8 个 Ct 代码块，条款 CG-1…CG-7：命名、对象式调用、能力寄生、三层模型、资源释放、
显式失败、映射唯一实现）不属于方法论，整份移交语言方。

PROP-004 的六项映射：

| CF-2 项 | 内容 |
| --- | --- |
| 现象 | 方法论目录含语言专用条款，非该语言的项目会被要求遵守无关规则 |
| 最小复现 | **不可复现**：这是文档归属问题，无运行时命令；证据是文件行数与代码块计数 |
| 期望行为 | 整份移出方法论，由语言方接收并维护 |
| 影响范围 | 只新增/接收一份文档；无代码改动 |
| 实测版本 | PROP-004 递交日 2026-11-23；原规范自 `1.15.0` 起纳入 |
| 承诺对应 | 原文第八节「处理记录」；本仓对应见 §6 |

## 2. 结论：接收（B 档）

### 2.1 为什么是 B，不是 A / C

| 档位 | 判断 | 理由 |
| --- | --- | --- |
| A 并入语言规范附录 | 不选 | `language-spec` 管语法、语义、容量与发射契约；包 API 设计条款会绑定它的发布节奏与门禁，且 §4.x 的条款体例不适合收纳“怎么设计包” |
| B 仓内独立文档 | **选** | 条款可独立演进，不与 spec 同版发布；通过 `package-guide` 与 spec 交叉引用即可到达 |
| C 参考 / 归档区 | 不选 | C 的语义是“暂不承诺维护”，与本条款属现行规范矛盾 |

### 2.2 落点与形态

- **路径**：[docs/package-coding-conventions.md](../../docs/package-coding-conventions.md)，单独成篇。
- **更名**：`ct-package-coding-general.md` → `package-coding-conventions.md`。仓内文件名按内容命名；
  “general” 是方法论拆分语境（相对“语言专用”），在 Ct 仓内没有区分度。**条款编号 CG-1…CG-7 保留**，
  作为稳定追溯键。
- **正文**：条款实质不改；只按本仓书写规范把语言名写作 Ct（DOC-94），并补来源与权威关系。
- **权威关系**：CG-1 的命名细则以 [language-spec §5.1](../../docs/language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约)
  为准，清单键与工具行为以 [package-guide](../../docs/package-guide.md) 为准；本文只补“包 API 怎么设计”
  这一层，避免第二事实源。
- **入口**：[docs/README.md](../../docs/README.md) 生态表新增一行；[package-guide](../../docs/package-guide.md)
  §0 与 §3 各加一处交叉引用。

## 3. 对规范组的三项答复

1. **接收**。
2. **B 档**：Ct 仓内独立文档，落点 `docs/package-coding-conventions.md`；
   `CG-1…CG-7` 原编号保留，标题仍为「Ct 包编码通用条款」。
3. **时间**：已在本轮完成，不需要 30 天复制窗口；提交即生效。

## 4. 历史演进记录：要，表格形式

请规范组按条款补一张表（Markdown 表或 TSV 均可），补到本卡「附录 A」：

| 条款 | 首次引入版本 | 变更版本 | 变更原因 | 关联决策 / 提案 |
| --- | --- | --- | --- | --- |

若无逐条记录，至少给一句确认「CG-1…CG-7 全部随 `1.15.0` 一次性引入」。历史记录只进本卡，
不另建文档，避免在 Ct 仓再造一份版本史。

## 5. 时间点与规范仓侧动作

- **Ct 侧已生效**（2026-11-23）。
- **建议规范仓立即**把原文件置 `deprecated` 并指向本文件与本卡，而不是等到 2.0.0：
  否则 `1.15.0`…`2.0.0` 之间会存在两份可引用正文，违反单一事实源。2.0.0 发布时删除或只读存档均可。
- 2.0.0 版本说明只记「语言专用编码条款已移出，去向见 PROP-004 / ct-lang DOC-95」，不复制内容。

## 6. 执行记录

- 新增 [docs/package-coding-conventions.md](../../docs/package-coding-conventions.md)（由本机原文逐条搬运）；
- [docs/README.md](../../docs/README.md) 生态表加索引行；
- [docs/package-guide.md](../../docs/package-guide.md) §0 / §3 加交叉引用；
- `python3 test/docs/check-docs.py` 绿（链接、锚点、Ct 书写 ratchet 均通过）；
- 纯文档提交，不动版本号、不改代码、不改测试。

## 7. 不做

- 不改任何 Ct 代码、测试或生成物；不 bump 版本；
- 不在本仓复制规范仓的 `methodology/` 目录结构；
- 不代规范仓删除或存档原文件（DB-5 / CF-1）；
- 不为这组条款新开 phase，也不改 `language-spec` 的既有条款编号。

## 8. 关联

- [package-coding-conventions](../../docs/package-coding-conventions.md)（接收落点）
- [package-guide](../../docs/package-guide.md)（清单与工具行为）
- [language-spec §5.1](../../docs/language-spec.md#51-源码命名约定语言--标准库--ct-pkg稳定契约)（命名契约）
- [DOC-94](doc-94-ct-spelling.md)（语言名写作 Ct）
- [AGENTS.md §9.10](../../AGENTS.md)（跨项目提案：观察方只提案，受理与落点归目标仓）
