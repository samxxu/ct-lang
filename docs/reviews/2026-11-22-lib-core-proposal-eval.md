# 对《lib/std → lib/core》提案（含 Ct 书写规范）与 Arena 补件的评估

> 评估对象：
> ①《提案：内置层目录更名 lib/std → lib/core（含书写规范：语言名「Ct」）》；
> ②《提议：std::arena 改名 std::Arena + 外部 std 依赖审计》（与 11-22 版逐字相同）。
> 核对基线：本仓 `main`（v0.88.3）。只做事实/排期核对，不改代码。
> 结论先行：**lib/core 主体与 DOC-87 一致，已按所有者改判提前到当前 pre 窗口**；
> 但提案有 3 处需修正或拆出：`AutoDrop` 不是 trait、LANG-23 的时点与“随本批执行”冲突、
> `CT → Ct` 没有仓库决策且不能搭 lib/core 的车。Arena 补件维持前次评估结论。

## 1. lib/core 主体：与 DOC-87 一致

| 提案内容 | 仓库现状 | 结论 |
| --- | --- | --- |
| `git mv lib/std lib/core`，文件名不变，不留双目录 | [DOC-87](../../issues/docs/doc-87-lib-core-rename.md) Stage 1 已写死 | 一致 |
| `CT_CORE_DIR` 五级解析、`CT_STD_DIR` 一个 MINOR 回退 | DOC-87 §1.2 已写死 | 一致 |
| 9 代码 + 21 脚本 + 12 活跃文档；历史不动 | DOC-87 §4 清单 | 一致 |
| `lib/` 下只有 `lib/std` 一个子目录 | `ls lib` 只输出 `std` | 事实成立 |
| `namespace` 改为 `core` | DOC-87 Stage 2；需先补 spec §4.51/§4.70/§4.71 | 一致，但提案没有 Stage 2 的执行步骤 |
| 排期“已在批” | 2026-11-22 所有者改判：当前 pre 窗口、不等 v1.0（`000a37cc`） | 一致，且已提前 |

提案的“执行要点”只覆盖 Stage 1；Stage 2（`core::*`、生成符号与 ABI、根拼写一个 MINOR 别名）
仍按 DOC-87 Stage 2 独立提交、独立回滚。不要把“namespace 相应改为 core”写成同一提交。

## 2. Drop / AutoDrop / Handback：一处事实错误 + 一处时点冲突

| 提案原文 | 实际 |
| --- | --- |
| “Drop / AutoDrop / Handback 三个语言级 trait 收归内建层” | **AutoDrop 不是 trait**，是 `own` 的自动释放机制；[LANG-23](../../issues/lang/lang-23-builtin-trait-declarations.md) 明确要求“不把 AutoDrop 变成 trait” |
| “机制一行不改，只是不再假装它们是普通 trait” | 当前 parser **拒绝** `trait Drop`（`'Drop' is a reserved built-in trait and cannot be defined`）。要提供可见声明，需要 [LANG-23](../../issues/lang/lang-23-builtin-trait-declarations.md) 的 parser 例外、Symbols 排除计数、Emitter 分支优先级、编辑器索引，**不是一行不改** |
| “随本批次一并执行” | LANG-23 状态是 `deferred`，落 **v1.1**，非目标写明“不在 v1.0 冻结期实施” | 

处理建议：Drop/Handback 声明仍由 LANG-23 承接；若所有者要把它们也提前到当前 pre 窗口，
应先改 LANG-23 的排期与“非目标”，再动代码。**AutoDrop 从提案的“三个 trait”里删掉**。

## 3. Arena 补件：维持前次结论

该文件与 11-22 版逐字相同，[前次评估](2026-11-22-arena-rename-proposal-eval.md) 已覆盖：

- “模块/类型 PascalCase”不成立：§5.1 只约束类型/函数/变量，`std` 的 16 个模块全小写；
  类型 `Arena` 已合规；
- `selfhost` 的 `import std::` 为 **0**，`std::arena` 在代码里 **0** 处；内部
  `runtime::arena::Arena` 是自实现，路径 B（上收 `lib/core`）不触发；
- 真正待办是 `std-catalog` / guide / battle 对 `std::arena` 是否存在的矛盾，已开
  [DOC-93](../../issues/docs/doc-93-std-arena-doc-consistency.md)。

另需修正一处术语：提案的“STD 组配合 `lib/std` 路径替换”应写成“外部 std 包 / 消费者是否
引用 CT 的 `lib/std`”；std 包本身叫 `std`（`ct/std`），不存在 `lib/std` 目录可替换。

## 4. `CT → Ct`：不能搭 DOC-87 的车

提案新增了“语言名 `CT` → `Ct`”与 check-docs ratchet（散文里全大写 `CT` 即红）。核对：

- 仓库没有这条决策：glossary 定义 `ct（CT = C with Traits）`，spec/README/路线图全部用 **CT**；
- 影响面是全仓散文，不是 `lib/core` 的 12 个活跃文档；`CT_CORE_DIR` / `CT_HOME` 等
  环境变量只是被“命令/路径豁免”覆盖，不代表散文可机械替换；
- 先上 ratchet 会让现有文档立即变红，与 v1.0 前的文档收口冲突；
- “C++ / C# / C3 的排版惯例”是品牌论证，不是技术约束，不能据此直接改全仓。

处理建议：**单独立命名 ADR**（或所有者书面决定），先全量替换、再开 ratchet；
在决定前，仓库继续用 **CT**，外部四份文档的写法不反向污染仓库。

## 5. 处置表

| 项 | 结论 |
| --- | --- |
| Stage 1 `lib/core` + `CT_CORE_DIR` | 接受；DOC-87 已排当前 pre 窗口，待 DEV |
| Stage 2 `namespace core` / `core::*` | 接受；先补 spec 命名空间条款，再独立提交 |
| Drop / Handback 可见声明 | 由 LANG-23 承接；是否提前到 pre 窗口需所有者另定 |
| AutoDrop | **不是 trait**，从本批删除 |
| `std::arena → std::Arena` | 不接受（模块名小写合规，见前次评估） |
| Arena 上收 `lib/core` | 不触发（selfhost 零外部 std 依赖） |
| `CT → Ct` | 待命名 ADR；不随 DOC-87 批次执行 |
| STD 配合清单措辞 | 改为“外部 std 消费者是否引用 CT 的 `lib/std`”，避免把 std 包叫 `lib/std` |

## 6. 需要所有者拍板的两件事

1. **LANG-23 是否也提前**：Drop/Handback 的可见声明是否要在当前 pre 窗口完成；
   若否，lib/core 批次只做目录/ENV + `namespace core`，不带 trait 声明。
2. **`CT → Ct` 是否立项**：若要做，按命名 ADR + 全量替换 + 最后开 ratchet 三步走；
   若不做，外部文档的 Ct 写法保持外部，仓库继续 CT。
