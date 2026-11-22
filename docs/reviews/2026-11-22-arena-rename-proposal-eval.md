# 对《std::arena 改名 std::Arena + 自举依赖审计》提议的评估

> 评估对象：外部提议草案（所有者提出，转 STD / CT 两个项目组）。
> 核对基线：本仓 `main`（v0.88.3），用 `ct v0.88.3` 与 grep 实测；不改代码。
> 结论先行：**不建议按现稿推进**。两条前提一条不成立、一条已被实测满足；
> 审计命令会误报；真正待办是查清 `std::arena` 在文档里的矛盾，而不是改名。

## 1. 前提一「命名不合规」不成立

提议写：“模块/类型用 PascalCase，`std::arena` 不合规”。核对 [spec §5.1](../language-spec.md#L2011-L2023)：

| 类别 | 规范要求 | `arena` 的情况 |
| --- | --- | --- |
| 函数 / 方法 | snake_case | 不适用 |
| 类型（struct / enum / trait / 类型别名） | **PascalCase** | 类型名已经是 **`Arena`**，合规 |
| 变量 / 字段 / 常量 | snake_case | 不适用 |
| 模块 / namespace | **§5.1 没有这条规则** | `std::arena` 是模块/命名空间路径 |

`std` 的 16 个模块全部是小写（`std::str`、`std::io`、`std::fs`、`std::num`、`std::arena`…），
见 [std-catalog](../std-catalog.md#L34-L52)；“模块 PascalCase”与现行目录 = namespace 的规则相冲突。
把 `arena` 改成 `Arena` 会让它成为唯一 PascalCase 模块，并改变 import 路径，属于**全生态命名政策变更**，
不是一个小修；需要 ADR 覆盖全部模块，不能只改 arena。

## 2. 前提二「selfhost 可能依赖外部 std」已被实测否定

| 检查 | 命令 | 结果 |
| --- | --- | --- |
| selfhost 实际 import std | `grep -rn '^[[:space:]]*import[[:space:]]\+std::' selfhost/` | **0 条** |
| selfhost 代码里的 `std::arena` | `grep -rn 'std::arena' --include='*.ct' --include='*.h.ct' --include='*.m.ct' .` | **0 条** |
| selfhost 的 Arena 来源 | `selfhost/ct-ast/main.ct:26` | `import runtime::arena::Arena;`（**仓内自实现**） |

`selfhost/ct-ast/frontend/parse/Expr.h.ct` 里出现的 `std::io::puts(...)` 是**注释中的语法示例**，
不是 import。selfhost 自带 [Arena.h.ct](../../selfhost/ct-ast/runtime/arena/Arena.h.ct)（`pub struct Arena`），
所以 `grep "Arena"` 命中的 100+ 处是内部运行时，不是外部 std。

结论：**所有者的自举纯度原则当前已满足**；提议预判的路径 B（selfhost 用了 std::arena）不成立，
不需要“上收 lib/core”，也不需要一次 lib/core 联动抖动。

## 3. 审计命令需要改

现稿第 0 步的两条命令会产生误报：

1. `grep "std::" selfhost/` 会命中注释与文档字符串（如 `Expr.h.ct:531`），不能作“自举纯度硬判据”；
   应改为 `^[[:space:]]*import[[:space:]]+std::`，或先剥注释。
2. `grep "Arena"` 会同时命中内部 `runtime::arena::Arena` 与外部 `std::arena`；应分开统计
   `std::arena`（外部）与 `runtime::arena`（内部）。
3. 路径 A 的判据“全仓 `grep std::arena` 零命中”目前**必然失败**：`docs/std-catalog.md`、
   `battle/ct-guide-1/*` 都有该字符串；判据应分成“代码零命中”和“文档已同步”两条。

## 4. 真正的问题：`std::arena` 在文档里自相矛盾

| 出处 | 说法 |
| --- | --- |
| [std-catalog](../std-catalog.md#L46) | `std::arena` 模块存在，入口 `std::arena::Arena`（std 0.19.0） |
| [guide-for-c-programmers](../guide-for-c-programmers.md#L284-L290) | “`lib/std` … 没有公开的 `std::arena`”（`lib/std` 是内置层，不是 std 包） |
| [battle/ct-guide-1](../../battle/ct-guide-1/verdict.md#L13) | `std::arena` 不存在，已从指引删除 |

三者不可能同时为真。提议拿“std::arena 存在”作前提，但仓内没有任何代码引用它；
在 STD 组确认包内是否真有该模块之前，改名与审计都没有对象。

## 5. 开放问题的回答

| 提议问题 | 评估 |
| --- | --- |
| arena 是否配得上“内建” | 不配。它是普通分块分配器库，无编译器魔法；selfhost 不用它，且已有内部 arena。上收缺触发条件 |
| selfhost 的 std 引用“极小”时移除还是上收 | 当前是 **0 引用**；既不移除也不上收。注释里的示例不必动 |

## 6. 处置建议

1. **不执行改名**：`std::arena` 模块名合规，`Arena` 类型名已合规；如要改模块命名政策，
   另开 ADR 覆盖全部 std 模块，不能单点改。
2. **不执行路径 B**：自举纯度审计已通过（0 个 `import std::`），不迁 `lib/core`。
3. **先解决文档矛盾**：请 STD 组确认 `std 0.19.0` 是否真的发布 `arena` 模块；CT 侧据结果
   统一 [std-catalog](../std-catalog.md) / [guide-for-c-programmers](../guide-for-c-programmers.md) /
   battle 记录。已开 [DOC-93](../../issues/docs/doc-93-std-arena-doc-consistency.md)，
   不新开架构卡。
4. **审计脚本若要入库**：按 §3 改成 `import std::` + 区分内部/外部 Arena，并明确“代码判据”
   与“文档判据”分开；不要用现在这两条命令直接做 CI 门禁。
5. **与 DOC-87 的关系**：路径 B 才需要“Arena 直接落 lib/core”；既然 B 不成立，
   本提议不占 DOC-87 Stage 1 的批次。
