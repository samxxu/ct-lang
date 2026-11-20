# Phase 84 — 最小 ADT / `match`（v1-pre 前置）

> **状态：实施中（准备；施工入口未过）**（2026-11-21 立项并开卡；`v0.84.0`）。
> **签收：EDITOR 2026-11-21**（主编统一签收；卡作者 REQ）。
> **施工闸门**：PH-83 已收口（`v0.83.3`）；本卡是 v1-pre 的第一步，完成后才进 PH-85。
> **前置**：[D3 裁定](../reviews/2026-11-21-v1-campaign-eval.md)（最小 ADT 先行）、
> [LANG-21](../../issues/lang/lang-21-minimal-adt-match.md)、
> [v1 路线 §2.3](../planning/v1-release-plan.md)。
> **布局说明**：phase-ID 迁移仍被 blocker 挡住，本卡暂用 legacy 路径 `docs/design/phase84.md`。

## 0 卡片字段（冻结）

| 项 | 值 |
| --- | --- |
| 编号 | v0-PH-84（legacy 文件 `phase84.md`） |
| 目标 | 为 ct-ast 重写提供穷尽判别：名义和类型 + 构造器负载 + 穷尽 `match` + 变量绑定 |
| 范围 | `enum` 负载变体、构造 `Type.Variant(...)`、`match` 语句、穷尽检查、payload 绑定、确定性布局 |
| 非目标 | 泛型 ADT；or/守卫/字面量/嵌套/结构体模式；表达式形式的 `match`；`Option`/`Result` 替代；借用模式 |
| 交付物 | 编译器改动、`test/ast/p84_*`、spec/tutorial、冻结清单登记 |
| 任务清单 | §2（S84a–S84d） |
| 退出判据 | E84-1…E84-8（§3） |
| version-minor | 84（PH-84，`d=0`） |
| 已知风险 | R84-1…R84-5（§4） |

## 1 需求与边界

### 1.1 语法（冻结）

```ct
enum Shape {
    Circle(int r),
    Rect(int w, int h),
}

int area(Shape s)
{
    match (s) {
        Shape.Circle(r) => { return 3 * r * r; }
        Shape.Rect(w, h) => { return w * h; }
    }
}
```

- **负载变体**：`enum` 任一成员带括号负载即为 ADT；所有成员都不带负载时保持现行 C `enum` 语义；
- **构造**：`Type.Variant(args)`；bare variant 名不引入（避免与 C 枚举常量冲突）；
- **match**：语句形式；每个分支是 `Type.Variant(bindings) => { ... }`，无 fallthrough；
- **穷尽**：必须覆盖全部变体，或显式 `_ => { ... }`；缺少分支编译错；
- **绑定**：负载按值绑定到局部名（owning 负载按 move）；本轮不做借用模式。

### 1.2 布局与 ABI

```c
struct Shape {
    int tag;
    union { struct { int r; } Circle; struct { int w; int h; } Rect; } u;
};
```

- 布局确定：`tag` 在前，payload union 在后；对齐取各成员最大对齐；
- `pub` ADT 类型进入 ABI 头时，布局与 `_Static_assert` 一起进 golden；
- 不引入 vtable；ADT 不是 trait 接口值。

### 1.3 非目标（明确不做）

- 泛型 `enum Option<T>`、or 模式、守卫、字面量模式、嵌套/结构体模式；
- `match` 作为表达式返回值的形态（本轮只用语句；需要时先绑局部再 match）；
- 自动把 `Option`/`Result` 改成 ADT；
- 借用/`ref` 模式与穷尽之外的流分析。

## 2 任务

| 任务 | 交付 | 验收 | effort |
| --- | --- | --- | --- |
| S84a 语法/类型 | `enum` 负载变体、`Type.Variant(...)`、类型检查 | `p84_syntax` | M |
| S84b 穷尽/诊断 | `match` 语句、穷尽检查、重复/未知变体/arity 错误 | `p84_match` / `p84_errors` | M |
| S84c 布局/发射 | tag+union 布局、绑定与 move、`_Static_assert` | `p84_layout` | M |
| S84d 文档/迁移 | spec/tutorial/patterns、冻结清单、C enum 不变说明 | `p84_docs` | S |

每项任务先提 `test(<scope>): <task-id> 红`（含 `baseline: <sha>`），实现提交随后转绿；
S84d 为纯文档任务，写 `no-test:` 并由 REVIEW 签字。

## 3 退出判据

| ID | 断言 |
| --- | --- |
| E84-1 | 带负载 `enum` 解析为 ADT；无负载 `enum` 的 C 语义与 golden 不变 |
| E84-2 | `Type.Variant(args)` 构造类型正确；arity/类型不符硬错 |
| E84-3 | `match` 覆盖全部变体才通过；漏分支、重复分支、未知变体均编译错并给位置 |
| E84-4 | payload 绑定按值/move；无 fallthrough；`_` 必须显式书写才允许兜底 |
| E84-5 | 布局为 tag+union 且确定；`pub` ADT 的 ABI 头 + `_Static_assert` 进 golden |
| E84-6 | 重写切片中的 `node->kind` 判别可机械替换为穷尽 `match`（以词法/AST 判别样例验证） |
| E84-7 | 既有测试/示例全绿；`check-all` 与 ASan 通过；无新增警告 |
| E84-8 | spec/tutorial/patterns 成文；冻结清单登记；单卡回滚不影响 `enum`/`switch` 旧代码 |

## 4 风险与回滚

| ID | 风险 | 缓解 |
| --- | --- | --- |
| R84-1 | `enum` 扩展与 C 枚举二义 | 规则写死：有负载=ADT，无负载=C enum；显式枚举值只允许 C enum；负例 |
| R84-2 | `_` 兜底掩盖漏分支 | `_` 必须显式；`ct check --types` 对“可穷尽却用 `_`”给 lint |
| R84-3 | 布局/ABI 不稳定 | tag+union 写死；`_Static_assert` 进 golden；不承诺跨版本 ABI |
| R84-4 | payload 所有权/move 语义不清 | 本轮按值/move；借用模式留后续；文档与负例 |
| R84-5 | 范围蔓延到泛型/全模式 | 非目标写死；需要时另立提案，不在本卡加 |

回滚：单卡回滚；`enum`（无负载）与 `switch` 行为不变。
