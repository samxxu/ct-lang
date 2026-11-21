# SH-104 · J-6 全量证据台账缺失（P-1…P-6）

| 项 | 值 |
| --- | --- |
| 模块 | selfhost（J-6 证据） |
| 定性 | 证据缺口（v1.0 闸门） |
| 严重度 | High |
| 锚点 | v0.83.3（2026-11-21） |
| 文件 | [v1-release-plan §1.5](../../docs/planning/v1-release-plan.md#L57-L71)、[D-011](../../docs/decisions/D-011.md) |
| 状态 | **实施中（台账已建；15 已过 / 9 部分 / 5 缺失 / 5 阻塞）** |
| 层级 | **Tier 1（`v1-PH-0` 入口）**，见 [battle/v1-readiness-1](../../battle/v1-readiness-1/verdict.md) |

## 进展（2026-11-21）

台账已落 [docs/planning/j6-evidence/ledger.md](../../docs/planning/j6-evidence/ledger.md)：

- 34 行 = P-1.1…P-1.4 / P-2.1…P-2.5 / P-3.1…P-3.8 / P-4.1…P-4.6 /
  P-5.1…P-5.7 / P-6.1…P-6.4（含附录 §C.5 的追加项）；P-7.x 原型与 P-8.1 不进闸门。
- **P-1.1 已过**：`examples test lib/std` 实测 1363 个 `.ct` / 31,183 行；字面量 2,275、
  `char *` 627、`T a[] =` 36、`T a[]` 后缀 37、`ref/out` 16、`new` 54（HEAD `10c7e439`，
  命令在台账内）。附录 A 的 649/494/36/2 是旧基线，**已标注作废**。
- **J-4a 判据与实测偏离**：D-011 原文写「容器 / Option / Result / 全局硬错」，
  v0.88 实测 `Vec<Str>`、`Option<Str>`、ADT 负载、全局字面量 `Str` 可编译（存视图）；
  字段 / `Map` 键仍硬错。台账按实测记，风险由 [LANG-22](../lang/lang-22-nonimmortal-view-store-lint.md) 承接。
- **P-2.1 口径**：按 D-016 记上下文关键字；附录 A 的「完全关键字」表述作废。
- **机判断言**：`check-docs` 新增 `check_j6_ledger`——34 个 ID 必须齐、状态只能四态、
  最小可判证据非空、`阻塞` 必须写依据；已做负例自测（改一个状态即红）。
- 仍缺：P-1.2 逐文件 CSV、P-1.3 lint dry-run（阻塞）、P-4.3 `Str` 逃逸 lint、
  P-5.2/P-5.3/P-5.5 `ref/out` 所有权夹具、P-6 跨仓迁移（阻塞于 std 发版）。

## 现象

J-6 全量证据仍未收口：P-1…P-6 的正式证据包（语料/语法/ABI/逃逸/所有权/跨仓）未齐，
roadmap 自标“J-6 未过”；J-3/J-4/J-5 也缺逐张核对。

## 期望

1. 建一份证据台账（表：判据 ID / 证据位置 / 状态 / 未决项 / 负责人）；
2. P-7.1a/P-7.1b/P-7.2/P-7.3 已落库的证据挂到台账；
3. 明确 P-1…P-6 各自的“最小可判证据”与产出物；
4. 台账进 check-docs 或 check-ast 的可机判断言，避免“写了但没跑”；
5. 清零“已实施未验证”。

## 验收

- 台账零未决，或每个未决都有 blocking 依据；
- v1.0 的 J-6 闸门可据此判定，不靠口头结论。

## 关联

- [2026-11-21 评估](../../docs/reviews/2026-11-21-v1-campaign-eval.md)、[v1 路线](../../docs/planning/v1-release-plan.md)
