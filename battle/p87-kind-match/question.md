# battle: PH-87 S87b 的 `node->kind` → 穷尽 `match`

- 日期：2026-11-21
- 状态：**open（DEV 建议稿；待 REVIEW/EDITOR 判决）**
- 关联：[phase87 卡](../../docs/design/phase87.md) §2 S87b / §3 E87-2、
  [D-017](../../docs/decisions/D-017.md) §2、[PH-84](../../docs/design/phase84.md)、
  [p87 证据](../../test/probes/p87_l2_adt_evidence.txt)。

## 争点

PH-87 卡要求把 `node->kind` 的 `switch` 判别“机械替换为穷尽 `match`”。但：

1. ct-ast 的节点池是扁平 `struct Node { int kind; … }`，`kind` 是手编号的
   `int`；`match`（language-spec §4.73）只接受 **ADT 值**，不接受 `int`。
2. 要让判别主语成为 ADT，只有两条路：
   - 把 `Arena::Node` 改成 ADT（整棵树 + 发射器重写，属 PH-88 范围）；
   - 或给 `match` 加字面量/整数模式（PH-84 明列非目标，改语言语义）。
3. 更硬的一条：ct-ast 源码由 **L2 引导编译**（`check-ast.sh:425`），L2 不实现
   PH-84 的 ADT/`match`。把 `pub enum NodeKind` 写进 ct-ast 源码，L2 原样
   发射成非法 C `enum`，`cc` 直接失败（原始输出见证据文件）。

即：**在 v0.87.0 的引导链下，ct-ast 源码里不可能出现 `match`**；这不是实现
选择，是工具链前置条件。

## 候选

| # | 方案 | 代价 |
| --- | --- | --- |
| A | 本卡不做字面 `match`；把检查器/解析器的 kind 分发改写成**按 kind 切片的单一判别**（每 kind 一个函数，判别式只读一次），并用探针把“漏切片”变红；`match` 拼写移交 PH-88（它负责把引导链搬到自举/种子） | E87-2 字面项未在本卡完成，需 REVIEW 认账；但交付可验证、可回滚、不动语义 |
| B | 先给 L2 补 ADT/`match` 下降，再在本卡写 `match` | 改冻结引导层与 L2 发射器，等于把 PH-84 重做一遍；跨 phase、远超预算，且会动 L2 产物 |
| C | 只在测试夹具里写 `match`，声称“可机械替换”即算通过 | 编译器源码没变，是假绿；E87-2 的“重写”落空 |

## 待判

选 A 是否成立；若成立，E87-2 的“字面 `match`”部分是否改为 PH-88 的入口判据
（PH-88 已有“自举不动点/轮数参数化”，是唯一能解开 L2 前置的卡）。
